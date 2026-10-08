-- ============================================================
-- PROPUESTA NO EJECUTADA (39-06) — no ejecutar sin aprobación explícita
-- ============================================================
-- 39 · 06 · Pruebas de privacidad de product_prices, en una transacción
-- revertida
-- ------------------------------------------------------------
-- Ejecutar SOLO después de aplicar 39-05 y 39-06. Rol postgres. Mismo patrón
-- que 39_moderation_checks.sql (JWT simulado: NO valida MFA real).
-- La superficie segura se prueba en 39_05_catalog_prices_checks.sql (que se
-- vuelve a ejecutar tras 39-06); aquí solo Q21 y Q22 la cruzan con la tabla
-- cerrada.
-- Q19 añade y retira una restricción NOT VALID en product_prices dentro de
-- su subtransacción: NO ejecutar con el piloto en uso.
--
-- Identidades (sin crear cuentas ni roles):
--   * Distribuidor A: el distribuidor verificado real.
--   * Profesional: el profesional real (role 'individual').
--   * Admin temporal: el profesional, dado de alta en mobau_admins SOLO
--     dentro de la subtransacción del caso.
--   * Distribuidor B: auxiliar sin usuario ('rls395-dist-b').
--   * anon.
-- Datos auxiliares (solo dentro de cada caso):
--   rls395-a  A · publicado · precio quote_required con importe 80 + nota interna
--   rls395-b  B · publicado · precio published 50, fuente mobau_estimate + referencia y nota
--   rls395-c  A · publicado · precio published 100, fuente demo
--   rls395-e  A · publicado · sin precio
--   rls395-h  B · publicado · precio quote_required con importe 60 + nota interna
-- Admins reales: mobau_admins puede tener filas reales. Precondición: ni el
-- profesional ni el distribuidor A tienen fila en mobau_admins (activa o
-- revocada); el profesional se da de alta aquí como admin temporal. Antes de
-- los casos se toma una línea base completa de mobau_admins (recuento y MD5
-- de todas las filas y columnas, sin filtrar ninguna) y R05 exige que al
-- final sea idéntica.
-- NADA queda guardado: BEGIN … ROLLBACK, MB001 por caso y MB999 final.
-- ============================================================

BEGIN;

DO $$
declare
  v_sup uuid; v_sup_dist text; v_pro uuid; v_cat1 text; v_sub1 text;
  n_own bigint;
  q1 constant text := '00000000-0000-4000-8000-000000395a01';  -- update de A: precio published 120 (aprobable)
  q2 constant text := '00000000-0000-4000-8000-000000395a02';  -- update de A: precio 777.77 (fallo forzado)
  v_admin text; v_admin_rev text;
  v_prod_a text; v_price_a text; v_dist_b text; v_prod_b text; v_price_b text;
  v_prod_c text; v_price_c text; v_prod_e text; v_prod_h text; v_price_h text;
  v_q1 text; v_q2 text; v_fail text;
  r jsonb := '[]'::jsonb; t record; i int;
  v_got text; v_n bigint; v_ok boolean; v_stmt text;
  n_total int := 0; n_ok int := 0;
  v_adm_n bigint; v_adm_md5 text;  -- línea base de mobau_admins (como postgres, antes de los casos)
  fn_save constant text := 'select set_config(''mobau.test_result'', public.moderate_product_proposal(%L::uuid, %L, %L, %s)::text, true)';
  fn_try constant text := 'do $t$ begin perform public.moderate_product_proposal(%L::uuid, %L, %L, %s);'
                          || ' perform set_config(''mobau.test_result'', ''sin error'', true);'
                          || ' exception when others then perform set_config(''mobau.test_result'', sqlstate, true); end $t$';
begin
  select dp.user_id, dp.distributor_id into v_sup, v_sup_dist
    from public.distributor_profiles dp join public.profiles p on p.id = dp.user_id
   where p.role = 'supplier' and dp.verification_status = 'verified' and dp.distributor_id is not null
   order by dp.created_at limit 1;
  select p.id into v_pro from public.profiles p where p.role = 'individual' order by p.created_at limit 1;
  select c.id, c.subcategories[1] into v_cat1, v_sub1
    from public.categories c where cardinality(c.subcategories) >= 1 order by c.id limit 1;
  if v_sup is null or v_pro is null or v_cat1 is null then
    raise exception 'MOBAU_39_06_PRECIOS: faltan datos de partida' using errcode = 'MB998';
  end if;
  if exists (select 1 from public.mobau_admins a where a.user_id in (v_pro, v_sup)) then
    raise exception 'MOBAU_39_06_PRECIOS: el profesional o el distribuidor de prueba ya tiene fila en mobau_admins' using errcode = 'MB998';
  end if;

  -- Línea base de mobau_admins: todas las filas y columnas, sin filtrar ninguna.
  select count(*), md5(coalesce(string_agg(to_jsonb(a)::text, '|' order by a.user_id), ''))
    into v_adm_n, v_adm_md5 from public.mobau_admins a;

  -- Referencias calculadas como postgres sobre los datos reales (sin auxiliares).
  select count(*) into n_own from public.product_prices pp join public.products p on p.id = pp.product_id
   where p.distributor_id = v_sup_dist;

  v_admin := format('insert into public.mobau_admins (user_id, granted_note) values (%L, %L)', v_pro, 'Admin temporal precios 39');
  v_admin_rev := format('insert into public.mobau_admins (user_id, granted_note, revoked_at) values (%L, %L, now())', v_pro, 'Admin revocado precios 39');
  v_prod_a := format('insert into public.products (id, name, distributor_id, category_id, subcategory, availability, publication_status) values (%L, %L, %L, %L, %L, %L, %L)',
                     'rls395-a', 'Producto A precios 39', v_sup_dist, v_cat1, v_sub1, 'en-stock', 'published');
  v_price_a := format('insert into public.product_prices (product_id, price_status, price_amount, currency, includes_itbis, price_source, price_note) values (%L, %L, 80, %L, true, %L, %L)',
                      'rls395-a', 'quote_required', 'USD', 'demo', 'Nota interna A');
  v_dist_b := format('insert into public.distributors (id, name) values (%L, %L)', 'rls395-dist-b', 'Distribuidor B (prueba precios 39)');
  v_prod_b := format('insert into public.products (id, name, distributor_id, category_id, publication_status) values (%L, %L, %L, %L, %L)',
                     'rls395-b', 'Producto B precios 39', 'rls395-dist-b', v_cat1, 'published');
  v_price_b := format('insert into public.product_prices (product_id, price_status, price_amount, currency, includes_itbis, price_source, price_reference, price_note) values (%L, %L, 50, %L, true, %L, %L, %L)',
                      'rls395-b', 'published', 'USD', 'mobau_estimate', 'Referencia interna B', 'Nota interna B');
  v_prod_c := format('insert into public.products (id, name, distributor_id, category_id, publication_status) values (%L, %L, %L, %L, %L)',
                     'rls395-c', 'Producto C precios 39', v_sup_dist, v_cat1, 'published');
  v_price_c := format('insert into public.product_prices (product_id, price_status, price_amount, currency, includes_itbis, price_source) values (%L, %L, 100, %L, true, %L)',
                      'rls395-c', 'published', 'USD', 'demo');
  v_prod_e := format('insert into public.products (id, name, distributor_id, category_id, publication_status) values (%L, %L, %L, %L, %L)',
                     'rls395-e', 'Producto E precios 39', v_sup_dist, v_cat1, 'published');
  v_prod_h := format('insert into public.products (id, name, distributor_id, category_id, publication_status) values (%L, %L, %L, %L, %L)',
                     'rls395-h', 'Producto H precios 39', 'rls395-dist-b', v_cat1, 'published');
  v_price_h := format('insert into public.product_prices (product_id, price_status, price_amount, currency, includes_itbis, price_source, price_note) values (%L, %L, 60, %L, true, %L, %L)',
                      'rls395-h', 'quote_required', 'USD', 'distributor', 'Nota interna H');
  v_q1 := format('insert into public.product_proposals (id, proposal_kind, product_id, distributor_id, status, version, proposed_changes, proposed_price_status, proposed_price_amount, product_snapshot, submitted_at)'
                 || ' select %L, %L, p.id, p.distributor_id, %L, 1, %L::jsonb, %L, 120,'
                 || ' jsonb_build_object(%L, to_jsonb(p), %L, (select to_jsonb(pp) from public.product_prices pp where pp.product_id = p.id), %L, now()), now()'
                 || ' from public.products p where p.id = %L',
                 q1, 'update', 'submitted', '{}', 'published', 'product', 'price', 'taken_at', 'rls395-a');
  v_q2 := format('insert into public.product_proposals (id, proposal_kind, product_id, distributor_id, status, version, proposed_changes, proposed_price_status, proposed_price_amount, product_snapshot, submitted_at)'
                 || ' select %L, %L, p.id, p.distributor_id, %L, 1, %L::jsonb, %L, 777.77,'
                 || ' jsonb_build_object(%L, to_jsonb(p), %L, (select to_jsonb(pp) from public.product_prices pp where pp.product_id = p.id), %L, now()), now()'
                 || ' from public.products p where p.id = %L',
                 q2, 'update', 'submitted', '{}', 'published', 'product', 'price', 'taken_at', 'rls395-a');
  v_fail := 'alter table public.product_prices add constraint rls395_fallo_simulado check (price_amount is distinct from 777.77) not valid';

  for t in
    select * from (values
      -- ========== Tabla privada (39-06) ==========
      ('Q01 anon sin permisos: no lee product_prices',         'anon', null::text, null::text, array[v_dist_b, v_prod_b, v_price_b]::text[],
         array['select count(*) from public.product_prices']::text[], 'exec', '42501'),
      ('Q02 anon no escribe product_prices',                   'anon', null, null, array[v_dist_b, v_prod_b],
         array[format('insert into public.product_prices (product_id, price_status) values (%L, %L)', 'rls395-b', 'quote_required')], 'exec', '42501'),
      ('Q03 profesional no lee ninguna fila directamente',     'authenticated', v_pro::text, 'aal1', array[v_prod_a, v_price_a, v_dist_b, v_prod_b, v_price_b, v_prod_c, v_price_c],
         array['select count(*) from public.product_prices'], 'count', '0'),
      ('Q04 profesional no lee directamente el precio publicado de B', 'authenticated', v_pro::text, 'aal1', array[v_dist_b, v_prod_b, v_price_b],
         array[format('select count(*) from public.product_prices where product_id = %L', 'rls395-b')], 'count', '0'),
      ('Q05 profesional no lee directamente el importe no publicado de A', 'authenticated', v_pro::text, 'aal1', array[v_prod_a, v_price_a],
         array[format('select count(price_amount) from public.product_prices where product_id = %L', 'rls395-a')], 'count', '0'),
      ('Q06 profesional no escribe product_prices',            'authenticated', v_pro::text, 'aal1', array[v_dist_b, v_prod_b],
         array[format('insert into public.product_prices (product_id, price_status) values (%L, %L)', 'rls395-b', 'quote_required')], 'exec', '42501'),
      ('Q07 distribuidor lee exactamente sus precios reales',  'authenticated', v_sup::text, 'aal1', array[v_dist_b, v_prod_b, v_price_b],
         array['select count(*) from public.product_prices'], 'count', n_own::text),
      ('Q08 distribuidor lee su estado no publicado, su importe y su nota interna', 'authenticated', v_sup::text, 'aal1', array[v_prod_a, v_price_a],
         array[format('select count(*) from public.product_prices where product_id = %L and price_status = %L and price_amount = 80 and price_note is not null and price_source is not null', 'rls395-a', 'quote_required')], 'count', '1'),
      ('Q09 distribuidor no lee el precio de otra empresa',    'authenticated', v_sup::text, 'aal1', array[v_dist_b, v_prod_b, v_price_b],
         array[format('select count(*) from public.product_prices where product_id = %L', 'rls395-b')], 'count', '0'),
      ('Q10 distribuidor no lee campos internos ajenos',       'authenticated', v_sup::text, 'aal1', array[v_dist_b, v_prod_b, v_price_b],
         array[format('select count(*) from public.product_prices where product_id = %L and (price_note is not null or price_reference is not null or price_source is not null)', 'rls395-b')], 'count', '0'),
      ('Q11 distribuidor no inserta precios',                  'authenticated', v_sup::text, 'aal1', array[v_prod_e],
         array[format('insert into public.product_prices (product_id, price_status) values (%L, %L)', 'rls395-e', 'quote_required')], 'exec', '42501'),
      ('Q12 distribuidor no actualiza precios',                'authenticated', v_sup::text, 'aal1', array[v_prod_a, v_price_a],
         array[format('update public.product_prices set price_amount = 1 where product_id = %L', 'rls395-a')], 'exec', '42501'),
      ('Q12b distribuidor no borra precios',                   'authenticated', v_sup::text, 'aal1', array[v_prod_a, v_price_a],
         array[format('delete from public.product_prices where product_id = %L', 'rls395-a')], 'exec', '42501'),
      ('Q13 admin con aal2 lee precio y campos internos ajenos', 'authenticated', v_pro::text, 'aal2', array[v_admin, v_dist_b, v_prod_b, v_price_b],
         array[format('select count(*) from public.product_prices where product_id = %L and price_amount = 50 and price_note is not null and price_reference is not null', 'rls395-b')], 'count', '1'),
      ('Q14 admin con aal2 lee el importe no publicado de A',  'authenticated', v_pro::text, 'aal2', array[v_admin, v_prod_a, v_price_a],
         array[format('select count(price_amount) from public.product_prices where product_id = %L', 'rls395-a')], 'count', '1'),
      ('Q15 admin sin aal2 no lee precios ajenos',             'authenticated', v_pro::text, 'aal1', array[v_admin, v_prod_a, v_price_a, v_dist_b, v_prod_b, v_price_b],
         array['select count(*) from public.product_prices'], 'count', '0'),
      ('Q16 admin revocado no lee precios',                    'authenticated', v_pro::text, 'aal2', array[v_admin_rev, v_dist_b, v_prod_b, v_price_b],
         array['select count(*) from public.product_prices'], 'count', '0'),
      ('Q17 admin con aal2 no escribe precios directamente',   'authenticated', v_pro::text, 'aal2', array[v_admin, v_prod_a, v_price_a],
         array[format('update public.product_prices set price_amount = 1 where product_id = %L', 'rls395-a')], 'exec', '42501'),
      ('Q18 la moderación aplica el precio propuesto',         'authenticated', v_pro::text, 'aal2', array[v_admin, v_prod_a, v_price_a, v_q1],
         array[format(fn_save, q1, 'approve', null, 1), 'reset role',
               format('select count(*) from public.product_prices where product_id = %L and price_status = %L and price_amount = 120 and price_source = %L'
                      || ' and (current_setting(%L)::jsonb ->> %L)::boolean', 'rls395-a', 'published', 'distributor', 'mobau.test_result', 'ok')], 'count', '1'),
      ('Q19 la moderación es atómica: un fallo no cambia el precio', 'authenticated', v_pro::text, 'aal2', array[v_admin, v_prod_a, v_price_a, v_q2, v_fail],
         array[format(fn_try, q2, 'approve', null, 1), 'reset role',
               format('select count(*) from public.product_prices pp, public.product_proposals pr where pp.product_id = %L and pr.id = %L'
                      || ' and current_setting(%L) = %L and to_jsonb(pp) = pr.product_snapshot -> %L and pr.status = %L',
                      'rls395-a', q2, 'mobau.test_result', '23514', 'price', 'submitted')], 'count', '1'),
      ('Q20 el snapshot del distribuidor conserva su precio',  'authenticated', v_sup::text, 'aal1', array[v_prod_a, v_price_a],
         array[format('insert into public.product_proposals (proposal_kind, product_id, proposed_changes) values (%L, %L, %L)', 'update', 'rls395-a', '{"brand": "Marca precios 39"}'),
               format('with u as (update public.product_proposals set status = %L where product_id = %L and status = %L returning (product_snapshot -> %L ->> %L) as amount)'
                      || ' select count(*) from u where amount::numeric = 80', 'submitted', 'rls395-a', 'draft', 'price', 'price_amount')], 'count', '1'),
      -- ========== Cruce con la superficie (tabla ya cerrada) ==========
      ('Q21 profesional: la superficie sigue dando el precio publicado de B con la tabla cerrada', 'authenticated', v_pro::text, 'aal1', array[v_dist_b, v_prod_b, v_price_b],
         array[format('select count(*) from public.catalog_published_prices(array[%L]) r where r.price_status = %L and r.price_amount = 50', 'rls395-b', 'published')], 'count', '1'),
      ('Q22 distribuidor A: de otra empresa solo recibe el estado, sin importe ni nota', 'authenticated', v_sup::text, 'aal1', array[v_dist_b, v_prod_h, v_price_h],
         array[format('select count(*) from public.catalog_published_prices(array[%L]) r where r.price_status = %L and r.price_amount is null'
                      || ' and not (to_jsonb(r) ?| array[%L, %L])', 'rls395-h', 'quote_required', 'price_note', 'price_source')], 'count', '1'),
      -- ========== Estado global ==========
      ('R01 anon sin ningún permiso sobre product_prices',     '-', null, null, null::text[],
         array['select count(*) from information_schema.role_table_grants where table_schema = ''public'' and table_name = ''product_prices'' and grantee = ''anon'''], 'count', '0'),
      ('R02 authenticated solo SELECT sobre product_prices',   '-', null, null, null::text[],
         array['select count(*) from information_schema.role_table_grants where table_schema = ''public'' and table_name = ''product_prices'' and grantee = ''authenticated'' and privilege_type <> ''SELECT'''], 'count', '0'),
      ('R03 políticas de product_prices: exactamente las 4 esperadas', '-', null, null, null::text[],
         array['select count(*) from pg_policies where schemaname = ''public'' and tablename = ''product_prices'' and policyname in (''product_prices_insert_own'', ''product_prices_select_mobau'', ''product_prices_select_own'', ''product_prices_update_own'')'
               || ' and (select count(*) from pg_policies where schemaname = ''public'' and tablename = ''product_prices'') = 4'], 'count', '4'),
      ('R04 políticas en public = 48',                         '-', null, null, null::text[],
         array['select count(*) from pg_policies where schemaname = ''public'''], 'count', '48'),
      ('R05 mobau_admins idéntica a la línea base (ningún admin de prueba queda)', '-', null, null, null::text[],
         array[format('select count(*) from (select count(*) as n, md5(coalesce(string_agg(to_jsonb(a)::text, %L order by a.user_id), %L)) as fp'
                      || ' from public.mobau_admins a) x where x.n = %s and x.fp = %L', '|', '', v_adm_n, v_adm_md5)], 'count', '1')
    ) as c(name, role, sub, aal, setup, sql, kind, expect)
  loop
    v_got := null;
    begin
      if t.setup is not null then
        foreach v_stmt in array t.setup loop execute v_stmt; end loop;
      end if;
      if t.role <> '-' then execute format('set local role %I', t.role); end if;
      perform set_config('request.jwt.claim.sub', coalesce(t.sub, ''), true);
      perform set_config('request.jwt.claims',
        case when t.sub is null then '' else json_build_object('sub', t.sub, 'role', t.role, 'aal', t.aal)::text end, true);
      for i in 1 .. array_length(t.sql, 1) loop
        if i < array_length(t.sql, 1) then
          execute t.sql[i];
        elsif t.kind = 'count' then
          execute t.sql[i] into v_n; v_got := v_n::text;
        else
          execute t.sql[i]; get diagnostics v_n = row_count; v_got := 'ok rows=' || v_n;
        end if;
      end loop;
      raise exception using errcode = 'MB001';
    exception
      when sqlstate 'MB001' then null;
      when others then v_got := sqlstate || ' ' || left(sqlerrm, 160);
    end;
    v_ok := case
      when t.kind = 'exec' and t.expect ~ '^[0-9A-Z]{5}$' then v_got like t.expect || '%'
      else v_got = t.expect
    end;
    n_total := n_total + 1;
    if v_ok then n_ok := n_ok + 1; end if;
    r := r || jsonb_build_object('prueba', t.name, 'esperado', t.expect, 'obtenido', v_got, 'ok', v_ok);
  end loop;

  raise exception 'MOBAU_39_06_PRECIOS total=% ok=% fallos=% :: %', n_total, n_ok, n_total - n_ok, r::text
    using errcode = 'MB999';
end $$;

ROLLBACK;
