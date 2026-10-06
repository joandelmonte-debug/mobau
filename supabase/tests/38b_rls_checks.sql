-- ============================================================
-- PROPUESTA NO EJECUTADA (38-B) — no ejecutar sin aprobación explícita
-- ============================================================
-- 38-B · Pruebas de RLS en una transacción revertida (ejecución inicial)
-- ------------------------------------------------------------
-- Ejecutar SOLO después de aplicar 38-B · 01–04. Pensado para el
-- editor SQL de Supabase (rol postgres, miembro de anon y authenticated).
--
-- Identidades: SOLO cuentas reales existentes, sin modificarlas:
--   * el distribuidor verificado real (el único supplier verificado);
--   * un profesional real (role 'individual') con un proyecto activo
--     que contiene al menos una línea con producto publicado;
--   * anónimo.
-- No se cambia ningún perfil. "Otro distribuidor verificado" y
-- "distribuidor no verificado" están en un archivo aparte
-- (38b_rls_checks_identidades_temporales.sql), EXCLUIDO de la
-- ejecución inicial.
--
-- NADA queda guardado (doble seguro):
--   1) todo ocurre dentro de BEGIN … ROLLBACK;
--   2) el bloque DO termina SIEMPRE con RAISE EXCEPTION (MB999), que
--      aborta la transacción completa aunque el cliente hiciera COMMIT.
--   Los resultados viajan en el mensaje de ese error final (JSON).
-- Además, cada prueba corre en su propia subtransacción que se deshace
-- al terminar (marcador MB001), incluidos el cambio de rol y cualquier
-- dato auxiliar de esa prueba:
--   * pre_sql (lista de sentencias, como postgres, solo dentro de esa
--     subtransacción) puede crear un producto auxiliar 'rls38b-tmp' del
--     distribuidor real o líneas auxiliares en el proyecto del
--     profesional o del distribuidor (marcadas notes = 'rls38b-aux').
--   * Las escrituras que se espera que funcionen (editar, borrar, excluir)
--     actúan SOLO sobre esas filas auxiliares. Ningún producto, perfil,
--     proyecto, línea ni precio existente se modifica ni se borra, ni
--     siquiera de forma provisional; las escrituras bloqueadas fallan
--     antes de tocar filas o afectan a 0 filas.
--
-- Sin IDs, correos, tokens ni secretos: todo se resuelve al ejecutar.
-- Los resultados solo muestran nombre de prueba, esperado y obtenido.
-- ============================================================

BEGIN;

DO $$
declare
  v_sup uuid; v_sup_dist text; v_sup_project uuid;
  v_pro uuid; v_pro_project uuid;
  v_pub_other text; v_pub_priced text; v_arch_own text;
  n_pub int; n_sup_nonpub int;
  v_tmp constant text := 'rls38b-tmp';
  v_tmp_insert text; v_aux_pro text; v_aux_sup text;
  v_line_arch text; v_line_arch_excluded text;
  v_rfq text;
  r jsonb := '[]'::jsonb;
  t record;
  v_got text; v_n bigint; v_ok boolean; v_stmt text; v_left bigint;
  n_total int := 0; n_ok int := 0;
begin
  -- ---------- datos de partida (lectura como postgres; no se modifican) ----------
  select dp.user_id, dp.distributor_id into v_sup, v_sup_dist
    from public.distributor_profiles dp join public.profiles p on p.id = dp.user_id
   where p.role = 'supplier' and dp.verification_status = 'verified' and dp.distributor_id is not null
   order by dp.created_at limit 1;
  select pr.id into v_sup_project from public.projects pr
   where pr.owner_user_id = v_sup and pr.status = 'active' order by pr.created_at limit 1;
  select pr.owner_user_id, pr.id into v_pro, v_pro_project
    from public.projects pr join public.profiles p on p.id = pr.owner_user_id
   where p.role = 'individual' and pr.status = 'active'
     and exists (select 1 from public.project_products pp join public.products x on x.id = pp.product_id
                  where pp.project_id = pr.id and x.publication_status = 'published')
     and not exists (select 1 from public.project_products pp join public.products x on x.id = pp.product_id
                      where pp.project_id = pr.id and pp.selected_for_rfq and x.publication_status <> 'published')
   order by pr.created_at limit 1;
  select id into v_pub_other from public.products
   where publication_status = 'published' and distributor_id <> v_sup_dist order by id limit 1;
  select p.id into v_pub_priced from public.products p
   where p.publication_status = 'published' and exists (select 1 from public.product_prices pp where pp.product_id = p.id)
   order by p.id limit 1;
  select p.id into v_arch_own from public.products p
   where p.distributor_id = v_sup_dist and p.publication_status <> 'published'
     and exists (select 1 from public.product_prices pp where pp.product_id = p.id) order by p.id limit 1;
  select count(*) into n_pub from public.products where publication_status = 'published';
  select count(*) into n_sup_nonpub from public.products where distributor_id = v_sup_dist and publication_status <> 'published';

  if v_sup is null or v_sup_project is null or v_pro is null
     or v_pub_other is null or v_pub_priced is null or v_arch_own is null then
    raise exception 'MOBAU_38B: faltan datos de partida para las pruebas' using errcode = 'MB998';
  end if;

  -- SQL auxiliar (solo se ejecuta como pre_sql, dentro de la subtransacción de cada prueba)
  v_tmp_insert := format(
    'insert into public.products (id, name, distributor_id, category_id, publication_status) values (%L, %L, %L, %L, %L)',
    v_tmp, 'Prueba RLS 38-B (auxiliar)', v_sup_dist, 'iluminacion', 'draft');
  v_line_arch := format(
    'insert into public.project_products (project_id, product_id, selected_for_rfq) values (%L, %L, true)',
    v_pro_project, v_arch_own);
  v_line_arch_excluded := format(
    'insert into public.project_products (project_id, product_id, selected_for_rfq) values (%L, %L, false)',
    v_pro_project, v_arch_own);
  v_aux_pro := format(
    'insert into public.project_products (project_id, product_id, notes) values (%L, %L, %L)',
    v_pro_project, v_pub_other, 'rls38b-aux');
  v_aux_sup := format(
    'insert into public.project_products (project_id, product_id, notes) values (%L, %L, %L)',
    v_sup_project, v_pub_other, 'rls38b-aux');
  v_rfq := 'insert into public.rfqs (project_id, requester_user_id, requester_name, requester_email, status) values (%L, %L, %L, %L, %L)';

  -- ---------- casos ----------
  -- kind: 'count' (sql es un SELECT count) | 'exec' (escritura; se mide row_count)
  --       | 'blocked' (escritura que debe fallar; después, dentro de la misma
  --         subtransacción y sin RLS, se cuentan las filas auxiliares marcadas)
  -- expect: 'N' (conteo exacto) | '42501' | 'ok' | 'rows=0' | 'rows>0' | 'not42501'
  --       | '42501|23502' (error de RLS o de NOT NULL, ambos válidos, y 0 filas auxiliares)
  -- role '-' = sin cambio de rol (postgres: moderación manual)
  -- pre_sql: lista de sentencias auxiliares (como postgres, dentro de la subtransacción)
  for t in
    select * from (values
      -- Visibilidad de productos
      ('V01 anon ve un producto publicado',               'anon', null::text, null::text[], format('select count(*) from public.products where id = %L', v_pub_other), 'count', '1'),
      ('V02 anon NO ve un archivado (URL directa)',        'anon', null, null, format('select count(*) from public.products where id = %L', v_arch_own), 'count', '0'),
      ('V03 anon NO ve un borrador',                       'anon', null, array[v_tmp_insert], format('select count(*) from public.products where id = %L', v_tmp), 'count', '0'),
      ('V04 anon: total = publicados',                     'anon', null, null, 'select count(*) from public.products', 'count', n_pub::text),
      ('V05 anon: sin permiso sobre product_prices (39-06)', 'anon', null, null, 'select count(*) from public.product_prices', 'exec', '42501'),
      ('V06 profesional ve un publicado',                  'authenticated', v_pro::text, null, format('select count(*) from public.products where id = %L', v_pub_other), 'count', '1'),
      ('V07 profesional NO ve un archivado',               'authenticated', v_pro::text, null, format('select count(*) from public.products where id = %L', v_arch_own), 'count', '0'),
      ('V08 profesional NO ve un borrador',                'authenticated', v_pro::text, array[v_tmp_insert], format('select count(*) from public.products where id = %L', v_tmp), 'count', '0'),
      ('V09 profesional: total = publicados',              'authenticated', v_pro::text, null, 'select count(*) from public.products', 'count', n_pub::text),
      ('V10 profesional: línea con archivado visible, producto no', 'authenticated', v_pro::text, array[v_line_arch],
         format('select count(*) from public.project_products pp join public.products p on p.id = pp.product_id where pp.project_id = %L and pp.product_id = %L', v_pro_project, v_arch_own), 'count', '0'),
      ('V11 distribuidor verificado ve un publicado ajeno', 'authenticated', v_sup::text, null, format('select count(*) from public.products where id = %L', v_pub_other), 'count', '1'),
      ('V12 distribuidor verificado ve SU archivado',      'authenticated', v_sup::text, null, format('select count(*) from public.products where id = %L', v_arch_own), 'count', '1'),
      ('V13 distribuidor verificado ve SU borrador',       'authenticated', v_sup::text, array[v_tmp_insert], format('select count(*) from public.products where id = %L', v_tmp), 'count', '1'),
      ('V14 distribuidor verificado: total = publicados + suyos no publicados', 'authenticated', v_sup::text, null, 'select count(*) from public.products', 'count', (n_pub + n_sup_nonpub)::text),
      -- Precios: misma visibilidad que su producto
      ('P01 profesional NO lee product_prices directamente (39-06; el catálogo usa catalog_published_prices)', 'authenticated', v_pro::text, null, format('select count(*) from public.product_prices where product_id = %L', v_pub_priced), 'count', '0'),
      ('P02 profesional NO ve precio de un archivado',     'authenticated', v_pro::text, null, format('select count(*) from public.product_prices where product_id = %L', v_arch_own), 'count', '0'),
      ('P03 distribuidor verificado ve precio de SU archivado', 'authenticated', v_sup::text, null, format('select count(*) from public.product_prices where product_id = %L', v_arch_own), 'count', '1'),
      ('P04 profesional: ningún precio de producto no visible', 'authenticated', v_pro::text, null,
         'select count(*) from public.product_prices pp where not exists (select 1 from public.products p where p.id = pp.product_id)', 'count', '0'),
      -- Distribuidor verificado: escrituras
      -- S01/N01 insertan con status 'archived': trg_enforce_active_project_limit
      -- (BEFORE INSERT) sale sin validar si status <> 'active', así el bloqueo
      -- lo decide la RLS y no el límite de plan.
      ('S01 distribuidor NO crea proyectos',               'authenticated', v_sup::text, null, format('insert into public.projects (owner_user_id, name, status) values (%L, %L, %L)', v_sup, 'RLS', 'archived'), 'exec', '42501'),
      ('S02 distribuidor NO edita su proyecto (0 filas)',  'authenticated', v_sup::text, null, format('update public.projects set name = name where id = %L', v_sup_project), 'exec', 'rows=0'),
      ('S03 distribuidor NO añade líneas',                 'authenticated', v_sup::text, null, format('insert into public.project_products (project_id, product_id) values (%L, %L)', v_sup_project, v_pub_other), 'exec', '42501'),
      ('S04 distribuidor NO edita líneas (0 filas)',       'authenticated', v_sup::text, null, format('update public.project_products set quantity = quantity where project_id = %L', v_sup_project), 'exec', 'rows=0'),
      ('S05 distribuidor SÍ borra una línea de su proyecto (solo la auxiliar)', 'authenticated', v_sup::text, array[v_aux_sup], format('delete from public.project_products where project_id = %L and notes = %L', v_sup_project, 'rls38b-aux'), 'exec', 'rows>0'),
      ('S06 distribuidor NO crea solicitudes',             'authenticated', v_sup::text, null, format(v_rfq, v_sup_project, v_sup, 'RLS', 'rls@example.invalid', 'submitted'), 'exec', '42501'),
      ('S07 distribuidor NO crea productos',               'authenticated', v_sup::text, null, format('insert into public.products (name, category_id) values (%L, %L)', 'RLS', 'iluminacion'), 'exec', '42501'),
      ('S08 distribuidor NO cambia publication_status',    'authenticated', v_sup::text, null, format('update public.products set publication_status = %L where id = %L', 'published', v_arch_own), 'exec', '42501'),
      ('S09 distribuidor NO cambia status',                'authenticated', v_sup::text, null, format('update public.products set status = %L where id = %L', 'active', v_arch_own), 'exec', '42501'),
      ('S10 distribuidor NO crea precios',                 'authenticated', v_sup::text, null, format('insert into public.product_prices (product_id, price_status) values (%L, %L)', v_arch_own, 'quote_required'), 'exec', '42501'),
      ('S11 distribuidor NO edita precios',                'authenticated', v_sup::text, null, format('update public.product_prices set price_status = price_status where product_id = %L', v_arch_own), 'exec', '42501'),
      ('S12 distribuidor NO escribe en rfq_distributors (RLS sin políticas)',  'authenticated', v_sup::text, null, format('insert into public.rfq_distributors (rfq_id, distributor_id) values (gen_random_uuid(), %L)', v_sup_dist), 'exec', '42501'),
      -- Profesional: escrituras
      ('C01 profesional añade un producto publicado',      'authenticated', v_pro::text, null, format('insert into public.project_products (project_id, product_id) values (%L, %L)', v_pro_project, v_pub_other), 'exec', 'ok'),
      ('C02 profesional NO añade un borrador',             'authenticated', v_pro::text, array[v_tmp_insert], format('insert into public.project_products (project_id, product_id) values (%L, %L)', v_pro_project, v_tmp), 'exec', '42501'),
      ('C03 profesional NO añade un archivado',            'authenticated', v_pro::text, null, format('insert into public.project_products (project_id, product_id) values (%L, %L)', v_pro_project, v_arch_own), 'exec', '42501'),
      ('C04 profesional edita la cantidad de su línea (auxiliar)', 'authenticated', v_pro::text, array[v_aux_pro], format('update public.project_products set quantity = 2 where project_id = %L and notes = %L', v_pro_project, 'rls38b-aux'), 'exec', 'rows>0'),
      ('C05 profesional NO cambia el producto de una línea', 'authenticated', v_pro::text, array[v_aux_pro], format('update public.project_products set product_id = %L where project_id = %L and notes = %L', v_pub_priced, v_pro_project, 'rls38b-aux'), 'exec', '42501'),
      ('C06 profesional excluye una línea no disponible',  'authenticated', v_pro::text, array[v_line_arch],
         format('update public.project_products set selected_for_rfq = false where project_id = %L and product_id = %L', v_pro_project, v_arch_own), 'exec', 'rows>0'),
      ('C07 profesional NO crea solicitud con línea no publicada incluida', 'authenticated', v_pro::text, array[v_line_arch],
         format(v_rfq, v_pro_project, v_pro, 'RLS', 'rls@example.invalid', 'submitted'), 'exec', '42501'),
      ('C08 profesional crea solicitud con la línea no publicada excluida', 'authenticated', v_pro::text, array[v_line_arch_excluded],
         format(v_rfq, v_pro_project, v_pro, 'RLS', 'rls@example.invalid', 'submitted'), 'exec', 'ok'),
      ('C09 profesional NO crea solicitud sobre proyecto ajeno', 'authenticated', v_pro::text, null,
         format(v_rfq, v_sup_project, v_pro, 'RLS', 'rls@example.invalid', 'submitted'), 'exec', '42501'),
      ('C10 profesional crea proyectos (RLS lo permite; el límite de plan puede responder P0001)', 'authenticated', v_pro::text, null,
         format('insert into public.projects (owner_user_id, name) values (%L, %L)', v_pro, 'RLS'), 'exec', 'not42501'),
      ('C11 profesional NO edita productos',               'authenticated', v_pro::text, null, format('update public.products set name = name where id = %L', v_pub_other), 'exec', '42501'),
      ('C12 profesional NO crea precios',                  'authenticated', v_pro::text, null, format('insert into public.product_prices (product_id, price_status) values (%L, %L)', v_pub_other, 'quote_required'), 'exec', '42501'),
      ('C13 profesional NO escribe en rfq_distributors (RLS sin políticas)', 'authenticated', v_pro::text, null, format('insert into public.rfq_distributors (rfq_id, distributor_id) values (gen_random_uuid(), %L)', v_sup_dist), 'exec', '42501'),
      ('C14 profesional NO crea solicitud con project_id NULL (42501 o 23502, sin fila)', 'authenticated', v_pro::text, null,
         format(v_rfq, null, v_pro, 'rls38b-c14', 'rls@example.invalid', 'submitted'), 'blocked', '42501|23502'),
      -- Anónimo: escrituras
      ('N01 anon NO crea proyectos',                       'anon', null, null, format('insert into public.projects (owner_user_id, name, status) values (%L, %L, %L)', v_pro, 'RLS', 'archived'), 'exec', '42501'),
      ('N02 anon NO crea solicitudes',                     'anon', null, null, format(v_rfq, v_pro_project, v_pro, 'RLS', 'rls@example.invalid', 'submitted'), 'exec', '42501'),
      ('N03 anon NO crea productos',                       'anon', null, null, format('insert into public.products (name, category_id) values (%L, %L)', 'RLS', 'iluminacion'), 'exec', '42501'),
      -- Moderación manual (postgres) sobre el producto auxiliar, nunca sobre uno real
      ('M01 publicar refleja status = active',             '-', null, array[v_tmp_insert, format('update public.products set publication_status = %L where id = %L', 'published', v_tmp)],
         format('select count(*) from public.products where id = %L and status = %L', v_tmp, 'active'), 'count', '1'),
      ('M02 pedir cambios refleja status = archived',      '-', null, array[v_tmp_insert, format('update public.products set publication_status = %L where id = %L', 'changes_requested', v_tmp)],
         format('select count(*) from public.products where id = %L and status = %L', v_tmp, 'archived'), 'count', '1'),
      ('M03 al publicarlo, anon lo ve',                    'anon', null, array[v_tmp_insert, format('update public.products set publication_status = %L where id = %L', 'published', v_tmp)],
         format('select count(*) from public.products where id = %L', v_tmp), 'count', '1')
    ) as c(name, role, sub, pre_sql, sql, kind, expect)
  loop
    v_got := null;
    begin
      -- pre_sql prepara datos auxiliares como postgres, antes del cambio de rol
      if t.pre_sql is not null then
        foreach v_stmt in array t.pre_sql loop
          execute v_stmt;
        end loop;
      end if;
      if t.role <> '-' then
        execute format('set local role %I', t.role);
      end if;
      perform set_config('request.jwt.claim.sub', coalesce(t.sub, ''), true);
      perform set_config('request.jwt.claims',
        case when t.sub is null then '' else json_build_object('sub', t.sub, 'role', t.role)::text end, true);
      if t.kind = 'count' then
        execute t.sql into v_n;
        v_got := v_n::text;
      elsif t.kind = 'blocked' then
        -- C14: el orden entre RLS y NOT NULL no es un contrato de la aplicación;
        -- la garantía es que no se crea la fila. Se intenta el INSERT en un
        -- bloque propio y, dentro de la subtransacción de la prueba, se
        -- comprueba sin RLS que no quedó ninguna RFQ auxiliar.
        begin
          execute t.sql;
          get diagnostics v_n = row_count;
          v_got := 'ok rows=' || v_n;
        exception
          when others then v_got := sqlstate || ' ' || left(sqlerrm, 140);
        end;
        execute 'reset role';
        select count(*) into v_left from public.rfqs where requester_name = 'rls38b-c14';
        v_got := v_got || ' | filas_aux=' || v_left;
      else
        execute t.sql;
        get diagnostics v_n = row_count;
        v_got := 'ok rows=' || v_n;
      end if;
      raise exception using errcode = 'MB001'; -- deshace la subtransacción (datos auxiliares y cambio de rol)
    exception
      when sqlstate 'MB001' then null;
      when others then v_got := sqlstate || ' ' || left(sqlerrm, 140);
    end;

    v_ok := case t.expect
      when '42501'    then v_got like '42501%'
      when 'ok'       then v_got like 'ok rows=%'
      when 'rows=0'   then v_got = 'ok rows=0'
      when 'rows>0'   then v_got like 'ok rows=%' and v_got <> 'ok rows=0'
      when 'not42501' then v_got not like '42501%'
      when '42501|23502' then (v_got like '42501%' or v_got like '23502%') and v_got like '%| filas_aux=0'
      else v_got = t.expect
    end;
    n_total := n_total + 1;
    if v_ok then n_ok := n_ok + 1; end if;
    r := r || jsonb_build_object('prueba', t.name, 'esperado', t.expect, 'obtenido', v_got, 'ok', v_ok);
  end loop;

  -- Fin: siempre se aborta la transacción completa; el resultado viaja en el mensaje
  raise exception 'MOBAU_38B_RLS total=% ok=% fallos=% :: %', n_total, n_ok, n_total - n_ok, r::text
    using errcode = 'MB999';
end $$;

ROLLBACK;
