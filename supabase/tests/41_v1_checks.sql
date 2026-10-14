-- ============================================================
-- PROPUESTA NO EJECUTADA (41 · V1) — no ejecutar sin aprobación explícita
-- ============================================================
-- 41 · V1 · Pruebas de 41-01 (permisos por columna, columnas de ciclo de
-- vida, mobau_private, copia de envío) y 41-02 (catalog_products,
-- catalog_version, defensa de precios), en una transacción revertida.
-- ------------------------------------------------------------
-- Ejecutar después de 41-01 y 41-02 (en E0, dentro de la misma transacción
-- que las migraciones). Rol postgres; JWT simulado como en 39.
--
-- Seis roles (todas las cuentas ya existen; no se crea ninguna):
--   anon                         sin JWT
--   profesional                  1.er perfil 'individual'
--   distribuidor dueño (A)       el distribuidor verificado real
--   otro distribuidor (B)        2.º perfil 'individual', vinculado SOLO
--                                dentro de cada caso a 'rls41-dist-b'
--                                (distributor_profiles verificado y, desde
--                                V3 / B3-C, role = 'supplier' también solo
--                                dentro del caso)
--   Mobau sin AAL2 / con AAL2    3.er perfil 'individual', admin temporal
--                                SOLO dentro de cada caso
-- Auxiliares (dentro de cada caso; nunca persisten): empresa
-- rls41-dist-b; productos rls41-a-pub, -draft, -rev, -chg, -leg (heredado),
-- -ret (retirado), -tr (papelera desde retirado), -trd (papelera desde
-- borrador), rls41-b-pub, rls41-b-ret; precios en a-pub, a-ret, a-draft,
-- a-trd; propuesta de cambio 41000000-…-0001 (solo en N01/N02).
-- Referencias: calculadas como postgres con los mismos auxiliares en una
-- subtransacción revertida (now() es constante en la transacción).
-- NADA queda guardado: BEGIN … ROLLBACK, MB001 por caso y MB999 final.
-- Puede consumir valores de secuencia (proposal_events por N01/N02): no
-- transaccional, esperado.
-- ============================================================

BEGIN;

DO $$
declare
  v_sup uuid; v_sup_dist text; v_pro uuid; v_pro2 uuid; v_pro3 uuid; v_cat1 text;
  v_aux text[]; v_retire_pub text; v_rename_dist text; v_rename_draft text; v_prop text;
  p41 constant text := '41000000-0000-4000-8000-000000000001';
  ref_pub_n bigint; ref_pub_fp text; ref_own_n bigint; ref_own_fp text; ref_oth_n bigint; ref_oth_fp text;
  ref_all_n bigint; ref_all_fp text; ref_view_n bigint; ref_view_fp text; ref_ver text;
  ref_price_n bigint; ref_price_fp text; v_real_n bigint; v_real_fp text;
  v_adm_n bigint; v_adm_md5 text;
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
  select c.id into v_cat1 from public.categories c order by c.id limit 1;
  if v_sup is null or v_pro is null or v_pro2 is null or v_pro3 is null or v_cat1 is null then
    raise exception 'MOBAU_41_V1: faltan datos de partida' using errcode = 'MB998';
  end if;
  if to_regclass('public.catalog_products') is null or to_regnamespace('mobau_private') is null then
    raise exception 'MOBAU_41_V1: faltan 41-01 o 41-02' using errcode = 'MB998';
  end if;

  select count(*), md5(coalesce(string_agg(to_jsonb(a)::text, '|' order by a.user_id), ''))
    into v_adm_n, v_adm_md5 from public.mobau_admins a;
  execute 'select count(*), md5(coalesce(string_agg(to_jsonb(r)::text, ''|'' order by r.id), '''')) from (select id, name, distributor_id, brand, category_id, subcategory, use_context, space, availability, description, measurements, materials, finishes, lead_time, icon, technical_sheet_url, cad_bim_3d_url, image_url, created_at, status, updated_at, publication_status from public.products) r' into v_real_n, v_real_fp;

  -- ---------- SQL auxiliar (como postgres, dentro de cada caso) ----------
  v_aux := array[
    format('insert into public.distributors (id, name) values (%L, %L)', 'rls41-dist-b', 'Distribuidor B (prueba 41)'),
    format('insert into public.distributor_profiles (user_id, nombre_comercial, razon_social, rnc, direccion_fiscal, telefono, email_contacto, nombre_contacto, cargo_contacto, verification_status, verified_at, distributor_id)' || ' values (%L, %L, %L, %L, %L, %L, %L, %L, %L, %L, now(), %L)', v_pro2, 'Prueba 41 B', 'Prueba 41 B SRL', '999999941', 'Calle de prueba 41', '0000000041', 'prueba41@example.invalid', 'Contacto prueba 41', 'Prueba', 'verified', 'rls41-dist-b'),
    -- V3 (B3-C): la regla única exige role = 'supplier'; solo dentro del caso.
    format('update public.profiles set role = %L where id = %L', 'supplier', v_pro2),
    format('insert into public.mobau_admins (user_id, granted_note) values (%L, %L)', v_pro3, 'Admin temporal de prueba 41'),
    format('insert into public.products (id, name, distributor_id, category_id, publication_status) values (%L, %L, %L, %L, %L)', 'rls41-a-pub', 'A publicado 41', v_sup_dist, v_cat1, 'published'),
    format('insert into public.products (id, name, distributor_id, category_id, publication_status) values (%L, %L, %L, %L, %L)', 'rls41-a-draft', 'A borrador 41', v_sup_dist, v_cat1, 'draft'),
    format('insert into public.products (id, name, distributor_id, category_id, publication_status) values (%L, %L, %L, %L, %L)', 'rls41-a-rev', 'A en revisión 41', v_sup_dist, v_cat1, 'in_review'),
    format('insert into public.products (id, name, distributor_id, category_id, publication_status) values (%L, %L, %L, %L, %L)', 'rls41-a-chg', 'A con cambios 41', v_sup_dist, v_cat1, 'changes_requested'),
    format('insert into public.products (id, name, distributor_id, category_id, publication_status) values (%L, %L, %L, %L, %L)', 'rls41-a-leg', 'A heredado 41', v_sup_dist, v_cat1, 'archived'),
    format('insert into public.products (id, name, distributor_id, category_id, publication_status, retired_at, retired_by, retired_reason) values (%L, %L, %L, %L, %L, now(), %L, ''Motivo de prueba 41'')', 'rls41-a-ret', 'A retirado 41', v_sup_dist, v_cat1, 'archived', v_pro3),
    format('insert into public.products (id, name, distributor_id, category_id, publication_status, retired_at, retired_by, retired_reason, trashed_at, trashed_by, trash_from, purge_after) values (%L, %L, %L, %L, %L, now(), %L, ''Motivo de prueba 41'', now(), %L, ''retired'', now() + interval ''30 days'')', 'rls41-a-tr', 'A en papelera (retirado) 41', v_sup_dist, v_cat1, 'archived', v_pro3, v_sup),
    format('insert into public.products (id, name, distributor_id, category_id, publication_status, trashed_at, trashed_by, trash_from, purge_after) values (%L, %L, %L, %L, %L, now(), %L, ''draft'', now() + interval ''30 days'')', 'rls41-a-trd', 'A en papelera (borrador) 41', v_sup_dist, v_cat1, 'draft', v_sup),
    format('insert into public.products (id, name, distributor_id, category_id, publication_status) values (%L, %L, %L, %L, %L)', 'rls41-b-pub', 'B publicado 41', 'rls41-dist-b', v_cat1, 'published'),
    format('insert into public.products (id, name, distributor_id, category_id, publication_status, retired_at, retired_by, retired_reason) values (%L, %L, %L, %L, %L, now(), %L, ''Motivo de prueba 41'')', 'rls41-b-ret', 'B retirado 41', 'rls41-dist-b', v_cat1, 'archived', v_pro3),
    format('insert into public.product_prices (product_id, price_status, price_amount, currency, includes_itbis, price_source) values (%L, %L, 50, %L, true, %L)', 'rls41-a-pub', 'published', 'USD', 'distributor'),
    format('insert into public.product_prices (product_id, price_status, price_amount, currency, includes_itbis, price_source) values (%L, %L, 60, %L, true, %L)', 'rls41-a-ret', 'published', 'USD', 'distributor'),
    format('insert into public.product_prices (product_id, price_status, price_amount, currency, includes_itbis, price_source) values (%L, %L, 70, %L, true, %L)', 'rls41-a-draft', 'published', 'USD', 'distributor'),
    format('insert into public.product_prices (product_id, price_status, price_amount, currency, includes_itbis, price_source) values (%L, %L, 80, %L, true, %L)', 'rls41-a-trd', 'published', 'USD', 'distributor')
  ];
  v_retire_pub := format('update public.products set publication_status = %L, retired_at = now(), retired_by = %L, retired_reason = %L where id = %L',
                         'archived', v_pro3, 'Motivo de prueba 41', 'rls41-a-pub');
  v_rename_dist := format('update public.distributors set name = name || %L where id = %L', ' (renombrado)', 'rls41-dist-b');
  v_rename_draft := format('update public.products set name = name || %L where id = %L', ' (renombrado)', 'rls41-a-draft');
  v_prop := format('insert into public.product_proposals (id, proposal_kind, product_id, distributor_id, status, proposed_changes) values (%L, %L, %L, %L, %L, %L)',
                   p41, 'update', 'rls41-a-pub', v_sup_dist, 'draft', '{"name": "Nombre propuesto 41"}');

  -- ---------- referencias (como postgres, con los auxiliares, revertido) ----------
  begin
    foreach v_stmt in array v_aux loop execute v_stmt; end loop;
    execute 'select count(*), md5(coalesce(string_agg(to_jsonb(r)::text, ''|'' order by r.id), '''')) from (select id, name, distributor_id, brand, category_id, subcategory, use_context, space, availability, description, measurements, materials, finishes, lead_time, icon, technical_sheet_url, cad_bim_3d_url, image_url, created_at, status, updated_at, publication_status from public.products where publication_status = ''published'') r' into ref_pub_n, ref_pub_fp;
    execute format('select count(*), md5(coalesce(string_agg(to_jsonb(r)::text, ''|'' order by r.id), '''')) from (select id, name, distributor_id, brand, category_id, subcategory, use_context, space, availability, description, measurements, materials, finishes, lead_time, icon, technical_sheet_url, cad_bim_3d_url, image_url, created_at, status, updated_at, publication_status from public.products where publication_status = ''published'' or distributor_id = %L) r', v_sup_dist) into ref_own_n, ref_own_fp;
    execute format('select count(*), md5(coalesce(string_agg(to_jsonb(r)::text, ''|'' order by r.id), '''')) from (select id, name, distributor_id, brand, category_id, subcategory, use_context, space, availability, description, measurements, materials, finishes, lead_time, icon, technical_sheet_url, cad_bim_3d_url, image_url, created_at, status, updated_at, publication_status from public.products where publication_status = ''published'' or distributor_id = %L) r', 'rls41-dist-b') into ref_oth_n, ref_oth_fp;
    execute 'select count(*), md5(coalesce(string_agg(to_jsonb(r)::text, ''|'' order by r.id), '''')) from (select id, name, distributor_id, brand, category_id, subcategory, use_context, space, availability, description, measurements, materials, finishes, lead_time, icon, technical_sheet_url, cad_bim_3d_url, image_url, created_at, status, updated_at, publication_status from public.products) r' into ref_all_n, ref_all_fp;
    execute 'select count(*), md5(coalesce(string_agg(to_jsonb(r)::text, ''|'' order by r.id), '''')) from (select id, name, brand, distributor_id, category_id, subcategory, use_context, space, availability, description, measurements, materials, finishes, lead_time, icon, image_url, technical_sheet_url, cad_bim_3d_url, status, created_at, updated_at from public.products where publication_status = ''published'' and status = ''active'') r' into ref_view_n, ref_view_fp;
    ref_ver := public.catalog_version();
    execute 'select count(*), md5(coalesce(string_agg(concat_ws('':'', r.product_id, coalesce(r.price_amount::text, ''-''), coalesce(r.currency, ''-''), r.price_status, coalesce(r.includes_itbis::text, ''-''), coalesce(r.itbis_rate::text, ''-''), coalesce(r.es_demo::text, ''-'')), ''|'' order by r.product_id), '''')) from (select pp.product_id, case when pp.price_status = ''published'' then pp.price_amount end as price_amount, pp.currency, pp.price_status, pp.includes_itbis, pp.itbis_rate, coalesce(pp.price_source = ''demo'', false) as es_demo from public.product_prices pp join public.products p on p.id = pp.product_id where p.publication_status = ''published'' and pp.price_status in (''published'', ''quote_required'', ''pending_confirmation'', ''unavailable'')) r' into ref_price_n, ref_price_fp;
    raise exception using errcode = 'MB001';
  exception when sqlstate 'MB001' then null;
  end;

  for t in
    select * from (values
      ('I01 dueño: my_verified_distributor_id() = empresa A', 'authenticated', v_sup::text, 'aal1', v_aux,
         array[format('select count(*) where public.my_verified_distributor_id() = %L', v_sup_dist)]::text[], 'count', '1'),
      ('I02 otro distribuidor (vínculo temporal): my_verified_distributor_id() = rls41-dist-b', 'authenticated', v_pro2::text, 'aal1', v_aux,
         array['select count(*) where public.my_verified_distributor_id() = ''rls41-dist-b''']::text[], 'count', '1'),
      ('I03 Mobau con AAL2: is_mobau_admin() verdadero', 'authenticated', v_pro3::text, 'aal2', v_aux,
         array['select count(*) where public.is_mobau_admin()']::text[], 'count', '1'),
      ('I04 Mobau sin AAL2: is_mobau_admin() falso', 'authenticated', v_pro3::text, 'aal1', v_aux,
         array['select count(*) where not public.is_mobau_admin()']::text[], 'count', '1'),
      ('G01 sin SELECT de tabla en products para anon y authenticated', '-', null, null, null::text[],
         array['select count(*) where not has_table_privilege(''anon'', ''public.products'', ''SELECT'') and not has_table_privilege(''authenticated'', ''public.products'', ''SELECT'')']::text[], 'count', '1'),
      ('G02 ACL de tabla exacta (solo se quitó SELECT; service_role igual)', '-', null, null, null::text[],
         array['select count(*) from pg_class where oid = ''public.products''::regclass and relacl::text = ''{postgres=arwdDxtm/postgres,anon=xtm/postgres,authenticated=xtm/postgres,service_role=arwdDxtm/postgres}''']::text[], 'count', '1'),
      ('G03 las 22 columnas actuales: SELECT para anon y authenticated (44)', '-', null, null, null::text[],
         array['select count(*) from unnest(array[''id'', ''name'', ''distributor_id'', ''brand'', ''category_id'', ''subcategory'', ''use_context'', ''space'', ''availability'', ''description'', ''measurements'', ''materials'', ''finishes'', ''lead_time'', ''icon'', ''technical_sheet_url'', ''cad_bim_3d_url'', ''image_url'', ''created_at'', ''status'', ''updated_at'', ''publication_status'']) c, unnest(array[''anon'', ''authenticated'']) g where has_column_privilege(g, ''public.products'', c, ''SELECT'')']::text[], 'count', '44'),
      ('G04 las 7 columnas nuevas: ni SELECT, ni INSERT, ni UPDATE para anon y authenticated', '-', null, null, null::text[],
         array['select count(*) from unnest(array[''retired_at'', ''retired_by'', ''retired_reason'', ''trashed_at'', ''trashed_by'', ''trash_from'', ''purge_after'']) c, unnest(array[''anon'', ''authenticated'']) g where has_column_privilege(g, ''public.products'', c, ''SELECT'') or has_column_privilege(g, ''public.products'', c, ''INSERT'') or has_column_privilege(g, ''public.products'', c, ''UPDATE'')']::text[], 'count', '0'),
      ('G05 las 7 columnas nuevas sin ninguna entrada de permisos (attacl nulo)', '-', null, null, null::text[],
         array['select count(*) from pg_attribute where attrelid = ''public.products''::regclass and attname = any (array[''retired_at'', ''retired_by'', ''retired_reason'', ''trashed_at'', ''trashed_by'', ''trash_from'', ''purge_after'']) and attacl is not null']::text[], 'count', '0'),
      ('G06 permisos por columna: solo SELECT, solo anon/authenticated, solo en las 22', '-', null, null, null::text[],
         array['select count(*) from pg_attribute t, aclexplode(t.attacl) a where t.attrelid = ''public.products''::regclass and not (a.grantee in (''anon''::regrole, ''authenticated''::regrole) and a.privilege_type = ''SELECT'' and t.attname = any (array[''id'', ''name'', ''distributor_id'', ''brand'', ''category_id'', ''subcategory'', ''use_context'', ''space'', ''availability'', ''description'', ''measurements'', ''materials'', ''finishes'', ''lead_time'', ''icon'', ''technical_sheet_url'', ''cad_bim_3d_url'', ''image_url'', ''created_at'', ''status'', ''updated_at'', ''publication_status'']))']::text[], 'count', '0'),
      ('G07 escrituras de cliente siguen cerradas (tabla y columnas)', '-', null, null, null::text[],
         array['select count(*) from unnest(array[''anon'', ''authenticated'']) g, unnest(array[''INSERT'', ''UPDATE'', ''DELETE'', ''TRUNCATE'']) p where has_table_privilege(g, ''public.products'', p) or (p in (''INSERT'', ''UPDATE'') and has_any_column_privilege(g, ''public.products'', p))']::text[], 'count', '0'),
      ('G08 service_role conserva SELECT de tabla (como hoy; ve las columnas nuevas)', '-', null, null, null::text[],
         array['select count(*) where has_table_privilege(''service_role'', ''public.products'', ''SELECT'') and has_column_privilege(''service_role'', ''public.products'', ''retired_by'', ''SELECT'')']::text[], 'count', '1'),
      ('G09 columnas de products: las 22 de antes y las 7 nuevas, en orden', '-', null, null, null::text[],
         array['select count(*) where (select string_agg(attname, '','' order by attnum) from pg_attribute where attrelid = ''public.products''::regclass and attnum > 0 and not attisdropped) = ''id,name,distributor_id,brand,category_id,subcategory,use_context,space,availability,description,measurements,materials,finishes,lead_time,icon,technical_sheet_url,cad_bim_3d_url,image_url,created_at,status,updated_at,publication_status,retired_at,retired_by,retired_reason,trashed_at,trashed_by,trash_from,purge_after''']::text[], 'count', '1'),
      ('G10 ninguna fila real con datos de ciclo de vida', '-', null, null, null::text[],
         array['select count(*) from public.products where retired_at is not null or retired_by is not null or retired_reason is not null or trashed_at is not null or trashed_by is not null or trash_from is not null or purge_after is not null']::text[], 'count', '0'),
      ('C-anon-retired_at anon no puede leer retired_at', 'anon', null, 'aal1', v_aux,
         array['select count(retired_at) from public.products']::text[], 'exec', '42501'),
      ('C-anon-retired_by anon no puede leer retired_by', 'anon', null, 'aal1', v_aux,
         array['select count(retired_by) from public.products']::text[], 'exec', '42501'),
      ('C-anon-retired_reason anon no puede leer retired_reason', 'anon', null, 'aal1', v_aux,
         array['select count(retired_reason) from public.products']::text[], 'exec', '42501'),
      ('C-anon-trashed_at anon no puede leer trashed_at', 'anon', null, 'aal1', v_aux,
         array['select count(trashed_at) from public.products']::text[], 'exec', '42501'),
      ('C-anon-trashed_by anon no puede leer trashed_by', 'anon', null, 'aal1', v_aux,
         array['select count(trashed_by) from public.products']::text[], 'exec', '42501'),
      ('C-anon-trash_from anon no puede leer trash_from', 'anon', null, 'aal1', v_aux,
         array['select count(trash_from) from public.products']::text[], 'exec', '42501'),
      ('C-anon-purge_after anon no puede leer purge_after', 'anon', null, 'aal1', v_aux,
         array['select count(purge_after) from public.products']::text[], 'exec', '42501'),
      ('C-pro-retired_at profesional no puede leer retired_at', 'authenticated', v_pro::text, 'aal1', v_aux,
         array['select count(retired_at) from public.products']::text[], 'exec', '42501'),
      ('C-pro-retired_by profesional no puede leer retired_by', 'authenticated', v_pro::text, 'aal1', v_aux,
         array['select count(retired_by) from public.products']::text[], 'exec', '42501'),
      ('C-pro-retired_reason profesional no puede leer retired_reason', 'authenticated', v_pro::text, 'aal1', v_aux,
         array['select count(retired_reason) from public.products']::text[], 'exec', '42501'),
      ('C-pro-trashed_at profesional no puede leer trashed_at', 'authenticated', v_pro::text, 'aal1', v_aux,
         array['select count(trashed_at) from public.products']::text[], 'exec', '42501'),
      ('C-pro-trashed_by profesional no puede leer trashed_by', 'authenticated', v_pro::text, 'aal1', v_aux,
         array['select count(trashed_by) from public.products']::text[], 'exec', '42501'),
      ('C-pro-trash_from profesional no puede leer trash_from', 'authenticated', v_pro::text, 'aal1', v_aux,
         array['select count(trash_from) from public.products']::text[], 'exec', '42501'),
      ('C-pro-purge_after profesional no puede leer purge_after', 'authenticated', v_pro::text, 'aal1', v_aux,
         array['select count(purge_after) from public.products']::text[], 'exec', '42501'),
      ('C-own-retired_at distribuidor dueño (A) no puede leer retired_at', 'authenticated', v_sup::text, 'aal1', v_aux,
         array['select count(retired_at) from public.products']::text[], 'exec', '42501'),
      ('C-own-retired_by distribuidor dueño (A) no puede leer retired_by', 'authenticated', v_sup::text, 'aal1', v_aux,
         array['select count(retired_by) from public.products']::text[], 'exec', '42501'),
      ('C-own-retired_reason distribuidor dueño (A) no puede leer retired_reason', 'authenticated', v_sup::text, 'aal1', v_aux,
         array['select count(retired_reason) from public.products']::text[], 'exec', '42501'),
      ('C-own-trashed_at distribuidor dueño (A) no puede leer trashed_at', 'authenticated', v_sup::text, 'aal1', v_aux,
         array['select count(trashed_at) from public.products']::text[], 'exec', '42501'),
      ('C-own-trashed_by distribuidor dueño (A) no puede leer trashed_by', 'authenticated', v_sup::text, 'aal1', v_aux,
         array['select count(trashed_by) from public.products']::text[], 'exec', '42501'),
      ('C-own-trash_from distribuidor dueño (A) no puede leer trash_from', 'authenticated', v_sup::text, 'aal1', v_aux,
         array['select count(trash_from) from public.products']::text[], 'exec', '42501'),
      ('C-own-purge_after distribuidor dueño (A) no puede leer purge_after', 'authenticated', v_sup::text, 'aal1', v_aux,
         array['select count(purge_after) from public.products']::text[], 'exec', '42501'),
      ('C-oth-retired_at otro distribuidor (B) no puede leer retired_at', 'authenticated', v_pro2::text, 'aal1', v_aux,
         array['select count(retired_at) from public.products']::text[], 'exec', '42501'),
      ('C-oth-retired_by otro distribuidor (B) no puede leer retired_by', 'authenticated', v_pro2::text, 'aal1', v_aux,
         array['select count(retired_by) from public.products']::text[], 'exec', '42501'),
      ('C-oth-retired_reason otro distribuidor (B) no puede leer retired_reason', 'authenticated', v_pro2::text, 'aal1', v_aux,
         array['select count(retired_reason) from public.products']::text[], 'exec', '42501'),
      ('C-oth-trashed_at otro distribuidor (B) no puede leer trashed_at', 'authenticated', v_pro2::text, 'aal1', v_aux,
         array['select count(trashed_at) from public.products']::text[], 'exec', '42501'),
      ('C-oth-trashed_by otro distribuidor (B) no puede leer trashed_by', 'authenticated', v_pro2::text, 'aal1', v_aux,
         array['select count(trashed_by) from public.products']::text[], 'exec', '42501'),
      ('C-oth-trash_from otro distribuidor (B) no puede leer trash_from', 'authenticated', v_pro2::text, 'aal1', v_aux,
         array['select count(trash_from) from public.products']::text[], 'exec', '42501'),
      ('C-oth-purge_after otro distribuidor (B) no puede leer purge_after', 'authenticated', v_pro2::text, 'aal1', v_aux,
         array['select count(purge_after) from public.products']::text[], 'exec', '42501'),
      ('C-m1-retired_at Mobau sin AAL2 no puede leer retired_at', 'authenticated', v_pro3::text, 'aal1', v_aux,
         array['select count(retired_at) from public.products']::text[], 'exec', '42501'),
      ('C-m1-retired_by Mobau sin AAL2 no puede leer retired_by', 'authenticated', v_pro3::text, 'aal1', v_aux,
         array['select count(retired_by) from public.products']::text[], 'exec', '42501'),
      ('C-m1-retired_reason Mobau sin AAL2 no puede leer retired_reason', 'authenticated', v_pro3::text, 'aal1', v_aux,
         array['select count(retired_reason) from public.products']::text[], 'exec', '42501'),
      ('C-m1-trashed_at Mobau sin AAL2 no puede leer trashed_at', 'authenticated', v_pro3::text, 'aal1', v_aux,
         array['select count(trashed_at) from public.products']::text[], 'exec', '42501'),
      ('C-m1-trashed_by Mobau sin AAL2 no puede leer trashed_by', 'authenticated', v_pro3::text, 'aal1', v_aux,
         array['select count(trashed_by) from public.products']::text[], 'exec', '42501'),
      ('C-m1-trash_from Mobau sin AAL2 no puede leer trash_from', 'authenticated', v_pro3::text, 'aal1', v_aux,
         array['select count(trash_from) from public.products']::text[], 'exec', '42501'),
      ('C-m1-purge_after Mobau sin AAL2 no puede leer purge_after', 'authenticated', v_pro3::text, 'aal1', v_aux,
         array['select count(purge_after) from public.products']::text[], 'exec', '42501'),
      ('C-m2-retired_at Mobau con AAL2 no puede leer retired_at', 'authenticated', v_pro3::text, 'aal2', v_aux,
         array['select count(retired_at) from public.products']::text[], 'exec', '42501'),
      ('C-m2-retired_by Mobau con AAL2 no puede leer retired_by', 'authenticated', v_pro3::text, 'aal2', v_aux,
         array['select count(retired_by) from public.products']::text[], 'exec', '42501'),
      ('C-m2-retired_reason Mobau con AAL2 no puede leer retired_reason', 'authenticated', v_pro3::text, 'aal2', v_aux,
         array['select count(retired_reason) from public.products']::text[], 'exec', '42501'),
      ('C-m2-trashed_at Mobau con AAL2 no puede leer trashed_at', 'authenticated', v_pro3::text, 'aal2', v_aux,
         array['select count(trashed_at) from public.products']::text[], 'exec', '42501'),
      ('C-m2-trashed_by Mobau con AAL2 no puede leer trashed_by', 'authenticated', v_pro3::text, 'aal2', v_aux,
         array['select count(trashed_by) from public.products']::text[], 'exec', '42501'),
      ('C-m2-trash_from Mobau con AAL2 no puede leer trash_from', 'authenticated', v_pro3::text, 'aal2', v_aux,
         array['select count(trash_from) from public.products']::text[], 'exec', '42501'),
      ('C-m2-purge_after Mobau con AAL2 no puede leer purge_after', 'authenticated', v_pro3::text, 'aal2', v_aux,
         array['select count(purge_after) from public.products']::text[], 'exec', '42501'),
      ('C50 anon: select * de products rechazado (42501)', 'anon', null, 'aal1', v_aux,
         array['select count(*) from (select * from public.products) x']::text[], 'exec', '42501'),
      ('C51 dueño: select * de products rechazado (42501) = comportamiento de distribuidor-producto.html:425 (página cerrada)', 'authenticated', v_sup::text, 'aal1', v_aux,
         array['select count(*) from (select * from public.products where id = ''rls41-a-pub'') x']::text[], 'exec', '42501'),
      ('C52 Mobau con AAL2: select * de products rechazado (42501)', 'authenticated', v_pro3::text, 'aal2', v_aux,
         array['select count(*) from (select * from public.products) x']::text[], 'exec', '42501'),
      ('C53 dueño: fila completa (to_jsonb(p)) rechazada (42501)', 'authenticated', v_sup::text, 'aal1', v_aux,
         array['select count(*) from (select to_jsonb(p) as j from public.products p) x']::text[], 'exec', '42501'),
      ('C54 anon: count(*) sin columnas sigue funcionando (solo publicados)', 'anon', null, 'aal1', v_aux,
         array['select count(*) from public.products']::text[], 'count', ref_pub_n::text),
      ('R-anon anon: las 22 columnas legibles; mismas filas que su RLS (recuento y huella)', 'anon', null, 'aal1', v_aux,
         array[format('select count(*) from (select count(*) as n, md5(coalesce(string_agg(to_jsonb(r)::text, ''|'' order by r.id), '''')) as fp from (select id, name, distributor_id, brand, category_id, subcategory, use_context, space, availability, description, measurements, materials, finishes, lead_time, icon, technical_sheet_url, cad_bim_3d_url, image_url, created_at, status, updated_at, publication_status from public.products) r) x where x.n = %s and x.fp = %L', ref_pub_n, ref_pub_fp)]::text[], 'count', '1'),
      ('R-pro profesional: las 22 columnas legibles; mismas filas que su RLS (recuento y huella)', 'authenticated', v_pro::text, 'aal1', v_aux,
         array[format('select count(*) from (select count(*) as n, md5(coalesce(string_agg(to_jsonb(r)::text, ''|'' order by r.id), '''')) as fp from (select id, name, distributor_id, brand, category_id, subcategory, use_context, space, availability, description, measurements, materials, finishes, lead_time, icon, technical_sheet_url, cad_bim_3d_url, image_url, created_at, status, updated_at, publication_status from public.products) r) x where x.n = %s and x.fp = %L', ref_pub_n, ref_pub_fp)]::text[], 'count', '1'),
      ('R-own distribuidor dueño (A): las 22 columnas legibles; mismas filas que su RLS (recuento y huella)', 'authenticated', v_sup::text, 'aal1', v_aux,
         array[format('select count(*) from (select count(*) as n, md5(coalesce(string_agg(to_jsonb(r)::text, ''|'' order by r.id), '''')) as fp from (select id, name, distributor_id, brand, category_id, subcategory, use_context, space, availability, description, measurements, materials, finishes, lead_time, icon, technical_sheet_url, cad_bim_3d_url, image_url, created_at, status, updated_at, publication_status from public.products) r) x where x.n = %s and x.fp = %L', ref_own_n, ref_own_fp)]::text[], 'count', '1'),
      ('R-oth otro distribuidor (B): las 22 columnas legibles; mismas filas que su RLS (recuento y huella)', 'authenticated', v_pro2::text, 'aal1', v_aux,
         array[format('select count(*) from (select count(*) as n, md5(coalesce(string_agg(to_jsonb(r)::text, ''|'' order by r.id), '''')) as fp from (select id, name, distributor_id, brand, category_id, subcategory, use_context, space, availability, description, measurements, materials, finishes, lead_time, icon, technical_sheet_url, cad_bim_3d_url, image_url, created_at, status, updated_at, publication_status from public.products) r) x where x.n = %s and x.fp = %L', ref_oth_n, ref_oth_fp)]::text[], 'count', '1'),
      ('R-m1 Mobau sin AAL2: las 22 columnas legibles; mismas filas que su RLS (recuento y huella)', 'authenticated', v_pro3::text, 'aal1', v_aux,
         array[format('select count(*) from (select count(*) as n, md5(coalesce(string_agg(to_jsonb(r)::text, ''|'' order by r.id), '''')) as fp from (select id, name, distributor_id, brand, category_id, subcategory, use_context, space, availability, description, measurements, materials, finishes, lead_time, icon, technical_sheet_url, cad_bim_3d_url, image_url, created_at, status, updated_at, publication_status from public.products) r) x where x.n = %s and x.fp = %L', ref_pub_n, ref_pub_fp)]::text[], 'count', '1'),
      ('R-m2 Mobau con AAL2: las 22 columnas legibles; mismas filas que su RLS (recuento y huella)', 'authenticated', v_pro3::text, 'aal2', v_aux,
         array[format('select count(*) from (select count(*) as n, md5(coalesce(string_agg(to_jsonb(r)::text, ''|'' order by r.id), '''')) as fp from (select id, name, distributor_id, brand, category_id, subcategory, use_context, space, availability, description, measurements, materials, finishes, lead_time, icon, technical_sheet_url, cad_bim_3d_url, image_url, created_at, status, updated_at, publication_status from public.products) r) x where x.n = %s and x.fp = %L', ref_all_n, ref_all_fp)]::text[], 'count', '1'),
      ('V-anon anon: catalog_products = consulta actual del catálogo (mismas filas y columnas) = referencia', 'anon', null, 'aal1', v_aux,
         array[format('select count(*) from (select (select count(*) from public.catalog_products) as n, (select md5(coalesce(string_agg(to_jsonb(r)::text, ''|'' order by r.id), '''')) from (select id, name, brand, distributor_id, category_id, subcategory, use_context, space, availability, description, measurements, materials, finishes, lead_time, icon, image_url, technical_sheet_url, cad_bim_3d_url, status, created_at, updated_at from public.catalog_products) r) as fv, (select md5(coalesce(string_agg(to_jsonb(r)::text, ''|'' order by r.id), '''')) from (select id, name, brand, distributor_id, category_id, subcategory, use_context, space, availability, description, measurements, materials, finishes, lead_time, icon, image_url, technical_sheet_url, cad_bim_3d_url, status, created_at, updated_at from public.products where status = ''active'' and publication_status = ''published'') r) as fo) x where x.n = %s and x.fv = %L and x.fo = x.fv', ref_view_n, ref_view_fp)]::text[], 'count', '1'),
      ('V-pro profesional: catalog_products = consulta actual del catálogo (mismas filas y columnas) = referencia', 'authenticated', v_pro::text, 'aal1', v_aux,
         array[format('select count(*) from (select (select count(*) from public.catalog_products) as n, (select md5(coalesce(string_agg(to_jsonb(r)::text, ''|'' order by r.id), '''')) from (select id, name, brand, distributor_id, category_id, subcategory, use_context, space, availability, description, measurements, materials, finishes, lead_time, icon, image_url, technical_sheet_url, cad_bim_3d_url, status, created_at, updated_at from public.catalog_products) r) as fv, (select md5(coalesce(string_agg(to_jsonb(r)::text, ''|'' order by r.id), '''')) from (select id, name, brand, distributor_id, category_id, subcategory, use_context, space, availability, description, measurements, materials, finishes, lead_time, icon, image_url, technical_sheet_url, cad_bim_3d_url, status, created_at, updated_at from public.products where status = ''active'' and publication_status = ''published'') r) as fo) x where x.n = %s and x.fv = %L and x.fo = x.fv', ref_view_n, ref_view_fp)]::text[], 'count', '1'),
      ('V-own distribuidor dueño (A): catalog_products = consulta actual del catálogo (mismas filas y columnas) = referencia', 'authenticated', v_sup::text, 'aal1', v_aux,
         array[format('select count(*) from (select (select count(*) from public.catalog_products) as n, (select md5(coalesce(string_agg(to_jsonb(r)::text, ''|'' order by r.id), '''')) from (select id, name, brand, distributor_id, category_id, subcategory, use_context, space, availability, description, measurements, materials, finishes, lead_time, icon, image_url, technical_sheet_url, cad_bim_3d_url, status, created_at, updated_at from public.catalog_products) r) as fv, (select md5(coalesce(string_agg(to_jsonb(r)::text, ''|'' order by r.id), '''')) from (select id, name, brand, distributor_id, category_id, subcategory, use_context, space, availability, description, measurements, materials, finishes, lead_time, icon, image_url, technical_sheet_url, cad_bim_3d_url, status, created_at, updated_at from public.products where status = ''active'' and publication_status = ''published'') r) as fo) x where x.n = %s and x.fv = %L and x.fo = x.fv', ref_view_n, ref_view_fp)]::text[], 'count', '1'),
      ('V-oth otro distribuidor (B): catalog_products = consulta actual del catálogo (mismas filas y columnas) = referencia', 'authenticated', v_pro2::text, 'aal1', v_aux,
         array[format('select count(*) from (select (select count(*) from public.catalog_products) as n, (select md5(coalesce(string_agg(to_jsonb(r)::text, ''|'' order by r.id), '''')) from (select id, name, brand, distributor_id, category_id, subcategory, use_context, space, availability, description, measurements, materials, finishes, lead_time, icon, image_url, technical_sheet_url, cad_bim_3d_url, status, created_at, updated_at from public.catalog_products) r) as fv, (select md5(coalesce(string_agg(to_jsonb(r)::text, ''|'' order by r.id), '''')) from (select id, name, brand, distributor_id, category_id, subcategory, use_context, space, availability, description, measurements, materials, finishes, lead_time, icon, image_url, technical_sheet_url, cad_bim_3d_url, status, created_at, updated_at from public.products where status = ''active'' and publication_status = ''published'') r) as fo) x where x.n = %s and x.fv = %L and x.fo = x.fv', ref_view_n, ref_view_fp)]::text[], 'count', '1'),
      ('V-m1 Mobau sin AAL2: catalog_products = consulta actual del catálogo (mismas filas y columnas) = referencia', 'authenticated', v_pro3::text, 'aal1', v_aux,
         array[format('select count(*) from (select (select count(*) from public.catalog_products) as n, (select md5(coalesce(string_agg(to_jsonb(r)::text, ''|'' order by r.id), '''')) from (select id, name, brand, distributor_id, category_id, subcategory, use_context, space, availability, description, measurements, materials, finishes, lead_time, icon, image_url, technical_sheet_url, cad_bim_3d_url, status, created_at, updated_at from public.catalog_products) r) as fv, (select md5(coalesce(string_agg(to_jsonb(r)::text, ''|'' order by r.id), '''')) from (select id, name, brand, distributor_id, category_id, subcategory, use_context, space, availability, description, measurements, materials, finishes, lead_time, icon, image_url, technical_sheet_url, cad_bim_3d_url, status, created_at, updated_at from public.products where status = ''active'' and publication_status = ''published'') r) as fo) x where x.n = %s and x.fv = %L and x.fo = x.fv', ref_view_n, ref_view_fp)]::text[], 'count', '1'),
      ('V-m2 Mobau con AAL2: catalog_products = consulta actual del catálogo (mismas filas y columnas) = referencia', 'authenticated', v_pro3::text, 'aal2', v_aux,
         array[format('select count(*) from (select (select count(*) from public.catalog_products) as n, (select md5(coalesce(string_agg(to_jsonb(r)::text, ''|'' order by r.id), '''')) from (select id, name, brand, distributor_id, category_id, subcategory, use_context, space, availability, description, measurements, materials, finishes, lead_time, icon, image_url, technical_sheet_url, cad_bim_3d_url, status, created_at, updated_at from public.catalog_products) r) as fv, (select md5(coalesce(string_agg(to_jsonb(r)::text, ''|'' order by r.id), '''')) from (select id, name, brand, distributor_id, category_id, subcategory, use_context, space, availability, description, measurements, materials, finishes, lead_time, icon, image_url, technical_sheet_url, cad_bim_3d_url, status, created_at, updated_at from public.products where status = ''active'' and publication_status = ''published'') r) as fo) x where x.n = %s and x.fv = %L and x.fo = x.fv', ref_view_n, ref_view_fp)]::text[], 'count', '1'),
      ('V07 catalog_products: exactamente las 21 columnas de PRODUCT_COLUMNS, en orden', '-', null, null, null::text[],
         array['select count(*) where (select string_agg(attname, '','' order by attnum) from pg_attribute where attrelid = ''public.catalog_products''::regclass and attnum > 0 and not attisdropped) = ''id,name,brand,distributor_id,category_id,subcategory,use_context,space,availability,description,measurements,materials,finishes,lead_time,icon,image_url,technical_sheet_url,cad_bim_3d_url,status,created_at,updated_at''']::text[], 'count', '1'),
      ('V08 catalog_products: security_invoker, security_barrier y ACL exacta (solo SELECT a anon y authenticated)', '-', null, null, null::text[],
         array['select count(*) from pg_class where oid = ''public.catalog_products''::regclass and reloptions @> array[''security_invoker=true'', ''security_barrier=true''] and relacl::text = ''{postgres=arwdDxtm/postgres,anon=r/postgres,authenticated=r/postgres}''']::text[], 'count', '1'),
      ('V09 anon no puede insertar en catalog_products', 'anon', null, 'aal1', v_aux,
         array['insert into public.catalog_products (id, name) values (''rls41-x'', ''x'')']::text[], 'exec', '42501'),
      ('V10 dueño no puede actualizar catalog_products', 'authenticated', v_sup::text, 'aal1', v_aux,
         array['update public.catalog_products set name = ''x'' where id = ''rls41-a-pub''']::text[], 'exec', '42501'),
      ('V11 Mobau con AAL2: de los 10 auxiliares solo aparecen los 2 publicados', 'authenticated', v_pro3::text, 'aal2', v_aux,
         array['select count(*) where (select array_agg(id order by id) from public.catalog_products where id like ''rls41-%'') = array[''rls41-a-pub'', ''rls41-b-pub'']']::text[], 'count', '1'),
      ('V12 datos reales: catalog_products = products publicados y activos (21 columnas, huella)', '-', null, null, null::text[],
         array['select count(*) where (select md5(coalesce(string_agg(to_jsonb(r)::text, ''|'' order by r.id), '''')) from (select id, name, brand, distributor_id, category_id, subcategory, use_context, space, availability, description, measurements, materials, finishes, lead_time, icon, image_url, technical_sheet_url, cad_bim_3d_url, status, created_at, updated_at from public.catalog_products) r) = (select md5(coalesce(string_agg(to_jsonb(r)::text, ''|'' order by r.id), '''')) from (select id, name, brand, distributor_id, category_id, subcategory, use_context, space, availability, description, measurements, materials, finishes, lead_time, icon, image_url, technical_sheet_url, cad_bim_3d_url, status, created_at, updated_at from public.products where publication_status = ''published'' and status = ''active'') r)']::text[], 'count', '1'),
      ('K-anon anon: catalog_version() igual a la referencia', 'anon', null, 'aal1', v_aux,
         array[format('select count(*) where public.catalog_version() = %L', ref_ver)]::text[], 'count', '1'),
      ('K-pro profesional: catalog_version() igual a la referencia', 'authenticated', v_pro::text, 'aal1', v_aux,
         array[format('select count(*) where public.catalog_version() = %L', ref_ver)]::text[], 'count', '1'),
      ('K-own distribuidor dueño (A): catalog_version() igual a la referencia', 'authenticated', v_sup::text, 'aal1', v_aux,
         array[format('select count(*) where public.catalog_version() = %L', ref_ver)]::text[], 'count', '1'),
      ('K-oth otro distribuidor (B): catalog_version() igual a la referencia', 'authenticated', v_pro2::text, 'aal1', v_aux,
         array[format('select count(*) where public.catalog_version() = %L', ref_ver)]::text[], 'count', '1'),
      ('K-m1 Mobau sin AAL2: catalog_version() igual a la referencia', 'authenticated', v_pro3::text, 'aal1', v_aux,
         array[format('select count(*) where public.catalog_version() = %L', ref_ver)]::text[], 'count', '1'),
      ('K-m2 Mobau con AAL2: catalog_version() igual a la referencia', 'authenticated', v_pro3::text, 'aal2', v_aux,
         array[format('select count(*) where public.catalog_version() = %L', ref_ver)]::text[], 'count', '1'),
      ('K07 retirar un publicado cambia catalog_version()', 'anon', null, 'aal1', v_aux || array[v_retire_pub],
         array[format('select count(*) where public.catalog_version() <> %L', ref_ver)]::text[], 'count', '1'),
      ('K08 cambiar un distribuidor cambia catalog_version()', 'anon', null, 'aal1', v_aux || array[v_rename_dist],
         array[format('select count(*) where public.catalog_version() <> %L', ref_ver)]::text[], 'count', '1'),
      ('K09 cambiar un borrador (fuera del catálogo) NO cambia catalog_version()', 'anon', null, 'aal1', v_aux || array[v_rename_draft],
         array[format('select count(*) where public.catalog_version() = %L', ref_ver)]::text[], 'count', '1'),
      ('K10 catalog_version: SECURITY INVOKER, STABLE, search_path vacío', '-', null, null, null::text[],
         array['select count(*) from pg_proc where oid = ''public.catalog_version()''::regprocedure and not prosecdef and provolatile = ''s'' and proconfig @> array[''search_path=""'']']::text[], 'count', '1'),
      ('K11 catalog_version: EXECUTE anon y authenticated; ni service_role ni PUBLIC', '-', null, null, null::text[],
         array['select count(*) from pg_proc p where p.oid = ''public.catalog_version()''::regprocedure and has_function_privilege(''anon'', p.oid, ''EXECUTE'') and has_function_privilege(''authenticated'', p.oid, ''EXECUTE'') and not has_function_privilege(''service_role'', p.oid, ''EXECUTE'') and not exists (select 1 from aclexplode(p.proacl) a where a.grantee = 0)']::text[], 'count', '1'),
      ('K12 service_role no puede ejecutar catalog_version (42501)', 'service_role', null, null, v_aux,
         array['select public.catalog_version()']::text[], 'exec', '42501'),
      ('P01 profesional: catalog_published_prices() = referencia de 39-05 (recuento y huella)', 'authenticated', v_pro::text, 'aal1', v_aux,
         array[format('select count(*) from (select count(*) as n, md5(coalesce(string_agg(concat_ws('':'', r.product_id, coalesce(r.price_amount::text, ''-''), coalesce(r.currency, ''-''), r.price_status, coalesce(r.includes_itbis::text, ''-''), coalesce(r.itbis_rate::text, ''-''), coalesce(r.es_demo::text, ''-'')), ''|'' order by r.product_id), '''')) as fp from public.catalog_published_prices() r) x where x.n = %s and x.fp = %L', ref_price_n, ref_price_fp)]::text[], 'count', '1'),
      ('P02 retirado, borrador y papelera con precio: ninguna fila', 'authenticated', v_pro::text, 'aal1', v_aux,
         array['select count(*) from public.catalog_published_prices(array[''rls41-a-ret'', ''rls41-a-draft'', ''rls41-a-trd''])']::text[], 'count', '0'),
      ('P03 publicado con precio: una fila', 'authenticated', v_pro::text, 'aal1', v_aux,
         array['select count(*) from public.catalog_published_prices(array[''rls41-a-pub''])']::text[], 'count', '1'),
      ('P04 anon no puede ejecutar catalog_published_prices', 'anon', null, 'aal1', v_aux,
         array['select count(*) from public.catalog_published_prices()']::text[], 'exec', '42501'),
      ('P05 catalog_published_prices: cuerpo de 41-02, misma ACL, SECURITY DEFINER, search_path vacío', '-', null, null, null::text[],
         array['select count(*) from pg_proc where oid = ''public.catalog_published_prices(text[], text, integer)''::regprocedure and md5(prosrc) = ''366f275cf85ec6c10956cecfbbc92ed5'' and proacl::text = ''{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}'' and prosecdef and proconfig @> array[''search_path=""'']']::text[], 'count', '1'),
      ('S01 mobau_private: sin USAGE para anon, authenticated ni service_role; ACL solo postgres', '-', null, null, null::text[],
         array['select count(*) where not has_schema_privilege(''anon'', ''mobau_private'', ''USAGE'') and not has_schema_privilege(''authenticated'', ''mobau_private'', ''USAGE'') and not has_schema_privilege(''service_role'', ''mobau_private'', ''USAGE'') and not exists (select 1 from pg_namespace n, aclexplode(n.nspacl) a where n.nspname = ''mobau_private'' and a.grantee <> ''postgres''::regrole)']::text[], 'count', '1'),
      ('S02 anon no puede leer la auditoría', 'anon', null, 'aal1', v_aux,
         array['select count(*) from mobau_private.product_lifecycle_events']::text[], 'exec', '42501'),
      ('S03 dueño no puede leer la auditoría', 'authenticated', v_sup::text, 'aal1', v_aux,
         array['select count(*) from mobau_private.product_lifecycle_events']::text[], 'exec', '42501'),
      ('S04 service_role no puede leer la auditoría', 'service_role', null, null, v_aux,
         array['select count(*) from mobau_private.product_lifecycle_events']::text[], 'exec', '42501'),
      ('S05 Mobau con AAL2 no puede escribir en la auditoría', 'authenticated', v_pro3::text, 'aal2', v_aux,
         array['insert into mobau_private.product_lifecycle_events (product_id, distributor_id, action, actor_kind) values (''rls41-a-pub'', ''x'', ''retire'', ''mobau'')']::text[], 'exec', '42501'),
      ('S06 auditoría: sin privilegios de tabla ni de secuencia para clientes; RLS activa; sin políticas; vacía', '-', null, null, null::text[],
         array['select count(*) where not exists (select 1 from unnest(array[''anon'', ''authenticated'', ''service_role'']) g, unnest(array[''SELECT'', ''INSERT'', ''UPDATE'', ''DELETE'', ''TRUNCATE'']) p where has_table_privilege(g, ''mobau_private.product_lifecycle_events'', p)) and not exists (select 1 from unnest(array[''anon'', ''authenticated'', ''service_role'']) g, unnest(array[''USAGE'', ''SELECT'', ''UPDATE'']) p where has_sequence_privilege(g, ''mobau_private.product_lifecycle_events_id_seq'', p)) and (select relrowsecurity from pg_class where oid = ''mobau_private.product_lifecycle_events''::regclass) and not exists (select 1 from pg_policies where schemaname = ''mobau_private'') and not exists (select 1 from mobau_private.product_lifecycle_events)']::text[], 'count', '1'),
      ('S07 product_lifecycle_state: sin EXECUTE para clientes ni PUBLIC; IMMUTABLE; invoker; search_path vacío', '-', null, null, null::text[],
         array['select count(*) from pg_proc p where p.oid = ''mobau_private.product_lifecycle_state(text, timestamptz, timestamptz)''::regprocedure and not has_function_privilege(''anon'', p.oid, ''EXECUTE'') and not has_function_privilege(''authenticated'', p.oid, ''EXECUTE'') and not has_function_privilege(''service_role'', p.oid, ''EXECUTE'') and not exists (select 1 from aclexplode(p.proacl) a where a.grantee <> ''postgres''::regrole) and p.provolatile = ''i'' and not p.prosecdef and p.proconfig @> array[''search_path=""'']']::text[], 'count', '1'),
      ('S08 dueño no puede llamar a product_lifecycle_state', 'authenticated', v_sup::text, 'aal1', v_aux,
         array['select mobau_private.product_lifecycle_state(''published'', null, null)']::text[], 'exec', '42501'),
      ('S09 product_lifecycle_state: los 8 casos dan el estado esperado', '-', null, null, null::text[],
         array['select count(*) from (values (''published'', null::timestamptz, null::timestamptz, ''published''), (''archived'', now(), null, ''retired''), (''archived'', null, null, ''legacy_retired''), (''archived'', now(), now(), ''trashed''), (''draft'', null, now(), ''trashed''), (''draft'', null, null, ''draft''), (''in_review'', null, null, ''in_review''), (''changes_requested'', null, null, ''changes_requested'')) v(s, r, t, e) where mobau_private.product_lifecycle_state(v.s, v.r, v.t) = v.e']::text[], 'count', '8'),
      ('X01 publicado con retired_*: rechazado', '-', null, null, v_aux,
         array[format('update public.products set retired_at = now(), retired_by = %L, retired_reason = ''Motivo 41'' where id = ''rls41-a-pub''', v_pro3)]::text[], 'exec', '23514'),
      ('X02 borrador con retired_*: rechazado', '-', null, null, v_aux,
         array[format('update public.products set retired_at = now(), retired_by = %L, retired_reason = ''Motivo 41'' where id = ''rls41-a-draft''', v_pro3)]::text[], 'exec', '23514'),
      ('X03 retired_at sin retired_by ni motivo: rechazado', '-', null, null, v_aux,
         array['update public.products set retired_at = now() where id = ''rls41-a-leg''']::text[], 'exec', '23514'),
      ('X04 motivo en blanco: rechazado', '-', null, null, v_aux,
         array[format('update public.products set retired_at = now(), retired_by = %L, retired_reason = ''   '' where id = ''rls41-a-leg''', v_pro3)]::text[], 'exec', '23514'),
      ('X05 motivo de 501 caracteres: rechazado', '-', null, null, v_aux,
         array[format('update public.products set retired_at = now(), retired_by = %L, retired_reason = repeat(''x'', 501) where id = ''rls41-a-leg''', v_pro3)]::text[], 'exec', '23514'),
      ('X06 papelera con purge_after distinto de +30 días: rechazado', '-', null, null, v_aux,
         array[format('update public.products set trashed_at = now(), trashed_by = %L, trash_from = ''retired'', purge_after = now() + interval ''29 days'' where id = ''rls41-a-ret''', v_pro3)]::text[], 'exec', '23514'),
      ('X07 papelera con trash_from no permitido: rechazado', '-', null, null, v_aux,
         array[format('update public.products set trashed_at = now(), trashed_by = %L, trash_from = ''published'', purge_after = now() + interval ''30 days'' where id = ''rls41-a-ret''', v_pro3)]::text[], 'exec', '23514'),
      ('X08 publicado en papelera: rechazado', '-', null, null, v_aux,
         array[format('update public.products set trashed_at = now(), trashed_by = %L, trash_from = ''draft'', purge_after = now() + interval ''30 days'' where id = ''rls41-a-pub''', v_pro3)]::text[], 'exec', '23514'),
      ('X09 trashed_at sin el resto de campos: rechazado', '-', null, null, v_aux,
         array['update public.products set trashed_at = now() where id = ''rls41-a-ret''']::text[], 'exec', '23514'),
      ('X10 retirada coherente (archivado + retired_*): aceptada', '-', null, null, v_aux,
         array[format('update public.products set publication_status = ''archived'', retired_at = now(), retired_by = %L, retired_reason = ''Motivo 41'' where id = ''rls41-a-pub''', v_pro3)]::text[], 'exec', 'ok'),
      ('X11 papelera coherente desde borrador: aceptada', '-', null, null, v_aux,
         array[format('update public.products set trashed_at = now(), trashed_by = %L, trash_from = ''draft'', purge_after = now() + interval ''30 days'' where id = ''rls41-a-draft''', v_pro3)]::text[], 'exec', 'ok'),
      ('N01 el distribuidor envía una propuesta de cambio: copia con exactamente las 22 claves (sin ciclo de vida)', 'authenticated', v_sup::text, 'aal1', v_aux || array[v_prop],
         array[format('with u as (update public.product_proposals set status = %L where id = %L returning product_snapshot) select count(*) from u where (select array_agg(k order by k) from jsonb_object_keys(u.product_snapshot -> %L) k) = %L::text[]', 'submitted', p41, 'product', '{availability,brand,cad_bim_3d_url,category_id,created_at,description,distributor_id,finishes,icon,id,image_url,lead_time,materials,measurements,name,publication_status,space,status,subcategory,technical_sheet_url,updated_at,use_context}')]::text[], 'count', '1'),
      ('N02 la copia es igual a las 22 columnas del producto', 'authenticated', v_sup::text, 'aal1', v_aux || array[v_prop],
         array[format('update public.product_proposals set status = %L where id = %L', 'submitted', p41),
               format('select count(*) from public.product_proposals pr where pr.id = %L and pr.product_snapshot -> %L = (select to_jsonb(s) from (select p.id, p.name, p.distributor_id, p.brand, p.category_id, p.subcategory, p.use_context, p.space, p.availability, p.description, p.measurements, p.materials, p.finishes, p.lead_time, p.icon, p.technical_sheet_url, p.cad_bim_3d_url, p.image_url, p.created_at, p.status, p.updated_at, p.publication_status from public.products p where p.id = %L) s)', p41, 'product', 'rls41-a-pub')]::text[], 'count', '1'),
      ('N03 snapshot_product_on_submit: cuerpo de 41-04 (41-01 + republish), misma ACL, invoker, search_path vacío', '-', null, null, null::text[],
         array['select count(*) from pg_proc where oid = ''public.snapshot_product_on_submit()''::regprocedure and md5(prosrc) = ''92d5158e8454b17263942346e5487d7c'' and proacl::text = ''{postgres=X/postgres,service_role=X/postgres}'' and not prosecdef and proconfig @> array[''search_path=""'']']::text[], 'count', '1'),
      ('Z01 moderate_product_proposal: cuerpo de 41-04 (40-01 + republish)', '-', null, null, null::text[],
         array['select count(*) from pg_proc where oid = ''public.moderate_product_proposal(uuid, text, text, integer)''::regprocedure and md5(prosrc) = ''aa4fac4c25f4634499532824782ee908''']::text[], 'count', '1'),
      ('Z02 políticas en public = 48', '-', null, null, null::text[],
         array['select count(*) from pg_policies where schemaname = ''public''']::text[], 'count', '48'),
      ('Z03 mobau_admins idéntica a la línea base', '-', null, null, null::text[],
         array[format('select count(*) from (select count(*) as n, md5(coalesce(string_agg(to_jsonb(a)::text, %L order by a.user_id), %L)) as fp from public.mobau_admins a) x where x.n = %s and x.fp = %L', '|', '', v_adm_n, v_adm_md5)]::text[], 'count', '1'),
      ('Z04 contexto de moderación vacío', '-', null, null, null::text[],
         array['select count(*) from public.mobau_moderation_context']::text[], 'count', '0'),
      ('Z05 sin restos rls41 (productos, distribuidores, perfiles, propuestas)', '-', null, null, null::text[],
         array['select (select count(*) from public.products where id like ''rls41-%'') + (select count(*) from public.distributors where id like ''rls41-%'') + (select count(*) from public.distributor_profiles where distributor_id like ''rls41-%'') + (select count(*) from public.product_proposals where id = ''41000000-0000-4000-8000-000000000001'')']::text[], 'count', '0'),
      ('Z06 productos reales: proyección de las 22 columnas igual a la tomada al empezar la suite', '-', null, null, null::text[],
         array[format('select count(*) from (select count(*) as n, md5(coalesce(string_agg(to_jsonb(r)::text, ''|'' order by r.id), '''')) as fp from (select id, name, distributor_id, brand, category_id, subcategory, use_context, space, availability, description, measurements, materials, finishes, lead_time, icon, technical_sheet_url, cad_bim_3d_url, image_url, created_at, status, updated_at, publication_status from public.products) r) x where x.n = %s and x.fp = %L', v_real_n, v_real_fp)]::text[], 'count', '1')
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

  raise exception 'MOBAU_41_V1 total=% ok=% fallos=% :: %', n_total, n_ok, n_total - n_ok, r::text
    using errcode = 'MB999';
end $$;

ROLLBACK;
