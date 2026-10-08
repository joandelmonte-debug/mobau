-- ============================================================
-- PROPUESTA NO EJECUTADA (40-01) — no ejecutar sin aprobación explícita
-- ============================================================
-- 40 · 01 · Aprobar una propuesta create publica el producto
-- ------------------------------------------------------------
-- Decisión de producto (2026-10-08, tras la prueba real 40-A): al aprobar
-- una propuesta create, el producto nuevo se crea YA PUBLICADO:
--   products.publication_status = 'published'
--   products.status             = 'active' (lo fija el trigger de espejo
--                                 trg_products_sync_legacy_status, 38-B)
--   product_proposals.status    = 'approved' (sin cambios)
-- Hasta ahora quedaba en 'draft' / 'archived' y no existía ninguna vía en la
-- aplicación para publicarlo (solo SQL manual).
--
-- Único objeto que cambia: public.moderate_product_proposal (39-04), con
-- CREATE OR REPLACE (misma firma, mismo propietario, mismos permisos). El
-- cuerpo es idéntico al aplicado salvo tres líneas:
--   1. INSERT del producto nuevo: 'draft' → 'published'.
--   2. Comentario de ese INSERT.
--   3. Evento y resultado de un create aprobado: nueva clave
--      publication_status = 'published' (jsonb_strip_nulls la omite en
--      update, rechazo y solicitud de cambios).
-- Sin cambios: autorización (admin activo con aal2), autoaprobación,
-- versión, empresa verificada, snapshot, categoría y subcategoría, precio
-- (solo si se propuso, tal cual; quote_required sin importe sigue siendo
-- quote_required sin importe), atomicidad, contexto y eventos. Las
-- propuestas update NO cambian la publicación del producto.
--
-- Prechecks: la función viva debe ser exactamente la de 39-04
-- (md5(prosrc) = a7b6b6405b93207fc9535fb14eaa7e02) y el contexto debe estar vacío.
-- Validación final: md5(prosrc) nuevo = e814b477d0e078872ad085e00157c2c2, SECURITY DEFINER,
-- search_path vacío, propietario postgres, EXECUTE solo authenticated,
-- una sola firma, contexto vacío, 48 políticas.
--
-- Efecto en la huella (39_huella.sql): cambia solo el md5 de
-- moderate_product_proposal en «39:funciones nuevas y reemplazadas» y
-- «migraciones registradas» (+1). Nada más.
--
-- Rollback: supabase/rollback/<versión>_40_01_approve_create_publishes.rollback.sql
-- Ejecutar completo (BEGIN … COMMIT).
-- ============================================================

BEGIN;

-- ---------- prechecks ----------
DO $$
begin
  if to_regprocedure('public.moderate_product_proposal(uuid, text, text, integer)') is null then
    raise exception '40-01: falta 39-04';
  end if;
  if (select md5(prosrc) from pg_proc where oid = 'public.moderate_product_proposal(uuid, text, text, integer)'::regprocedure) <> 'a7b6b6405b93207fc9535fb14eaa7e02' then
    raise exception '40-01: moderate_product_proposal no es la versión de 39-04';
  end if;
  if (select count(*) from public.mobau_moderation_context) <> 0 then
    raise exception '40-01: hay una decisión de Mobau en curso (contexto no vacío)';
  end if;
end $$;

create or replace function public.moderate_product_proposal(
  p_proposal_id      uuid,
  p_decision         text,
  p_message          text,
  p_expected_version integer
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  -- Mismos campos que admite validate_proposal_changes (38-C).
  c_allowed constant text[] := array['name', 'description', 'category_id', 'subcategory', 'image_url', 'availability',
                                     'lead_time', 'brand', 'measurements', 'materials', 'finishes',
                                     'technical_sheet_url', 'cad_bim_3d_url', 'use_context', 'space'];
  v_uid uuid := (select auth.uid());
  v_msg text := nullif(pg_catalog.btrim(coalesce(p_message, '')), '');
  v_p public.product_proposals%rowtype;
  v_changes jsonb := '{}'::jsonb;
  v_change_keys text[] := '{}'::text[];
  v_new_sub text;
  v_cur public.products%rowtype;
  v_cur_json jsonb;
  v_snap jsonb;
  v_cur_price public.product_prices%rowtype;
  v_has_price boolean := false;
  v_price_found boolean;
  v_keys text[];
  k text;
  v_conflicts jsonb := '[]'::jsonb;
  v_category text;
  v_sub text;
  v_sub_result text;
  v_cat_subs text[];
  v_set text[] := '{}'::text[];
  v_product_id text;
  v_created_id text;
  v_event jsonb;
  v_norm_new text;
  v_result text;
begin
  -- ===== 1. Sesión =====
  if v_uid is null then
    raise exception 'No tienes permiso para moderar propuestas.' using errcode = '42501', hint = 'not_authenticated';
  end if;

  -- ===== 2. Admin activo con segundo factor (aal2) =====
  if not (select public.is_mobau_admin()) then
    if (select (public.mobau_admin_session() ->> 'admin')::boolean) then
      raise exception 'Verifica tu sesión con el segundo factor (MFA) para moderar propuestas.'
        using errcode = '42501', hint = 'aal2_required';
    end if;
    raise exception 'No tienes permiso para moderar propuestas.' using errcode = '42501', hint = 'not_admin';
  end if;

  -- ===== 3. Parámetros (solo de decisión) =====
  if p_decision is null or p_decision not in ('approve', 'request_changes', 'reject') then
    raise exception 'Decisión no válida: usa approve, request_changes o reject.' using errcode = '22023';
  end if;
  if p_expected_version is null or p_expected_version < 1 then
    raise exception 'Falta la versión de la propuesta que estás revisando.' using errcode = '22023';
  end if;
  if v_msg is not null and pg_catalog.char_length(v_msg) > 2000 then
    raise exception 'El mensaje supera los 2000 caracteres.' using errcode = '22023';
  end if;
  if p_decision in ('request_changes', 'reject') and v_msg is null then
    raise exception 'Indica al distribuidor el motivo y cómo solucionarlo.' using errcode = '22023';
  end if;

  -- ===== 4. Bloqueo 1/4 · propuesta =====
  select * into v_p from public.product_proposals where id = p_proposal_id for update;
  if not found then
    raise exception 'No encontramos la propuesta.' using errcode = 'P0002';
  end if;

  -- ===== 5. En revisión =====
  if v_p.status <> 'submitted' then
    raise exception 'La propuesta ya no está en revisión (estado: %).', v_p.status using errcode = '55000';
  end if;

  -- ===== 6. Autoaprobación: nunca sobre la propia empresa ni sobre una
  --      propuesta propia (relación real: distributor_profiles y autoría;
  --      no profiles.role ni metadatos). Antes de la versión, para que un
  --      intento bloqueado no deje ningún evento. =====
  if v_p.author_id = v_uid
     or exists (select 1 from public.distributor_profiles dp
                 where dp.user_id = v_uid and dp.distributor_id = v_p.distributor_id) then
    raise exception 'No puedes moderar propuestas de tu propia empresa.'
      using errcode = '42501', hint = 'self_moderation_forbidden';
  end if;

  -- ===== 7. Versión: conflicto de revisión, auditado, sin aplicar nada =====
  if v_p.version <> p_expected_version then
    insert into public.proposal_events (proposal_id, actor_id, actor_kind, from_status, to_status, version, payload)
    values (v_p.id, v_uid, 'mobau', 'submitted', 'submitted', v_p.version,
            pg_catalog.jsonb_build_object('type', 'version_conflict', 'decision', p_decision,
                                          'expected_version', p_expected_version, 'current_version', v_p.version));
    return pg_catalog.jsonb_build_object('ok', false, 'code', 'version_conflict', 'proposal_id', v_p.id,
      'expected_version', p_expected_version, 'current_version', v_p.version,
      'message', 'La propuesta cambió desde que la abriste. Vuelve a cargarla antes de decidir.');
  end if;

  if p_decision = 'approve' then
    -- ===== 8. Empresa todavía verificada (solo al aprobar) =====
    if not exists (select 1 from public.distributor_profiles dp
                    where dp.distributor_id = v_p.distributor_id and dp.verification_status = 'verified') then
      raise exception 'La empresa de esta propuesta ya no está verificada: solicita cambios o rechaza.' using errcode = '55000';
    end if;

    -- ===== 9. Comprobaciones de producto, snapshot, categoría,
    --      subcategoría y precio. Nada se escribe aquí salvo el evento de
    --      un conflicto con el snapshot. =====
    v_changes := v_p.proposed_changes;
    v_new_sub := v_p.proposed_new_subcategory;
    v_has_price := v_p.proposed_price_status is not null;
    v_change_keys := array(select x from pg_catalog.jsonb_object_keys(v_changes) as x order by x);

    -- 9a. Defensivas (ya las garantizan el trigger 30 y las restricciones de 38-C).
    if not (v_change_keys <@ c_allowed) then
      raise exception 'La propuesta contiene un campo no permitido: solicita cambios.' using errcode = '55000';
    end if;
    if v_new_sub is not null and v_changes ? 'subcategory' then
      raise exception 'La propuesta trae subcategoría de la lista y subcategoría nueva: solicita cambios.' using errcode = '55000';
    end if;
    if (v_p.proposed_price_amount is not null and not v_has_price)
       or (v_p.proposed_price_status = 'published' and v_p.proposed_price_amount is null)
       or v_p.proposed_price_amount < 0 then
      raise exception 'El precio propuesto no es válido: solicita cambios.' using errcode = '55000';
    end if;

    if v_p.proposal_kind = 'update' then
      -- 9b. Bloqueo 2/4 · producto, y comparación selectiva con el snapshot.
      select * into v_cur from public.products where id = v_p.product_id for update;
      if not found or v_cur.distributor_id <> v_p.distributor_id then
        raise exception 'El producto ya no existe o no es de esta empresa: solicita cambios o rechaza.' using errcode = '55000';
      end if;
      v_snap := v_p.product_snapshot -> 'product';
      if v_snap is null then
        raise exception 'La propuesta no tiene la copia del producto del envío: solicita cambios.' using errcode = '55000';
      end if;
      v_cur_json := pg_catalog.to_jsonb(v_cur);

      v_keys := v_change_keys;
      if v_new_sub is not null then
        v_keys := v_keys || array['subcategory'];
      end if;
      foreach k in array v_keys loop
        if (v_snap -> k) is distinct from (v_cur_json -> k) then
          v_conflicts := v_conflicts || pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object(
            'field', k,
            'at_submit', v_snap -> k,
            'current', v_cur_json -> k,
            'proposed', case when k = 'subcategory' and v_new_sub is not null then pg_catalog.to_jsonb(v_new_sub) else v_changes -> k end));
        end if;
      end loop;

      if v_has_price then
        -- Bloqueo 3/4 · precio (si existe).
        select * into v_cur_price from public.product_prices where product_id = v_p.product_id for update;
        v_price_found := found;
        if (v_p.product_snapshot -> 'price' ->> 'price_status') is distinct from (case when v_price_found then v_cur_price.price_status end)
           or (v_p.product_snapshot -> 'price' ->> 'price_amount')::numeric is distinct from (case when v_price_found then v_cur_price.price_amount end) then
          v_conflicts := v_conflicts || pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object(
            'field', 'price',
            'at_submit', pg_catalog.jsonb_build_object('price_status', v_p.product_snapshot -> 'price' -> 'price_status',
                                                       'price_amount', v_p.product_snapshot -> 'price' -> 'price_amount'),
            'current', case when v_price_found then pg_catalog.jsonb_build_object('price_status', v_cur_price.price_status,
                                                                                  'price_amount', v_cur_price.price_amount) end,
            'proposed', pg_catalog.jsonb_build_object('price_status', v_p.proposed_price_status,
                                                      'price_amount', v_p.proposed_price_amount)));
        end if;
      end if;

      if pg_catalog.jsonb_array_length(v_conflicts) > 0 then
        -- Conflicto de revisión: auditado, sin aplicar nada.
        insert into public.proposal_events (proposal_id, actor_id, actor_kind, from_status, to_status, version, payload)
        values (v_p.id, v_uid, 'mobau', 'submitted', 'submitted', v_p.version,
                pg_catalog.jsonb_build_object('type', 'snapshot_conflict', 'decision', 'approve', 'conflicts', v_conflicts));
        return pg_catalog.jsonb_build_object('ok', false, 'code', 'snapshot_conflict', 'proposal_id', v_p.id, 'version', v_p.version,
          'conflicts', v_conflicts,
          'message', 'Algún campo propuesto cambió en el catálogo después del envío. No se puede aprobar: solicita cambios o rechaza.');
      end if;

      v_product_id := v_p.product_id;
      v_category := coalesce(v_changes ->> 'category_id', v_cur.category_id);
    else
      v_category := v_changes ->> 'category_id';
    end if;

    -- 9c. Bloqueo 4/4 · categoría (FOR UPDATE si se añadirá una
    --     subcategoría, FOR SHARE si solo se comprueba). Se decide aquí si
    --     la subcategoría nueva se añade o ya existe; se escribe en el paso 11.
    if v_new_sub is not null then
      select c.subcategories into v_cat_subs from public.categories c where c.id = v_category for update;
    else
      select c.subcategories into v_cat_subs from public.categories c where c.id = v_category for share;
    end if;
    if v_category is null or not found then
      raise exception 'La categoría de la propuesta ya no existe: solicita cambios o rechaza.' using errcode = '55000';
    end if;
    if v_new_sub is not null then
      if v_new_sub <> pg_catalog.btrim(v_new_sub) or v_new_sub ~ '\s{2,}' then
        raise exception 'La subcategoría propuesta tiene espacios sobrantes: solicita cambios al distribuidor.' using errcode = '55000';
      end if;
      v_norm_new := pg_catalog.btrim(pg_catalog.regexp_replace(pg_catalog.lower(v_new_sub), '\s+', ' ', 'g'));
      select s into v_sub from pg_catalog.unnest(coalesce(v_cat_subs, '{}'::text[])) as s
       where pg_catalog.btrim(pg_catalog.regexp_replace(pg_catalog.lower(s), '\s+', ' ', 'g')) = v_norm_new
       limit 1;
      if v_sub is null then
        v_sub := v_new_sub;
        v_sub_result := 'added';
      else
        v_sub_result := 'existing';
      end if;
    else
      v_sub := case when v_changes ? 'subcategory' then v_changes ->> 'subcategory'
                    when v_p.proposal_kind = 'update' then v_cur.subcategory end;
      if v_sub is not null and not (v_sub = any (coalesce(v_cat_subs, '{}'::text[]))) then
        raise exception 'La subcategoría "%" ya no existe en la categoría: solicita cambios.', v_sub using errcode = '55000';
      end if;
    end if;

    -- 9d. Id del producto nuevo (regla existente: <distribuidor>-<8 hex>).
    if v_p.proposal_kind = 'create' then
      loop
        v_created_id := v_p.distributor_id || '-' || pg_catalog.substr(pg_catalog.replace(pg_catalog.gen_random_uuid()::text, '-', ''), 1, 8);
        exit when not exists (select 1 from public.products where id = v_created_id);
      end loop;
      v_product_id := v_created_id;
    end if;

    v_result := 'approved';
    v_event := pg_catalog.jsonb_strip_nulls(pg_catalog.jsonb_build_object(
      'decision', 'approve',
      'message', v_msg,
      'applied_fields', pg_catalog.to_jsonb(v_change_keys),
      'price_applied', v_has_price,
      'price', case when v_has_price then pg_catalog.jsonb_build_object('price_status', v_p.proposed_price_status,
                                                                        'price_amount', v_p.proposed_price_amount) end,
      'product_id', v_product_id,
      'created_product_id', v_created_id,
      'publication_status', case when v_p.proposal_kind = 'create' then 'published' end,
      'subcategory', case when v_sub_result is not null then
                       pg_catalog.jsonb_build_object('proposed', v_new_sub, 'value', v_sub, 'category_id', v_category, 'result', v_sub_result) end));
  else
    v_result := case p_decision when 'reject' then 'rejected' else 'changes_requested' end;
    v_event := pg_catalog.jsonb_build_object('decision', p_decision);
  end if;

  -- ===== 10. Contexto privado de esta decisión: ligado a esta transacción
  --      (txid), a esta propuesta y a este admin. Los triggers reconocen a
  --      Mobau solo con él. El PK (txid) impide un segundo contexto
  --      simultáneo en la misma transacción. =====
  insert into public.mobau_moderation_context (txid, proposal_id, admin_id, event)
  values (pg_catalog.txid_current(), v_p.id, v_uid, v_event);

  -- ===== 11. Aplicar la decisión =====
  if p_decision = 'approve' then
    if v_sub_result = 'added' then
      update public.categories
         set subcategories = pg_catalog.array_append(coalesce(subcategories, '{}'::text[]), v_sub)
       where id = v_category;
    end if;

    if v_p.proposal_kind = 'update' then
      -- Solo las columnas propuestas (nombres de la lista cerrada c_allowed;
      -- valores como parámetros). Si solo hay precio, el producto no se toca.
      foreach k in array v_change_keys loop
        v_set := v_set || pg_catalog.format('%I = $1 ->> %L', k, k);
      end loop;
      if v_new_sub is not null then
        v_set := v_set || 'subcategory = $2'::text;
      end if;
      if pg_catalog.cardinality(v_set) > 0 then
        execute pg_catalog.format('update public.products set %s where id = $3', pg_catalog.array_to_string(v_set, ', '))
          using v_changes, v_sub, v_product_id;
      end if;
    else
      -- 40-01: producto nuevo publicado al aprobar (publication_status =
      -- 'published'; el trigger de 38-B fija status = 'active').
      insert into public.products (id, distributor_id, name, description, category_id, subcategory, image_url, availability,
                                   lead_time, brand, measurements, materials, finishes, technical_sheet_url, cad_bim_3d_url,
                                   use_context, space, publication_status)
      values (v_created_id, v_p.distributor_id, v_changes ->> 'name', v_changes ->> 'description', v_category, v_sub,
              v_changes ->> 'image_url', v_changes ->> 'availability', v_changes ->> 'lead_time', v_changes ->> 'brand',
              v_changes ->> 'measurements', v_changes ->> 'materials', v_changes ->> 'finishes',
              v_changes ->> 'technical_sheet_url', v_changes ->> 'cad_bim_3d_url', v_changes ->> 'use_context',
              v_changes ->> 'space', 'published');
    end if;

    -- Precio: solo si se propuso; estado e importe tal cual (un estado no
    -- publicado puede llevar importe o no). currency 'USD' (restricción
    -- product_prices_currency_usd) e includes_itbis true (restricción
    -- product_prices_published_includes_itbis para publicados; la propuesta
    -- no tiene campo de ITBIS). Una fila por producto (UNIQUE product_id);
    -- el trigger de precios marca price_source = 'distributor'. No cambia
    -- price_status a published si no se propuso así.
    if v_has_price then
      insert into public.product_prices (product_id, price_status, price_amount, currency, includes_itbis)
      values (v_product_id, v_p.proposed_price_status, v_p.proposed_price_amount, 'USD', true)
      on conflict (product_id) do update
        set price_status = excluded.price_status,
            price_amount = excluded.price_amount,
            includes_itbis = true;
    end if;

    update public.product_proposals
       set status = 'approved',
           rejection_reason = null,
           reviewed_at = pg_catalog.now(),
           reviewed_by = v_uid,
           created_product_id = v_created_id
     where id = v_p.id;
  else
    update public.product_proposals
       set status = v_result,
           rejection_reason = v_msg,
           reviewed_at = pg_catalog.now(),
           reviewed_by = v_uid
     where id = v_p.id;
  end if;

  -- ===== 12. Borrar el contexto (si algo falla antes, se revierte con todo) =====
  delete from public.mobau_moderation_context where txid = pg_catalog.txid_current();

  -- ===== 13. Resultado =====
  if p_decision = 'approve' then
    return pg_catalog.jsonb_build_object('ok', true, 'result', 'approved')
           || (v_event - 'decision')
           || pg_catalog.jsonb_build_object('proposal_id', v_p.id, 'version', v_p.version);
  end if;
  return pg_catalog.jsonb_build_object('ok', true, 'result', v_result, 'proposal_id', v_p.id, 'version', v_p.version);
end;
$$;

comment on function public.moderate_product_proposal(uuid, text, text, integer) is
  '39/40-01: única vía de escritura de Mobau sobre propuestas. Solo datos de decisión; aplica la propuesta exacta. Al aprobar un create, el producto nuevo queda publicado. Exige admin activo con aal2.';

revoke all on function public.moderate_product_proposal(uuid, text, text, integer) from public, anon;
grant execute on function public.moderate_product_proposal(uuid, text, text, integer) to authenticated;

-- ---------- validación final ----------
DO $$
declare
  f constant regprocedure := 'public.moderate_product_proposal(uuid, text, text, integer)'::regprocedure;
begin
  if (select md5(prosrc) from pg_proc where oid = f) <> 'e814b477d0e078872ad085e00157c2c2' then
    raise exception '40-01: el cuerpo de la función no es el esperado';
  end if;
  if not (select prosecdef from pg_proc where oid = f)
     or not exists (select 1 from pg_proc where oid = f and proconfig @> array['search_path=""'])
     or (select proowner from pg_proc where oid = f) <> 'postgres'::regrole then
    raise exception '40-01: la función debe ser SECURITY DEFINER, con search_path vacío y propietario postgres';
  end if;
  if has_function_privilege('anon', f, 'EXECUTE') or not has_function_privilege('authenticated', f, 'EXECUTE')
     or exists (select 1 from aclexplode((select proacl from pg_proc where oid = f)) a where a.grantee = 0) then
    raise exception '40-01: permisos de ejecución inesperados';
  end if;
  if (select count(*) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'moderate_product_proposal') <> 1
     or (select pronargs from pg_proc where oid = f) <> 4 then
    raise exception '40-01: debe existir una sola firma, con 4 parámetros';
  end if;
  if (select count(*) from public.mobau_moderation_context) <> 0 then
    raise exception '40-01: mobau_moderation_context debe estar vacía';
  end if;
  if (select count(*) from pg_policies where schemaname = 'public') <> 48 then
    raise exception '40-01: se esperaban 48 políticas';
  end if;
  raise notice '40-01 OK: aprobar un create publica el producto.';
end $$;

COMMIT;
