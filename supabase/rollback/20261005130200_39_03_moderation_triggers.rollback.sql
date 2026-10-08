-- ============================================================
-- PROPUESTA NO EJECUTADA (39) — no ejecutar sin aprobación explícita
-- ============================================================
-- 39 · 03 · ROLLBACK · Triggers de nuevo como en 38-C 04
-- ------------------------------------------------------------
-- Restaura el texto literal de 38-C 04 (transition, validate, log) y de
-- products_before_insert, y quita created_product_id. Se niega si 39-04
-- sigue aplicada o si alguna propuesta tiene created_product_id (se
-- perdería el enlace con el producto creado). Ejecutar completo.
-- ============================================================

BEGIN;

DO $$
begin
  if to_regprocedure('public.moderate_product_proposal(uuid, text, text, integer)') is not null then
    raise exception '39-03 rollback: 39-04 sigue aplicada (revertir 39-04 antes)';
  end if;
  if exists (select 1 from public.product_proposals where created_product_id is not null) then
    raise exception '39-03 rollback: hay propuestas enlazadas a productos creados';
  end if;
end $$;

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

create or replace function public.products_before_insert()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if (select auth.uid()) is not null then
    new.distributor_id := public.my_verified_distributor_id();
    if new.distributor_id is null then
      raise exception 'Tu perfil de distribuidor no está verificado.' using errcode = '42501';
    end if;
    new.id := new.distributor_id || '-' || substr(replace(gen_random_uuid()::text, '-', ''), 1, 8);
  end if;
  return new;
end $$;

revoke all on function public.transition_proposal_status() from public, anon, authenticated;
revoke all on function public.validate_proposal_changes() from public, anon, authenticated;
revoke all on function public.log_proposal_event() from public, anon, authenticated;

alter table public.product_proposals
  drop constraint product_proposals_created_product_only_create_approved,
  drop column created_product_id;

DO $$
begin
  if (select md5(prosrc) from pg_proc where oid = 'public.transition_proposal_status()'::regprocedure) <> '27c1ed36fdb48de5d783d7eb66347f3c'
     or (select md5(prosrc) from pg_proc where oid = 'public.validate_proposal_changes()'::regprocedure) <> 'd5f7c78c81dc2994319478a0192d0a6c'
     or (select md5(prosrc) from pg_proc where oid = 'public.log_proposal_event()'::regprocedure) <> 'cb9d627bdfabe22bfcaadb02b1e8034d' then
    raise exception '39-03 rollback: las funciones no coinciden con 38-C 04';
  end if;
  if (select md5(prosrc) from pg_proc where oid = 'public.products_before_insert()'::regprocedure) <> '0ccab1710153433701870754ae268a65' then
    raise exception '39-03 rollback: products_before_insert no coincide con la versión original';
  end if;
  raise notice '39-03 rollback OK: triggers como en 38-C 04.';
end $$;

COMMIT;
