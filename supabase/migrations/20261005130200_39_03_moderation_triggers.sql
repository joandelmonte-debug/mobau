-- ============================================================
-- PROPUESTA NO EJECUTADA (39) — no ejecutar sin aprobación explícita
-- ============================================================
-- 39 · 03 · Triggers preparados para la decisión de Mobau
-- ------------------------------------------------------------
-- Requiere 39-01. Los triggers actuales tratan como distribuidor a toda
-- sesión con auth.uid(); la cuenta de Mobau quedaría bloqueada o mal
-- registrada. Aquí se añade una rama de Mobau que SOLO se activa con
-- mobau_moderating(id): (contexto privado de esta transacción para esta
-- propuesta, que solo crea moderate_product_proposal, 39-04) AND (id no
-- nulo) AND (admin activo con aal2). Un set_config del cliente no la activa.
--
--   product_proposals.created_product_id  enlace create aprobada → producto
--          creado (solo lo escribe Mobau; restricción: solo create aprobada).
--   transition_proposal_status()  rama de Mobau: submitted → approved |
--          changes_requested | rejected, sin tocar el contenido enviado y
--          nunca sobre la propia empresa del admin.
--          Distribuidor: igual que 38-C 04 y además no puede tocar
--          created_product_id.
--   validate_proposal_changes()   no revalida durante la decisión de Mobau.
--   log_proposal_event()          actor 'mobau', resumen de la decisión (leído
--          del contexto privado) en payload y mensaje como nota.
--   products_before_insert()      no fuerza id ni distributor_id durante la
--          decisión de Mobau (los fija la función).
-- Fuera de la decisión de Mobau, todo se comporta exactamente como hoy.
-- Las partes no modificadas son las de 38-C 04 y de la función viva
-- products_before_insert, con las funciones del sistema cualificadas como
-- pg_catalog.* (search_path vacío). Ejecutar completo (BEGIN … COMMIT).
-- ============================================================

BEGIN;

-- ---------- prechecks ----------
DO $$
begin
  if to_regprocedure('public.mobau_moderating(uuid)') is null or to_regprocedure('public.is_mobau_admin()') is null
     or to_regprocedure('public.mobau_moderation_proposal_id()') is null or to_regclass('public.mobau_moderation_context') is null then
    raise exception '39-03: falta 39-01';
  end if;
  if exists (select 1 from information_schema.columns
              where table_schema = 'public' and table_name = 'product_proposals' and column_name = 'created_product_id') then
    raise exception '39-03: created_product_id ya existe';
  end if;
  -- Las funciones de propuestas deben ser exactamente las de 38-C 04.
  if (select md5(prosrc) from pg_proc where oid = 'public.transition_proposal_status()'::regprocedure) <> '27c1ed36fdb48de5d783d7eb66347f3c'
     or (select md5(prosrc) from pg_proc where oid = 'public.validate_proposal_changes()'::regprocedure) <> 'd5f7c78c81dc2994319478a0192d0a6c'
     or (select md5(prosrc) from pg_proc where oid = 'public.log_proposal_event()'::regprocedure) <> 'cb9d627bdfabe22bfcaadb02b1e8034d' then
    raise exception '39-03: las funciones de propuestas no son las de 38-C 04';
  end if;
  if (select md5(prosrc) from pg_proc where oid = 'public.products_before_insert()'::regprocedure) <> '0ccab1710153433701870754ae268a65' then
    raise exception '39-03: products_before_insert no es la versión esperada (38-B)';
  end if;
  if exists (select 1 from public.product_proposals where status = 'approved') then
    raise exception '39-03: ya hay propuestas aprobadas (se esperaba ninguna antes de 39)';
  end if;
end $$;

-- ---------- enlace con el producto creado ----------
alter table public.product_proposals
  add column created_product_id text references public.products (id),
  add constraint product_proposals_created_product_only_create_approved
    check (created_product_id is null or (proposal_kind = 'create' and status = 'approved'));

comment on column public.product_proposals.created_product_id is
  '39: producto creado al aprobar una propuesta create. Solo lo escribe moderate_product_proposal.';

-- ---------- funciones ----------
-- 20 · transiciones
create or replace function public.transition_proposal_status()
returns trigger
language plpgsql
set search_path = ''
as $$
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
$$;

-- 30 · validación
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
  -- 39: durante la decisión de Mobau el contenido no cambia (lo impide el
  -- trigger 20) y ya se validó al enviarse. No se revalida contra el
  -- catálogo que la propia decisión está actualizando (p. ej. la
  -- subcategoría nueva que se acaba de añadir).
  if tg_op = 'UPDATE' and (select public.mobau_moderating(new.id)) then
    return new;
  end if;

  v_new_sub := new.proposed_new_subcategory;

  -- Lista cerrada, tipos, longitudes, URLs y valores permitidos (como 38-C 02).
  for k, v in select e.key, e.value from pg_catalog.jsonb_each(new.proposed_changes) e loop
    if not (k = any (allowed)) then
      raise exception 'Campo no permitido en la propuesta: %.', k using errcode = '23514';
    end if;
    if pg_catalog.jsonb_typeof(v) not in ('string', 'null') then
      raise exception 'El campo % debe ser texto.', k using errcode = '23514';
    end if;
    s := v #>> '{}';

    if k in ('name', 'category_id', 'availability') and (s is null or pg_catalog.btrim(s) = '') then
      raise exception 'El campo % no puede quedar vacío.', k using errcode = '23514';
    end if;
    if s is not null and max_len ? k and pg_catalog.char_length(s) > (max_len ->> k)::int then
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
    if v_subcategory is null or pg_catalog.btrim(v_subcategory) = '' then
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
       select 1 from public.categories c, pg_catalog.unnest(c.subcategories) as sc(name)
        where c.id = v_category
          and pg_catalog.btrim(pg_catalog.regexp_replace(pg_catalog.lower(sc.name), '\s+', ' ', 'g'))
            = pg_catalog.btrim(pg_catalog.regexp_replace(pg_catalog.lower(v_new_sub), '\s+', ' ', 'g'))) then
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
      if pg_catalog.btrim(coalesce(new.proposed_changes ->> k, '')) = '' then
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

-- 90/91 · historial
create or replace function public.log_proposal_event()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_moderating boolean;
  v_decision jsonb := '{}'::jsonb;
begin
  -- 39: en una decisión de Mobau, el evento es de 'mobau' y lleva en el
  -- payload el resumen que moderate_product_proposal guarda en el contexto
  -- privado (decisión, campos aplicados, precio, subcategoría, producto
  -- creado) y su mensaje como nota. Un ajuste de sesión no influye.
  v_moderating := (select public.mobau_moderating(new.id));
  if v_moderating then
    select c.event into v_decision
      from public.mobau_moderation_context c
     where c.txid = pg_catalog.txid_current_if_assigned() and c.proposal_id = new.id;
    v_decision := coalesce(v_decision, '{}'::jsonb);
  end if;

  insert into public.proposal_events (proposal_id, actor_id, actor_kind, from_status, to_status, version, payload, note)
  values (
    new.id,
    v_uid,
    case when v_moderating or v_uid is null then 'mobau' else 'distributor' end,
    case when tg_op = 'INSERT' then null else old.status end,
    new.status,
    new.version,
    pg_catalog.jsonb_build_object('proposal_kind', new.proposal_kind)
      || case when new.status = 'submitted' then
           pg_catalog.jsonb_build_object('proposed_changes', new.proposed_changes,
                              'proposed_new_subcategory', new.proposed_new_subcategory,
                              'proposed_price_status', new.proposed_price_status,
                              'proposed_price_amount', new.proposed_price_amount,
                              'internal_note', new.internal_note)
         else '{}'::jsonb end
      || v_decision,
    case when new.status in ('changes_requested', 'rejected') then new.rejection_reason
         when v_moderating then nullif(v_decision ->> 'message', '') end
  );
  return null;
end;
$$;

-- products · alta
create or replace function public.products_before_insert()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if (select auth.uid()) is not null then
    -- 39: producto nuevo aprobado por Mobau (moderate_product_proposal):
    -- id y distributor_id los fija la función a partir de la propuesta.
    -- (marca correcta) AND (proposal_id no nulo) AND (is_mobau_admin()).
    if (select public.mobau_moderating((select public.mobau_moderation_proposal_id()))) then
      return new;
    end if;
    new.distributor_id := public.my_verified_distributor_id();
    if new.distributor_id is null then
      raise exception 'Tu perfil de distribuidor no está verificado.' using errcode = '42501';
    end if;
    new.id := new.distributor_id || '-' || pg_catalog.substr(pg_catalog.replace(pg_catalog.gen_random_uuid()::text, '-', ''), 1, 8);
  end if;
  return new;
end $$;

revoke all on function public.transition_proposal_status() from public, anon, authenticated;
revoke all on function public.validate_proposal_changes() from public, anon, authenticated;
revoke all on function public.log_proposal_event() from public, anon, authenticated;
-- products_before_insert conserva sus permisos actuales (create or replace no los cambia).

-- ---------- validación final ----------
DO $$
begin
  if (select count(*) from pg_trigger where not tgisinternal and tgrelid = 'public.product_proposals'::regclass) <> 7 then
    raise exception '39-03: product_proposals debe seguir con 7 triggers';
  end if;
  if (select prosrc from pg_proc where oid = 'public.transition_proposal_status()'::regprocedure) not like '%mobau_moderating%'
     or (select prosrc from pg_proc where oid = 'public.validate_proposal_changes()'::regprocedure) not like '%mobau_moderating%'
     or (select prosrc from pg_proc where oid = 'public.log_proposal_event()'::regprocedure) not like '%mobau_moderating%'
     or (select prosrc from pg_proc where oid = 'public.products_before_insert()'::regprocedure) not like '%mobau_moderating%'
     or (select prosrc from pg_proc where oid = 'public.log_proposal_event()'::regprocedure) not like '%mobau_moderation_context%' then
    raise exception '39-03: alguna función no quedó adaptada';
  end if;
  if not (select prosecdef from pg_proc where oid = 'public.log_proposal_event()'::regprocedure)
     or (select prosecdef from pg_proc where oid = 'public.transition_proposal_status()'::regprocedure)
     or (select prosecdef from pg_proc where oid = 'public.validate_proposal_changes()'::regprocedure)
     or (select prosecdef from pg_proc where oid = 'public.products_before_insert()'::regprocedure) then
    raise exception '39-03: SECURITY DEFINER inesperado';
  end if;
  if exists (select 1 from pg_proc where oid in ('public.transition_proposal_status()'::regprocedure,
                 'public.validate_proposal_changes()'::regprocedure, 'public.log_proposal_event()'::regprocedure,
                 'public.products_before_insert()'::regprocedure)
               and (proowner <> 'postgres'::regrole or not proconfig @> array['search_path=""'])) then
    raise exception '39-03: las funciones deben seguir con propietario postgres y search_path vacío';
  end if;
  if has_column_privilege('authenticated', 'public.product_proposals', 'created_product_id', 'INSERT,UPDATE') then
    raise exception '39-03: authenticated no debe poder escribir created_product_id';
  end if;
  if (select count(*) from pg_policies where schemaname = 'public') <> 47 then
    raise exception '39-03: se esperaban 47 políticas (39-02 aplicada)';
  end if;
  raise notice '39-03 OK: rama de Mobau en 4 funciones; created_product_id añadido.';
end $$;

COMMIT;
