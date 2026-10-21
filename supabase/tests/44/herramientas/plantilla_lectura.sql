-- ============================================================
-- 44-01 · lectura (solo SELECT; vale antes y después de aplicar)
-- ============================================================
-- Una fila. Antes de 44-01: aplicada=false y el resto vacío o en cero.
-- Después: aplicada=true, md5 de transición {{TRANSITION_NEW_MD5}},
-- 2 buckets, 5 políticas de Storage y los recuentos del producto 3225.
-- ============================================================
select
  (select count(*) from supabase_migrations.schema_migrations) as migraciones,
  (select max(version) from supabase_migrations.schema_migrations) as ultima,
  exists (select 1 from supabase_migrations.schema_migrations where version = '20261021120000') as registrada,
  to_regclass('public.product_assets') is not null as aplicada,
  (select md5(prosrc) from pg_proc where oid = 'public.transition_proposal_status()'::regprocedure) as md5_transicion,
  md5(pg_get_viewdef('public.catalog_products'::regclass)) as md5_vista,
  (select reloptions::text || ' ' || relacl::text from pg_class where oid = 'public.catalog_products'::regclass) as vista_opciones_permisos,
  (select coalesce(string_agg(id || ':' || public::text || ':' || coalesce(file_size_limit::text, '-'), ',' order by id), '') from storage.buckets
    where id in ('productos-imagenes', 'productos-archivos')) as buckets,
  (select count(*) from pg_policies where schemaname = 'storage' and policyname like '44 %') as politicas_storage,
  (select count(*) from pg_policies where schemaname = 'public' and tablename in ('product_assets', 'product_finishes')) as politicas_tablas,
  (select count(*) from storage.objects where bucket_id in ('productos-imagenes', 'productos-archivos')) as objetos,
  case when to_regclass('public.product_assets') is not null then
    (xpath('/row/n/text()', query_to_xml(
      'select string_agg(status || '':'' || n, '','' order by status) as n from (select status, count(*) n from public.product_assets group by status) s',
      false, false, '')))[1]::text end as archivos_por_estado,
  case when to_regclass('public.product_assets') is not null then
    (xpath('/row/n/text()', query_to_xml(
      'select coalesce(p.id || ''|'' || p.reference_code || ''|'' || p.publication_status || ''|portada='' || (p.cover_asset_id is not null)::text'
      || ' || ''|acabados='' || (select count(*) from public.product_finishes f where f.product_id = p.id)'
      || ' || ''|archivos='' || (select count(*) from public.product_assets a where a.product_id = p.id and a.status = ''aprobado''), ''-'') as n'
      || ' from public.products p where p.distributor_id = ''spectro'' and p.reference_code = ''3225''',
      false, false, '')))[1]::text end as producto_3225,
  case when to_regclass('public.product_assets') is not null then
    (xpath('/row/n/text()', query_to_xml(
      'select count(*) as n from public.project_products where finish_code is not null', false, false, '')))[1]::text end as lineas_con_acabado,
  (select count(*) from pg_class where relnamespace = 'mobau_private'::regnamespace and relname like 'r44\_%') as respaldos_r44,
  (select count(*) from public.project_products) as lineas_proyecto,
  (select count(*) from public.products where publication_status = 'published' and status = 'active') as catalogo_publicado;
