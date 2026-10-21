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
  t_mig text := $M44$-- ============================================================
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
$M44$;
  t_rec text := $R44$-- ============================================================
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
$R44$;
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
  if md5(t_mig) <> '872f463c2aee16659b76dee96d15573d' or md5(t_rec) <> '4e0b2ef941a70e20c6f2efe00a08ecc7' then
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
    execute 'reset role';
    perform set_config('request.jwt.claims', '{"role": "anon"}', true);
    perform set_config('request.jwt.claim.sub', '', true);
    execute 'set local role anon';
    p0 := (select count(*)::text from public.catalog_products) || '|'
          || (select md5(string_agg(id || ':' || name || ':' || coalesce(image_url, '-'), ',' order by id)) from public.catalog_products);
    execute 'reset role';
    perform set_config('request.jwt.claims', json_build_object('sub', v_ind, 'role', 'authenticated', 'aal', 'aal1')::text, true);
    perform set_config('request.jwt.claim.sub', v_ind::text, true);
    execute 'set local role authenticated';
    p0 := p0 || '|' || (select count(*) || ':' || coalesce(sum(quantity), 0) from public.project_products) || '|' || (select count(*) from public.projects);
    execute 'reset role';
    perform set_config('request.jwt.claims', json_build_object('sub', v_gra, 'role', 'authenticated', 'aal', 'aal1')::text, true);
    perform set_config('request.jwt.claim.sub', v_gra::text, true);
    execute 'set local role authenticated';
    p0 := p0 || '|' || (select count(*) from public.projects) || '|' || (select count(*) from public.catalog_products);
    execute 'reset role';
    perform set_config('request.jwt.claims', json_build_object('sub', v_sup, 'role', 'authenticated', 'aal', 'aal1')::text, true);
    perform set_config('request.jwt.claim.sub', v_sup::text, true);
    execute 'set local role authenticated';
    p0 := p0 || '|' || (select count(*) from public.products) || ':' || (select count(*) from public.product_proposals);
    execute 'reset role';

  -- ---------- 1. Aplicar 44-01 ----------
  v_b := strpos(t_mig, E'\nBEGIN;\n'); v_e := strpos(t_mig, E'\nCOMMIT;\n');
  execute substr(t_mig, v_b + 8, v_e - (v_b + 8));
  execute q_huella into h1;
    execute 'reset role';
    perform set_config('request.jwt.claims', '{"role": "anon"}', true);
    perform set_config('request.jwt.claim.sub', '', true);
    execute 'set local role anon';
    p1 := (select count(*)::text from public.catalog_products) || '|'
          || (select md5(string_agg(id || ':' || name || ':' || coalesce(image_url, '-'), ',' order by id)) from public.catalog_products);
    execute 'reset role';
    perform set_config('request.jwt.claims', json_build_object('sub', v_ind, 'role', 'authenticated', 'aal', 'aal1')::text, true);
    perform set_config('request.jwt.claim.sub', v_ind::text, true);
    execute 'set local role authenticated';
    p1 := p1 || '|' || (select count(*) || ':' || coalesce(sum(quantity), 0) from public.project_products) || '|' || (select count(*) from public.projects);
    execute 'reset role';
    perform set_config('request.jwt.claims', json_build_object('sub', v_gra, 'role', 'authenticated', 'aal', 'aal1')::text, true);
    perform set_config('request.jwt.claim.sub', v_gra::text, true);
    execute 'set local role authenticated';
    p1 := p1 || '|' || (select count(*) from public.projects) || '|' || (select count(*) from public.catalog_products);
    execute 'reset role';
    perform set_config('request.jwt.claims', json_build_object('sub', v_sup, 'role', 'authenticated', 'aal', 'aal1')::text, true);
    perform set_config('request.jwt.claim.sub', v_sup::text, true);
    execute 'set local role authenticated';
    p1 := p1 || '|' || (select count(*) from public.products) || ':' || (select count(*) from public.product_proposals);
    execute 'reset role';

  -- ---------- 2. Flujo de 3225 (se deshace con MB001) ----------
  begin
    v_paso := 'S00';
    -- Archivo de otra empresa (para S11), como postgres.
    insert into public.product_assets (distributor_id, kind, bucket, path, original_name, format)
    values ('baccara', 'foto', 'productos-imagenes', 'baccara/' || f || '/ajena.jpg', 'ajena.jpg', 'jpg') returning id into a0;

    -- S01 Spectro registra sus 9 archivos (pendientes)
    execute 'reset role';
    perform set_config('request.jwt.claims', json_build_object('sub', v_sup, 'role', 'authenticated', 'aal', 'aal1')::text, true);
    perform set_config('request.jwt.claim.sub', v_sup::text, true);
    execute 'set local role authenticated';
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
    v_paso := 'S01';
    v_t := ((select count(*) from public.product_assets where distributor_id = 'spectro' and status = 'pendiente' and product_id is null and uploaded_by = v_sup))::text;
    res := res || ' S01=' || coalesce(v_t, '∅');
    if v_t is distinct from '9' then fallos := fallos + 1; res := res || '!'; end if;

    -- S02–S07 Altas no permitidas
    v_paso := 'S02';
    begin
      insert into public.product_assets (distributor_id, kind, bucket, path, original_name, format) values ('baccara', 'foto', 'productos-imagenes', 'baccara/' || f || '/x.jpg', 'x.jpg', 'jpg');
      v_t := 'sin_error';
    exception when others then
      v_t := sqlstate;
    end;
    res := res || ' S02=' || v_t;
    if v_t is distinct from '42501' then fallos := fallos + 1; res := res || '!'; end if;
    v_paso := 'S03';
    begin
      insert into public.product_assets (distributor_id, kind, bucket, path, original_name, format, status) values ('spectro', 'foto', 'productos-imagenes', 'spectro/' || f || '/y.jpg', 'y.jpg', 'jpg', 'aprobado');
      v_t := 'sin_error';
    exception when others then
      v_t := sqlstate;
    end;
    res := res || ' S03=' || v_t;
    if v_t is distinct from '42501' then fallos := fallos + 1; res := res || '!'; end if;
    v_paso := 'S04';
    begin
      insert into public.product_assets (distributor_id, kind, bucket, path, original_name, format) values ('spectro', 'foto', 'productos-imagenes', 'spectro/' || f || '/z.png', 'z.png', 'png');
      v_t := 'sin_error';
    exception when others then
      v_t := sqlstate;
    end;
    res := res || ' S04=' || v_t;
    if v_t is distinct from '23514' then fallos := fallos + 1; res := res || '!'; end if;
    v_paso := 'S05';
    begin
      insert into public.product_assets (distributor_id, kind, bucket, path, original_name, format) values ('spectro', 'foto', 'productos-imagenes', 'spectro/../baccara/w.jpg', 'w.jpg', 'jpg');
      v_t := 'sin_error';
    exception when others then
      v_t := sqlstate;
    end;
    res := res || ' S05=' || v_t;
    if v_t is distinct from '23514' then fallos := fallos + 1; res := res || '!'; end if;
    v_paso := 'S06';
    begin
      insert into public.product_assets (distributor_id, kind, bucket, path, variants, original_name, format) values ('spectro', 'ficha_tecnica', 'productos-archivos', 'spectro/' || f || '/v.pdf', '{"card": "spectro/x/v.jpg"}', 'v.pdf', 'pdf');
      v_t := 'sin_error';
    exception when others then
      v_t := sqlstate;
    end;
    res := res || ' S06=' || v_t;
    if v_t is distinct from '23514' then fallos := fallos + 1; res := res || '!'; end if;
    v_paso := 'S07';
    begin
      insert into public.product_assets (distributor_id, kind, bucket, path, original_name, format) values ('spectro', 'cad_2d', 'productos-imagenes', 'spectro/' || f || '/u.dwg', 'u.dwg', 'dwg');
      v_t := 'sin_error';
    exception when others then
      v_t := sqlstate;
    end;
    res := res || ' S07=' || v_t;
    if v_t is distinct from '23514' then fallos := fallos + 1; res := res || '!'; end if;
    execute 'reset role';
    perform set_config('request.jwt.claims', '{"role": "anon"}', true);
    perform set_config('request.jwt.claim.sub', '', true);
    execute 'set local role anon';
    v_paso := 'S08';
    begin
      insert into public.product_assets (distributor_id, kind, bucket, path, original_name, format) values ('spectro', 'foto', 'productos-imagenes', 'spectro/' || f || '/t.jpg', 't.jpg', 'jpg');
      v_t := 'sin_error';
    exception when others then
      v_t := sqlstate;
    end;
    res := res || ' S08=' || v_t;
    if v_t is distinct from '42501' then fallos := fallos + 1; res := res || '!'; end if;

    -- S09–S11 Storage: subir solo en la carpeta propia
    execute 'reset role';
    perform set_config('request.jwt.claims', json_build_object('sub', v_sup, 'role', 'authenticated', 'aal', 'aal1')::text, true);
    perform set_config('request.jwt.claim.sub', v_sup::text, true);
    execute 'set local role authenticated';
    v_paso := 'S09';
    insert into storage.objects (bucket_id, name)
    select a.bucket, a.path from public.product_assets a where a.distributor_id = 'spectro';
    v_paso := 'S09';
    v_t := ((select count(*) from storage.objects where name like 'spectro/' || f || '/%'))::text;
    res := res || ' S09=' || coalesce(v_t, '∅');
    if v_t is distinct from '9' then fallos := fallos + 1; res := res || '!'; end if;
    v_paso := 'S10';
    begin
      insert into storage.objects (bucket_id, name) values ('productos-archivos', 'baccara/' || f || '/x.pdf');
      v_t := 'sin_error';
    exception when others then
      v_t := sqlstate;
    end;
    res := res || ' S10=' || v_t;
    if v_t is distinct from '42501' then fallos := fallos + 1; res := res || '!'; end if;
    execute 'reset role';
    perform set_config('request.jwt.claims', '{"role": "anon"}', true);
    perform set_config('request.jwt.claim.sub', '', true);
    execute 'set local role anon';
    v_paso := 'S11';
    begin
      insert into storage.objects (bucket_id, name) values ('productos-imagenes', 'spectro/' || f || '/anon.jpg');
      v_t := 'sin_error';
    exception when others then
      v_t := sqlstate;
    end;
    res := res || ' S11=' || v_t;
    if v_t is distinct from '42501' then fallos := fallos + 1; res := res || '!'; end if;

    -- S12–S18 Propuesta de producto nuevo (borrador → envío)
    execute 'reset role';
    perform set_config('request.jwt.claims', json_build_object('sub', v_sup, 'role', 'authenticated', 'aal', 'aal1')::text, true);
    perform set_config('request.jwt.claim.sub', v_sup::text, true);
    execute 'set local role authenticated';
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
    v_paso := 'S12';
    begin
      insert into public.product_proposals (proposal_kind, distributor_id, proposed_changes, proposed_price_status, proposed_media) values ('create', 'spectro', ch, 'quote_required', jsonb_build_object('assets', jsonb_build_array(jsonb_build_object('id', a0))));
      v_t := 'sin_error';
    exception when others then
      v_t := sqlstate;
    end;
    res := res || ' S12=' || v_t;
    if v_t is distinct from '23514' then fallos := fallos + 1; res := res || '!'; end if;
    insert into public.product_proposals (proposal_kind, distributor_id, proposed_changes, proposed_price_status, proposed_media)
    values ('create', 'spectro', ch, 'quote_required', m1) returning id into pid;
    v_paso := 'S13';
    v_t := ((select status || ':' || (proposed_media ->> 'reference_code' is null)::text from public.product_proposals where id = pid))::text;
    res := res || ' S13=' || coalesce(v_t, '∅');
    if v_t is distinct from 'draft:true' then fallos := fallos + 1; res := res || '!'; end if;
    v_paso := 'S14';
    begin
      update public.product_proposals set proposed_media = m1 || jsonb_build_object('cover_asset_id', a4) where id = pid;
      v_t := 'sin_error';
    exception when others then
      v_t := sqlstate;
    end;
    res := res || ' S14=' || v_t;
    if v_t is distinct from '23514' then fallos := fallos + 1; res := res || '!'; end if;
    v_paso := 'S15';
    begin
      update public.product_proposals set proposed_media = jsonb_set(m1, '{finishes,1,is_default}', 'true') where id = pid;
      v_t := 'sin_error';
    exception when others then
      v_t := sqlstate;
    end;
    res := res || ' S15=' || v_t;
    if v_t is distinct from '23514' then fallos := fallos + 1; res := res || '!'; end if;
    v_paso := 'S16';
    begin
      update public.product_proposals set proposed_media = jsonb_set(m1, '{assets}', (m1 -> 'assets') || jsonb_build_array(jsonb_build_object('id', a1))) where id = pid;
      v_t := 'sin_error';
    exception when others then
      v_t := sqlstate;
    end;
    res := res || ' S16=' || v_t;
    if v_t is distinct from '23514' then fallos := fallos + 1; res := res || '!'; end if;
    v_paso := 'S17';
    begin
      update public.product_proposals set status = 'submitted' where id = pid;
      v_t := 'sin_error';
    exception when others then
      v_t := sqlstate;
    end;
    res := res || ' S17=' || v_t;
    if v_t is distinct from '23514' then fallos := fallos + 1; res := res || '!'; end if;
    v_paso := 'S18';
    -- Referencia sí, portada todavía no (para ensayar que Mobau no puede aprobar sin ella).
    m2 := m1 || jsonb_build_object('reference_code', '3225');
    update public.product_proposals set proposed_media = m2 where id = pid;
    update public.product_proposals set status = 'submitted' where id = pid;
    v_paso := 'S18';
    v_t := ((select status from public.product_proposals where id = pid))::text;
    res := res || ' S18=' || coalesce(v_t, '∅');
    if v_t is distinct from 'submitted' then fallos := fallos + 1; res := res || '!'; end if;
    v_paso := 'S19';
    begin
      update public.product_proposals set proposed_media = m2 || jsonb_build_object('cover_asset_id', a1) where id = pid;
      v_t := 'sin_error';
    exception when others then
      v_t := sqlstate;
    end;
    res := res || ' S19=' || v_t;
    if v_t is distinct from '42501' then fallos := fallos + 1; res := res || '!'; end if;

    -- S20–S23 Moderación: sin portada no se aprueba
    execute 'reset role';
    perform set_config('request.jwt.claims', json_build_object('sub', v_adm, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    perform set_config('request.jwt.claim.sub', v_adm::text, true);
    execute 'set local role authenticated';
    v_paso := 'S20';
    select version into v_ver from public.product_proposals where id = pid;
    v_paso := 'S20';
    begin
      perform public.moderate_product_proposal(pid, 'approve', null, v_ver);
      v_t := 'sin_error';
    exception when others then
      v_t := sqlstate;
    end;
    res := res || ' S20=' || v_t;
    if v_t is distinct from '55000' then fallos := fallos + 1; res := res || '!'; end if;
    v_paso := 'S21';
    v_t := ((select count(*) from public.products where distributor_id = 'spectro' and name = 'P44 Dama ensayo'))::text;
    res := res || ' S21=' || coalesce(v_t, '∅');
    if v_t is distinct from '0' then fallos := fallos + 1; res := res || '!'; end if;
    v_paso := 'S22';
    perform public.moderate_product_proposal(pid, 'request_changes', 'Elige la foto de portada.', v_ver);
    execute 'reset role';
    perform set_config('request.jwt.claims', json_build_object('sub', v_sup, 'role', 'authenticated', 'aal', 'aal1')::text, true);
    perform set_config('request.jwt.claim.sub', v_sup::text, true);
    execute 'set local role authenticated';
    v_paso := 'S23';
    m2 := m2 || jsonb_build_object('cover_asset_id', a1);
    update public.product_proposals set proposed_media = m2 where id = pid;
    update public.product_proposals set status = 'submitted' where id = pid;
    v_paso := 'S23';
    v_t := ((select status || ':' || (proposed_media ->> 'cover_asset_id') from public.product_proposals where id = pid))::text;
    res := res || ' S23=' || coalesce(v_t, '∅');
    if v_t is distinct from 'submitted:' || a1::text || '' then fallos := fallos + 1; res := res || '!'; end if;
    execute 'reset role';
    perform set_config('request.jwt.claims', json_build_object('sub', v_adm, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    perform set_config('request.jwt.claim.sub', v_adm::text, true);
    execute 'set local role authenticated';
    v_paso := 'S24';
    select version into v_ver from public.product_proposals where id = pid;
    v_r := public.moderate_product_proposal(pid, 'approve', null, v_ver);
    select created_product_id into v_prod from public.product_proposals where id = pid;
    v_paso := 'S24';
    v_t := ((v_r ->> 'result') || ':' || (v_prod is not null)::text)::text;
    res := res || ' S24=' || coalesce(v_t, '∅');
    if v_t is distinct from 'approved:true' then fallos := fallos + 1; res := res || '!'; end if;

    -- S25–S27 Resultado en la base
    execute 'reset role';
    perform set_config('request.jwt.claims', '', true);
    perform set_config('request.jwt.claim.sub', '', true);
    v_paso := 'S25';
    v_t := ((select reference_code || '|' || (cover_asset_id = a1)::text || '|' || publication_status || '|' || status || '|' || coalesce(finishes, '-') from public.products where id = v_prod))::text;
    res := res || ' S25=' || coalesce(v_t, '∅');
    if v_t is distinct from '3225|true|published|active|Beige D1, Black' then fallos := fallos + 1; res := res || '!'; end if;
    v_paso := 'S26';
    v_t := ((select string_agg(a.status || ':' || count, ',' order by a.status) from (select status, count(*)::text as count from public.product_assets where distributor_id = 'spectro' and path like 'spectro/' || f || '/%' group by status) a) || '|' || (select count(*) from public.product_assets where product_id = v_prod and proposal_id = pid and status = 'aprobado') || '|' || (select label from public.product_assets where id = a5))::text;
    res := res || ' S26=' || coalesce(v_t, '∅');
    if v_t is distinct from 'aprobado:8,pendiente:1|8|Ficha técnica' then fallos := fallos + 1; res := res || '!'; end if;
    v_paso := 'S27';
    v_t := ((select string_agg(code || ':' || name || ':' || coalesce(reference_code, '-') || ':' || is_default::text || ':' || (image_asset_id = case code when '25' then a2 else a3 end)::text, '|' order by sort_order) from public.product_finishes where product_id = v_prod))::text;
    res := res || ' S27=' || coalesce(v_t, '∅');
    if v_t is distinct from '25:Beige D1:3225-25:true:true|11:Black:3225-11:false:true' then fallos := fallos + 1; res := res || '!'; end if;

    -- S28–S31 Lo que ve el público
    execute 'reset role';
    perform set_config('request.jwt.claims', '{"role": "anon"}', true);
    perform set_config('request.jwt.claim.sub', '', true);
    execute 'set local role anon';
    v_paso := 'S28';
    v_t := ((select reference_code || '|' || (cover_path = 'spectro/' || f || '/portada.jpg')::text || '|' || (cover_card_path = 'spectro/' || f || '/portada-card.jpg')::text || '|' || jsonb_array_length(finish_options)::text || '|' || (finish_options -> 0 ->> 'code') || ':' || (finish_options -> 0 ->> 'is_default') || ':' || (finish_options -> 0 ->> 'image_card_path') from public.catalog_products where id = v_prod))::text;
    res := res || ' S28=' || coalesce(v_t, '∅');
    if v_t is distinct from '3225|true|true|2|25:true:spectro/' || f || '/acabado-25-card.jpg' then fallos := fallos + 1; res := res || '!'; end if;
    v_paso := 'S29';
    v_t := ((select count(*) from public.product_assets where product_id = v_prod) || '|' || (select count(*) from public.product_assets where id in (a9, a0)) || '|' || (select count(*) from public.product_finishes where product_id = v_prod))::text;
    res := res || ' S29=' || coalesce(v_t, '∅');
    if v_t is distinct from '8|0|2' then fallos := fallos + 1; res := res || '!'; end if;
    v_paso := 'S30';
    v_t := ((select count(*) from storage.objects where bucket_id = 'productos-archivos'))::text;
    res := res || ' S30=' || coalesce(v_t, '∅');
    if v_t is distinct from '0' then fallos := fallos + 1; res := res || '!'; end if;
    v_paso := 'S31';
    begin
      perform public.can_download_product_file('spectro/' || f || '/3225.obj');
      v_t := 'sin_error';
    exception when others then
      v_t := sqlstate;
    end;
    res := res || ' S31=' || v_t;
    if v_t is distinct from '42501' then fallos := fallos + 1; res := res || '!'; end if;

    -- S32–S35 Descargas privadas por rol (a5–a8 aprobados; a9 pendiente)
    execute 'reset role';
    perform set_config('request.jwt.claims', json_build_object('sub', v_gra, 'role', 'authenticated', 'aal', 'aal1')::text, true);
    perform set_config('request.jwt.claim.sub', v_gra::text, true);
    execute 'set local role authenticated';
    v_paso := 'S32';
    v_t := ((select count(*) from storage.objects where bucket_id = 'productos-archivos' and name like 'spectro/' || f || '/%'))::text;
    res := res || ' S32=' || coalesce(v_t, '∅');
    if v_t is distinct from '4' then fallos := fallos + 1; res := res || '!'; end if;
    execute 'reset role';
    perform set_config('request.jwt.claims', json_build_object('sub', v_ind, 'role', 'authenticated', 'aal', 'aal1')::text, true);
    perform set_config('request.jwt.claim.sub', v_ind::text, true);
    execute 'set local role authenticated';
    v_paso := 'S33';
    v_t := ((select count(*) from storage.objects where bucket_id = 'productos-archivos' and name like 'spectro/' || f || '/%'))::text;
    res := res || ' S33=' || coalesce(v_t, '∅');
    if v_t is distinct from '4' then fallos := fallos + 1; res := res || '!'; end if;
    execute 'reset role';
    perform set_config('request.jwt.claims', json_build_object('sub', v_sup, 'role', 'authenticated', 'aal', 'aal1')::text, true);
    perform set_config('request.jwt.claim.sub', v_sup::text, true);
    execute 'set local role authenticated';
    v_paso := 'S34';
    v_t := ((select count(*) from storage.objects where bucket_id = 'productos-archivos' and name like 'spectro/' || f || '/%'))::text;
    res := res || ' S34=' || coalesce(v_t, '∅');
    if v_t is distinct from '5' then fallos := fallos + 1; res := res || '!'; end if;
    execute 'reset role';
    perform set_config('request.jwt.claims', json_build_object('sub', v_adm, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    perform set_config('request.jwt.claim.sub', v_adm::text, true);
    execute 'set local role authenticated';
    v_paso := 'S35';
    v_t := ((select count(*) from storage.objects where bucket_id = 'productos-archivos' and name like 'spectro/' || f || '/%'))::text;
    res := res || ' S35=' || coalesce(v_t, '∅');
    if v_t is distinct from '5' then fallos := fallos + 1; res := res || '!'; end if;

    -- S36–S41 Proyecto de Individual: una línea por producto y acabado
    execute 'reset role';
    perform set_config('request.jwt.claims', json_build_object('sub', v_ind, 'role', 'authenticated', 'aal', 'aal1')::text, true);
    perform set_config('request.jwt.claim.sub', v_ind::text, true);
    execute 'set local role authenticated';
    v_paso := 'S36';
    insert into public.project_products (project_id, product_id, quantity, unit, finish_code) values (v_proj, v_prod, 2, 'ud.', '25');
    insert into public.project_products (project_id, product_id, quantity, unit, finish_code) values (v_proj, v_prod, 1, 'ud.', '11');
    v_paso := 'S36';
    v_t := ((select string_agg(coalesce(finish_code, '-') || ':' || quantity::text || ':' || unit, '|' order by finish_code) from public.project_products where project_id = v_proj and product_id = v_prod))::text;
    res := res || ' S36=' || coalesce(v_t, '∅');
    if v_t is distinct from '11:1.00:ud.|25:2.00:ud.' then fallos := fallos + 1; res := res || '!'; end if;
    v_paso := 'S37';
    begin
      insert into public.project_products (project_id, product_id, quantity, unit, finish_code) values (v_proj, v_prod, 5, 'ud.', '25');
      v_t := 'sin_error';
    exception when others then
      v_t := sqlstate;
    end;
    res := res || ' S37=' || v_t;
    if v_t is distinct from '23505' then fallos := fallos + 1; res := res || '!'; end if;
    v_paso := 'S38';
    update public.project_products set quantity = 3 where project_id = v_proj and product_id = v_prod and finish_code = '25';
    v_paso := 'S38';
    v_t := ((select quantity::text from public.project_products where project_id = v_proj and product_id = v_prod and finish_code = '25'))::text;
    res := res || ' S38=' || coalesce(v_t, '∅');
    if v_t is distinct from '3.00' then fallos := fallos + 1; res := res || '!'; end if;
    v_paso := 'S39';
    begin
      update public.project_products set finish_code = '11' where project_id = v_proj and product_id = v_prod and finish_code = '25';
      v_t := 'sin_error';
    exception when others then
      v_t := sqlstate;
    end;
    res := res || ' S39=' || v_t;
    if v_t is distinct from '42501' then fallos := fallos + 1; res := res || '!'; end if;
    v_paso := 'S40';
    begin
      insert into public.project_products (project_id, product_id, quantity, unit, finish_code) values (v_proj, v_prod, 1, 'ud.', ' 25');
      v_t := 'sin_error';
    exception when others then
      v_t := sqlstate;
    end;
    res := res || ' S40=' || v_t;
    if v_t is distinct from '23514' then fallos := fallos + 1; res := res || '!'; end if;
    v_paso := 'S41';
    insert into public.project_products (project_id, product_id, quantity, unit) values (v_proj, v_prod, 1, 'ud.');
    v_paso := 'S41';
    begin
      insert into public.project_products (project_id, product_id, quantity, unit) values (v_proj, v_prod, 1, 'ud.');
      v_t := 'sin_error';
    exception when others then
      v_t := sqlstate;
    end;
    res := res || ' S41=' || v_t;
    if v_t is distinct from '23505' then fallos := fallos + 1; res := res || '!'; end if;

    -- S42–S45 Propuesta de cambio solo con archivos (añade el LDT)
    execute 'reset role';
    perform set_config('request.jwt.claims', json_build_object('sub', v_sup, 'role', 'authenticated', 'aal', 'aal1')::text, true);
    perform set_config('request.jwt.claim.sub', v_sup::text, true);
    execute 'set local role authenticated';
    v_paso := 'S42';
    m3 := jsonb_set(m2, '{assets}', (m2 -> 'assets') || jsonb_build_array(jsonb_build_object('id', a9, 'label', 'LDT 2700K')));
    insert into public.product_proposals (proposal_kind, product_id, distributor_id, proposed_media)
    values ('update', v_prod, 'spectro', m3) returning id into uid2;
    update public.product_proposals set status = 'submitted' where id = uid2;
    v_paso := 'S42';
    v_t := ((select status from public.product_proposals where id = uid2))::text;
    res := res || ' S42=' || coalesce(v_t, '∅');
    if v_t is distinct from 'submitted' then fallos := fallos + 1; res := res || '!'; end if;
    execute 'reset role';
    perform set_config('request.jwt.claims', json_build_object('sub', v_adm, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    perform set_config('request.jwt.claim.sub', v_adm::text, true);
    execute 'set local role authenticated';
    v_paso := 'S43';
    select version into v_ver from public.product_proposals where id = uid2;
    v_r := public.moderate_product_proposal(uid2, 'approve', null, v_ver);
    v_paso := 'S43';
    v_t := ((v_r ->> 'result') || '|' || (select count(*) from public.product_assets where product_id = v_prod and status = 'aprobado') || '|' || (select label from public.product_assets where id = a9))::text;
    res := res || ' S43=' || coalesce(v_t, '∅');
    if v_t is distinct from 'approved|9|LDT 2700K' then fallos := fallos + 1; res := res || '!'; end if;
    -- Sigue rechazándose una propuesta de cambio sin cambios ni archivos.
    execute 'reset role';
    perform set_config('request.jwt.claims', json_build_object('sub', v_sup, 'role', 'authenticated', 'aal', 'aal1')::text, true);
    perform set_config('request.jwt.claim.sub', v_sup::text, true);
    execute 'set local role authenticated';
    v_paso := 'S44';
    insert into public.product_proposals (proposal_kind, product_id, distributor_id) values ('update', v_prod, 'spectro') returning id into uid3;
    v_paso := 'S44';
    begin
      update public.product_proposals set status = 'submitted' where id = uid3;
      v_t := 'sin_error';
    exception when others then
      v_t := sqlstate;
    end;
    res := res || ' S44=' || v_t;
    if v_t is distinct from '23514' then fallos := fallos + 1; res := res || '!'; end if;
    execute 'reset role';
    perform set_config('request.jwt.claims', '{"role": "anon"}', true);
    perform set_config('request.jwt.claim.sub', '', true);
    execute 'set local role anon';
    v_paso := 'S45';
    v_t := ((select count(*) from public.catalog_products where id = v_prod and reference_code = '3225') || '|' || (select count(*) from public.product_assets where product_id = v_prod))::text;
    res := res || ' S45=' || coalesce(v_t, '∅');
    if v_t is distinct from '1|9' then fallos := fallos + 1; res := res || '!'; end if;

    -- S46–S47 Recuperación con datos (se deshace con MB002)
    execute 'reset role';
    perform set_config('request.jwt.claims', '', true);
    perform set_config('request.jwt.claim.sub', '', true);
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
    execute 'reset role';
    perform set_config('request.jwt.claims', '{"role": "anon"}', true);
    perform set_config('request.jwt.claim.sub', '', true);
    execute 'set local role anon';
    p2 := (select count(*)::text from public.catalog_products) || '|'
          || (select md5(string_agg(id || ':' || name || ':' || coalesce(image_url, '-'), ',' order by id)) from public.catalog_products);
    execute 'reset role';
    perform set_config('request.jwt.claims', json_build_object('sub', v_ind, 'role', 'authenticated', 'aal', 'aal1')::text, true);
    perform set_config('request.jwt.claim.sub', v_ind::text, true);
    execute 'set local role authenticated';
    p2 := p2 || '|' || (select count(*) || ':' || coalesce(sum(quantity), 0) from public.project_products) || '|' || (select count(*) from public.projects);
    execute 'reset role';
    perform set_config('request.jwt.claims', json_build_object('sub', v_gra, 'role', 'authenticated', 'aal', 'aal1')::text, true);
    perform set_config('request.jwt.claim.sub', v_gra::text, true);
    execute 'set local role authenticated';
    p2 := p2 || '|' || (select count(*) from public.projects) || '|' || (select count(*) from public.catalog_products);
    execute 'reset role';
    perform set_config('request.jwt.claims', json_build_object('sub', v_sup, 'role', 'authenticated', 'aal', 'aal1')::text, true);
    perform set_config('request.jwt.claim.sub', v_sup::text, true);
    execute 'set local role authenticated';
    p2 := p2 || '|' || (select count(*) from public.products) || ':' || (select count(*) from public.product_proposals);
    execute 'reset role';

  raise exception 'MOBAU_44_P cambia=% identico=% sondas=% fallos=% :: %',
    (h1 <> h0), (h2 = h0), (p1 = p0 and p2 = p0), fallos, res || ' | sondas ' || p0 using errcode = 'MB990';
end $P44$;

COMMIT;
