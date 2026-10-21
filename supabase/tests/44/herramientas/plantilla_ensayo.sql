-- ============================================================
-- PROPUESTA NO EJECUTADA (44 · ensayo P44 con Vibia 3225, revertido) — no ejecutar sin aprobación explícita
-- ============================================================
-- Generado por herramientas/generar_44.py. Una sola transacción que
-- SIEMPRE termina con MB990 (nada persiste: ni filas, ni buckets, ni
-- archivos; en Storage solo se insertan filas de prueba, sin contenido):
--   1. huella y sondas de la web de partida;
--   2. aplica 44-01 (texto incrustado con su MD5);
--   3. flujo completo de 3225 como Spectro, Mobau (aal2), Gratis e
--      Individual, en una subtransacción que se deshace (MB001);
--      dentro, la recuperación con datos (respaldo r44) se ensaya en otra
--      subtransacción que también se deshace (MB002);
--   4. aplica la recuperación sin datos (texto incrustado con su MD5);
--   5. huella y sondas finales: deben ser idénticas a las de partida.
-- Éxito: «MOBAU_44_P cambia=true identico=true sondas=true fallos=0» y
-- ningún «!» ni «ABORTO» en la lista de casos.
-- Ejecutar completo, con el control MD5 del archivo.
-- ============================================================

BEGIN;

DO $P44$
declare
  t_mig text := $M44${{MIGRACION}}$M44$;
  t_rec text := $R44${{RECUPERACION}}$R44$;
  q_huella text := $Q$
    select md5(concat_ws('#',
      (select string_agg(table_name || '.' || column_name || ':' || data_type || ':' || is_nullable || ':' || coalesce(column_default, '-'), '|' order by table_name, ordinal_position)
         from information_schema.columns where table_schema = 'public'),
      (select string_agg(schemaname || '.' || tablename || '.' || policyname || ':' || permissive || ':' || cmd || ':' || roles::text || ':' || coalesce(qual, '-') || ':' || coalesce(with_check, '-'), '|' order by schemaname, tablename, policyname)
         from pg_policies where schemaname in ('public', 'storage')),
      (select string_agg(p.oid::regprocedure::text || ':' || md5(p.prosrc) || ':' || p.prosecdef::text || ':' || coalesce(p.proacl::text, '-') || ':' || coalesce(array_to_string(p.proconfig, ','), '-'), '|' order by p.oid::regprocedure::text)
         from pg_proc p where p.pronamespace = 'public'::regnamespace),
      (select string_agg(tgrelid::regclass::text || '.' || tgname || ':' || tgfoid::regproc::text || ':' || tgtype::text, '|' order by tgrelid::regclass::text, tgname)
         from pg_trigger where not tgisinternal and tgrelid in (select oid from pg_class where relnamespace in ('public'::regnamespace, 'storage'::regnamespace))),
      (select string_agg(c.relname || ':' || c.relkind::text || ':' || coalesce(c.relacl::text, '-') || ':' || coalesce(c.reloptions::text, '-') || ':' || c.relrowsecurity::text
                         || ':' || coalesce(obj_description(c.oid, 'pg_class'), '-') || ':' || case when c.relkind = 'v' then md5(pg_get_viewdef(c.oid)) else '-' end, '|' order by c.relname)
         from pg_class c where c.relnamespace = 'public'::regnamespace and c.relkind in ('r', 'v', 'i', 'S')),
      (select string_agg(conrelid::regclass::text || '.' || conname || ':' || pg_get_constraintdef(oid), '|' order by conrelid::regclass::text, conname)
         from pg_constraint where connamespace = 'public'::regnamespace),
      (select string_agg(grantee || ':' || table_name || '.' || column_name || ':' || privilege_type, '|' order by grantee, table_name, column_name, privilege_type)
         from information_schema.column_privileges where table_schema = 'public' and grantee in ('anon', 'authenticated')),
      (select coalesce(string_agg(id || ':' || public::text, '|' order by id), '-') from storage.buckets),
      (select coalesce(string_agg(relname, '|' order by relname), '-') from pg_class where relnamespace = 'mobau_private'::regnamespace),
      (select count(*)::text from supabase_migrations.schema_migrations),
      (select string_agg(id || ':' || coalesce(publication_status, '-') || ':' || updated_at::text || ':' || coalesce(finishes, '-'), '|' order by id) from public.products),
      (select string_agg(id::text || ':' || product_id || ':' || quantity::text || ':' || unit, '|' order by id) from public.project_products),
      (select string_agg(id::text || ':' || status || ':' || version::text, '|' order by id) from public.product_proposals),
      (select count(*)::text from storage.objects)))
  $Q$;
  h0 text; h1 text; h2 text;
  p0 text; p1 text; p2 text;
  res text := '';
  fallos integer := 0;
  v_paso text := 'inicio';
  v_t text;
  v_b integer; v_e integer;
  v_sup uuid; v_adm uuid; v_ind uuid; v_gra uuid; v_proj uuid;
  a0 uuid; a1 uuid; a2 uuid; a3 uuid; a4 uuid; a5 uuid; a6 uuid; a7 uuid; a8 uuid; a9 uuid;
  pid uuid; uid2 uuid; uid3 uuid;
  v_prod text;
  v_ver integer;
  v_r jsonb;
  m1 jsonb; m2 jsonb; m3 jsonb;
  f text := '00000000-0000-4044-8000-000000004401';
  ch jsonb := jsonb_build_object('name', 'P44 Dama ensayo', 'brand', 'Vibia',
                                 'description', 'Lámpara de sobremesa Dama (ensayo 44, se deshace).',
                                 'category_id', 'iluminacion', 'subcategory', 'Decorativa', 'availability', 'bajo-pedido');
begin
  if md5(t_mig) <> '{{MIGRACION_MD5}}' or md5(t_rec) <> '{{RECUPERACION_MD5}}' then
    raise exception 'MOBAU_44_P: los textos incrustados no coinciden con su MD5' using errcode = 'MB997';
  end if;
  if current_user <> 'postgres' then
    raise exception 'MOBAU_44_P: ejecutar como postgres' using errcode = 'MB998';
  end if;

  -- ---------- 0. Identidades (por prefijo) y partida ----------
  select id into v_sup from public.profiles where id::text like '392a9eb4%' and role = 'supplier';
  select id into v_adm from public.profiles where id::text like 'a8fe42e8%' and role = 'admin';
  select id into v_ind from public.profiles where id::text like 'e2a655c1%' and role = 'individual';
  select id into v_gra from public.profiles where id::text like '46ea4397%' and role = 'individual';
  select id into v_proj from public.projects where owner_user_id = v_ind and status = 'active' order by created_at limit 1;
  if v_sup is null or v_adm is null or v_ind is null or v_gra is null or v_proj is null
     or not exists (select 1 from public.distributor_profiles where user_id = v_sup and distributor_id = 'spectro' and verification_status = 'verified')
     or not exists (select 1 from public.mobau_admins where user_id = v_adm) then
    raise exception 'MOBAU_44_P: faltan identidades o el proyecto activo de Individual' using errcode = 'MB998';
  end if;
  if exists (select 1 from public.products where distributor_id = 'spectro' and name = 'P44 Dama ensayo') then
    raise exception 'MOBAU_44_P: ya existe un producto de ensayo' using errcode = 'MB998';
  end if;

  execute q_huella into h0;
{{SONDAS:p0}}

  -- ---------- 1. Aplicar 44-01 ----------
  v_b := strpos(t_mig, E'\nBEGIN;\n'); v_e := strpos(t_mig, E'\nCOMMIT;\n');
  execute substr(t_mig, v_b + 8, v_e - (v_b + 8));
  execute q_huella into h1;
{{SONDAS:p1}}

  -- ---------- 2. Flujo de 3225 (se deshace con MB001) ----------
  begin
    v_paso := 'S00';
    -- Archivo de otra empresa (para S11), como postgres.
    insert into public.product_assets (distributor_id, kind, bucket, path, original_name, format)
    values ('baccara', 'foto', 'productos-imagenes', 'baccara/' || f || '/ajena.jpg', 'ajena.jpg', 'jpg') returning id into a0;

    -- S01 Spectro registra sus 9 archivos (pendientes)
{{COMO:v_sup:aal1}}
    v_paso := 'S01';
    insert into public.product_assets (distributor_id, kind, bucket, path, variants, original_name, format, bytes, width, height)
    values ('spectro', 'foto', 'productos-imagenes', 'spectro/' || f || '/portada.jpg',
            jsonb_build_object('card', 'spectro/' || f || '/portada-card.jpg'), 'Vibia_Dama_3225-25_04.jpg', 'jpg', 420000, 1600, 2000) returning id into a1;
    insert into public.product_assets (distributor_id, kind, bucket, path, variants, original_name, format, bytes, width, height)
    values ('spectro', 'foto', 'productos-imagenes', 'spectro/' || f || '/acabado-25.jpg',
            jsonb_build_object('card', 'spectro/' || f || '/acabado-25-card.jpg'), 'Vibia_Dama_3225-25_sob_Silueta.png', 'jpg', 180000, 1600, 2000) returning id into a2;
    insert into public.product_assets (distributor_id, kind, bucket, path, variants, original_name, format, bytes, width, height)
    values ('spectro', 'foto', 'productos-imagenes', 'spectro/' || f || '/acabado-11.jpg',
            jsonb_build_object('card', 'spectro/' || f || '/acabado-11-card.jpg'), 'Vibia_Dama_3225-11_sob_Silueta.png', 'jpg', 170000, 1600, 2000) returning id into a3;
    insert into public.product_assets (distributor_id, kind, bucket, path, original_name, format, bytes, width, height)
    values ('spectro', 'foto', 'productos-imagenes', 'spectro/' || f || '/galeria-1.jpg', 'Vibia_Dama_3225-25_03.jpg', 'jpg', 650000, 2080, 2400) returning id into a4;
    insert into public.product_assets (distributor_id, kind, bucket, path, original_name, format, bytes)
    values ('spectro', 'ficha_tecnica', 'productos-archivos', 'spectro/' || f || '/specSheet3225_es.pdf', 'specSheet3225_es.pdf', 'pdf', 900000) returning id into a5;
    insert into public.product_assets (distributor_id, kind, bucket, path, original_name, format, bytes)
    values ('spectro', 'cad_2d', 'productos-archivos', 'spectro/' || f || '/3225_Dama.dwg', '3225_Dama.dwg', 'dwg', 300000) returning id into a6;
    insert into public.product_assets (distributor_id, kind, bucket, path, original_name, format, bytes)
    values ('spectro', 'cad_3d', 'productos-archivos', 'spectro/' || f || '/3225.obj', '3225.obj', 'obj', 5000000) returning id into a7;
    insert into public.product_assets (distributor_id, kind, bucket, path, original_name, format, bytes)
    values ('spectro', 'calculo_iluminacion', 'productos-archivos', 'spectro/' || f || '/3225-2700K.IES', '3225-2700K.IES', 'ies', 20000) returning id into a8;
    insert into public.product_assets (distributor_id, kind, bucket, path, original_name, format, bytes)
    values ('spectro', 'calculo_iluminacion', 'productos-archivos', 'spectro/' || f || '/3225-2700K.LDT', '3225-2700K.LDT', 'ldt', 20000) returning id into a9;
@@CHECK S01 | (select count(*) from public.product_assets where distributor_id = 'spectro' and status = 'pendiente' and product_id is null and uploaded_by = v_sup) | 9

    -- S02–S07 Altas no permitidas
@@ERR S02 | insert into public.product_assets (distributor_id, kind, bucket, path, original_name, format) values ('baccara', 'foto', 'productos-imagenes', 'baccara/' || f || '/x.jpg', 'x.jpg', 'jpg') | 42501
@@ERR S03 | insert into public.product_assets (distributor_id, kind, bucket, path, original_name, format, status) values ('spectro', 'foto', 'productos-imagenes', 'spectro/' || f || '/y.jpg', 'y.jpg', 'jpg', 'aprobado') | 42501
@@ERR S04 | insert into public.product_assets (distributor_id, kind, bucket, path, original_name, format) values ('spectro', 'foto', 'productos-imagenes', 'spectro/' || f || '/z.png', 'z.png', 'png') | 23514
@@ERR S05 | insert into public.product_assets (distributor_id, kind, bucket, path, original_name, format) values ('spectro', 'foto', 'productos-imagenes', 'spectro/../baccara/w.jpg', 'w.jpg', 'jpg') | 23514
@@ERR S06 | insert into public.product_assets (distributor_id, kind, bucket, path, variants, original_name, format) values ('spectro', 'ficha_tecnica', 'productos-archivos', 'spectro/' || f || '/v.pdf', '{"card": "spectro/x/v.jpg"}', 'v.pdf', 'pdf') | 23514
@@ERR S07 | insert into public.product_assets (distributor_id, kind, bucket, path, original_name, format) values ('spectro', 'cad_2d', 'productos-imagenes', 'spectro/' || f || '/u.dwg', 'u.dwg', 'dwg') | 23514
{{COMO_ANON}}
@@ERR S08 | insert into public.product_assets (distributor_id, kind, bucket, path, original_name, format) values ('spectro', 'foto', 'productos-imagenes', 'spectro/' || f || '/t.jpg', 't.jpg', 'jpg') | 42501

    -- S09–S11 Storage: subir solo en la carpeta propia
{{COMO:v_sup:aal1}}
    v_paso := 'S09';
    insert into storage.objects (bucket_id, name)
    select a.bucket, a.path from public.product_assets a where a.distributor_id = 'spectro';
@@CHECK S09 | (select count(*) from storage.objects where name like 'spectro/' || f || '/%') | 9
@@ERR S10 | insert into storage.objects (bucket_id, name) values ('productos-archivos', 'baccara/' || f || '/x.pdf') | 42501
{{COMO_ANON}}
@@ERR S11 | insert into storage.objects (bucket_id, name) values ('productos-imagenes', 'spectro/' || f || '/anon.jpg') | 42501

    -- S12–S18 Propuesta de producto nuevo (borrador → envío)
{{COMO:v_sup:aal1}}
    v_paso := 'S12';
    m1 := jsonb_build_object(
      'finishes', jsonb_build_array(
         jsonb_build_object('code', '25', 'name', 'Beige D1', 'reference_code', '3225-25', 'image_asset_id', a2, 'is_default', true),
         jsonb_build_object('code', '11', 'name', 'Black', 'reference_code', '3225-11', 'image_asset_id', a3, 'is_default', false)),
      'assets', jsonb_build_array(
         jsonb_build_object('id', a1, 'label', 'Portada'), jsonb_build_object('id', a2, 'label', 'Beige D1'),
         jsonb_build_object('id', a3, 'label', 'Black'), jsonb_build_object('id', a4),
         jsonb_build_object('id', a5, 'label', 'Ficha técnica'), jsonb_build_object('id', a6, 'label', 'Planta y alzado'),
         jsonb_build_object('id', a7, 'label', 'Modelo 3D'), jsonb_build_object('id', a8, 'label', 'IES 2700K')));
@@ERR S12 | insert into public.product_proposals (proposal_kind, distributor_id, proposed_changes, proposed_price_status, proposed_media) values ('create', 'spectro', ch, 'quote_required', jsonb_build_object('assets', jsonb_build_array(jsonb_build_object('id', a0)))) | 23514
    insert into public.product_proposals (proposal_kind, distributor_id, proposed_changes, proposed_price_status, proposed_media)
    values ('create', 'spectro', ch, 'quote_required', m1) returning id into pid;
@@CHECK S13 | (select status || ':' || (proposed_media ->> 'reference_code' is null)::text from public.product_proposals where id = pid) | draft:true
@@ERR S14 | update public.product_proposals set proposed_media = m1 || jsonb_build_object('cover_asset_id', a4) where id = pid | 23514
@@ERR S15 | update public.product_proposals set proposed_media = jsonb_set(m1, '{finishes,1,is_default}', 'true') where id = pid | 23514
@@ERR S16 | update public.product_proposals set proposed_media = jsonb_set(m1, '{assets}', (m1 -> 'assets') || jsonb_build_array(jsonb_build_object('id', a1))) where id = pid | 23514
@@ERR S17 | update public.product_proposals set status = 'submitted' where id = pid | 23514
    v_paso := 'S18';
    -- Referencia sí, portada todavía no (para ensayar que Mobau no puede aprobar sin ella).
    m2 := m1 || jsonb_build_object('reference_code', '3225');
    update public.product_proposals set proposed_media = m2 where id = pid;
    update public.product_proposals set status = 'submitted' where id = pid;
@@CHECK S18 | (select status from public.product_proposals where id = pid) | submitted
@@ERR S19 | update public.product_proposals set proposed_media = m2 || jsonb_build_object('cover_asset_id', a1) where id = pid | 42501

    -- S20–S23 Moderación: sin portada no se aprueba
{{COMO:v_adm:aal2}}
    v_paso := 'S20';
    select version into v_ver from public.product_proposals where id = pid;
@@ERR S20 | perform public.moderate_product_proposal(pid, 'approve', null, v_ver) | 55000
@@CHECK S21 | (select count(*) from public.products where distributor_id = 'spectro' and name = 'P44 Dama ensayo') | 0
    v_paso := 'S22';
    perform public.moderate_product_proposal(pid, 'request_changes', 'Elige la foto de portada.', v_ver);
{{COMO:v_sup:aal1}}
    v_paso := 'S23';
    m2 := m2 || jsonb_build_object('cover_asset_id', a1);
    update public.product_proposals set proposed_media = m2 where id = pid;
    update public.product_proposals set status = 'submitted' where id = pid;
@@CHECK S23 | (select status || ':' || (proposed_media ->> 'cover_asset_id') from public.product_proposals where id = pid) | submitted:' || a1::text || '
{{COMO:v_adm:aal2}}
    v_paso := 'S24';
    select version into v_ver from public.product_proposals where id = pid;
    v_r := public.moderate_product_proposal(pid, 'approve', null, v_ver);
    select created_product_id into v_prod from public.product_proposals where id = pid;
@@CHECK S24 | (v_r ->> 'result') || ':' || (v_prod is not null)::text | approved:true

    -- S25–S27 Resultado en la base
{{COMO_PG}}
@@CHECK S25 | (select reference_code || '|' || (cover_asset_id = a1)::text || '|' || publication_status || '|' || status || '|' || coalesce(finishes, '-') from public.products where id = v_prod) | 3225|true|published|active|Beige D1, Black
@@CHECK S26 | (select string_agg(a.status || ':' || count, ',' order by a.status) from (select status, count(*)::text as count from public.product_assets where distributor_id = 'spectro' and path like 'spectro/' || f || '/%' group by status) a) || '|' || (select count(*) from public.product_assets where product_id = v_prod and proposal_id = pid and status = 'aprobado') || '|' || (select label from public.product_assets where id = a5) | aprobado:8,pendiente:1|8|Ficha técnica
@@CHECK S27 | (select string_agg(code || ':' || name || ':' || coalesce(reference_code, '-') || ':' || is_default::text || ':' || (image_asset_id = case code when '25' then a2 else a3 end)::text, '|' order by sort_order) from public.product_finishes where product_id = v_prod) | 25:Beige D1:3225-25:true:true|11:Black:3225-11:false:true

    -- S28–S31 Lo que ve el público
{{COMO_ANON}}
@@CHECK S28 | (select reference_code || '|' || (cover_path = 'spectro/' || f || '/portada.jpg')::text || '|' || (cover_card_path = 'spectro/' || f || '/portada-card.jpg')::text || '|' || jsonb_array_length(finish_options)::text || '|' || (finish_options -> 0 ->> 'code') || ':' || (finish_options -> 0 ->> 'is_default') || ':' || (finish_options -> 0 ->> 'image_card_path') from public.catalog_products where id = v_prod) | 3225|true|true|2|25:true:spectro/' || f || '/acabado-25-card.jpg
@@CHECK S29 | (select count(*) from public.product_assets where product_id = v_prod) || '|' || (select count(*) from public.product_assets where id in (a9, a0)) || '|' || (select count(*) from public.product_finishes where product_id = v_prod) | 8|0|2
@@CHECK S30 | (select count(*) from storage.objects where bucket_id = 'productos-archivos') | 0
@@ERR S31 | perform public.can_download_product_file('spectro/' || f || '/3225.obj') | 42501

    -- S32–S35 Descargas privadas por rol (a5–a8 aprobados; a9 pendiente)
{{COMO:v_gra:aal1}}
@@CHECK S32 | (select count(*) from storage.objects where bucket_id = 'productos-archivos' and name like 'spectro/' || f || '/%') | 4
{{COMO:v_ind:aal1}}
@@CHECK S33 | (select count(*) from storage.objects where bucket_id = 'productos-archivos' and name like 'spectro/' || f || '/%') | 4
{{COMO:v_sup:aal1}}
@@CHECK S34 | (select count(*) from storage.objects where bucket_id = 'productos-archivos' and name like 'spectro/' || f || '/%') | 5
{{COMO:v_adm:aal2}}
@@CHECK S35 | (select count(*) from storage.objects where bucket_id = 'productos-archivos' and name like 'spectro/' || f || '/%') | 5

    -- S36–S41 Proyecto de Individual: una línea por producto y acabado
{{COMO:v_ind:aal1}}
    v_paso := 'S36';
    insert into public.project_products (project_id, product_id, quantity, unit, finish_code) values (v_proj, v_prod, 2, 'ud.', '25');
    insert into public.project_products (project_id, product_id, quantity, unit, finish_code) values (v_proj, v_prod, 1, 'ud.', '11');
@@CHECK S36 | (select string_agg(coalesce(finish_code, '-') || ':' || quantity::text || ':' || unit, '|' order by finish_code) from public.project_products where project_id = v_proj and product_id = v_prod) | 11:1.00:ud.|25:2.00:ud.
@@ERR S37 | insert into public.project_products (project_id, product_id, quantity, unit, finish_code) values (v_proj, v_prod, 5, 'ud.', '25') | 23505
    v_paso := 'S38';
    update public.project_products set quantity = 3 where project_id = v_proj and product_id = v_prod and finish_code = '25';
@@CHECK S38 | (select quantity::text from public.project_products where project_id = v_proj and product_id = v_prod and finish_code = '25') | 3.00
@@ERR S39 | update public.project_products set finish_code = '11' where project_id = v_proj and product_id = v_prod and finish_code = '25' | 42501
@@ERR S40 | insert into public.project_products (project_id, product_id, quantity, unit, finish_code) values (v_proj, v_prod, 1, 'ud.', ' 25') | 23514
    v_paso := 'S41';
    insert into public.project_products (project_id, product_id, quantity, unit) values (v_proj, v_prod, 1, 'ud.');
@@ERR S41 | insert into public.project_products (project_id, product_id, quantity, unit) values (v_proj, v_prod, 1, 'ud.') | 23505

    -- S42–S45 Propuesta de cambio solo con archivos (añade el LDT)
{{COMO:v_sup:aal1}}
    v_paso := 'S42';
    m3 := jsonb_set(m2, '{assets}', (m2 -> 'assets') || jsonb_build_array(jsonb_build_object('id', a9, 'label', 'LDT 2700K')));
    insert into public.product_proposals (proposal_kind, product_id, distributor_id, proposed_media)
    values ('update', v_prod, 'spectro', m3) returning id into uid2;
    update public.product_proposals set status = 'submitted' where id = uid2;
@@CHECK S42 | (select status from public.product_proposals where id = uid2) | submitted
{{COMO:v_adm:aal2}}
    v_paso := 'S43';
    select version into v_ver from public.product_proposals where id = uid2;
    v_r := public.moderate_product_proposal(uid2, 'approve', null, v_ver);
@@CHECK S43 | (v_r ->> 'result') || '|' || (select count(*) from public.product_assets where product_id = v_prod and status = 'aprobado') || '|' || (select label from public.product_assets where id = a9) | approved|9|LDT 2700K
    -- Sigue rechazándose una propuesta de cambio sin cambios ni archivos.
{{COMO:v_sup:aal1}}
    v_paso := 'S44';
    insert into public.product_proposals (proposal_kind, product_id, distributor_id) values ('update', v_prod, 'spectro') returning id into uid3;
@@ERR S44 | update public.product_proposals set status = 'submitted' where id = uid3 | 23514
{{COMO_ANON}}
@@CHECK S45 | (select count(*) from public.catalog_products where id = v_prod and reference_code = '3225') || '|' || (select count(*) from public.product_assets where product_id = v_prod) | 1|9

    -- S46–S47 Recuperación con datos (se deshace con MB002)
{{COMO_PG}}
    v_paso := 'S46';
    begin
      v_b := strpos(t_rec, E'\nBEGIN;\n'); v_e := strpos(t_rec, E'\nCOMMIT;\n');
      begin
        execute substr(t_rec, v_b + 8, v_e - (v_b + 8));
        v_t := 'sin_error';
      exception when others then
        v_t := sqlstate;
      end;
      res := res || ' S46=' || v_t;
      if v_t is distinct from 'MB441' then fallos := fallos + 1; res := res || '!'; end if;
      -- Queda una sola línea por producto en el proyecto (decisión simulada).
      delete from public.project_products where project_id = v_proj and product_id = v_prod and finish_code is distinct from '25';
      v_paso := 'S47';
      execute substr(t_rec, v_b + 8, v_e - (v_b + 8));
      v_t := (select count(*) from mobau_private.r44_product_assets) || '|' || (select count(*) from mobau_private.r44_product_finishes)
             || '|' || (select count(*) from mobau_private.r44_products) || '|' || (select count(*) from mobau_private.r44_proposals_media)
             || '|' || (select count(*) from mobau_private.r44_project_lines) || '|' || (select count(*) from mobau_private.r44_storage_objects)
             || '|' || (select string_agg(id, ',' order by id) from storage.buckets where id like 'productos-%')
             || '|' || (to_regclass('public.product_assets') is null)::text
             || '|' || (select md5(prosrc) from pg_proc where oid = 'public.transition_proposal_status()'::regprocedure)
             || '|' || md5(pg_get_viewdef('public.catalog_products'::regclass));
      res := res || ' S47=' || v_t;
      if v_t is distinct from '10|2|1|2|1|9|productos-archivos,productos-imagenes|true|19d26a925b9d97c89715254f219fbe7e|44a582cd1073c43ac3e0e0faa864f9cf' then
        fallos := fallos + 1; res := res || '!';
      end if;
      raise exception using errcode = 'MB002';
    exception when sqlstate 'MB002' then null;
    end;

    raise exception using errcode = 'MB001';
  exception
    when sqlstate 'MB001' then null;
    when others then
      fallos := fallos + 1;
      res := res || ' ABORTO[' || v_paso || ']=' || sqlstate || ':' || sqlerrm;
  end;
  execute 'reset role';

  -- ---------- 3. Recuperación sin datos ----------
  v_b := strpos(t_rec, E'\nBEGIN;\n'); v_e := strpos(t_rec, E'\nCOMMIT;\n');
  execute substr(t_rec, v_b + 8, v_e - (v_b + 8));
  execute q_huella into h2;
{{SONDAS:p2}}

  raise exception 'MOBAU_44_P cambia=% identico=% sondas=% fallos=% :: %',
    (h1 <> h0), (h2 = h0), (p1 = p0 and p2 = p0), fallos, res || ' | sondas ' || p0 using errcode = 'MB990';
end $P44$;

COMMIT;
