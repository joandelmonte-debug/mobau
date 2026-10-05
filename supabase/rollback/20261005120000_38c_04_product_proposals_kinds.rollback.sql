-- ============================================================
-- PROPUESTA NO EJECUTADA (38-C) — no ejecutar sin aprobación explícita
-- ============================================================
-- 38-C · 04 · ROLLBACK · Vuelve al modelo de 38-C 01–03 (solo update)
-- ------------------------------------------------------------
-- Se niega si alguna propuesta usa proposal_kind = 'create' o
-- proposed_new_subcategory: revertir borraría ese significado. No borra
-- propuestas, eventos ni datos de otras tablas (los eventos ya escritos
-- conservan "proposal_kind" en su payload jsonb, que es solo histórico).
--
-- Restaura, en este orden:
--   1. los permisos por columna de 38-C 03 (retira los añadidos por 04);
--   2. las 5 funciones con el texto literal de 38-C 02;
--   3. el índice de una propuesta abierta por producto de 38-C 01
--      (comprobando antes que no hay conflictos) y quita el de create;
--   4. quita las 5 restricciones y las 2 columnas de 04, y vuelve a
--      product_id not null.
-- Triggers y políticas no se tocan (7 y 44). Ejecutar completo (BEGIN … COMMIT).
-- ============================================================

BEGIN;

-- ---------- prechecks ----------
DO $$
begin
  if not exists (select 1 from information_schema.columns
                  where table_schema = 'public' and table_name = 'product_proposals' and column_name = 'proposal_kind')
     or not exists (select 1 from information_schema.columns
                     where table_schema = 'public' and table_name = 'product_proposals' and column_name = 'proposed_new_subcategory') then
    raise exception '38-C 04 rollback: 04 no está aplicada (faltan proposal_kind o proposed_new_subcategory)';
  end if;
  if exists (select 1 from public.product_proposals where proposal_kind = 'create') then
    raise exception '38-C 04 rollback: hay propuestas de producto nuevo (create); revertir borraría su significado';
  end if;
  if exists (select 1 from public.product_proposals where proposed_new_subcategory is not null) then
    raise exception '38-C 04 rollback: hay propuestas con subcategoría nueva; revertir borraría ese dato';
  end if;
  if exists (select 1 from public.product_proposals where product_id is null) then
    raise exception '38-C 04 rollback: hay propuestas sin product_id';
  end if;
  -- Conflictos con el índice original (sin filtro de tipo).
  if exists (select 1 from public.product_proposals
              where status in ('draft', 'submitted', 'changes_requested')
              group by product_id having count(*) > 1) then
    raise exception '38-C 04 rollback: hay más de una propuesta abierta para un mismo producto; no se puede restaurar el índice';
  end if;
  if (select count(*) from pg_trigger
       where not tgisinternal and tgrelid = 'public.product_proposals'::regclass
         and tgname like 'trg_product_proposals_%') <> 7 then
    raise exception '38-C 04 rollback: se esperan los 7 triggers';
  end if;
end $$;

-- ---------- 1. permisos por columna de 38-C 03 ----------
revoke insert (proposal_kind, proposed_new_subcategory) on table public.product_proposals from authenticated;
revoke update (proposed_new_subcategory) on table public.product_proposals from authenticated;

-- ---------- 2. funciones de 38-C 02 (texto literal) ----------
-- ---------- 1. distribuidor y autor fijados por el servidor ----------
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
  if not exists (select 1 from public.products p
                  where p.id = new.product_id and p.distributor_id = new.distributor_id) then
    raise exception 'El producto no pertenece a la empresa de la propuesta.' using errcode = '42501';
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
  v_cur_category text;
  v_cur_subcategory text;
  v_category text;
  v_subcategory text;
begin
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

  -- Subcategoría coherente con la categoría resultante (como
  -- products_validate_subcategory): lo propuesto o, si no se propone, lo actual.
  if new.proposed_changes ? 'category_id' or new.proposed_changes ? 'subcategory' then
    select p.category_id, p.subcategory into v_cur_category, v_cur_subcategory
      from public.products p where p.id = new.product_id;
    v_category := coalesce(new.proposed_changes ->> 'category_id', v_cur_category);
    v_subcategory := case when new.proposed_changes ? 'subcategory'
                          then new.proposed_changes ->> 'subcategory'
                          else v_cur_subcategory end;
    if v_subcategory is not null and not exists (
         select 1 from public.categories c
          where c.id = v_category and v_subcategory = any (c.subcategories)) then
      raise exception 'La subcategoría "%" no pertenece a la categoría "%": propón también la subcategoría (o vacíala).',
        v_subcategory, v_category using errcode = '23514';
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
     or new.product_id is distinct from old.product_id
     or new.distributor_id is distinct from old.distributor_id
     or new.author_id is distinct from old.author_id
     or new.created_at is distinct from old.created_at then
    raise exception 'No se puede cambiar el producto, la empresa ni el autor de una propuesta.' using errcode = '42501';
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

  if new.status = 'submitted'
     and new.proposed_changes = '{}'::jsonb and new.proposed_price_status is null then
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
  select to_jsonb(p) into v_product from public.products p where p.id = new.product_id;
  if v_product is null then
    raise exception 'No se encontró el producto % para guardar la copia.', new.product_id using errcode = '42501';
  end if;
  select to_jsonb(pp) into v_price from public.product_prices pp where pp.product_id = new.product_id;

  new.product_snapshot := jsonb_build_object('product', v_product, 'price', v_price, 'taken_at', now());
  new.submitted_at := now();
  if old.status = 'changes_requested' then
    new.version := old.version + 1;
  end if;
  return new;
end;
$$;

-- ---------- 5. historial (solo anexar) ----------
-- SECURITY DEFINER: proposal_events no tendrá permisos de escritura para
-- ningún cliente; solo este trigger la escribe.
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
    case when new.status = 'submitted' then
      jsonb_build_object('proposed_changes', new.proposed_changes,
                         'proposed_price_status', new.proposed_price_status,
                         'proposed_price_amount', new.proposed_price_amount,
                         'internal_note', new.internal_note)
    end,
    case when new.status in ('changes_requested', 'rejected') then new.rejection_reason end
  );
  return null;
end;
$$;

revoke all on function public.fix_proposal_author() from public, anon, authenticated;
revoke all on function public.validate_proposal_changes() from public, anon, authenticated;
revoke all on function public.transition_proposal_status() from public, anon, authenticated;
revoke all on function public.snapshot_product_on_submit() from public, anon, authenticated;
revoke all on function public.log_proposal_event() from public, anon, authenticated;

-- ---------- 3. índices ----------
drop index public.product_proposals_one_open_create_per_name;
drop index public.product_proposals_one_open_per_product;
create unique index product_proposals_one_open_per_product
  on public.product_proposals (product_id)
  where status in ('draft', 'submitted', 'changes_requested');

-- ---------- 4. restricciones y columnas ----------
alter table public.product_proposals
  drop constraint product_proposals_create_has_name,
  drop constraint product_proposals_new_subcategory_exclusive,
  drop constraint product_proposals_new_subcategory_length,
  drop constraint product_proposals_kind_product,
  drop constraint product_proposals_kind_check;

alter table public.product_proposals
  drop column proposed_new_subcategory,
  drop column proposal_kind;

alter table public.product_proposals
  alter column product_id set not null;

comment on table public.product_proposals is
  '38-C: propuesta de cambio de información y/o precio de un producto existente, hecha por su distribuidor verificado. No modifica products ni product_prices; la aplicación es del punto 39.';

-- ---------- validación final ----------
DO $$
declare
  f text;
  r text;
  v_insert_cols text;
  v_update_cols text;
begin
  if exists (select 1 from information_schema.columns
              where table_schema = 'public' and table_name = 'product_proposals'
                and column_name in ('proposal_kind', 'proposed_new_subcategory'))
     or (select is_nullable from information_schema.columns
          where table_schema = 'public' and table_name = 'product_proposals' and column_name = 'product_id') <> 'NO' then
    raise exception '38-C 04 rollback: columnas no restauradas';
  end if;
  if exists (select 1 from pg_constraint
              where conrelid = 'public.product_proposals'::regclass
                and conname in ('product_proposals_kind_check', 'product_proposals_kind_product',
                                'product_proposals_new_subcategory_length', 'product_proposals_new_subcategory_exclusive',
                                'product_proposals_create_has_name')) then
    raise exception '38-C 04 rollback: quedan restricciones de 04';
  end if;
  if to_regclass('public.product_proposals_one_open_create_per_name') is not null
     or not exists (select 1 from pg_index i join pg_class c on c.oid = i.indexrelid
                     where c.relname = 'product_proposals_one_open_per_product' and i.indisunique
                       and pg_get_expr(i.indpred, i.indrelid) not like '%proposal_kind%') then
    raise exception '38-C 04 rollback: índices no restaurados';
  end if;

  foreach f in array array['public.fix_proposal_author()', 'public.validate_proposal_changes()',
                           'public.transition_proposal_status()', 'public.snapshot_product_on_submit()',
                           'public.log_proposal_event()'] loop
    if pg_get_functiondef(f::regprocedure) like '%proposal_kind%'
       or pg_get_functiondef(f::regprocedure) like '%proposed_new_subcategory%' then
      raise exception '38-C 04 rollback: % sigue siendo la versión de 04', f;
    end if;
    if not exists (select 1 from pg_proc p
                    where p.oid = f::regprocedure and p.proconfig @> array['search_path=""']) then
      raise exception '38-C 04 rollback: % no tiene search_path vacío', f;
    end if;
    foreach r in array array['anon', 'authenticated'] loop
      if has_function_privilege(r, f, 'EXECUTE') then
        raise exception '38-C 04 rollback: % puede ejecutar %', r, f;
      end if;
    end loop;
  end loop;
  if (select count(*) from pg_proc
       where oid in ('public.fix_proposal_author()'::regprocedure, 'public.validate_proposal_changes()'::regprocedure,
                     'public.transition_proposal_status()'::regprocedure, 'public.snapshot_product_on_submit()'::regprocedure)
         and prosecdef) <> 0
     or not (select prosecdef from pg_proc where oid = 'public.log_proposal_event()'::regprocedure) then
    raise exception '38-C 04 rollback: SECURITY DEFINER debe estar solo en log_proposal_event()';
  end if;

  if (select count(*) from pg_trigger
       where not tgisinternal and tgrelid = 'public.product_proposals'::regclass) <> 7 then
    raise exception '38-C 04 rollback: se esperan 7 triggers';
  end if;
  if (select count(*) from pg_policies where schemaname = 'public') <> 44 then
    raise exception '38-C 04 rollback: se esperaban 44 políticas en public';
  end if;

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
    raise exception '38-C 04 rollback: permisos por columna distintos de 38-C 03 (INSERT: %; UPDATE: %)', v_insert_cols, v_update_cols;
  end if;
  if has_table_privilege('anon', 'public.product_proposals', 'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER')
     or has_any_column_privilege('anon', 'public.product_proposals', 'SELECT,INSERT,UPDATE,REFERENCES') then
    raise exception '38-C 04 rollback: anon tiene algún permiso sobre product_proposals';
  end if;

  raise notice '38-C 04 rollback OK: modelo de 38-C 01–03 restaurado; propuestas y eventos intactos.';
end $$;

COMMIT;
