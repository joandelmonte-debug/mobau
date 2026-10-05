-- ============================================================
-- PROPUESTA NO EJECUTADA (38-C) — no ejecutar sin aprobación explícita
-- ============================================================
-- 38-C · 04 · Propuestas de producto nuevo (create) y de cambio (update)
-- ------------------------------------------------------------
-- Requiere 38-C 01, 02 y 03. Compatible con los datos existentes: toda
-- fila actual pasa a ser 'update' (ya tiene product_id) y nada más cambia.
--
-- Tabla product_proposals:
--   + proposal_kind text not null default 'update'  ('create' | 'update')
--   + proposed_new_subcategory text                  (subcategoría que no
--     está en la lista; la decide Mobau en el punto 39)
--   product_id pasa a admitir null, solo para 'create'.
--
-- Reglas (D1–D5 aprobadas):
--   D1  Una sola propuesta 'create' abierta por empresa y nombre
--       normalizado (minúsculas, espacios recortados y colapsados; sin
--       tratar tildes ni equivalencias). Coincidir con un producto ya
--       existente NO bloquea (solo aviso en la web).
--   D2  Enviar un 'create' exige name, description, category_id,
--       availability y una subcategoría (de la lista o nueva). El precio
--       no es obligatorio. Un borrador 'create' solo exige name.
--   D3  proposed_new_subcategory vale para 'create' y para 'update'.
--   D4  Sin created_product_id (punto 39).
--   Precio (create y update por igual): proposed_price_status y
--       proposed_price_amount con las restricciones de 38-C 01, que no
--       dependen del tipo: price_status_check, price_amount_check (>= 0),
--       price_published_amount (published exige importe) y
--       price_amount_needs_status (importe exige estado). Es información
--       para la revisión de Mobau: nada escribe en product_prices (solo la
--       copia de update la lee) y en create product_snapshot queda null.
--   D5  'update': si propone category_id, debe aportar a la vez una
--       subcategoría válida de la nueva categoría o una subcategoría nueva;
--       si propone subcategory, debe ser válida para la categoría
--       resultante. Nunca subcategoría de la lista y nueva a la vez.
--
-- Funciones: se reemplazan las 5 de 38-C 02 (mismos nombres, mismo modelo
-- de seguridad). Los 7 triggers no se tocan. Políticas: sin cambios (44).
-- Permisos: solo se amplían los permisos por columna de authenticated.
--
-- La página distribuidor-propuestas.html nueva depende de esta migración:
-- no publicarla antes. Ejecutar completo (BEGIN … COMMIT).
-- ============================================================

BEGIN;

-- ---------- prechecks ----------
DO $$
declare
  v_col text;
  v_rows bigint;
  v_insert_cols text;
  v_update_cols text;
begin
  if not exists (select 1 from supabase_migrations.schema_migrations where version = '20261002120200') then
    raise exception '38-C 04: falta 38-C 03 (20261002120200) en schema_migrations';
  end if;
  if to_regclass('public.product_proposals') is null or to_regclass('public.proposal_events') is null then
    raise exception '38-C 04: faltan las tablas de propuestas';
  end if;
  if exists (select 1 from information_schema.columns
              where table_schema = 'public' and table_name = 'product_proposals'
                and column_name in ('proposal_kind', 'proposed_new_subcategory')) then
    raise exception '38-C 04: proposal_kind o proposed_new_subcategory ya existen (¿04 ya aplicada?)';
  end if;
  if (select is_nullable from information_schema.columns
       where table_schema = 'public' and table_name = 'product_proposals' and column_name = 'product_id') <> 'NO' then
    raise exception '38-C 04: product_id ya admite null';
  end if;
  if to_regclass('public.product_proposals_one_open_per_product') is null then
    raise exception '38-C 04: falta el índice product_proposals_one_open_per_product de 38-C 01';
  end if;
  if to_regclass('public.product_proposals_one_open_create_per_name') is not null then
    raise exception '38-C 04: el índice product_proposals_one_open_create_per_name ya existe';
  end if;
  if (select count(*) from pg_trigger
       where not tgisinternal and tgrelid = 'public.product_proposals'::regclass
         and tgname like 'trg_product_proposals_%') <> 7 then
    raise exception '38-C 04: se esperan los 7 triggers de 38-C 02';
  end if;
  if (select count(*) from pg_policies where schemaname = 'public' and tablename in ('product_proposals', 'proposal_events')) <> 4
     or (select count(*) from pg_policies where schemaname = 'public') <> 44 then
    raise exception '38-C 04: se esperan las 4 políticas de 38-C 03 (44 en public)';
  end if;

  -- Permisos de columna exactamente los de 38-C 03.
  select string_agg(column_name, ',' order by column_name) into v_insert_cols
    from information_schema.column_privileges
   where table_schema = 'public' and table_name = 'product_proposals'
     and grantee = 'authenticated' and privilege_type = 'INSERT';
  select string_agg(column_name, ',' order by column_name) into v_update_cols
    from information_schema.column_privileges
   where table_schema = 'public' and table_name = 'product_proposals'
     and grantee = 'authenticated' and privilege_type = 'UPDATE';
  if v_insert_cols is distinct from 'internal_note,product_id,proposed_changes,proposed_price_amount,proposed_price_status'
     or v_update_cols is distinct from 'internal_note,proposed_changes,proposed_price_amount,proposed_price_status,status' then
    raise exception '38-C 04: los permisos por columna no son los de 38-C 03 (INSERT: %; UPDATE: %)', v_insert_cols, v_update_cols;
  end if;

  -- Columnas reales que usan las funciones.
  foreach v_col in array array['name', 'description', 'category_id', 'subcategory', 'image_url', 'availability',
                               'lead_time', 'brand', 'measurements', 'materials', 'finishes',
                               'technical_sheet_url', 'cad_bim_3d_url', 'use_context', 'space', 'distributor_id'] loop
    if not exists (select 1 from information_schema.columns
                    where table_schema = 'public' and table_name = 'products' and column_name = v_col) then
      raise exception '38-C 04: products.% no existe', v_col;
    end if;
  end loop;
  if (select data_type from information_schema.columns
       where table_schema = 'public' and table_name = 'categories' and column_name = 'subcategories') is distinct from 'ARRAY' then
    raise exception '38-C 04: categories.subcategories no es un array';
  end if;

  -- Conflictos con el índice de update que se recrea (deberían ser 0: lo
  -- garantiza el índice actual).
  if exists (select 1 from public.product_proposals
              where status in ('draft', 'submitted', 'changes_requested')
              group by product_id having count(*) > 1) then
    raise exception '38-C 04: hay más de una propuesta abierta para un mismo producto';
  end if;

  select count(*) into v_rows from public.product_proposals;
  raise notice '38-C 04: % propuestas existentes; quedarán como update.', v_rows;
end $$;

-- ---------- columnas ----------
alter table public.product_proposals
  add column proposal_kind text not null default 'update',
  add column proposed_new_subcategory text;

alter table public.product_proposals
  alter column product_id drop not null;

-- ---------- restricciones ----------
alter table public.product_proposals
  add constraint product_proposals_kind_check
    check (proposal_kind in ('create', 'update')),
  add constraint product_proposals_kind_product
    check ((proposal_kind = 'update' and product_id is not null)
        or (proposal_kind = 'create' and product_id is null)),
  add constraint product_proposals_new_subcategory_length
    check (proposed_new_subcategory is null
           or (char_length(proposed_new_subcategory) <= 100 and btrim(proposed_new_subcategory) <> '')),
  add constraint product_proposals_new_subcategory_exclusive
    check (proposed_new_subcategory is null or not (proposed_changes ? 'subcategory')),
  add constraint product_proposals_create_has_name
    check (proposal_kind <> 'create' or btrim(coalesce(proposed_changes ->> 'name', '')) <> '');

comment on table public.product_proposals is
  '38-C: propuesta de un distribuidor verificado: producto nuevo (create, sin product_id) o cambio de información y/o precio de un producto propio (update). No modifica products ni product_prices; la aplicación es del punto 39.';
comment on column public.product_proposals.proposal_kind is
  'create: producto nuevo (product_id null). update: cambio de un producto existente. Se fija al crear y no cambia.';
comment on column public.product_proposals.proposed_new_subcategory is
  'Subcategoría que el distribuidor no encuentra en la lista. Excluye proposed_changes.subcategory. Mobau decide en el punto 39.';

-- ---------- índices únicos parciales ----------
-- Conflictos para el índice de create (deberían ser 0: no hay filas create).
DO $$
begin
  if exists (select 1 from public.product_proposals
              where proposal_kind = 'create' and status in ('draft', 'submitted', 'changes_requested')
              group by distributor_id, btrim(regexp_replace(lower(proposed_changes ->> 'name'), '\s+', ' ', 'g'))
              having count(*) > 1) then
    raise exception '38-C 04: hay propuestas create abiertas duplicadas por nombre';
  end if;
end $$;

drop index public.product_proposals_one_open_per_product;
create unique index product_proposals_one_open_per_product
  on public.product_proposals (product_id)
  where proposal_kind = 'update'
    and status in ('draft', 'submitted', 'changes_requested');

-- D1: misma empresa + mismo nombre normalizado, solo entre propuestas
-- create abiertas. No mira products: coincidir con un producto existente
-- no bloquea.
create unique index product_proposals_one_open_create_per_name
  on public.product_proposals
     (distributor_id, (btrim(regexp_replace(lower(proposed_changes ->> 'name'), '\s+', ' ', 'g'))))
  where proposal_kind = 'create'
    and status in ('draft', 'submitted', 'changes_requested');

-- ---------- 1. distribuidor, autor y tipo ----------
create or replace function public.fix_proposal_author()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
begin
  if v_uid is not null then
    new.distributor_id := (select public.my_verified_distributor_id());
    if new.distributor_id is null then
      raise exception 'Tu empresa no está verificada: no puedes crear propuestas.' using errcode = '42501';
    end if;
    new.author_id := v_uid;
    if new.status is distinct from 'draft' then
      raise exception 'Una propuesta nueva empieza siempre como borrador.' using errcode = '42501';
    end if;
    -- Campos del sistema y de Mobau: nunca los fija el cliente.
    new.version := 1;
    new.product_snapshot := null;
    new.submitted_at := null;
    new.reviewed_at := null;
    new.reviewed_by := null;
    new.rejection_reason := null;
    new.created_at := now();
    new.updated_at := now();
  end if;

  if new.proposal_kind is null or new.proposal_kind not in ('create', 'update') then
    raise exception 'Tipo de propuesta no válido: %. Usa create (producto nuevo) o update (cambio).', new.proposal_kind
      using errcode = '23514';
  end if;

  if new.proposal_kind = 'create' then
    if new.product_id is not null then
      raise exception 'Una propuesta de producto nuevo no puede indicar un producto existente.' using errcode = '23514';
    end if;
  else
    if new.product_id is null then
      raise exception 'Una propuesta de cambio necesita el producto que se quiere cambiar.' using errcode = '23514';
    end if;
    if not exists (select 1 from public.products p
                    where p.id = new.product_id and p.distributor_id = new.distributor_id) then
      raise exception 'El producto no pertenece a la empresa de la propuesta.' using errcode = '42501';
    end if;
  end if;
  return new;
end;
$$;

-- ---------- 2. validación de los datos propuestos ----------
create or replace function public.validate_proposal_changes()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  k text;
  v jsonb;
  s text;
  allowed constant text[] := array['name', 'description', 'category_id', 'subcategory', 'image_url', 'availability',
                                   'lead_time', 'brand', 'measurements', 'materials', 'finishes',
                                   'technical_sheet_url', 'cad_bim_3d_url', 'use_context', 'space'];
  -- Mismos límites que products_text_lengths.
  max_len constant jsonb := '{"name":120, "brand":80, "description":2000, "measurements":200, "materials":200,
                              "finishes":200, "lead_time":160, "image_url":500, "technical_sheet_url":500,
                              "cad_bim_3d_url":500, "category_id":100, "subcategory":100}';
  -- Mismo patrón que products_urls_http.
  url_re constant text := '^https?://[^\s"''<>`]+$';
  -- D2: obligatorios para enviar un producto nuevo (además de la subcategoría).
  required_on_create constant text[] := array['name', 'description', 'category_id', 'availability'];
  required_labels constant jsonb := '{"name": "nombre", "description": "descripción", "category_id": "categoría",
                                      "availability": "disponibilidad"}';
  v_cur_category text;
  v_cur_subcategory text;
  v_category text;
  v_subcategory text;
  v_new_sub text;
  v_entering_submitted boolean;
begin
  v_new_sub := new.proposed_new_subcategory;

  -- Lista cerrada, tipos, longitudes, URLs y valores permitidos (como 38-C 02).
  for k, v in select e.key, e.value from jsonb_each(new.proposed_changes) e loop
    if not (k = any (allowed)) then
      raise exception 'Campo no permitido en la propuesta: %.', k using errcode = '23514';
    end if;
    if jsonb_typeof(v) not in ('string', 'null') then
      raise exception 'El campo % debe ser texto.', k using errcode = '23514';
    end if;
    s := v #>> '{}';

    if k in ('name', 'category_id', 'availability') and (s is null or btrim(s) = '') then
      raise exception 'El campo % no puede quedar vacío.', k using errcode = '23514';
    end if;
    if s is not null and max_len ? k and char_length(s) > (max_len ->> k)::int then
      raise exception 'El campo % supera los % caracteres.', k, max_len ->> k using errcode = '23514';
    end if;
    if k in ('image_url', 'technical_sheet_url', 'cad_bim_3d_url') and s is not null and s !~* url_re then
      raise exception 'El campo % debe ser un enlace que empiece por http:// o https://.', k using errcode = '23514';
    end if;
    if k = 'availability' and s not in ('en-stock', 'bajo-pedido', 'por-confirmar') then
      raise exception 'Disponibilidad no válida: %.', s using errcode = '23514';
    end if;
    if k = 'use_context' and s is not null and s not in ('residencial', 'comercial', 'hospitality', 'oficina') then
      raise exception 'Uso no válido: %.', s using errcode = '23514';
    end if;
    if k = 'space' and s is not null
       and s not in ('sala', 'comedor', 'dormitorio', 'cocina', 'bano', 'oficina', 'areas-comunes', 'retail', 'exterior') then
      raise exception 'Espacio no válido: %.', s using errcode = '23514';
    end if;
    if k = 'category_id' and not exists (select 1 from public.categories c where c.id = s) then
      raise exception 'Categoría no válida: %.', s using errcode = '23514';
    end if;
  end loop;

  -- ---- Clasificación (D3, D5) ----
  if new.proposed_changes ? 'subcategory' and v_new_sub is not null then
    raise exception 'Elige una subcategoría de la lista o propón una nueva, no las dos.' using errcode = '23514';
  end if;

  -- Categoría resultante: la propuesta o, en update, la actual del producto.
  if new.proposal_kind = 'update' then
    select p.category_id, p.subcategory into v_cur_category, v_cur_subcategory
      from public.products p where p.id = new.product_id;
  end if;
  v_category := case when new.proposed_changes ? 'category_id'
                     then new.proposed_changes ->> 'category_id'
                     else v_cur_category end;

  -- D5: en update, cambiar la categoría exige aportar la subcategoría.
  if new.proposal_kind = 'update' and new.proposed_changes ? 'category_id'
     and not (new.proposed_changes ? 'subcategory') and v_new_sub is null then
    raise exception 'Si cambias la categoría, elige también una subcategoría de la nueva categoría o propón una nueva.'
      using errcode = '23514';
  end if;

  -- Subcategoría de la lista: no vacía y válida para la categoría resultante.
  if new.proposed_changes ? 'subcategory' then
    v_subcategory := new.proposed_changes ->> 'subcategory';
    if v_subcategory is null or btrim(v_subcategory) = '' then
      raise exception 'La subcategoría no puede quedar vacía: elige una de la lista o propón una nueva.' using errcode = '23514';
    end if;
    if v_category is null or not exists (
         select 1 from public.categories c
          where c.id = v_category and v_subcategory = any (c.subcategories)) then
      raise exception 'La subcategoría "%" no pertenece a la categoría "%".', v_subcategory, coalesce(v_category, 'sin categoría')
        using errcode = '23514';
    end if;
  end if;

  -- Subcategoría nueva: no puede repetir una de la lista de su categoría
  -- (misma normalización que el nombre en D1).
  if v_new_sub is not null and v_category is not null and exists (
       select 1 from public.categories c, unnest(c.subcategories) as sc(name)
        where c.id = v_category
          and btrim(regexp_replace(lower(sc.name), '\s+', ' ', 'g'))
            = btrim(regexp_replace(lower(v_new_sub), '\s+', ' ', 'g'))) then
    raise exception 'La subcategoría "%" ya existe en la categoría "%": elígela de la lista.', v_new_sub, v_category
      using errcode = '23514';
  end if;

  -- ---- D2: producto nuevo completo al enviarlo (no en borrador) ----
  if tg_op = 'UPDATE' then
    v_entering_submitted := new.status = 'submitted' and old.status is distinct from 'submitted';
  else
    v_entering_submitted := new.status = 'submitted';
  end if;
  if new.proposal_kind = 'create' and v_entering_submitted then
    foreach k in array required_on_create loop
      if btrim(coalesce(new.proposed_changes ->> k, '')) = '' then
        raise exception 'Para enviar un producto nuevo falta: %.', required_labels ->> k using errcode = '23514';
      end if;
    end loop;
    if not (new.proposed_changes ? 'subcategory') and v_new_sub is null then
      raise exception 'Para enviar un producto nuevo elige una subcategoría de la lista o propón una nueva.' using errcode = '23514';
    end if;
  end if;

  return new;
end;
$$;

-- ---------- 3. transiciones del distribuidor ----------
create or replace function public.transition_proposal_status()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
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
     or new.version is distinct from old.version then
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
$$;

-- ---------- 4. copia del producto al enviar ----------
create or replace function public.snapshot_product_on_submit()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_product jsonb;
  v_price jsonb;
begin
  if new.proposal_kind = 'update' then
    select to_jsonb(p) into v_product from public.products p where p.id = new.product_id;
    if v_product is null then
      raise exception 'No se encontró el producto % para guardar la copia.', new.product_id using errcode = '42501';
    end if;
    select to_jsonb(pp) into v_price from public.product_prices pp where pp.product_id = new.product_id;
    new.product_snapshot := jsonb_build_object('product', v_product, 'price', v_price, 'taken_at', now());
  else
    -- create: no hay producto que copiar.
    new.product_snapshot := null;
  end if;

  new.submitted_at := now();
  if old.status = 'changes_requested' then
    new.version := old.version + 1;
  end if;
  return new;
end;
$$;

-- ---------- 5. historial (solo anexar) ----------
-- SECURITY DEFINER: proposal_events no tiene permisos de escritura para
-- ningún cliente; solo este trigger la escribe. El tipo queda en todos los
-- eventos; el contenido propuesto, en los envíos.
create or replace function public.log_proposal_event()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
begin
  insert into public.proposal_events (proposal_id, actor_id, actor_kind, from_status, to_status, version, payload, note)
  values (
    new.id,
    v_uid,
    case when v_uid is null then 'mobau' else 'distributor' end,
    case when tg_op = 'INSERT' then null else old.status end,
    new.status,
    new.version,
    jsonb_build_object('proposal_kind', new.proposal_kind)
      || case when new.status = 'submitted' then
           jsonb_build_object('proposed_changes', new.proposed_changes,
                              'proposed_new_subcategory', new.proposed_new_subcategory,
                              'proposed_price_status', new.proposed_price_status,
                              'proposed_price_amount', new.proposed_price_amount,
                              'internal_note', new.internal_note)
         else '{}'::jsonb end,
    case when new.status in ('changes_requested', 'rejected') then new.rejection_reason end
  );
  return null;
end;
$$;

-- create or replace conserva los permisos; se repite el cierre por claridad.
revoke all on function public.fix_proposal_author() from public, anon, authenticated;
revoke all on function public.validate_proposal_changes() from public, anon, authenticated;
revoke all on function public.transition_proposal_status() from public, anon, authenticated;
revoke all on function public.snapshot_product_on_submit() from public, anon, authenticated;
revoke all on function public.log_proposal_event() from public, anon, authenticated;

-- ---------- permisos por columna ----------
-- El tipo se fija al crear (INSERT) y no se puede cambiar (sin UPDATE).
grant insert (proposal_kind, proposed_new_subcategory) on table public.product_proposals to authenticated;
grant update (proposed_new_subcategory) on table public.product_proposals to authenticated;

-- ---------- validación final ----------
DO $$
declare
  f text;
  r text;
  v_insert_cols text;
  v_update_cols text;
  v_expected_triggers constant text[] := array[
    'trg_product_proposals_10_author', 'trg_product_proposals_20_transition', 'trg_product_proposals_30_validate',
    'trg_product_proposals_40_snapshot', 'trg_product_proposals_50_updated_at',
    'trg_product_proposals_90_event_insert', 'trg_product_proposals_91_event_status'];
begin
  -- Columnas
  if not exists (select 1 from information_schema.columns
                  where table_schema = 'public' and table_name = 'product_proposals' and column_name = 'proposal_kind'
                    and data_type = 'text' and is_nullable = 'NO' and column_default like '''update''%')
     or not exists (select 1 from information_schema.columns
                     where table_schema = 'public' and table_name = 'product_proposals'
                       and column_name = 'proposed_new_subcategory' and data_type = 'text' and is_nullable = 'YES')
     or (select is_nullable from information_schema.columns
          where table_schema = 'public' and table_name = 'product_proposals' and column_name = 'product_id') <> 'YES' then
    raise exception '38-C 04: columnas no esperadas en product_proposals';
  end if;
  if exists (select 1 from public.product_proposals where proposal_kind <> 'update') then
    raise exception '38-C 04: las filas existentes deberían ser update';
  end if;

  -- Restricciones
  if (select count(*) from pg_constraint
       where conrelid = 'public.product_proposals'::regclass and contype = 'c'
         and conname in ('product_proposals_kind_check', 'product_proposals_kind_product',
                         'product_proposals_new_subcategory_length', 'product_proposals_new_subcategory_exclusive',
                         'product_proposals_create_has_name')) <> 5 then
    raise exception '38-C 04: faltan restricciones nuevas';
  end if;

  -- Restricciones de precio de 38-C 01 (se aplican también a create)
  if (select count(*) from pg_constraint
       where conrelid = 'public.product_proposals'::regclass and contype = 'c'
         and conname in ('product_proposals_price_status_check', 'product_proposals_price_amount_check',
                         'product_proposals_price_published_amount', 'product_proposals_price_amount_needs_status')) <> 4 then
    raise exception '38-C 04: faltan las restricciones de precio de 38-C 01';
  end if;

  -- Índices
  if not exists (select 1 from pg_index i join pg_class c on c.oid = i.indexrelid
                  where c.relname = 'product_proposals_one_open_per_product' and i.indisunique
                    and pg_get_expr(i.indpred, i.indrelid) like '%proposal_kind = ''update''%')
     or not exists (select 1 from pg_index i join pg_class c on c.oid = i.indexrelid
                     where c.relname = 'product_proposals_one_open_create_per_name' and i.indisunique
                       and pg_get_expr(i.indpred, i.indrelid) like '%proposal_kind = ''create''%') then
    raise exception '38-C 04: índices únicos parciales no esperados';
  end if;

  -- Triggers: los mismos 7
  if (select count(*) from pg_trigger
       where not tgisinternal and tgrelid = 'public.product_proposals'::regclass
         and tgname = any (v_expected_triggers)) <> 7
     or (select count(*) from pg_trigger
          where not tgisinternal and tgrelid = 'public.product_proposals'::regclass) <> 7
     or exists (select 1 from pg_trigger where not tgisinternal and tgrelid = 'public.proposal_events'::regclass) then
    raise exception '38-C 04: los triggers no son los 7 esperados';
  end if;

  -- Funciones: search_path vacío, sin EXECUTE de cliente, SECURITY DEFINER solo el historial
  foreach f in array array['public.fix_proposal_author()', 'public.validate_proposal_changes()',
                           'public.transition_proposal_status()', 'public.snapshot_product_on_submit()',
                           'public.log_proposal_event()'] loop
    if not exists (select 1 from pg_proc p
                    where p.oid = f::regprocedure and p.proconfig @> array['search_path=""']) then
      raise exception '38-C 04: % no tiene search_path vacío', f;
    end if;
    foreach r in array array['anon', 'authenticated'] loop
      if has_function_privilege(r, f, 'EXECUTE') then
        raise exception '38-C 04: % puede ejecutar %', r, f;
      end if;
    end loop;
  end loop;
  if (select count(*) from pg_proc
       where oid in ('public.fix_proposal_author()'::regprocedure, 'public.validate_proposal_changes()'::regprocedure,
                     'public.transition_proposal_status()'::regprocedure, 'public.snapshot_product_on_submit()'::regprocedure)
         and prosecdef) <> 0
     or not (select prosecdef from pg_proc where oid = 'public.log_proposal_event()'::regprocedure) then
    raise exception '38-C 04: SECURITY DEFINER debe estar solo en log_proposal_event()';
  end if;

  -- Políticas: sin cambios
  if (select count(*) from pg_policies where schemaname = 'public' and tablename in ('product_proposals', 'proposal_events')) <> 4
     or (select count(*) from pg_policies where schemaname = 'public') <> 44 then
    raise exception '38-C 04: el número de políticas ha cambiado (esperado 4 / 44)';
  end if;

  -- Permisos: anon nada; authenticated solo por columna
  if has_table_privilege('anon', 'public.product_proposals', 'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER')
     or has_any_column_privilege('anon', 'public.product_proposals', 'SELECT,INSERT,UPDATE,REFERENCES') then
    raise exception '38-C 04: anon tiene algún permiso sobre product_proposals';
  end if;
  if has_table_privilege('authenticated', 'public.product_proposals', 'INSERT')
     or has_table_privilege('authenticated', 'public.product_proposals', 'UPDATE')
     or has_table_privilege('authenticated', 'public.product_proposals', 'DELETE,TRUNCATE,REFERENCES,TRIGGER') then
    raise exception '38-C 04: authenticated tiene permisos de tabla de más';
  end if;
  select string_agg(column_name, ',' order by column_name) into v_insert_cols
    from information_schema.column_privileges
   where table_schema = 'public' and table_name = 'product_proposals'
     and grantee = 'authenticated' and privilege_type = 'INSERT';
  select string_agg(column_name, ',' order by column_name) into v_update_cols
    from information_schema.column_privileges
   where table_schema = 'public' and table_name = 'product_proposals'
     and grantee = 'authenticated' and privilege_type = 'UPDATE';
  if v_insert_cols is distinct from 'internal_note,product_id,proposal_kind,proposed_changes,proposed_new_subcategory,proposed_price_amount,proposed_price_status' then
    raise exception '38-C 04: columnas de INSERT inesperadas: %', v_insert_cols;
  end if;
  if v_update_cols is distinct from 'internal_note,proposed_changes,proposed_new_subcategory,proposed_price_amount,proposed_price_status,status' then
    raise exception '38-C 04: columnas de UPDATE inesperadas: %', v_update_cols;
  end if;

  raise notice '38-C 04 OK: create/update, 5 restricciones, 2 índices únicos parciales, 5 funciones reemplazadas, 7 triggers, 44 políticas.';
end $$;

COMMIT;
