-- ============================================================
-- PROPUESTA NO EJECUTADA (41 · V2 · datos reales) — no ejecutar sin aprobación explícita
-- ============================================================
-- 41 · V2 · Superficie de catálogo (41-02) con los DATOS REALES, sin
-- productos ni precios auxiliares, en una transacción revertida.
-- ------------------------------------------------------------
-- Ejecutar después de 41-01 y 41-02. Rol postgres; JWT simulado como en 39.
--
-- Seis roles (todas las cuentas ya existen; no se crea ninguna):
--   anon                         sin JWT                         (sin auxiliares)
--   profesional                  1.er perfil 'individual'         (sin auxiliares)
--   distribuidor dueño (A)       el distribuidor verificado real  (sin auxiliares)
--   otro distribuidor (B)        2.º perfil 'individual', vinculado SOLO dentro
--                                del caso a 'rls41r-dist-b' (empresa sin productos)
--   Mobau sin AAL2 / con AAL2    3.er perfil 'individual', admin temporal SOLO
--                                dentro del caso
-- Los auxiliares de identidad no crean productos ni precios: catalog_products
-- es exactamente el catálogo real en los seis roles. La empresa auxiliar de B
-- sí entra en catalog_version (distribuidores): su referencia se calcula como
-- postgres con el mismo auxiliar (subtransacción revertida).
--
-- Grupos:
--   RV (6)  catalog_products = consulta actual del catálogo (script.js:482) =
--           referencia real tomada como postgres (recuento y huella, 21 columnas)
--   KV (6)  catalog_version() = referencia real como postgres
--   LV (6)  cada fila de catalog_products tiene exactamente las 21 claves y
--           ninguna de las 7 de ciclo de vida
--   PV (6)  catalog_published_prices() = regla de 39-05 sobre los datos reales
--           (5 roles autenticados); anon 42501
--   SV (1)  service_role no puede leer catalog_products (42501)
--   ZV (3)  sin restos; admins y proyección de products iguales al empezar
-- NADA queda guardado: BEGIN … ROLLBACK, MB001 por caso y MB999 final.
-- ============================================================

BEGIN;

DO $$
declare
  v_sup uuid; v_sup_dist text; v_pro uuid; v_pro2 uuid; v_pro3 uuid;
  v_aux_b text[]; v_aux_m text[];
  ref_cat_n bigint; ref_cat_fp text; ref_ver text; ref_ver_b text; ref_price_n bigint; ref_price_fp text;
  v_real_n bigint; v_real_fp text; v_adm_n bigint; v_adm_md5 text;
  q_rv text; q_lv text; q_pv text;
  r jsonb := '[]'::jsonb; t record; i int;
  v_got text; v_n bigint; v_ok boolean; v_stmt text;
  n_total int := 0; n_ok int := 0;
begin
  -- ---------- datos de partida (lectura como postgres) ----------
  select dp.user_id, dp.distributor_id into v_sup, v_sup_dist
    from public.distributor_profiles dp join public.profiles p on p.id = dp.user_id
   where p.role = 'supplier' and dp.verification_status = 'verified' and dp.distributor_id is not null
   order by dp.created_at limit 1;
  select p.id into v_pro from public.profiles p
   where p.role = 'individual' and not exists (select 1 from public.mobau_admins a where a.user_id = p.id)
     and not exists (select 1 from public.distributor_profiles d where d.user_id = p.id)
   order by p.created_at limit 1;
  select p.id into v_pro2 from public.profiles p
   where p.role = 'individual' and p.id <> v_pro and not exists (select 1 from public.mobau_admins a where a.user_id = p.id)
     and not exists (select 1 from public.distributor_profiles d where d.user_id = p.id)
   order by p.created_at limit 1;
  select p.id into v_pro3 from public.profiles p
   where p.role = 'individual' and p.id not in (v_pro, v_pro2) and not exists (select 1 from public.mobau_admins a where a.user_id = p.id)
     and not exists (select 1 from public.distributor_profiles d where d.user_id = p.id)
   order by p.created_at limit 1;
  if v_sup is null or v_pro is null or v_pro2 is null or v_pro3 is null then
    raise exception 'MOBAU_41_V2_REAL: faltan datos de partida' using errcode = 'MB998';
  end if;
  if to_regclass('public.catalog_products') is null or to_regprocedure('public.catalog_version()') is null or to_regnamespace('mobau_private') is null then
    raise exception 'MOBAU_41_V2_REAL: faltan 41-01 o 41-02' using errcode = 'MB998';
  end if;

  select count(*), md5(coalesce(string_agg(to_jsonb(a)::text, '|' order by a.user_id), ''))
    into v_adm_n, v_adm_md5 from public.mobau_admins a;
  execute 'select count(*), md5(coalesce(string_agg(to_jsonb(r)::text, ''|'' order by r.id), '''')) from (select id, name, distributor_id, brand, category_id, subcategory, use_context, space, availability, description, measurements, materials, finishes, lead_time, icon, technical_sheet_url, cad_bim_3d_url, image_url, created_at, status, updated_at, publication_status from public.products) r' into v_real_n, v_real_fp;

  -- ---------- referencias reales (como postgres, sin auxiliares) ----------
  execute 'select count(*), md5(coalesce(string_agg(to_jsonb(r)::text, ''|'' order by r.id), '''')) from (select id, name, brand, distributor_id, category_id, subcategory, use_context, space, availability, description, measurements, materials, finishes, lead_time, icon, image_url, technical_sheet_url, cad_bim_3d_url, status, created_at, updated_at from public.products where status = ''active'' and publication_status = ''published'') r' into ref_cat_n, ref_cat_fp;
  ref_ver := public.catalog_version();
  execute 'select count(*), md5(coalesce(string_agg(concat_ws('':'', r.product_id, coalesce(r.price_amount::text, ''-''), coalesce(r.currency, ''-''), r.price_status, coalesce(r.includes_itbis::text, ''-''), coalesce(r.itbis_rate::text, ''-''), coalesce(r.es_demo::text, ''-'')), ''|'' order by r.product_id), '''')) from (select pp.product_id, case when pp.price_status = ''published'' then pp.price_amount end as price_amount, pp.currency, pp.price_status, pp.includes_itbis, pp.itbis_rate, coalesce(pp.price_source = ''demo'', false) as es_demo from public.product_prices pp join public.products p on p.id = pp.product_id where p.publication_status = ''published'' and pp.price_status in (''published'', ''quote_required'', ''pending_confirmation'', ''unavailable'')) r' into ref_price_n, ref_price_fp;
  if ref_cat_n = 0 or ref_ver !~ '^[0-9a-f]{32}$' then
    raise exception 'MOBAU_41_V2_REAL: catálogo real vacío o catalog_version inválido' using errcode = 'MB998';
  end if;

  -- ---------- auxiliares de identidad (como postgres, dentro de cada caso) ----------
  v_aux_b := array[
    format('insert into public.distributors (id, name) values (%L, %L)', 'rls41r-dist-b', 'Distribuidor B (prueba 41 real)'),
    format('insert into public.distributor_profiles (user_id, nombre_comercial, razon_social, rnc, direccion_fiscal, telefono, email_contacto, nombre_contacto, cargo_contacto, verification_status, verified_at, distributor_id)' || ' values (%L, %L, %L, %L, %L, %L, %L, %L, %L, %L, now(), %L)', v_pro2, 'Prueba 41R B', 'Prueba 41R B SRL', '999999942', 'Calle de prueba 41R', '0000000042', 'prueba41r@example.invalid', 'Contacto prueba 41R', 'Prueba', 'verified', 'rls41r-dist-b')
  ];
  v_aux_m := array[
    format('insert into public.mobau_admins (user_id, granted_note) values (%L, %L)', v_pro3, 'Admin temporal de prueba 41 real')
  ];
  begin
    foreach v_stmt in array v_aux_b loop execute v_stmt; end loop;
    ref_ver_b := public.catalog_version();
    raise exception using errcode = 'MB001';
  exception when sqlstate 'MB001' then null;
  end;

  -- ---------- consultas de los casos ----------
  q_rv := format('select count(*) from (select (select count(*) from public.catalog_products) as n,'
    || ' (select md5(coalesce(string_agg(to_jsonb(r)::text, ''|'' order by r.id), '''')) from (select id, name, brand, distributor_id, category_id, subcategory, use_context, space, availability, description, measurements, materials, finishes, lead_time, icon, image_url, technical_sheet_url, cad_bim_3d_url, status, created_at, updated_at from public.catalog_products) r) as fv,'
    || ' (select md5(coalesce(string_agg(to_jsonb(r)::text, ''|'' order by r.id), '''')) from (select id, name, brand, distributor_id, category_id, subcategory, use_context, space, availability, description, measurements, materials, finishes, lead_time, icon, image_url, technical_sheet_url, cad_bim_3d_url, status, created_at, updated_at from public.products where status = ''active'' and publication_status = ''published'') r) as fo) x'
    || ' where x.n = %s and x.fv = %L and x.fo = %L', ref_cat_n, ref_cat_fp, ref_cat_fp);
  q_lv := 'select count(*) from public.catalog_products c where (select count(*) from jsonb_object_keys(to_jsonb(c))) <> 21'
    || ' or to_jsonb(c) ?| array[''retired_at'', ''retired_by'', ''retired_reason'', ''trashed_at'', ''trashed_by'', ''trash_from'', ''purge_after'']';
  -- (que el catálogo no esté vacío lo exige RV: n = ref_cat_n > 0)
  q_pv := format('select count(*) from (select count(*) as n, md5(coalesce(string_agg(concat_ws('':'', r.product_id, coalesce(r.price_amount::text, ''-''), coalesce(r.currency, ''-''), r.price_status, coalesce(r.includes_itbis::text, ''-''), coalesce(r.itbis_rate::text, ''-''), coalesce(r.es_demo::text, ''-'')), ''|'' order by r.product_id), '''')) as fp from public.catalog_published_prices() r) x where x.n = %s and x.fp = %L', ref_price_n, ref_price_fp);

  for t in
    select * from (values
      ('RV-anon anon: catalog_products = catálogo actual = referencia real', 'anon', null, 'aal1', null::text[], array[q_rv], 'count', '1'),
      ('RV-pro profesional: catalog_products = catálogo actual = referencia real', 'authenticated', v_pro::text, 'aal1', null::text[], array[q_rv], 'count', '1'),
      ('RV-own distribuidor dueño (A): catalog_products = catálogo actual = referencia real', 'authenticated', v_sup::text, 'aal1', null::text[], array[q_rv], 'count', '1'),
      ('RV-oth otro distribuidor (B): catalog_products = catálogo actual = referencia real', 'authenticated', v_pro2::text, 'aal1', v_aux_b, array[q_rv], 'count', '1'),
      ('RV-m1 Mobau sin AAL2: catalog_products = catálogo actual = referencia real', 'authenticated', v_pro3::text, 'aal1', v_aux_m, array[q_rv], 'count', '1'),
      ('RV-m2 Mobau con AAL2: catalog_products = catálogo actual = referencia real', 'authenticated', v_pro3::text, 'aal2', v_aux_m, array[q_rv], 'count', '1'),
      ('KV-anon anon: catalog_version() = referencia real', 'anon', null, 'aal1', null::text[], array[format('select count(*) where public.catalog_version() = %L', ref_ver)], 'count', '1'),
      ('KV-pro profesional: catalog_version() = referencia real', 'authenticated', v_pro::text, 'aal1', null::text[], array[format('select count(*) where public.catalog_version() = %L', ref_ver)], 'count', '1'),
      ('KV-own distribuidor dueño (A): catalog_version() = referencia real', 'authenticated', v_sup::text, 'aal1', null::text[], array[format('select count(*) where public.catalog_version() = %L', ref_ver)], 'count', '1'),
      ('KV-oth otro distribuidor (B): catalog_version() = referencia real con su empresa auxiliar', 'authenticated', v_pro2::text, 'aal1', v_aux_b, array[format('select count(*) where public.catalog_version() = %L', ref_ver_b)], 'count', '1'),
      ('KV-m1 Mobau sin AAL2: catalog_version() = referencia real', 'authenticated', v_pro3::text, 'aal1', v_aux_m, array[format('select count(*) where public.catalog_version() = %L', ref_ver)], 'count', '1'),
      ('KV-m2 Mobau con AAL2: catalog_version() = referencia real', 'authenticated', v_pro3::text, 'aal2', v_aux_m, array[format('select count(*) where public.catalog_version() = %L', ref_ver)], 'count', '1'),
      ('LV-anon anon: filas de catalog_products con 21 claves y sin ciclo de vida', 'anon', null, 'aal1', null::text[], array[q_lv], 'count', '0'),
      ('LV-pro profesional: filas de catalog_products con 21 claves y sin ciclo de vida', 'authenticated', v_pro::text, 'aal1', null::text[], array[q_lv], 'count', '0'),
      ('LV-own distribuidor dueño (A): filas de catalog_products con 21 claves y sin ciclo de vida', 'authenticated', v_sup::text, 'aal1', null::text[], array[q_lv], 'count', '0'),
      ('LV-oth otro distribuidor (B): filas de catalog_products con 21 claves y sin ciclo de vida', 'authenticated', v_pro2::text, 'aal1', v_aux_b, array[q_lv], 'count', '0'),
      ('LV-m1 Mobau sin AAL2: filas de catalog_products con 21 claves y sin ciclo de vida', 'authenticated', v_pro3::text, 'aal1', v_aux_m, array[q_lv], 'count', '0'),
      ('LV-m2 Mobau con AAL2: filas de catalog_products con 21 claves y sin ciclo de vida', 'authenticated', v_pro3::text, 'aal2', v_aux_m, array[q_lv], 'count', '0'),
      ('PV-anon anon no puede ejecutar catalog_published_prices', 'anon', null, 'aal1', null::text[], array['select count(*) from public.catalog_published_prices()'], 'exec', '42501'),
      ('PV-pro profesional: catalog_published_prices() = regla 39-05 real', 'authenticated', v_pro::text, 'aal1', null::text[], array[q_pv], 'count', '1'),
      ('PV-own distribuidor dueño (A): catalog_published_prices() = regla 39-05 real', 'authenticated', v_sup::text, 'aal1', null::text[], array[q_pv], 'count', '1'),
      ('PV-oth otro distribuidor (B): catalog_published_prices() = regla 39-05 real', 'authenticated', v_pro2::text, 'aal1', v_aux_b, array[q_pv], 'count', '1'),
      ('PV-m1 Mobau sin AAL2: catalog_published_prices() = regla 39-05 real', 'authenticated', v_pro3::text, 'aal1', v_aux_m, array[q_pv], 'count', '1'),
      ('PV-m2 Mobau con AAL2: catalog_published_prices() = regla 39-05 real', 'authenticated', v_pro3::text, 'aal2', v_aux_m, array[q_pv], 'count', '1'),
      ('SV01 service_role no puede leer catalog_products (42501)', 'service_role', null, null, null::text[], array['select count(*) from public.catalog_products'], 'exec', '42501'),
      ('ZV01 mobau_admins idéntica a la de partida', '-', null, null, null::text[],
         array[format('select count(*) from (select count(*) as n, md5(coalesce(string_agg(to_jsonb(a)::text, %L order by a.user_id), %L)) as fp from public.mobau_admins a) x where x.n = %s and x.fp = %L', '|', '', v_adm_n, v_adm_md5)], 'count', '1'),
      ('ZV02 sin restos rls41r (distribuidores y perfiles de distribuidor)', '-', null, null, null::text[],
         array['select (select count(*) from public.distributors where id like ''rls41r-%'') + (select count(*) from public.distributor_profiles where distributor_id like ''rls41r-%'')'], 'count', '0'),
      ('ZV03 productos reales: proyección de las 22 columnas igual a la de partida', '-', null, null, null::text[],
         array[format('select count(*) from (select count(*) as n, md5(coalesce(string_agg(to_jsonb(r)::text, ''|'' order by r.id), '''')) as fp from (select id, name, distributor_id, brand, category_id, subcategory, use_context, space, availability, description, measurements, materials, finishes, lead_time, icon, technical_sheet_url, cad_bim_3d_url, image_url, created_at, status, updated_at, publication_status from public.products) r) x where x.n = %s and x.fp = %L', v_real_n, v_real_fp)], 'count', '1')
    ) as c(name, role, sub, aal, setup, sql, kind, expect)
  loop
    v_got := null;
    begin
      if t.setup is not null then
        foreach v_stmt in array t.setup loop execute v_stmt; end loop;
      end if;
      if t.role <> '-' then execute format('set local role %I', t.role); end if;
      perform set_config('request.jwt.claim.sub', coalesce(t.sub, ''), true);
      perform set_config('request.jwt.claim.role', '', true);
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
      when t.expect = 'ok' then v_got like 'ok rows=%' and v_got <> 'ok rows=0'
      else v_got = t.expect
    end;
    n_total := n_total + 1;
    if v_ok then n_ok := n_ok + 1; end if;
    r := r || jsonb_build_object('prueba', t.name, 'esperado', t.expect, 'obtenido', v_got, 'ok', v_ok);
  end loop;

  raise exception 'MOBAU_41_V2_REAL total=% ok=% fallos=% catalogo=%/% :: %', n_total, n_ok, n_total - n_ok, ref_cat_n, ref_cat_fp, r::text
    using errcode = 'MB999';
end $$;

ROLLBACK;
