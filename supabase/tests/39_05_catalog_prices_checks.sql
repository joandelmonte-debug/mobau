-- ============================================================
-- PROPUESTA NO EJECUTADA (39-05) — no ejecutar sin aprobación explícita
-- ============================================================
-- 39 · 05 · Pruebas de la superficie segura catalog_published_prices,
-- en una transacción revertida
-- ------------------------------------------------------------
-- Ejecutar después de aplicar 39-05. Vale ANTES y DESPUÉS de 39-06 (la
-- función es SECURITY DEFINER y no depende de las políticas de la tabla).
-- Rol postgres. Mismo patrón que 39_moderation_checks.sql (JWT simulado).
--
-- Identidades (sin crear cuentas ni roles):
--   * Distribuidor A: el distribuidor verificado real.
--   * Profesional: el profesional real (role 'individual').
--   * Distribuidor B: auxiliar sin usuario ('rls395-dist-b').
--   * anon, y authenticated sin sesión (sin sub).
-- Datos auxiliares (solo dentro de cada caso):
--   rls395-a  A · publicado · quote_required, importe guardado 80, fuente demo, nota interna
--   rls395-b  B · publicado · published 50, fuente mobau_estimate, referencia y nota internas
--   rls395-c  A · publicado · published 100, fuente demo
--   rls395-d  A · borrador  · published 70
--   rls395-e  A · publicado · sin precio
--   rls395-f  A · publicado · pending_confirmation, importe guardado 90
--   rls395-g  A · publicado · unavailable, importe guardado 95
-- NADA queda guardado: BEGIN … ROLLBACK, MB001 por caso y MB999 final.
-- ============================================================

BEGIN;

DO $$
declare
  v_sup uuid; v_sup_dist text; v_pro uuid; v_cat1 text;
  n_cat bigint; v_cat_fp text; v_cat_estados text;
  v_dist_b text; v_prod_a text; v_price_a text; v_prod_b text; v_price_b text;
  v_prod_c text; v_price_c text; v_prod_d text; v_price_d text; v_prod_e text;
  v_prod_f text; v_price_f text; v_prod_g text; v_price_g text;
  v_aux text[]; v_ids constant text := 'array[''rls395-a'', ''rls395-b'', ''rls395-c'', ''rls395-f'', ''rls395-g'']';
  r jsonb := '[]'::jsonb; t record; i int;
  v_got text; v_n bigint; v_ok boolean; v_stmt text;
  n_total int := 0; n_ok int := 0;
  -- Huella de una salida con las 7 columnas (alias r).
  fp_sql constant text := 'md5(coalesce(string_agg(concat_ws('':'', r.product_id, coalesce(r.price_amount::text, ''-''), coalesce(r.currency, ''-''), r.price_status,'
                          || ' coalesce(r.includes_itbis::text, ''-''), coalesce(r.itbis_rate::text, ''-''), coalesce(r.es_demo::text, ''-'')), ''|'' order by r.product_id), ''''))';
  -- Lo que el catálogo debe recibir, calculado como postgres sobre la tabla (misma regla que la función).
  ref_sql constant text := 'select pp.product_id, case when pp.price_status = ''published'' then pp.price_amount end as price_amount, pp.currency, pp.price_status,'
                           || ' pp.includes_itbis, pp.itbis_rate, coalesce(pp.price_source = ''demo'', false) as es_demo'
                           || ' from public.product_prices pp join public.products p on p.id = pp.product_id'
                           || ' where p.publication_status = ''published'''
                           || ' and pp.price_status in (''published'', ''quote_required'', ''pending_confirmation'', ''unavailable'')';
  estados_sql constant text := 'coalesce(string_agg(s.price_status || ''='' || s.n, '','' order by s.price_status), ''-'')';
begin
  select dp.user_id, dp.distributor_id into v_sup, v_sup_dist
    from public.distributor_profiles dp join public.profiles p on p.id = dp.user_id
   where p.role = 'supplier' and dp.verification_status = 'verified' and dp.distributor_id is not null
   order by dp.created_at limit 1;
  select p.id into v_pro from public.profiles p where p.role = 'individual' order by p.created_at limit 1;
  select c.id into v_cat1 from public.categories c order by c.id limit 1;
  if v_sup is null or v_pro is null or v_cat1 is null then
    raise exception 'MOBAU_39_05_PRECIOS: faltan datos de partida' using errcode = 'MB998';
  end if;
  if to_regprocedure('public.catalog_published_prices(text[], text, integer)') is null then
    raise exception 'MOBAU_39_05_PRECIOS: falta 39-05' using errcode = 'MB998';
  end if;

  -- Referencia sobre los datos reales (sin auxiliares).
  execute 'select count(*), ' || fp_sql || ' from (' || ref_sql || ') r' into n_cat, v_cat_fp;
  execute 'select ' || estados_sql || ' from (select r.price_status, count(*) n from (' || ref_sql || ') r group by r.price_status) s' into v_cat_estados;
  if n_cat > 1000 then
    raise exception 'MOBAU_39_05_PRECIOS: más de 1000 precios en el catálogo; S17 y S21 deben paginar' using errcode = 'MB998';
  end if;

  v_dist_b  := format('insert into public.distributors (id, name) values (%L, %L)', 'rls395-dist-b', 'Distribuidor B (prueba precios 39)');
  v_prod_a  := format('insert into public.products (id, name, distributor_id, category_id, publication_status) values (%L, %L, %L, %L, %L)', 'rls395-a', 'Producto A precios 39', v_sup_dist, v_cat1, 'published');
  v_price_a := format('insert into public.product_prices (product_id, price_status, price_amount, currency, includes_itbis, price_source, price_note) values (%L, %L, 80, %L, true, %L, %L)',
                      'rls395-a', 'quote_required', 'USD', 'demo', 'Nota interna A');
  v_prod_b  := format('insert into public.products (id, name, distributor_id, category_id, publication_status) values (%L, %L, %L, %L, %L)', 'rls395-b', 'Producto B precios 39', 'rls395-dist-b', v_cat1, 'published');
  v_price_b := format('insert into public.product_prices (product_id, price_status, price_amount, currency, includes_itbis, price_source, price_reference, price_note) values (%L, %L, 50, %L, true, %L, %L, %L)',
                      'rls395-b', 'published', 'USD', 'mobau_estimate', 'Referencia interna B', 'Nota interna B');
  v_prod_c  := format('insert into public.products (id, name, distributor_id, category_id, publication_status) values (%L, %L, %L, %L, %L)', 'rls395-c', 'Producto C precios 39', v_sup_dist, v_cat1, 'published');
  v_price_c := format('insert into public.product_prices (product_id, price_status, price_amount, currency, includes_itbis, price_source) values (%L, %L, 100, %L, true, %L)',
                      'rls395-c', 'published', 'USD', 'demo');
  v_prod_d  := format('insert into public.products (id, name, distributor_id, category_id, publication_status) values (%L, %L, %L, %L, %L)', 'rls395-d', 'Producto D precios 39', v_sup_dist, v_cat1, 'draft');
  v_price_d := format('insert into public.product_prices (product_id, price_status, price_amount, currency, includes_itbis, price_source) values (%L, %L, 70, %L, true, %L)',
                      'rls395-d', 'published', 'USD', 'distributor');
  v_prod_e  := format('insert into public.products (id, name, distributor_id, category_id, publication_status) values (%L, %L, %L, %L, %L)', 'rls395-e', 'Producto E precios 39', v_sup_dist, v_cat1, 'published');
  v_prod_f  := format('insert into public.products (id, name, distributor_id, category_id, publication_status) values (%L, %L, %L, %L, %L)', 'rls395-f', 'Producto F precios 39', v_sup_dist, v_cat1, 'published');
  v_price_f := format('insert into public.product_prices (product_id, price_status, price_amount, currency, includes_itbis, price_source, price_note) values (%L, %L, 90, %L, true, %L, %L)',
                      'rls395-f', 'pending_confirmation', 'USD', 'distributor', 'Nota interna F');
  v_prod_g  := format('insert into public.products (id, name, distributor_id, category_id, publication_status) values (%L, %L, %L, %L, %L)', 'rls395-g', 'Producto G precios 39', v_sup_dist, v_cat1, 'published');
  v_price_g := format('insert into public.product_prices (product_id, price_status, price_amount, currency, includes_itbis, price_source) values (%L, %L, 95, %L, true, %L)',
                      'rls395-g', 'unavailable', 'USD', 'distributor');
  v_aux := array[v_dist_b, v_prod_a, v_price_a, v_prod_b, v_price_b, v_prod_c, v_price_c, v_prod_d, v_price_d, v_prod_e, v_prod_f, v_price_f, v_prod_g, v_price_g];

  for t in
    select * from (values
      -- ========== Estados y columnas ==========
      ('S01 published: devuelve estado e importe',                  'authenticated', v_pro::text, v_aux,
         array[format('select count(*) from public.catalog_published_prices(array[%L, %L]) r where r.price_status = %L and ((r.product_id = %L and r.price_amount = 50) or (r.product_id = %L and r.price_amount = 100))',
                      'rls395-b', 'rls395-c', 'published', 'rls395-b', 'rls395-c')]::text[], 'count', '2'),
      ('S02 quote_required: devuelve estado y price_amount NULL (aunque haya importe guardado)', 'authenticated', v_pro::text, v_aux,
         array[format('select count(*) from public.catalog_published_prices(array[%L]) r where r.price_status = %L and r.price_amount is null', 'rls395-a', 'quote_required')], 'count', '1'),
      ('S03 pending_confirmation: devuelve estado y price_amount NULL', 'authenticated', v_pro::text, v_aux,
         array[format('select count(*) from public.catalog_published_prices(array[%L]) r where r.price_status = %L and r.price_amount is null', 'rls395-f', 'pending_confirmation')], 'count', '1'),
      ('S04 unavailable: devuelve estado y price_amount NULL',      'authenticated', v_pro::text, v_aux,
         array[format('select count(*) from public.catalog_published_prices(array[%L]) r where r.price_status = %L and r.price_amount is null', 'rls395-g', 'unavailable')], 'count', '1'),
      ('S05 producto en borrador con precio publicado: ninguna fila', 'authenticated', v_pro::text, v_aux,
         array[format('select count(*) from public.catalog_published_prices(array[%L])', 'rls395-d')], 'count', '0'),
      ('S06 cada fila tiene exactamente las 7 columnas aprobadas',  'authenticated', v_pro::text, v_aux,
         array['select count(*) from public.catalog_published_prices(' || v_ids || ') r where (select array_agg(k order by k) from jsonb_object_keys(to_jsonb(r)) as k)'
               || format(' = array[%L, %L, %L, %L, %L, %L, %L]', 'currency', 'es_demo', 'includes_itbis', 'itbis_rate', 'price_amount', 'price_status', 'product_id')], 'count', '5'),
      ('S07 sin campos internos: ni columnas ni valores de price_source, price_reference, price_reference_date, price_note', 'authenticated', v_pro::text, v_aux,
         array['select count(*) from public.catalog_published_prices(' || v_ids || ') r where not exists (select 1 from jsonb_each_text(to_jsonb(r)) e'
               || format(' where e.key in (%L, %L, %L, %L) or e.value in (%L, %L, %L, %L, %L, %L, %L))',
                         'price_source', 'price_reference', 'price_reference_date', 'price_note',
                         'Nota interna A', 'Nota interna B', 'Nota interna F', 'Referencia interna B', 'mobau_estimate', 'distributor', 'demo')], 'count', '5'),
      ('S08 es_demo: true si la fuente es demo (c, a), false si no (b, f, g)', 'authenticated', v_pro::text, v_aux,
         array['select count(*) from public.catalog_published_prices(' || v_ids || ') r'
               || format(' where (r.product_id in (%L, %L) and r.es_demo) or (r.product_id in (%L, %L, %L) and not r.es_demo)', 'rls395-a', 'rls395-c', 'rls395-b', 'rls395-f', 'rls395-g')], 'count', '5'),
      ('S09 producto sin precio: ninguna fila y sin error',         'authenticated', v_pro::text, v_aux,
         array[format('select count(*) from public.catalog_published_prices(array[%L])', 'rls395-e')], 'count', '0'),
      -- ========== Acceso ==========
      ('S10 anon no puede ejecutar la función',                     'anon', null, v_aux,
         array['select count(*) from public.catalog_published_prices()'], 'exec', '42501'),
      ('S11 authenticated sin sesión (sin sub): rechazado',         'authenticated', null, v_aux,
         array['select count(*) from public.catalog_published_prices()'], 'exec', '42501'),
      -- ========== Parámetros cerrados y límites ==========
      ('S12 más de 200 ids: rechazado',                             'authenticated', v_pro::text, null::text[],
         array['select count(*) from public.catalog_published_prices(array(select ''x'' || g from generate_series(1, 201) g))'], 'exec', '22023'),
      ('S12b exactamente 200 ids: aceptado',                        'authenticated', v_pro::text, null::text[],
         array['select count(*) from public.catalog_published_prices(array(select ''x'' || g from generate_series(1, 200) g))'], 'count', '0'),
      ('S13a p_limit = 1001: rechazado',                            'authenticated', v_pro::text, null::text[],
         array['select count(*) from public.catalog_published_prices(null, null, 1001)'], 'exec', '22023'),
      ('S13b p_limit = 0: rechazado',                               'authenticated', v_pro::text, null::text[],
         array['select count(*) from public.catalog_published_prices(null, null, 0)'], 'exec', '22023'),
      ('S13c p_after de más de 200 caracteres: rechazado',          'authenticated', v_pro::text, null::text[],
         array['select count(*) from public.catalog_published_prices(null, repeat(''x'', 201), 10)'], 'exec', '22023'),
      ('S14a no acepta un parámetro de columnas',                   'authenticated', v_pro::text, null::text[],
         array['select count(*) from public.catalog_published_prices(p_product_ids => null, p_columns => ''price_note'')'], 'exec', '42883'),
      ('S14b no acepta un parámetro de estado',                     'authenticated', v_pro::text, null::text[],
         array['select count(*) from public.catalog_published_prices(p_product_ids => null, p_status => ''quote_required'')'], 'exec', '42883'),
      ('S15 p_limit = 2 devuelve 2 filas de 5 posibles',            'authenticated', v_pro::text, v_aux,
         array['select count(*) from public.catalog_published_prices(' || v_ids || ', null, 2)'], 'count', '2'),
      ('S16 paginación por product_id: 3 páginas de 2 cubren las 5 filas sin repetir', 'authenticated', v_pro::text, v_aux,
         array['with p1 as (select * from public.catalog_published_prices(' || v_ids || ', null, 2)),'
               || ' p2 as (select * from public.catalog_published_prices(' || v_ids || ', (select max(product_id) from p1), 2)),'
               || ' p3 as (select * from public.catalog_published_prices(' || v_ids || ', (select max(product_id) from p2), 2)),'
               || ' u as (select product_id from p1 union all select product_id from p2 union all select product_id from p3)'
               || ' select case when count(*) = count(distinct product_id) then count(*) else -1 end from u'], 'count', '5'),
      -- ========== Catálogo real: mismo contenido y mismo significado ==========
      ('S17 catálogo real: recuento y huella iguales a la referencia (estado, importe solo si published, es_demo)', 'authenticated', v_pro::text, null::text[],
         array[format('select count(*) from (select count(*) as n, ' || fp_sql || ' as fp from public.catalog_published_prices() r) x where x.n = %s and x.fp = %L', n_cat, v_cat_fp)], 'count', '1'),
      ('S18 catálogo real: ningún estado no publicado trae importe', 'authenticated', v_pro::text, null::text[],
         array['select count(*) from public.catalog_published_prices() r where r.price_status <> ''published'' and r.price_amount is not null'], 'count', '0'),
      ('S19 catálogo real: mismo recuento por estado que la referencia', 'authenticated', v_pro::text, null::text[],
         array[format('select count(*) from (select ' || estados_sql || ' as e from (select r.price_status, count(*) n from public.catalog_published_prices() r group by r.price_status) s) x where x.e = %L', v_cat_estados)], 'count', '1'),
      ('S20 catálogo real: la página siguiente empieza después de p_after', 'authenticated', v_pro::text, null::text[],
         array['with a as (select * from public.catalog_published_prices(null, null, 1)), b as (select * from public.catalog_published_prices(null, (select product_id from a), 1))'
               || ' select count(*) from b where b.product_id > (select product_id from a)'], 'count', case when n_cat >= 2 then '1' else '0' end),
      ('S21 el distribuidor recibe el mismo catálogo que el profesional', 'authenticated', v_sup::text, null::text[],
         array[format('select count(*) from (select count(*) as n, ' || fp_sql || ' as fp from public.catalog_published_prices() r) x where x.n = %s and x.fp = %L', n_cat, v_cat_fp)], 'count', '1'),
      -- ========== Definición de la función ==========
      ('R01 EXECUTE solo authenticated (ni anon ni PUBLIC)',        '-', null, null::text[],
         array['select count(*) from pg_proc p where p.oid = ''public.catalog_published_prices(text[], text, integer)''::regprocedure'
               || ' and not has_function_privilege(''anon'', p.oid, ''EXECUTE'') and has_function_privilege(''authenticated'', p.oid, ''EXECUTE'')'
               || ' and not exists (select 1 from aclexplode(p.proacl) a where a.grantee = 0 and a.privilege_type = ''EXECUTE'')'], 'count', '1'),
      ('R02 SECURITY DEFINER, search_path vacío, propietario postgres', '-', null, null::text[],
         array['select count(*) from pg_proc p where p.oid = ''public.catalog_published_prices(text[], text, integer)''::regprocedure'
               || ' and p.prosecdef and p.proconfig @> array[''search_path=""''] and p.proowner = ''postgres''::regrole'], 'count', '1'),
      ('R03 una sola firma y exactamente las 7 columnas',          '-', null, null::text[],
         array['select count(*) from pg_proc p where p.pronamespace = ''public''::regnamespace and p.proname = ''catalog_published_prices'''
               || ' and array_to_string(p.proargnames, '','') = ''p_product_ids,p_after,p_limit,product_id,price_amount,currency,price_status,includes_itbis,itbis_rate,es_demo'''
               || ' and (select count(*) from pg_proc q where q.pronamespace = ''public''::regnamespace and q.proname = ''catalog_published_prices'') = 1'], 'count', '1'),
      ('R04 ningún admin permanente',                               '-', null, null::text[],
         array['select count(*) from public.mobau_admins'], 'count', '0')
    ) as c(name, role, sub, setup, sql, kind, expect)
  loop
    v_got := null;
    begin
      if t.setup is not null then
        foreach v_stmt in array t.setup loop execute v_stmt; end loop;
      end if;
      if t.role <> '-' then execute format('set local role %I', t.role); end if;
      perform set_config('request.jwt.claim.sub', coalesce(t.sub, ''), true);
      perform set_config('request.jwt.claims',
        case when t.sub is null then '' else json_build_object('sub', t.sub, 'role', t.role, 'aal', 'aal1')::text end, true);
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

  raise exception 'MOBAU_39_05_PRECIOS total=% ok=% fallos=% :: %', n_total, n_ok, n_total - n_ok, r::text
    using errcode = 'MB999';
end $$;

ROLLBACK;
