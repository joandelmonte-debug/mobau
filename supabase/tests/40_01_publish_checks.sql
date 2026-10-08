-- ============================================================
-- PROPUESTA NO EJECUTADA (40-01) — no ejecutar sin aprobación explícita
-- ============================================================
-- 40-01 · Pruebas de «aprobar y publicar», en una transacción revertida
-- ------------------------------------------------------------
-- Ejecutar SOLO después de aplicar 40-01. Editor SQL de Supabase (rol
-- postgres). Mismo patrón y mismas reglas que 39_moderation_checks.sql:
-- JWT simulado (no valida el MFA real), cada caso en su subtransacción
-- (MB001), error final MB999 con los resultados, BEGIN … ROLLBACK.
--
-- Identidades (sin crear cuentas ni roles):
--   * Distribuidor A: el distribuidor verificado real.
--   * Admin temporal: el primer profesional real ('individual'), dado de
--     alta en mobau_admins SOLO dentro del caso (se deshace con el caso).
--   * Profesional: otro profesional real, sin fila en mobau_admins.
--   * anon.
-- Precondición: ni el distribuidor A ni los dos profesionales tienen fila
-- en mobau_admins. Línea base de mobau_admins (recuento + MD5) y R02 exige
-- que al final sea idéntica.
--
-- Datos auxiliares (solo dentro de cada caso): productos 'rls40-a'
-- (publicado) y 'rls40-d' (borrador) de A y propuestas con ids fijos
-- 00000000-0000-4000-8000-000000040a__, insertadas como postgres ya en
-- 'submitted' (con snapshot en las update). NADA queda guardado.
-- Después: repetir 39_moderation_checks.sql (80), 39_05 (29), 39_06 (28),
-- 38c (74) y 38b (50).
-- ============================================================

BEGIN;

DO $$
declare
  v_sup uuid; v_sup_dist text; v_pro uuid; v_pro2 uuid;
  v_cat1 text; v_sub1 text;
  c1 constant text := '00000000-0000-4000-8000-000000040a01';  -- create: quote_required sin importe
  c2 constant text := '00000000-0000-4000-8000-000000040a02';  -- create: precio publicado 250
  c3 constant text := '00000000-0000-4000-8000-000000040a03';  -- create: quote_required con importe 80
  c4 constant text := '00000000-0000-4000-8000-000000040a04';  -- create: sin precio
  c5 constant text := '00000000-0000-4000-8000-000000040a05';  -- create: precio 777.77 que fallará
  u1 constant text := '00000000-0000-4000-8000-000000040a06';  -- update sobre producto en borrador
  u2 constant text := '00000000-0000-4000-8000-000000040a07';  -- update sobre producto publicado
  v_admin text; v_prod_a text; v_prod_d text; v_fail_price text;
  v_c1 text; v_c2 text; v_c3 text; v_c4 text; v_c5 text; v_u1 text; v_u2 text;
  f_create text; f_update text;
  as_pro text; as_sup text; as_anon text;
  r jsonb := '[]'::jsonb;
  t record;
  i int;
  v_got text; v_n bigint; v_ok boolean; v_stmt text;
  n_total int := 0; n_ok int := 0;
  v_adm_n bigint; v_adm_md5 text;
  fn_call constant text := 'select public.moderate_product_proposal(%L::uuid, %L, %L, %s)';
  fn_save constant text := 'select set_config(''mobau.test_result'', public.moderate_product_proposal(%L::uuid, %L, %L, %s)::text, true)';
  res constant text := 'current_setting(''mobau.test_result'')::jsonb';
  fn_try constant text := 'do $t$ begin perform public.moderate_product_proposal(%L::uuid, %L, %L, %s);'
                          || ' perform set_config(''mobau.test_result'', ''sin error'', true);'
                          || ' exception when others then perform set_config(''mobau.test_result'', sqlstate, true); end $t$';
  -- Producto creado en el caso (id devuelto por la función).
  pid constant text := '(current_setting(''mobau.test_result'')::jsonb ->> ''created_product_id'')';
begin
  -- ---------- datos de partida (lectura como postgres) ----------
  select dp.user_id, dp.distributor_id into v_sup, v_sup_dist
    from public.distributor_profiles dp join public.profiles p on p.id = dp.user_id
   where p.role = 'supplier' and dp.verification_status = 'verified' and dp.distributor_id is not null
   order by dp.created_at limit 1;
  select p.id into v_pro from public.profiles p where p.role = 'individual' order by p.created_at limit 1;
  select p.id into v_pro2 from public.profiles p where p.role = 'individual' and p.id <> v_pro order by p.created_at limit 1;
  select c.id, c.subcategories[1] into v_cat1, v_sub1
    from public.categories c where cardinality(c.subcategories) >= 1 order by c.id limit 1;
  if v_sup is null or v_pro is null or v_pro2 is null or v_cat1 is null then
    raise exception 'MOBAU_40: faltan datos de partida' using errcode = 'MB998';
  end if;
  if exists (select 1 from public.mobau_admins a where a.user_id in (v_pro, v_pro2, v_sup)) then
    raise exception 'MOBAU_40: una identidad de prueba ya tiene fila en mobau_admins' using errcode = 'MB998';
  end if;
  if exists (select 1 from public.products where id like 'rls40%') then
    raise exception 'MOBAU_40: ya existen productos rls40' using errcode = 'MB998';
  end if;
  select count(*), md5(coalesce(string_agg(to_jsonb(a)::text, '|' order by a.user_id), ''))
    into v_adm_n, v_adm_md5 from public.mobau_admins a;

  -- ---------- SQL auxiliar (como postgres, dentro de cada caso) ----------
  v_admin := format('insert into public.mobau_admins (user_id, granted_note) values (%L, %L)', v_pro, 'Admin temporal de prueba 40');
  v_prod_a := format('insert into public.products (id, name, distributor_id, category_id, subcategory, availability, publication_status) values (%L, %L, %L, %L, %L, %L, %L)',
                     'rls40-a', 'Producto A40 publicado', v_sup_dist, v_cat1, v_sub1, 'en-stock', 'published');
  v_prod_d := format('insert into public.products (id, name, distributor_id, category_id, subcategory, availability, publication_status) values (%L, %L, %L, %L, %L, %L, %L)',
                     'rls40-d', 'Producto D40 borrador', v_sup_dist, v_cat1, v_sub1, 'en-stock', 'draft');
  v_fail_price := 'alter table public.product_prices add constraint rls40_fallo_simulado check (price_amount is distinct from 777.77) not valid';
  f_create := 'insert into public.product_proposals (id, proposal_kind, distributor_id, status, version, proposed_changes, proposed_price_status, proposed_price_amount, submitted_at)'
              || ' values (%L, %L, %L, %L, 1, %L::jsonb, %L, %L::numeric, now())';
  v_c1 := format(f_create, c1, 'create', v_sup_dist, 'submitted',
                 jsonb_build_object('name', 'Producto nuevo 40 cotización', 'description', 'Descripción 40', 'category_id', v_cat1,
                                    'subcategory', v_sub1, 'availability', 'por-confirmar')::text, 'quote_required', null);
  v_c2 := format(f_create, c2, 'create', v_sup_dist, 'submitted',
                 jsonb_build_object('name', 'Producto nuevo 40 publicado', 'description', 'Descripción 40', 'category_id', v_cat1,
                                    'subcategory', v_sub1, 'availability', 'en-stock')::text, 'published', 250);
  v_c3 := format(f_create, c3, 'create', v_sup_dist, 'submitted',
                 jsonb_build_object('name', 'Producto nuevo 40 cotización con importe', 'description', 'Descripción 40', 'category_id', v_cat1,
                                    'subcategory', v_sub1, 'availability', 'bajo-pedido')::text, 'quote_required', 80);
  v_c4 := format(f_create, c4, 'create', v_sup_dist, 'submitted',
                 jsonb_build_object('name', 'Producto nuevo 40 sin precio', 'description', 'Descripción 40', 'category_id', v_cat1,
                                    'subcategory', v_sub1, 'availability', 'por-confirmar')::text, null, null);
  v_c5 := format(f_create, c5, 'create', v_sup_dist, 'submitted',
                 jsonb_build_object('name', 'Producto nuevo 40 atómico', 'description', 'Descripción 40', 'category_id', v_cat1,
                                    'subcategory', v_sub1, 'availability', 'por-confirmar')::text, 'published', 777.77);
  f_update := 'insert into public.product_proposals (id, proposal_kind, product_id, distributor_id, status, version, proposed_changes, product_snapshot, submitted_at)'
              || ' select %L, %L, p.id, p.distributor_id, %L, 1, %L::jsonb,'
              || ' jsonb_build_object(%L, to_jsonb(p), %L, (select to_jsonb(pp) from public.product_prices pp where pp.product_id = p.id), %L, now()), now()'
              || ' from public.products p where p.id = %L';
  v_u1 := format(f_update, u1, 'update', 'submitted', '{"name": "Borrador renombrado 40"}', 'product', 'price', 'taken_at', 'rls40-d');
  v_u2 := format(f_update, u2, 'update', 'submitted', '{"name": "Publicado renombrado 40"}', 'product', 'price', 'taken_at', 'rls40-a');
  -- Cambiar de identidad dentro de un caso (después de la decisión del admin).
  as_pro := format('select set_config(%L, %L, true), set_config(%L, %L, true)',
                   'request.jwt.claims', json_build_object('sub', v_pro2, 'role', 'authenticated', 'aal', 'aal1')::text, 'request.jwt.claim.sub', v_pro2);
  as_sup := format('select set_config(%L, %L, true), set_config(%L, %L, true)',
                   'request.jwt.claims', json_build_object('sub', v_sup, 'role', 'authenticated', 'aal', 'aal1')::text, 'request.jwt.claim.sub', v_sup);
  as_anon := 'select set_config(''request.jwt.claims'', '''', true), set_config(''request.jwt.claim.sub'', '''', true)';

  -- kind: 'count' (última sentencia devuelve un número) | 'exec' (row_count de la última)
  -- expect: número | 'ok' | 'rows=0' | SQLSTATE | 'SQLSTATE:texto'. role '-' = postgres.
  for t in
    select * from (values
      -- ---------- Aprobar un create publica ----------
      ('N01 aprobar create: publicado, activo, campos exactos y enlazado', 'authenticated', v_pro::text, 'aal2', array[v_admin, v_c1]::text[],
         array[format(fn_save, c1, 'approve', null, 1),
               format('select count(*) from public.products p where p.id = %s and p.distributor_id = %L and p.name = %L and p.description = %L'
                      || ' and p.category_id = %L and p.subcategory = %L and p.availability = %L and p.publication_status = %L and p.status = %L'
                      || ' and p.brand is null and p.image_url is null and p.lead_time is null'
                      || ' and %s ->> %L = %L and %s ->> %L = %L and (%s ->> %L)::boolean'
                      || ' and exists (select 1 from public.product_proposals pr where pr.id = %L and pr.status = %L and pr.created_product_id = p.id and pr.reviewed_by = %L)'
                      || ' and exists (select 1 from public.proposal_events e where e.proposal_id = %L and e.to_status = %L and e.actor_kind = %L'
                      || '             and e.payload ->> %L = %L and e.payload ->> %L = p.id)',
                      pid, v_sup_dist, 'Producto nuevo 40 cotización', 'Descripción 40', v_cat1, v_sub1, 'por-confirmar', 'published', 'active',
                      res, 'result', 'approved', res, 'publication_status', 'published', res, 'ok',
                      c1, 'approved', v_pro, c1, 'approved', 'mobau', 'publication_status', 'published', 'created_product_id')]::text[], 'count', '1'),
      ('N02 anon ve el producto creado',                       'authenticated', v_pro::text, 'aal2', array[v_admin, v_c1],
         array[format(fn_save, c1, 'approve', null, 1), 'set local role anon', as_anon,
               format('select count(*) from public.products where id = %s and publication_status = %L', pid, 'published')], 'count', '1'),
      ('N03 profesional lo ve con el filtro del catálogo',     'authenticated', v_pro::text, 'aal2', array[v_admin, v_c1],
         array[format(fn_save, c1, 'approve', null, 1), as_pro,
               format('select count(*) from public.products where id = %s and status = %L and publication_status = %L', pid, 'active', 'published')], 'count', '1'),
      ('N04 profesional: precio bajo cotización, sin importe, sin demo', 'authenticated', v_pro::text, 'aal2', array[v_admin, v_c1],
         array[format(fn_save, c1, 'approve', null, 1), as_pro,
               format('select count(*) from public.catalog_published_prices(array[%s], null, 50) c'
                      || ' where c.price_status = %L and c.price_amount is null and c.currency = %L and c.includes_itbis and not c.es_demo', pid, 'quote_required', 'USD')], 'count', '1'),
      ('N05 anon no puede usar la función de precios',         'authenticated', v_pro::text, 'aal2', array[v_admin, v_c1],
         array[format(fn_save, c1, 'approve', null, 1), 'set local role anon', as_anon,
               format('select count(*) from public.catalog_published_prices(array[%s], null, 50)', pid)], 'exec', '42501'),
      ('N06 anon no puede leer product_prices',                'authenticated', v_pro::text, 'aal2', array[v_admin, v_c1],
         array[format(fn_save, c1, 'approve', null, 1), 'set local role anon', as_anon,
               format('select count(*) from public.product_prices where product_id = %s', pid)], 'exec', '42501'),
      ('N07 profesional no lee la fila interna de product_prices', 'authenticated', v_pro::text, 'aal2', array[v_admin, v_c1],
         array[format(fn_save, c1, 'approve', null, 1), as_pro,
               format('select count(*) from public.product_prices where product_id = %s', pid)], 'count', '0'),
      -- ---------- Precio ----------
      ('N08 create con precio publicado: importe visible en el catálogo', 'authenticated', v_pro::text, 'aal2', array[v_admin, v_c2],
         array[format(fn_save, c2, 'approve', null, 1), as_pro,
               format('select count(*) from public.catalog_published_prices(array[%s], null, 50) c'
                      || ' where c.price_status = %L and c.price_amount = 250 and c.includes_itbis', pid, 'published')], 'count', '1'),
      ('N09 create bajo cotización con importe: se guarda, el catálogo no lo muestra', 'authenticated', v_pro::text, 'aal2', array[v_admin, v_c3],
         array[format(fn_save, c3, 'approve', null, 1),
               format('select set_config(%L, (select price_amount::text from public.product_prices where product_id = %s), true)', 'mobau.test_amount', pid),
               as_pro,
               format('select count(*) from public.catalog_published_prices(array[%s], null, 50) c'
                      || ' where c.price_status = %L and c.price_amount is null and current_setting(%L)::numeric = 80', pid, 'quote_required', 'mobau.test_amount')], 'count', '1'),
      ('N10 create sin precio: publicado, sin fila de precio', 'authenticated', v_pro::text, 'aal2', array[v_admin, v_c4],
         array[format(fn_save, c4, 'approve', null, 1),
               format('select count(*) from public.products p where p.id = %s and p.publication_status = %L'
                      || ' and not exists (select 1 from public.product_prices pp where pp.product_id = p.id)'
                      || ' and not (%s ->> %L)::boolean', pid, 'published', res, 'price_applied')], 'count', '1'),
      ('N11 distribuidor ve su producto publicado y su precio', 'authenticated', v_pro::text, 'aal2', array[v_admin, v_c1],
         array[format(fn_save, c1, 'approve', null, 1), as_sup,
               format('select count(*) from public.products p join public.product_prices pp on pp.product_id = p.id'
                      || ' where p.id = %s and p.publication_status = %L and pp.price_status = %L', pid, 'published', 'quote_required')], 'count', '1'),
      -- ---------- Solo create publica ----------
      ('N12 aprobar update de un borrador: sigue en borrador',  'authenticated', v_pro::text, 'aal2', array[v_admin, v_prod_d, v_u1],
         array[format(fn_save, u1, 'approve', null, 1),
               format('select count(*) from public.products where id = %L and name = %L and publication_status = %L and status = %L'
                      || ' and %s ->> %L = %L and not (%s ? %L)',
                      'rls40-d', 'Borrador renombrado 40', 'draft', 'archived', res, 'result', 'approved', res, 'publication_status')], 'count', '1'),
      ('N13 aprobar update de un publicado: sigue publicado',  'authenticated', v_pro::text, 'aal2', array[v_admin, v_prod_a, v_u2],
         array[format(fn_save, u2, 'approve', null, 1),
               format('select count(*) from public.products where id = %L and name = %L and publication_status = %L and status = %L',
                      'rls40-a', 'Publicado renombrado 40', 'published', 'active')], 'count', '1'),
      -- ---------- Sin aprobación, sin producto ----------
      ('N14 rechazar create: no se crea producto',             'authenticated', v_pro::text, 'aal2', array[v_admin, v_c1],
         array[format(fn_save, c1, 'reject', 'Motivo 40.', 1),
               format('select count(*) from public.product_proposals pr where pr.id = %L and pr.status = %L and pr.created_product_id is null'
                      || ' and not exists (select 1 from public.products where name = %L)', c1, 'rejected', 'Producto nuevo 40 cotización')], 'count', '1'),
      ('N15 solicitar cambios en create: no se crea producto', 'authenticated', v_pro::text, 'aal2', array[v_admin, v_c1],
         array[format(fn_save, c1, 'request_changes', 'Cambios 40.', 1),
               format('select count(*) from public.product_proposals pr where pr.id = %L and pr.status = %L and pr.created_product_id is null'
                      || ' and not exists (select 1 from public.products where name = %L)', c1, 'changes_requested', 'Producto nuevo 40 cotización')], 'count', '1'),
      ('N16 conflicto de versión en create: nada publicado',   'authenticated', v_pro::text, 'aal2', array[v_admin, v_c1],
         array[format(fn_save, c1, 'approve', null, 2),
               format('select count(*) where %s ->> %L = %L and not exists (select 1 from public.products where name = %L)'
                      || ' and exists (select 1 from public.product_proposals where id = %L and status = %L)',
                      res, 'code', 'version_conflict', 'Producto nuevo 40 cotización', c1, 'submitted')], 'count', '1'),
      ('N17 admin sin aal2 no puede aprobar un create',         'authenticated', v_pro::text, 'aal1', array[v_admin, v_c1],
         array[format(fn_call, c1, 'approve', null, 1)], 'exec', '42501:segundo factor'),
      ('N18 fallo al guardar el precio: no queda producto publicado', 'authenticated', v_pro::text, 'aal2', array[v_admin, v_c5, v_fail_price],
         array[format(fn_try, c5, 'approve', null, 1), 'reset role',
               format('select count(*) where current_setting(%L) = %L and not exists (select 1 from public.products where name = %L)'
                      || ' and exists (select 1 from public.product_proposals where id = %L and status = %L and created_product_id is null and reviewed_by is null)'
                      || ' and (select count(*) from public.mobau_moderation_context) = 0',
                      'mobau.test_result', '23514', 'Producto nuevo 40 atómico', c5, 'submitted')], 'count', '1'),
      -- ---------- El distribuidor sigue sin poder publicar ----------
      ('N19 distribuidor no puede publicar su borrador',       'authenticated', v_sup::text, 'aal1', array[v_prod_d],
         array[format('update public.products set publication_status = %L where id = %L', 'published', 'rls40-d')], 'exec', '42501'),
      ('N20 distribuidor no puede insertar un producto publicado', 'authenticated', v_sup::text, 'aal1', null::text[],
         array[format('insert into public.products (name, category_id, publication_status) values (%L, %L, %L)', 'Directo 40', v_cat1, 'published')], 'exec', '42501'),
      -- ---------- Función ----------
      ('F01 función: cuerpo 40-01, SECURITY DEFINER, search_path vacío, propietario postgres', '-', null, null, null::text[],
         array['select count(*) from pg_proc where oid = ''public.moderate_product_proposal(uuid, text, text, integer)''::regprocedure'
               || ' and md5(prosrc) = ''e814b477d0e078872ad085e00157c2c2'' and prosecdef and proconfig @> array[''search_path=""''] and proowner = ''postgres''::regrole'], 'count', '1'),
      ('F02 función: EXECUTE solo authenticated (ni anon ni PUBLIC)', '-', null, null, null::text[],
         array['select count(*) from pg_proc p where p.oid = ''public.moderate_product_proposal(uuid, text, text, integer)''::regprocedure'
               || ' and not has_function_privilege(''anon'', p.oid, ''EXECUTE'') and has_function_privilege(''authenticated'', p.oid, ''EXECUTE'')'
               || ' and not exists (select 1 from aclexplode(p.proacl) a where a.grantee = 0)'], 'count', '1'),
      -- ---------- Estado global ----------
      ('R01 políticas en public = 48',                         '-', null, null, null::text[],
         array['select count(*) from pg_policies where schemaname = ''public'''], 'count', '48'),
      ('R02 mobau_admins idéntica a la línea base',            '-', null, null, null::text[],
         array[format('select count(*) from (select count(*) as n, md5(coalesce(string_agg(to_jsonb(a)::text, %L order by a.user_id), %L)) as fp'
                      || ' from public.mobau_admins a) x where x.n = %s and x.fp = %L', '|', '', v_adm_n, v_adm_md5)], 'count', '1'),
      ('R03 contexto de moderación vacío',                     '-', null, null, null::text[],
         array['select count(*) from public.mobau_moderation_context'], 'count', '0'),
      ('R04 sin productos ni propuestas de prueba',            '-', null, null, null::text[],
         array['select count(*) from public.products where id like ''rls40%'' or name like ''Producto nuevo 40%'''], 'count', '0')
    ) as c(name, role, sub, aal, setup, sql, kind, expect)
  loop
    v_got := null;
    begin
      if t.setup is not null then
        foreach v_stmt in array t.setup loop
          execute v_stmt;
        end loop;
      end if;
      if t.role <> '-' then
        execute format('set local role %I', t.role);
      end if;
      perform set_config('request.jwt.claim.sub', coalesce(t.sub, ''), true);
      perform set_config('request.jwt.claims',
        case when t.sub is null then '' else json_build_object('sub', t.sub, 'role', t.role, 'aal', t.aal)::text end, true);
      for i in 1 .. array_length(t.sql, 1) loop
        if i < array_length(t.sql, 1) then
          execute t.sql[i];
        elsif t.kind = 'count' then
          execute t.sql[i] into v_n;
          v_got := v_n::text;
        else
          execute t.sql[i];
          get diagnostics v_n = row_count;
          v_got := 'ok rows=' || v_n;
        end if;
      end loop;
      raise exception using errcode = 'MB001'; -- deshace el caso
    exception
      when sqlstate 'MB001' then null;
      when others then v_got := sqlstate || ' ' || left(sqlerrm, 160);
    end;

    v_ok := case
      when t.kind = 'exec' and t.expect ~ '^[0-9A-Z]{5}:' then
        v_got like split_part(t.expect, ':', 1) || '%' and v_got ilike '%' || split_part(t.expect, ':', 2) || '%'
      when t.kind = 'exec' and t.expect ~ '^[0-9A-Z]{5}$' then v_got like t.expect || '%'
      when t.expect = 'ok' then v_got like 'ok rows=%' and v_got <> 'ok rows=0'
      when t.expect = 'rows=0' then v_got = 'ok rows=0'
      else v_got = t.expect
    end;
    n_total := n_total + 1;
    if v_ok then n_ok := n_ok + 1; end if;
    r := r || jsonb_build_object('prueba', t.name, 'esperado', t.expect, 'obtenido', v_got, 'ok', v_ok);
  end loop;

  raise exception 'MOBAU_40_PUBLICAR total=% ok=% fallos=% :: %', n_total, n_ok, n_total - n_ok, r::text
    using errcode = 'MB999';
end $$;

ROLLBACK;
