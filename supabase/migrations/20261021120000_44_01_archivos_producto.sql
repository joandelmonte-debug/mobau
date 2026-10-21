-- ============================================================
-- PROPUESTA NO EJECUTADA (44-01 · archivos reales de producto, acabados, referencia y portada) — no ejecutar sin aprobación explícita
-- ============================================================
-- Punto 44 · primera subida real de Spectro (prueba con Vibia 3225).
--   * products: reference_code (la indica el distribuidor; única por
--     empresa) y cover_asset_id (portada elegida a mano).
--   * product_assets: registro de cada archivo subido a Storage (fotos,
--     vídeos, ficha técnica, CAD 2D, CAD 3D, BIM, cálculo de iluminación y
--     manual). El distribuidor solo crea filas «pendiente» en su carpeta;
--     pasan a «aprobado» cuando Mobau aprueba la propuesta que las incluye.
--   * product_finishes: acabados del producto (código, nombre, referencia,
--     foto y uno por defecto). Sin duplicar el producto.
--   * product_proposals.proposed_media: referencia, portada, acabados y
--     lista de archivos propuestos. La valida el trigger 35 y la aplica, al
--     aprobar, el trigger 60. Sin portada o sin referencia no se aprueba.
--   * transition_proposal_status: una propuesta de cambio puede contener
--     solo archivos; Mobau no puede modificar proposed_media.
--   * project_products.finish_code: una línea por producto y acabado
--     (índice único; sin acabado cuenta como uno por defecto).
--   * catalog_products: añade al final reference_code, cover_path,
--     cover_card_path y finish_options.
--   * Storage: bucket público productos-imagenes y bucket privado
--     productos-archivos; subida solo en la carpeta de la propia empresa;
--     descarga privada con can_download_product_file (reglas del punto 42).
-- No toca datos existentes, roles, planes ni habilitaciones.
-- Recuperación: rollback/20261021120000_44_01_archivos_producto.rollback.sql.
-- Ejecutar completo.
-- ============================================================

BEGIN;

DO $$
begin
  if current_user <> 'postgres' then
    raise exception '44-01: ejecutar como postgres';
  end if;
  if not exists (select 1 from supabase_migrations.schema_migrations where version = '20261020180000')
     or exists (select 1 from supabase_migrations.schema_migrations where version = '20261021120000') then
    raise exception '44-01: el registro de migraciones no es el esperado (SEG-01 registrada y 44-01 sin registrar)';
  end if;
  if to_regclass('public.product_assets') is not null or to_regclass('public.product_finishes') is not null
     or exists (select 1 from information_schema.columns where table_schema = 'public'
                and ((table_name = 'products' and column_name in ('reference_code', 'cover_asset_id'))
                  or (table_name = 'product_proposals' and column_name = 'proposed_media')
                  or (table_name = 'project_products' and column_name = 'finish_code'))) then
    raise exception '44-01: ya existe algún objeto de 44-01';
  end if;
  if exists (select 1 from storage.buckets where id in ('productos-imagenes', 'productos-archivos'))
     or exists (select 1 from pg_policies where schemaname = 'storage' and policyname like '44 %') then
    raise exception '44-01: ya existe algún bucket o política de 44-01';
  end if;
  if (select md5(prosrc) from pg_proc where oid = 'public.transition_proposal_status()'::regprocedure) <> '19d26a925b9d97c89715254f219fbe7e'
     or md5(pg_get_viewdef('public.catalog_products'::regclass)) <> '44a582cd1073c43ac3e0e0faa864f9cf'
     or (select reloptions::text from pg_class where oid = 'public.catalog_products'::regclass) <> '{security_invoker=true,security_barrier=true}' then
    raise exception '44-01: la función de transición o la vista del catálogo no son las esperadas';
  end if;
  if exists (select 1 from public.project_products group by project_id, product_id having count(*) > 1) then
    raise exception '44-01: hay líneas de proyecto duplicadas';
  end if;
  perform set_config('mobau.p44_datos', md5(
      coalesce((select string_agg(id || ':' || coalesce(publication_status, '-') || ':' || updated_at::text, '|' order by id) from public.products), '')
   || coalesce((select string_agg(id::text || ':' || product_id || ':' || quantity::text || coalesce(unit, '-'), '|' order by id) from public.project_products), '')
   || coalesce((select string_agg(id::text || ':' || status || ':' || version::text, '|' order by id) from public.product_proposals), '')), true);
end $$;

-- ---------- 1. Producto: referencia y portada ----------
alter table public.products
  add column reference_code text,
  add column cover_asset_id uuid;
alter table public.products
  add constraint products_reference_code_valid
  check (reference_code is null or (reference_code = btrim(reference_code) and char_length(reference_code) between 1 and 60));
create unique index products_reference_code_unique on public.products (distributor_id, lower(reference_code)) where reference_code is not null;
grant select (reference_code, cover_asset_id) on table public.products to anon, authenticated;

-- ---------- 2. Visibilidad de catálogo (para las políticas) ----------
create function public.catalog_product_visible(p_product_id text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (select 1 from public.products p
                  where p.id = p_product_id and p.publication_status = 'published' and p.status = 'active')
$$;
revoke all on function public.catalog_product_visible(text) from public, anon, authenticated;
grant execute on function public.catalog_product_visible(text) to anon, authenticated;

-- ---------- 3. Archivos ----------
create table public.product_assets (
  id uuid primary key default gen_random_uuid(),
  distributor_id text not null references public.distributors(id),
  product_id text references public.products(id) on delete cascade,
  proposal_id uuid references public.product_proposals(id) on delete set null,
  kind text not null,
  bucket text not null,
  path text not null,
  variants jsonb not null default '{}'::jsonb,
  original_name text not null,
  format text not null,
  label text,
  bytes bigint,
  width integer,
  height integer,
  sort_order integer not null default 0,
  status text not null default 'pendiente',
  uploaded_by uuid default auth.uid(),
  created_at timestamptz not null default now(),
  constraint product_assets_path_unique unique (path),
  constraint product_assets_kind_valid
    check (kind in ('foto', 'video', 'ficha_tecnica', 'cad_2d', 'cad_3d', 'bim', 'calculo_iluminacion', 'manual')),
  constraint product_assets_bucket_kind
    check (bucket in ('productos-imagenes', 'productos-archivos') and ((kind in ('foto', 'video')) = (bucket = 'productos-imagenes'))),
  constraint product_assets_format_valid check (
       (kind = 'foto' and format = 'jpg')
    or (kind = 'video' and format in ('mp4', 'webm'))
    or (kind in ('ficha_tecnica', 'manual') and format = 'pdf')
    or (kind = 'cad_2d' and format in ('dwg', 'dxf'))
    or (kind = 'cad_3d' and format in ('dwg', 'dxf', '3ds', 'max', 'obj', 'mtl', 'fbx', 'skp', 'stp', 'step'))
    or (kind = 'bim' and format in ('ifc', 'rfa', 'rvt'))
    or (kind = 'calculo_iluminacion' and format in ('ies', 'ldt', 'oxl', 'ulf', 'pdf'))),
  constraint product_assets_status_valid check (status in ('pendiente', 'aprobado', 'retirado')),
  constraint product_assets_path_valid
    check (split_part(path, '/', 1) = distributor_id and char_length(path) <= 300
           and path !~ '(^|/)\.\.(/|$)' and path !~ '[[:cntrl:]]'),
  constraint product_assets_variants_object check (jsonb_typeof(variants) = 'object'),
  constraint product_assets_text_lengths
    check (char_length(original_name) between 1 and 200 and char_length(coalesce(label, '')) <= 80),
  constraint product_assets_sizes
    check ((bytes is null or bytes >= 0) and (width is null or width > 0) and (height is null or height > 0)),
  constraint product_assets_approved_has_product check (status <> 'aprobado' or product_id is not null)
);
create index product_assets_product_idx on public.product_assets (product_id);

create function public.product_assets_check_variants()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  k text;
  v jsonb;
begin
  if new.kind <> 'foto' and new.variants <> '{}'::jsonb then
    raise exception 'Solo las fotos tienen versiones recortadas.' using errcode = '23514';
  end if;
  for k, v in select e.key, e.value from pg_catalog.jsonb_each(new.variants) e loop
    if k <> 'card' or pg_catalog.jsonb_typeof(v) <> 'string'
       or pg_catalog.split_part(v #>> '{}', '/', 1) <> new.distributor_id
       or pg_catalog.char_length(v #>> '{}') > 300
       or (v #>> '{}') ~ '(^|/)\.\.(/|$)' then
      raise exception 'Versión de imagen no válida.' using errcode = '23514';
    end if;
  end loop;
  return new;
end;
$$;
revoke all on function public.product_assets_check_variants() from public, anon, authenticated;
create trigger trg_product_assets_variants
  before insert or update on public.product_assets
  for each row execute function public.product_assets_check_variants();

alter table public.product_assets enable row level security;
revoke all on table public.product_assets from public, anon, authenticated;
grant select on table public.product_assets to anon, authenticated;
grant insert (distributor_id, kind, bucket, path, variants, original_name, format, bytes, width, height)
  on table public.product_assets to authenticated;
grant delete on table public.product_assets to authenticated;

create policy product_assets_select_public on public.product_assets for select to anon, authenticated
  using (status = 'aprobado' and public.catalog_product_visible(product_id));
create policy product_assets_select_own on public.product_assets for select to authenticated
  using (distributor_id = (select public.my_verified_distributor_id()));
create policy product_assets_select_mobau on public.product_assets for select to authenticated
  using ((select public.is_mobau_admin()));
create policy product_assets_insert_own on public.product_assets for insert to authenticated
  with check (distributor_id = (select public.my_verified_distributor_id())
              and status = 'pendiente' and product_id is null and proposal_id is null);
create policy product_assets_delete_own on public.product_assets for delete to authenticated
  using (distributor_id = (select public.my_verified_distributor_id()) and status = 'pendiente');

alter table public.products
  add constraint products_cover_asset_fk foreign key (cover_asset_id) references public.product_assets(id) on delete set null;

-- ---------- 4. Acabados ----------
create table public.product_finishes (
  product_id text not null references public.products(id) on delete cascade,
  code text not null,
  name text not null,
  reference_code text,
  image_asset_id uuid references public.product_assets(id) on delete set null,
  sort_order integer not null default 0,
  is_default boolean not null default false,
  primary key (product_id, code),
  constraint product_finishes_text check (
        code = btrim(code) and char_length(code) between 1 and 20
    and name = btrim(name) and char_length(name) between 1 and 60
    and (reference_code is null or (reference_code = btrim(reference_code) and char_length(reference_code) between 1 and 60)))
);
create unique index product_finishes_one_default on public.product_finishes (product_id) where is_default;

alter table public.product_finishes enable row level security;
revoke all on table public.product_finishes from public, anon, authenticated;
grant select on table public.product_finishes to anon, authenticated;
create policy product_finishes_select_public on public.product_finishes for select to anon, authenticated
  using (public.catalog_product_visible(product_id));
create policy product_finishes_select_own on public.product_finishes for select to authenticated
  using (exists (select 1 from public.products p
                  where p.id = product_finishes.product_id
                    and p.distributor_id = (select public.my_verified_distributor_id())));
create policy product_finishes_select_mobau on public.product_finishes for select to authenticated
  using ((select public.is_mobau_admin()));

-- ---------- 5. Propuestas: archivos propuestos ----------
alter table public.product_proposals add column proposed_media jsonb;
alter table public.product_proposals
  add constraint product_proposals_media_object check (proposed_media is null or jsonb_typeof(proposed_media) = 'object'),
  add constraint product_proposals_media_size check (proposed_media is null or pg_column_size(proposed_media) <= 32768);
grant insert (proposed_media), update (proposed_media) on table public.product_proposals to authenticated;

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
       or new.internal_note is distinct from old.internal_note
       or new.proposed_media is distinct from old.proposed_media then
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
  -- nueva), de precio o de archivos (44). create: los obligatorios los
  -- exigen los triggers 30 y 35.
  if new.status = 'submitted' and new.proposal_kind = 'update'
     and new.proposed_changes = '{}'::jsonb and new.proposed_new_subcategory is null
     and new.proposed_price_status is null and new.proposed_media is null then
    raise exception 'La propuesta no contiene ningún cambio.' using errcode = '23514';
  end if;

  return new;
end;
$function$;

create function public.validate_proposal_media()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  m jsonb := new.proposed_media;
  v_ref text;
  v_assets jsonb;
  v_finishes jsonb;
  v_item jsonb;
  v_ids uuid[] := '{}'::uuid[];
  v_id uuid;
  v_codes text[] := '{}'::text[];
  v_code text;
  v_defaults integer := 0;
  v_cover uuid;
  v_kind text;
  v_photos integer := 0;
  v_entering boolean;
  k text;
begin
  -- Durante la decisión de Mobau el contenido no cambia y ya se validó al enviarse.
  if tg_op = 'UPDATE' and (select public.mobau_moderating(new.id)) then
    return new;
  end if;
  if tg_op = 'UPDATE' then
    v_entering := new.status = 'submitted' and old.status is distinct from 'submitted';
  else
    v_entering := new.status = 'submitted';
  end if;
  -- Sin cambios en los archivos y sin envío: nada que validar (p. ej. retirar la propuesta).
  if tg_op = 'UPDATE' and not v_entering and new.proposed_media is not distinct from old.proposed_media then
    return new;
  end if;

  if m is null then
    if new.proposal_kind = 'create' and v_entering then
      raise exception 'Para enviar un producto nuevo indica la referencia y añade al menos una foto.' using errcode = '23514';
    end if;
    return new;
  end if;

  for k in select pg_catalog.jsonb_object_keys(m) loop
    if k not in ('reference_code', 'cover_asset_id', 'finishes', 'assets') then
      raise exception 'Campo no permitido en los archivos de la propuesta: %.', k using errcode = '23514';
    end if;
  end loop;

  -- Referencia
  if m ? 'reference_code' and pg_catalog.jsonb_typeof(m -> 'reference_code') not in ('string', 'null') then
    raise exception 'La referencia debe ser texto.' using errcode = '23514';
  end if;
  v_ref := m ->> 'reference_code';
  if v_ref is not null then
    if v_ref <> pg_catalog.btrim(v_ref) or pg_catalog.char_length(v_ref) not between 1 and 60 then
      raise exception 'La referencia debe tener entre 1 y 60 caracteres, sin espacios al principio ni al final.' using errcode = '23514';
    end if;
    if exists (select 1 from public.products p
                where p.distributor_id = new.distributor_id
                  and pg_catalog.lower(p.reference_code) = pg_catalog.lower(v_ref)
                  and p.id is distinct from new.product_id) then
      raise exception 'Ya tienes otro producto con la referencia %.', v_ref using errcode = '23514';
    end if;
  end if;

  -- Archivos: propios, pendientes o ya aprobados de este mismo producto
  v_assets := coalesce(m -> 'assets', '[]'::jsonb);
  if pg_catalog.jsonb_typeof(v_assets) <> 'array' or pg_catalog.jsonb_array_length(v_assets) > 80 then
    raise exception 'La lista de archivos no es válida (máximo 80).' using errcode = '23514';
  end if;
  for v_item in select e from pg_catalog.jsonb_array_elements(v_assets) e loop
    if pg_catalog.jsonb_typeof(v_item) <> 'object' or not (v_item ? 'id')
       or exists (select 1 from pg_catalog.jsonb_object_keys(v_item) x where x not in ('id', 'label'))
       or pg_catalog.jsonb_typeof(v_item -> 'id') <> 'string'
       or (v_item ? 'label' and pg_catalog.jsonb_typeof(v_item -> 'label') not in ('string', 'null'))
       or pg_catalog.char_length(coalesce(v_item ->> 'label', '')) > 80 then
      raise exception 'Algún archivo de la lista no es válido.' using errcode = '23514';
    end if;
    begin
      v_id := (v_item ->> 'id')::uuid;
    exception when invalid_text_representation then
      raise exception 'Algún archivo de la lista no es válido.' using errcode = '23514';
    end;
    if v_id = any (v_ids) then
      raise exception 'Un archivo aparece dos veces en la lista.' using errcode = '23514';
    end if;
    select a.kind into v_kind from public.product_assets a
     where a.id = v_id and a.distributor_id = new.distributor_id
       and (a.status = 'pendiente' or (a.status = 'aprobado' and a.product_id = new.product_id));
    if not found then
      raise exception 'Algún archivo de la lista no existe o no es de tu empresa.' using errcode = '23514';
    end if;
    if v_kind = 'foto' then
      v_photos := v_photos + 1;
    end if;
    v_ids := v_ids || v_id;
  end loop;

  -- Portada: una de las fotos de la lista, recortada en 4:5 (con versión de tarjeta)
  if m ? 'cover_asset_id' and pg_catalog.jsonb_typeof(m -> 'cover_asset_id') not in ('string', 'null') then
    raise exception 'La portada no es válida.' using errcode = '23514';
  end if;
  if m ->> 'cover_asset_id' is not null then
    begin
      v_cover := (m ->> 'cover_asset_id')::uuid;
    exception when invalid_text_representation then
      raise exception 'La portada no es válida.' using errcode = '23514';
    end;
    if not (v_cover = any (v_ids))
       or not exists (select 1 from public.product_assets a where a.id = v_cover and a.kind = 'foto' and a.variants ? 'card') then
      raise exception 'La portada debe ser una de las fotos de la propuesta, recortada en formato 4:5.' using errcode = '23514';
    end if;
  end if;

  -- Acabados
  v_finishes := coalesce(m -> 'finishes', '[]'::jsonb);
  if pg_catalog.jsonb_typeof(v_finishes) <> 'array' or pg_catalog.jsonb_array_length(v_finishes) > 30 then
    raise exception 'La lista de acabados no es válida (máximo 30).' using errcode = '23514';
  end if;
  for v_item in select e from pg_catalog.jsonb_array_elements(v_finishes) e loop
    if pg_catalog.jsonb_typeof(v_item) <> 'object'
       or exists (select 1 from pg_catalog.jsonb_object_keys(v_item) x
                   where x not in ('code', 'name', 'reference_code', 'image_asset_id', 'is_default'))
       or pg_catalog.jsonb_typeof(v_item -> 'code') is distinct from 'string'
       or pg_catalog.jsonb_typeof(v_item -> 'name') is distinct from 'string'
       or (v_item ? 'reference_code' and pg_catalog.jsonb_typeof(v_item -> 'reference_code') not in ('string', 'null'))
       or (v_item ? 'image_asset_id' and pg_catalog.jsonb_typeof(v_item -> 'image_asset_id') not in ('string', 'null'))
       or (v_item ? 'is_default' and pg_catalog.jsonb_typeof(v_item -> 'is_default') <> 'boolean') then
      raise exception 'Algún acabado no es válido.' using errcode = '23514';
    end if;
    v_code := v_item ->> 'code';
    if v_code <> pg_catalog.btrim(v_code) or pg_catalog.char_length(v_code) not between 1 and 20
       or (v_item ->> 'name') <> pg_catalog.btrim(v_item ->> 'name') or pg_catalog.char_length(v_item ->> 'name') not between 1 and 60
       or (v_item ->> 'reference_code' is not null
           and ((v_item ->> 'reference_code') <> pg_catalog.btrim(v_item ->> 'reference_code')
                or pg_catalog.char_length(v_item ->> 'reference_code') not between 1 and 60)) then
      raise exception 'Revisa el código (1–20 caracteres), el nombre (1–60) y la referencia de cada acabado.' using errcode = '23514';
    end if;
    if pg_catalog.lower(v_code) = any (v_codes) then
      raise exception 'Hay dos acabados con el código %.', v_code using errcode = '23514';
    end if;
    v_codes := v_codes || pg_catalog.lower(v_code);
    if coalesce((v_item ->> 'is_default')::boolean, false) then
      v_defaults := v_defaults + 1;
    end if;
    if v_item ->> 'image_asset_id' is not null then
      begin
        v_id := (v_item ->> 'image_asset_id')::uuid;
      exception when invalid_text_representation then
        raise exception 'La foto de un acabado no es válida.' using errcode = '23514';
      end;
      if not (v_id = any (v_ids))
         or not exists (select 1 from public.product_assets a where a.id = v_id and a.kind = 'foto' and a.variants ? 'card') then
        raise exception 'La foto de cada acabado debe ser una de las fotos de la propuesta, recortada en formato 4:5.' using errcode = '23514';
      end if;
    end if;
  end loop;
  if pg_catalog.jsonb_array_length(v_finishes) > 0 and v_defaults <> 1 then
    raise exception 'Marca un único acabado por defecto.' using errcode = '23514';
  end if;

  -- Al enviar
  if v_entering then
    if v_ref is null then
      raise exception 'Para enviar indica la referencia del producto.' using errcode = '23514';
    end if;
    if new.proposal_kind = 'create' and v_photos = 0 then
      raise exception 'Para enviar un producto nuevo añade al menos una foto.' using errcode = '23514';
    end if;
  end if;
  return new;
end;
$$;
revoke all on function public.validate_proposal_media() from public, anon, authenticated;
create trigger trg_product_proposals_35_media
  before insert or update on public.product_proposals
  for each row execute function public.validate_proposal_media();

create function public.apply_proposal_media()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  m jsonb := new.proposed_media;
  v_product text := coalesce(new.product_id, new.created_product_id);
  v_ref text;
  v_cover uuid;
  v_item jsonb;
  v_ord bigint;
  v_ids uuid[] := '{}'::uuid[];
  v_codes text[];
  v_names text;
begin
  if new.status <> 'approved' or old.status = 'approved' then
    return null;
  end if;
  if m is null then
    if new.proposal_kind = 'create' then
      raise exception 'Este producto nuevo no tiene referencia ni fotos: solicita cambios a la empresa.'
        using errcode = '55000', hint = 'media_required';
    end if;
    return null;
  end if;
  v_ref := nullif(pg_catalog.btrim(coalesce(m ->> 'reference_code', '')), '');
  v_cover := nullif(m ->> 'cover_asset_id', '')::uuid;
  if v_ref is null then
    raise exception 'Falta la referencia del producto: solicita cambios a la empresa.'
      using errcode = '55000', hint = 'reference_required';
  end if;
  if v_cover is null then
    raise exception 'Falta la foto de portada: solicita a la empresa que la elija.'
      using errcode = '55000', hint = 'cover_required';
  end if;

  for v_item, v_ord in
    select t.e, t.o from pg_catalog.jsonb_array_elements(coalesce(m -> 'assets', '[]'::jsonb)) with ordinality as t(e, o)
  loop
    update public.product_assets a
       set product_id = v_product, proposal_id = new.id, status = 'aprobado',
           label = nullif(pg_catalog.btrim(coalesce(v_item ->> 'label', '')), ''), sort_order = v_ord::integer
     where a.id = (v_item ->> 'id')::uuid and a.distributor_id = new.distributor_id
       and a.status in ('pendiente', 'aprobado') and (a.product_id is null or a.product_id = v_product);
    if not found then
      raise exception 'Algún archivo de la propuesta ya no está disponible: solicita cambios a la empresa.'
        using errcode = '55000', hint = 'asset_missing';
    end if;
    v_ids := v_ids || (v_item ->> 'id')::uuid;
  end loop;
  if not (v_cover = any (v_ids)) then
    raise exception 'Falta la foto de portada: solicita a la empresa que la elija.'
      using errcode = '55000', hint = 'cover_required';
  end if;

  update public.product_assets
     set status = 'retirado'
   where product_id = v_product and status = 'aprobado' and not (id = any (v_ids));

  select coalesce(pg_catalog.array_agg(f ->> 'code'), '{}'::text[]) into v_codes
    from pg_catalog.jsonb_array_elements(coalesce(m -> 'finishes', '[]'::jsonb)) f;
  delete from public.product_finishes where product_id = v_product and not (code = any (v_codes));
  update public.product_finishes set is_default = false where product_id = v_product and is_default;
  insert into public.product_finishes (product_id, code, name, reference_code, image_asset_id, sort_order, is_default)
  select v_product, t.f ->> 'code', t.f ->> 'name', nullif(t.f ->> 'reference_code', ''),
         nullif(t.f ->> 'image_asset_id', '')::uuid, t.o::integer, coalesce((t.f ->> 'is_default')::boolean, false)
    from pg_catalog.jsonb_array_elements(coalesce(m -> 'finishes', '[]'::jsonb)) with ordinality as t(f, o)
  on conflict (product_id, code) do update
    set name = excluded.name, reference_code = excluded.reference_code, image_asset_id = excluded.image_asset_id,
        sort_order = excluded.sort_order, is_default = excluded.is_default;

  select pg_catalog.left(pg_catalog.string_agg(t.f ->> 'name', ', ' order by t.o), 200) into v_names
    from pg_catalog.jsonb_array_elements(coalesce(m -> 'finishes', '[]'::jsonb)) with ordinality as t(f, o);

  update public.products
     set reference_code = v_ref, cover_asset_id = v_cover, finishes = coalesce(v_names, finishes)
   where id = v_product;
  return null;
end;
$$;
revoke all on function public.apply_proposal_media() from public, anon, authenticated;
create trigger trg_product_proposals_60_media_apply
  after update of status on public.product_proposals
  for each row execute function public.apply_proposal_media();

-- ---------- 6. Proyectos: una línea por producto y acabado ----------
alter table public.project_products
  add column finish_code text,
  add constraint project_products_finish_code_valid
    check (finish_code is null or (finish_code = btrim(finish_code) and char_length(finish_code) between 1 and 20));
create unique index project_products_line_unique on public.project_products (project_id, product_id, (coalesce(finish_code, '')));

-- ---------- 7. Catálogo: referencia, portada y acabados ----------
create or replace view public.catalog_products with (security_invoker = true, security_barrier = true) as
 select p.id, p.name, p.brand, p.distributor_id, p.category_id, p.subcategory, p.use_context, p.space,
        p.availability, p.description, p.measurements, p.materials, p.finishes, p.lead_time, p.icon,
        p.image_url, p.technical_sheet_url, p.cad_bim_3d_url, p.status, p.created_at, p.updated_at,
        p.reference_code,
        cov.path as cover_path,
        cov.variants ->> 'card' as cover_card_path,
        coalesce((select jsonb_agg(jsonb_build_object(
                           'code', f.code, 'name', f.name, 'reference_code', f.reference_code, 'is_default', f.is_default,
                           'image_path', fa.path, 'image_card_path', fa.variants ->> 'card')
                         order by f.sort_order, f.code)
                    from public.product_finishes f
                    left join public.product_assets fa on fa.id = f.image_asset_id and fa.status = 'aprobado'
                   where f.product_id = p.id), '[]'::jsonb) as finish_options
   from public.products p
   left join public.product_assets cov on cov.id = p.cover_asset_id and cov.status = 'aprobado'
  where p.publication_status = 'published' and p.status = 'active';
comment on view public.catalog_products is '44-01: catálogo público (publicado y activo): las 21 columnas de 41-02 más reference_code, cover_path, cover_card_path y finish_options. security_invoker: RLS y permisos de quien consulta. Solo SELECT para anon y authenticated.';

-- ---------- 8. Storage ----------
create function public.can_download_product_file(p_name text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.product_assets a
     where a.bucket = 'productos-archivos' and a.path = p_name
       and ((select public.is_mobau_admin())
            or a.distributor_id = (select public.my_verified_distributor_id())
            or (a.status = 'aprobado'
                and public.catalog_product_visible(a.product_id)
                and exists (select 1 from public.profiles pr
                             where pr.id = (select auth.uid()) and pr.role in ('individual', 'studio_member')))))
$$;
revoke all on function public.can_download_product_file(text) from public, anon, authenticated;
grant execute on function public.can_download_product_file(text) to authenticated;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('productos-imagenes', 'productos-imagenes', true, 52428800, array['image/jpeg', 'video/mp4', 'video/webm']),
       ('productos-archivos', 'productos-archivos', false, 52428800, null);

create policy "44 productos-imagenes: subir en la carpeta propia" on storage.objects for insert to authenticated
  with check (bucket_id = 'productos-imagenes' and (storage.foldername(name))[1] = (select public.my_verified_distributor_id()));
create policy "44 productos-archivos: subir en la carpeta propia" on storage.objects for insert to authenticated
  with check (bucket_id = 'productos-archivos' and (storage.foldername(name))[1] = (select public.my_verified_distributor_id()));
create policy "44 productos-imagenes: ver la carpeta propia" on storage.objects for select to authenticated
  using (bucket_id = 'productos-imagenes' and (storage.foldername(name))[1] = (select public.my_verified_distributor_id()));
create policy "44 productos-archivos: ver la carpeta propia" on storage.objects for select to authenticated
  using (bucket_id = 'productos-archivos' and (storage.foldername(name))[1] = (select public.my_verified_distributor_id()));
create policy "44 productos-archivos: descargar con permiso" on storage.objects for select to authenticated
  using (bucket_id = 'productos-archivos' and public.can_download_product_file(name));

-- ---------- 9. Comprobación final ----------
DO $$
begin
  if (select md5(prosrc) from pg_proc where oid = 'public.transition_proposal_status()'::regprocedure) <> '3eef0e1ad9a754c54fcc1ac536301b53' then
    raise exception '44-01: la función de transición no quedó como se esperaba';
  end if;
  if not (select relrowsecurity from pg_class where oid = 'public.product_assets'::regclass)
     or not (select relrowsecurity from pg_class where oid = 'public.product_finishes'::regclass)
     or (select count(*) from pg_policies where schemaname = 'public' and tablename = 'product_assets') <> 5
     or (select count(*) from pg_policies where schemaname = 'public' and tablename = 'product_finishes') <> 3
     or (select count(*) from pg_policies where schemaname = 'storage' and policyname like '44 %') <> 5 then
    raise exception '44-01: faltan políticas o RLS';
  end if;
  if has_table_privilege('anon', 'public.product_assets', 'INSERT') or has_table_privilege('anon', 'public.product_assets', 'DELETE')
     or has_table_privilege('authenticated', 'public.product_assets', 'UPDATE')
     or has_table_privilege('anon', 'public.product_finishes', 'INSERT') or has_table_privilege('authenticated', 'public.product_finishes', 'INSERT')
     or has_table_privilege('authenticated', 'public.product_finishes', 'UPDATE') or has_table_privilege('authenticated', 'public.product_finishes', 'DELETE')
     or exists (select 1 from unnest(array['anon', 'authenticated']) r, unnest(array['TRUNCATE', 'REFERENCES', 'TRIGGER', 'MAINTAIN']) pr,
                              unnest(array['public.product_assets', 'public.product_finishes']::regclass[]) t
                 where has_table_privilege(r, t, pr))
     or not has_column_privilege('authenticated', 'public.product_assets', 'path', 'INSERT')
     or has_column_privilege('authenticated', 'public.product_assets', 'status', 'INSERT')
     or has_column_privilege('authenticated', 'public.product_assets', 'product_id', 'INSERT')
     or not has_column_privilege('authenticated', 'public.product_proposals', 'proposed_media', 'UPDATE')
     or not has_column_privilege('anon', 'public.products', 'reference_code', 'SELECT')
     or has_column_privilege('authenticated', 'public.project_products', 'finish_code', 'UPDATE') then
    raise exception '44-01: los permisos de las tablas nuevas no son los esperados';
  end if;
  if has_function_privilege('anon', 'public.can_download_product_file(text)', 'EXECUTE')
     or not has_function_privilege('authenticated', 'public.can_download_product_file(text)', 'EXECUTE')
     or not has_function_privilege('anon', 'public.catalog_product_visible(text)', 'EXECUTE')
     or has_function_privilege('authenticated', 'public.apply_proposal_media()', 'EXECUTE') then
    raise exception '44-01: los permisos de las funciones nuevas no son los esperados';
  end if;
  if (select string_agg(id || ':' || public::text, ',' order by id) from storage.buckets where id in ('productos-imagenes', 'productos-archivos'))
     <> 'productos-archivos:false,productos-imagenes:true' then
    raise exception '44-01: los buckets no quedaron como se esperaba';
  end if;
  if (select reloptions::text from pg_class where oid = 'public.catalog_products'::regclass) <> '{security_invoker=true,security_barrier=true}'
     or (select relacl::text from pg_class where oid = 'public.catalog_products'::regclass) <> '{postgres=arwdDxtm/postgres,anon=r/postgres,authenticated=r/postgres}' then
    raise exception '44-01: la vista del catálogo cambió de opciones o de permisos';
  end if;
  if md5(
      coalesce((select string_agg(id || ':' || coalesce(publication_status, '-') || ':' || updated_at::text, '|' order by id) from public.products), '')
   || coalesce((select string_agg(id::text || ':' || product_id || ':' || quantity::text || coalesce(unit, '-'), '|' order by id) from public.project_products), '')
   || coalesce((select string_agg(id::text || ':' || status || ':' || version::text, '|' order by id) from public.product_proposals), ''))
     <> current_setting('mobau.p44_datos') then
    raise exception '44-01: ha cambiado algún dato existente';
  end if;
end $$;

COMMIT;
