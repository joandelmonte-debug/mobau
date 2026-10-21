-- ============================================================
-- PROPUESTA NO EJECUTADA (44-01 · recuperación) — no ejecutar sin aprobación explícita
-- ============================================================
-- Deshace 20261021120000_44_01_archivos_producto.sql y deja el esquema
-- como estaba (vista del catálogo, función de transición, permisos).
--   * Si hay datos de 44 (archivos, acabados, referencias, portadas,
--     archivos propuestos o líneas por acabado), primero los copia a
--     mobau_private.r44_* (solo postgres) y luego quita columnas y tablas.
--   * Si quitar finish_code dejara dos líneas del mismo producto en un
--     proyecto, se detiene (MB441): antes hay que decidir qué línea queda.
--   * Los buckets solo se borran si están vacíos. Si tienen archivos se
--     conservan (y siguen sirviéndose): los archivos se borran desde la API
--     de Storage, nunca borrando filas de storage.objects.
-- Si alguna vez se aplica, se registra como migración NUEVA (versión y
-- nombre propios) tras confirmar su COMMIT. La fila de 44-01 no se borra.
-- Ejecutar completo.
-- ============================================================

BEGIN;

DO $$
begin
  if current_user <> 'postgres' then
    raise exception '44-01 R: ejecutar como postgres';
  end if;
  if to_regclass('public.product_assets') is null or to_regclass('public.product_finishes') is null
     or (select md5(prosrc) from pg_proc where oid = 'public.transition_proposal_status()'::regprocedure) <> '3eef0e1ad9a754c54fcc1ac536301b53' then
    raise exception '44-01 R: 44-01 no está aplicada como se esperaba';
  end if;
  if exists (select 1 from public.project_products group by project_id, product_id having count(*) > 1) then
    raise exception '44-01 R: hay productos con varias líneas por acabado en un mismo proyecto; decidir qué línea queda antes de recuperar'
      using errcode = 'MB441';
  end if;
  perform set_config('mobau.r44_datos', md5(
      coalesce((select string_agg(id || ':' || coalesce(publication_status, '-') || ':' || updated_at::text, '|' order by id) from public.products), '')
   || coalesce((select string_agg(id::text || ':' || product_id || ':' || quantity::text || coalesce(unit, '-'), '|' order by id) from public.project_products), '')
   || coalesce((select string_agg(id::text || ':' || status || ':' || version::text, '|' order by id) from public.product_proposals), '')), true);
end $$;

-- ---------- 1. Respaldo (solo si hay datos de 44) ----------
DO $$
begin
  if exists (select 1 from public.product_assets) or exists (select 1 from public.product_finishes)
     or exists (select 1 from public.products where reference_code is not null or cover_asset_id is not null)
     or exists (select 1 from public.product_proposals where proposed_media is not null)
     or exists (select 1 from public.project_products where finish_code is not null)
     or exists (select 1 from storage.objects where bucket_id in ('productos-imagenes', 'productos-archivos')) then
    if exists (select 1 from pg_class where relnamespace = 'mobau_private'::regnamespace and relname like 'r44\_%') then
      raise exception '44-01 R: ya existe un respaldo r44 en mobau_private' using errcode = 'MB442';
    end if;
    create table mobau_private.r44_product_assets as select * from public.product_assets;
    create table mobau_private.r44_product_finishes as select * from public.product_finishes;
    create table mobau_private.r44_products as
      select id, reference_code, cover_asset_id, finishes from public.products where reference_code is not null or cover_asset_id is not null;
    create table mobau_private.r44_proposals_media as
      select id, proposed_media from public.product_proposals where proposed_media is not null;
    create table mobau_private.r44_project_lines as
      select id, project_id, product_id, finish_code, quantity, unit from public.project_products where finish_code is not null;
    create table mobau_private.r44_storage_objects as
      select id, bucket_id, name, created_at from storage.objects where bucket_id in ('productos-imagenes', 'productos-archivos');
    revoke all on table mobau_private.r44_product_assets, mobau_private.r44_product_finishes, mobau_private.r44_products,
                        mobau_private.r44_proposals_media, mobau_private.r44_project_lines, mobau_private.r44_storage_objects
      from public, anon, authenticated;
  end if;
end $$;

-- ---------- 2. Storage ----------
drop policy "44 productos-imagenes: subir en la carpeta propia" on storage.objects;
drop policy "44 productos-archivos: subir en la carpeta propia" on storage.objects;
drop policy "44 productos-imagenes: ver la carpeta propia" on storage.objects;
drop policy "44 productos-archivos: ver la carpeta propia" on storage.objects;
drop policy "44 productos-archivos: descargar con permiso" on storage.objects;

DO $$
begin
  perform set_config('storage.allow_delete_query', 'true', true);
  delete from storage.buckets b
   where b.id in ('productos-imagenes', 'productos-archivos')
     and not exists (select 1 from storage.objects o where o.bucket_id = b.id);
  perform set_config('storage.allow_delete_query', 'false', true);
end $$;

-- ---------- 3. Catálogo como en 41-02 ----------
drop view public.catalog_products;
create view public.catalog_products with (security_invoker = true, security_barrier = true) as
 SELECT id,
    name,
    brand,
    distributor_id,
    category_id,
    subcategory,
    use_context,
    space,
    availability,
    description,
    measurements,
    materials,
    finishes,
    lead_time,
    icon,
    image_url,
    technical_sheet_url,
    cad_bim_3d_url,
    status,
    created_at,
    updated_at
   FROM public.products p
  WHERE ((publication_status = 'published'::text) AND (status = 'active'::text));
revoke all on table public.catalog_products from public, anon, authenticated;
grant select on table public.catalog_products to anon, authenticated;
comment on view public.catalog_products is '41-02: catálogo público (publicado y activo), 21 columnas de PRODUCT_COLUMNS. security_invoker: RLS y permisos de quien consulta. Solo SELECT para anon y authenticated.';

-- ---------- 4. Función de transición como en 39-03 ----------
CREATE OR REPLACE FUNCTION public.transition_proposal_status()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
begin
  -- 39: decisión de Mobau en curso (moderate_product_proposal, 39-04, con
  -- admin activo y aal2). Solo submitted → approved | changes_requested |
  -- rejected, y solo campos de revisión: el contenido enviado por el
  -- distribuidor no se puede modificar.
  if (select public.mobau_moderating(new.id)) then
    if old.status <> 'submitted' or new.status not in ('approved', 'changes_requested', 'rejected') then
      raise exception 'Transición no permitida para Mobau: % → %.', old.status, new.status using errcode = '42501';
    end if;
    -- Defensa en profundidad: moderate_product_proposal ya lo impide antes.
    if old.author_id = (select auth.uid())
       or exists (select 1 from public.distributor_profiles dp
                   where dp.user_id = (select auth.uid()) and dp.distributor_id = old.distributor_id) then
      raise exception 'No puedes moderar propuestas de tu propia empresa.'
        using errcode = '42501', hint = 'self_moderation_forbidden';
    end if;
    if new.id is distinct from old.id
       or new.proposal_kind is distinct from old.proposal_kind
       or new.product_id is distinct from old.product_id
       or new.distributor_id is distinct from old.distributor_id
       or new.author_id is distinct from old.author_id
       or new.created_at is distinct from old.created_at
       or new.version is distinct from old.version
       or new.submitted_at is distinct from old.submitted_at
       or new.product_snapshot is distinct from old.product_snapshot
       or new.proposed_changes is distinct from old.proposed_changes
       or new.proposed_new_subcategory is distinct from old.proposed_new_subcategory
       or new.proposed_price_status is distinct from old.proposed_price_status
       or new.proposed_price_amount is distinct from old.proposed_price_amount
       or new.internal_note is distinct from old.internal_note then
      raise exception 'Mobau no puede modificar el contenido de una propuesta.' using errcode = '42501';
    end if;
    return new;
  end if;

  -- Sin sesión de cliente (Mobau desde el editor SQL): sin reglas de distribuidor.
  if (select auth.uid()) is null then
    return new;
  end if;

  if old.distributor_id is distinct from (select public.my_verified_distributor_id()) then
    raise exception 'Esta propuesta no es de tu empresa verificada.' using errcode = '42501';
  end if;
  if new.id is distinct from old.id
     or new.proposal_kind is distinct from old.proposal_kind
     or new.product_id is distinct from old.product_id
     or new.distributor_id is distinct from old.distributor_id
     or new.author_id is distinct from old.author_id
     or new.created_at is distinct from old.created_at then
    raise exception 'No se puede cambiar el tipo, el producto, la empresa ni el autor de una propuesta.' using errcode = '42501';
  end if;
  if new.rejection_reason is distinct from old.rejection_reason
     or new.reviewed_at is distinct from old.reviewed_at
     or new.reviewed_by is distinct from old.reviewed_by
     or new.product_snapshot is distinct from old.product_snapshot
     or new.submitted_at is distinct from old.submitted_at
     or new.version is distinct from old.version
     or new.created_product_id is distinct from old.created_product_id then
    raise exception 'Esos campos los gestiona Mobau o el sistema.' using errcode = '42501';
  end if;

  -- Sin cambio de estado: edición del contenido, solo en borrador o con cambios solicitados.
  if new.status = old.status then
    if old.status not in ('draft', 'changes_requested') then
      raise exception 'Una propuesta en estado % ya no se puede editar.', old.status using errcode = '42501';
    end if;
    return new;
  end if;

  if not ((old.status = 'draft' and new.status in ('submitted', 'withdrawn'))
          or (old.status = 'submitted' and new.status = 'withdrawn')
          or (old.status = 'changes_requested' and new.status in ('submitted', 'withdrawn'))) then
    raise exception 'Transición no permitida: % → %.', old.status, new.status using errcode = '42501';
  end if;

  -- update: al menos un cambio de información (incluida una subcategoría
  -- nueva) o de precio. create: los obligatorios los exige el trigger 30.
  if new.status = 'submitted' and new.proposal_kind = 'update'
     and new.proposed_changes = '{}'::jsonb and new.proposed_new_subcategory is null
     and new.proposed_price_status is null then
    raise exception 'La propuesta no contiene ningún cambio.' using errcode = '23514';
  end if;

  return new;
end;
$function$;

-- ---------- 5. Triggers, funciones, columnas y tablas ----------
drop trigger trg_product_proposals_35_media on public.product_proposals;
drop trigger trg_product_proposals_60_media_apply on public.product_proposals;
drop function public.validate_proposal_media();
drop function public.apply_proposal_media();
drop function public.can_download_product_file(text);

drop index public.project_products_line_unique;
alter table public.project_products drop constraint project_products_finish_code_valid, drop column finish_code;

alter table public.product_proposals
  drop constraint product_proposals_media_object,
  drop constraint product_proposals_media_size,
  drop column proposed_media;

alter table public.products drop constraint products_cover_asset_fk;
drop index public.products_reference_code_unique;
alter table public.products
  drop constraint products_reference_code_valid,
  drop column cover_asset_id,
  drop column reference_code;

drop table public.product_finishes;
drop table public.product_assets;
drop function public.product_assets_check_variants();
drop function public.catalog_product_visible(text);

-- ---------- 6. Comprobación final ----------
DO $$
begin
  if to_regclass('public.product_assets') is not null or to_regclass('public.product_finishes') is not null
     or exists (select 1 from information_schema.columns where table_schema = 'public'
                and ((table_name = 'products' and column_name in ('reference_code', 'cover_asset_id'))
                  or (table_name = 'product_proposals' and column_name = 'proposed_media')
                  or (table_name = 'project_products' and column_name = 'finish_code')))
     or exists (select 1 from pg_proc where pronamespace = 'public'::regnamespace
                and proname in ('catalog_product_visible', 'product_assets_check_variants', 'validate_proposal_media',
                                'apply_proposal_media', 'can_download_product_file'))
     or exists (select 1 from pg_policies where schemaname = 'storage' and policyname like '44 %') then
    raise exception '44-01 R: queda algún objeto de 44-01';
  end if;
  if (select md5(prosrc) from pg_proc where oid = 'public.transition_proposal_status()'::regprocedure) <> '19d26a925b9d97c89715254f219fbe7e'
     or md5(pg_get_viewdef('public.catalog_products'::regclass)) <> '44a582cd1073c43ac3e0e0faa864f9cf'
     or (select reloptions::text from pg_class where oid = 'public.catalog_products'::regclass) <> '{security_invoker=true,security_barrier=true}'
     or (select relacl::text from pg_class where oid = 'public.catalog_products'::regclass) <> '{postgres=arwdDxtm/postgres,anon=r/postgres,authenticated=r/postgres}' then
    raise exception '44-01 R: la función de transición o la vista del catálogo no volvieron a su estado';
  end if;
  if md5(
      coalesce((select string_agg(id || ':' || coalesce(publication_status, '-') || ':' || updated_at::text, '|' order by id) from public.products), '')
   || coalesce((select string_agg(id::text || ':' || product_id || ':' || quantity::text || coalesce(unit, '-'), '|' order by id) from public.project_products), '')
   || coalesce((select string_agg(id::text || ':' || status || ':' || version::text, '|' order by id) from public.product_proposals), ''))
     <> current_setting('mobau.r44_datos') then
    raise exception '44-01 R: ha cambiado algún dato existente';
  end if;
end $$;

COMMIT;
