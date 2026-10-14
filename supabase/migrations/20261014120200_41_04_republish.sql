-- ============================================================
-- PROPUESTA NO EJECUTADA (41-04) — no ejecutar sin aprobación explícita
-- ============================================================
-- 41 · 04 · Propuestas republish, INSTALADAS Y BLOQUEADAS
-- ------------------------------------------------------------
-- Requiere 41-03 (interruptor apagado). Transacción única.
--
-- Por qué un trigger nuevo y no validate_proposal_changes: los triggers de
-- propuestas 10/20/30/40 se ejecutan con el rol del CLIENTE y no pueden leer
-- mobau_private (interruptor) ni retired_at/trashed_at (41-01 no da SELECT de
-- esas columnas). Además fix_proposal_author (10) rechaza hoy cualquier tipo
-- que no sea create/update. Por eso:
--   1. Restricciones: product_proposals_kind_check admite 'republish';
--      product_proposals_kind_product exige product_id también en republish;
--      nueva product_proposals_republish_empty (sin cambios, sin subcategoría
--      nueva y sin precio propuesto).
--   2. Índice product_proposals_one_open_per_product: una abierta por
--      producto entre update y republish.
--   3. mobau_private.product_proposals_lifecycle_gate(), SECURITY DEFINER,
--      sin EXECUTE de cliente (PostgreSQL no comprueba EXECUTE al disparar un
--      trigger), en el trigger NUEVO trg_product_proposals_05_lifecycle_gate,
--      BEFORE INSERT OR UPDATE, el PRIMERO de la tabla:
--        republish + interruptor apagado → 55000 hint feature_disabled, antes
--        de cualquier otro trigger y de cualquier escritura, para crear,
--        editar, cambiar el tipo y enviar (INSERT y UPDATE directos por la RLS
--        de 38-C, también como service_role y postgres). EXCEPCIÓN (plan rev3
--        §3, cierre sin atascos): retirar una republish abierta (→ withdrawn) y,
--        dentro de la decisión de Mobau, rechazarla o pedir cambios desde
--        submitted. Ninguna de esas operaciones toca products;
--        encendido y abierta: el producto debe ser de la empresa (42501
--        product_not_found) y estar 'retired' (55000 legacy_pending_review |
--        republish_requires_retired). Durante la decisión de Mobau no revalida.
--      Propiedades exigidas a la puerta: SECURITY DEFINER, propietario postgres,
--      search_path vacío, todas las referencias calificadas (public.*,
--      mobau_private.*, auth.uid), ACL exacta {postgres=X/postgres} (sin EXECUTE
--      para PUBLIC, anon, authenticated ni service_role). El trigger está en
--      public.product_proposals; la función vive en mobau_private.
--
--      ORDEN REAL DE DISPARO en public.product_proposals tras 41-04 (PostgreSQL
--      dispara los triggers del mismo momento y evento por orden de nombre;
--      los BEFORE ROW, antes de escribir la fila; los AFTER ROW, después):
--        INSERT  BEFORE ROW: 05_lifecycle_gate → 10_author → 30_validate
--                (después: RLS WITH CHECK, restricciones, índices únicos y la fila)
--                AFTER ROW:  90_event_insert (escribe proposal_events) y las FK
--        UPDATE  BEFORE ROW: 05_lifecycle_gate → 20_transition → 30_validate →
--                40_snapshot (WHEN a submitted) → 50_updated_at
--                AFTER ROW:  91_event_status (WHEN cambia status) y las FK
--      La puerta es el PRIMER BEFORE ROW en INSERT y en UPDATE, no tiene WHEN ni
--      lista de columnas, y si falla la fila no se escribe: ningún AFTER se
--      dispara. No hay triggers de sentencia, ni triggers internos BEFORE, ni
--      reglas (pg_rewrite) en la tabla. La validación final lo comprueba con la
--      lista exacta nombre:tipo:función (no basta con el prefijo 05).
--   4. fix_proposal_author (38c-04): acepta 'republish' con las mismas reglas
--      que update (producto existente de la propia empresa).
--   5. snapshot_product_on_submit (41-01): republish guarda la misma copia.
--   6. moderate_product_proposal (40-01): paso 5b (APROBAR una republish con el
--      interruptor apagado → 55000 feature_disabled, antes de cualquier
--      escritura; rechazar y pedir cambios siguen permitidos y no tocan el
--      producto) y rama
--      republish al aprobar: producto aún retirado, sin cambios de producto ni
--      de precio desde el envío (si los hay: snapshot_conflict auditado), y
--      aplica published + retired_* a null + evento de auditoría 'republish'.
--      Las ramas create y update no cambian de comportamiento.
-- validate_proposal_changes, transition_proposal_status y log_proposal_event
-- NO cambian (republish no trae cambios que validar).
--
-- MD5 (prosrc) antes → después:
--   fix_proposal_author        c6a8e41f6e16418e8647b255b3f25ee8 → e940852f2e658861dd0653585ce982ab
--   snapshot_product_on_submit c92b110bbe7d742854379ac64746b484 → 92d5158e8454b17263942346e5487d7c
--   moderate_product_proposal  e814b477d0e078872ad085e00157c2c2 → aa4fac4c25f4634499532824782ee908
--   product_proposals_lifecycle_gate (nueva)                  → b4a6d365255e8498a8838be5e6d5fd27
-- ACL de las tres funciones existentes: sin cambios (create or replace).
-- Rollback: supabase/rollback/20261014120200_41_04_republish.rollback.sql
-- ============================================================

BEGIN;

-- ALTER TABLE e índice sobre product_proposals: ACCESS EXCLUSIVE breve.
-- Si en 5 s no se obtiene (piloto en uso), aborta con 55P03 sin cambios.
set local lock_timeout = '5s';
lock table public.product_proposals in access exclusive mode;

-- ---------- 0. prechecks ----------
DO $$
declare
  pp constant regclass := 'public.product_proposals'::regclass;
begin
  if current_user <> 'postgres' then
    raise exception '41-04: ejecutar como postgres';
  end if;
  if to_regclass('mobau_private.product_lifecycle_settings') is null
     or (select md5(prosrc) from pg_proc where oid = to_regprocedure('mobau_private.product_lifecycle_enabled()'))
        is distinct from '070bbe66427c67b1315c4ea1d0097f85'
     or (select md5(prosrc) from pg_proc where oid = to_regprocedure('mobau_private.log_lifecycle_event(text, text, text, text, text, uuid, text, text, jsonb, text, jsonb)'))
        is distinct from 'a57570b8fb64aed5c05ca39ff3ad5be5' then
    raise exception '41-04: falta 41-03';
  end if;
  if mobau_private.product_lifecycle_enabled() then
    raise exception '41-04: el interruptor debe estar apagado';
  end if;
  if (select md5(prosrc) from pg_proc where oid = 'public.fix_proposal_author()'::regprocedure) is distinct from 'c6a8e41f6e16418e8647b255b3f25ee8'
     or (select md5(prosrc) from pg_proc where oid = 'public.snapshot_product_on_submit()'::regprocedure) is distinct from 'c92b110bbe7d742854379ac64746b484'
     or (select md5(prosrc) from pg_proc where oid = 'public.moderate_product_proposal(uuid, text, text, integer)'::regprocedure) is distinct from 'e814b477d0e078872ad085e00157c2c2' then
    raise exception '41-04: fix_proposal_author, snapshot_product_on_submit o moderate_product_proposal no son las esperadas';
  end if;
  if to_regprocedure('mobau_private.product_proposals_lifecycle_gate()') is not null
     or exists (select 1 from pg_constraint where conrelid = pp and conname = 'product_proposals_republish_empty')
     or exists (select 1 from pg_constraint where conrelid = pp and pg_get_constraintdef(oid) like '%republish%')
     or pg_get_indexdef('public.product_proposals_one_open_per_product'::regclass) like '%republish%' then
    raise exception '41-04: 41-04 ya está (parcialmente) aplicada';
  end if;
  if not exists (select 1 from pg_constraint where conrelid = pp and conname = 'product_proposals_kind_check')
     or not exists (select 1 from pg_constraint where conrelid = pp and conname = 'product_proposals_kind_product') then
    raise exception '41-04: faltan las restricciones de tipo de 38-C 04';
  end if;
  if (select string_agg(t.tgname || ':' || t.tgtype || ':' || n.nspname || '.' || f.proname, ',' order by t.tgname collate "C") from pg_trigger t join pg_proc f on f.oid = t.tgfoid join pg_namespace n on n.oid = f.pronamespace where t.tgrelid = 'public.product_proposals'::regclass and not t.tgisinternal) is distinct from 'trg_product_proposals_10_author:7:public.fix_proposal_author,trg_product_proposals_20_transition:19:public.transition_proposal_status,trg_product_proposals_30_validate:23:public.validate_proposal_changes,trg_product_proposals_40_snapshot:19:public.snapshot_product_on_submit,trg_product_proposals_50_updated_at:19:public.set_updated_at,trg_product_proposals_90_event_insert:5:public.log_proposal_event,trg_product_proposals_91_event_status:17:public.log_proposal_event' then
    raise exception '41-04: los triggers de product_proposals no son los 7 esperados (nombre, tipo y función)';
  end if;
  if exists (select 1 from pg_rewrite where ev_class = pp) then
    raise exception '41-04: product_proposals tiene reglas';
  end if;
  if exists (select 1 from public.product_proposals where status in ('draft', 'submitted', 'changes_requested')) then
    raise exception '41-04: hay propuestas abiertas';
  end if;
  if exists (select 1 from public.mobau_moderation_context) then
    raise exception '41-04: hay una decisión de Mobau en curso';
  end if;
  if (select count(*) from pg_policies where schemaname = 'public') <> 48 then
    raise exception '41-04: se esperaban 48 políticas';
  end if;
  perform set_config('mobau.v3_acl_fix', coalesce((select proacl::text from pg_proc where oid = 'public.fix_proposal_author()'::regprocedure), '-'), true);
  perform set_config('mobau.v3_acl_snap', coalesce((select proacl::text from pg_proc where oid = 'public.snapshot_product_on_submit()'::regprocedure), '-'), true);
  perform set_config('mobau.v3_acl_mod', coalesce((select proacl::text from pg_proc where oid = 'public.moderate_product_proposal(uuid, text, text, integer)'::regprocedure), '-'), true);
end $$;

-- ---------- 1. restricciones ----------
alter table public.product_proposals
  drop constraint product_proposals_kind_check,
  drop constraint product_proposals_kind_product,
  add constraint product_proposals_kind_check
    check (proposal_kind in ('create', 'update', 'republish')),
  add constraint product_proposals_kind_product
    check ((proposal_kind in ('update', 'republish') and product_id is not null)
        or (proposal_kind = 'create' and product_id is null)),
  add constraint product_proposals_republish_empty
    check (proposal_kind <> 'republish'
           or (proposed_changes = '{}'::jsonb and proposed_new_subcategory is null
               and proposed_price_status is null and proposed_price_amount is null));

-- ---------- 2. una abierta por producto (update o republish) ----------
drop index public.product_proposals_one_open_per_product;
create unique index product_proposals_one_open_per_product
  on public.product_proposals (product_id)
  where proposal_kind in ('update', 'republish')
    and status in ('draft', 'submitted', 'changes_requested');

-- ---------- 3. puerta de ciclo de vida (primer trigger) ----------
create function mobau_private.product_proposals_lifecycle_gate()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid;
  v_dist text;
  v_p record;
  v_state text;
begin
  if new.proposal_kind is distinct from 'republish' then
    return new;
  end if;
  -- 1. Interruptor apagado: antes de cualquier otro trigger y de cualquier escritura.
  --    Bloquea crear, editar, cambiar el tipo, enviar y aprobar. Solo se permite
  --    CERRAR una republish ya abierta (plan rev3 §3), sin tocar el producto:
  --      · retirarla (status → withdrawn), por el distribuidor o el sistema;
  --      · rechazarla o pedir cambios desde submitted, solo dentro de la decisión
  --        de Mobau (moderate_product_proposal, contexto mobau_moderating).
  if not mobau_private.product_lifecycle_enabled() then
    if tg_op = 'UPDATE' then
      if old.proposal_kind = 'republish'
         and old.status in ('draft', 'submitted', 'changes_requested')
         and (new.status = 'withdrawn'
              or (old.status = 'submitted' and new.status in ('rejected', 'changes_requested')
                  and (select public.mobau_moderating(new.id)))) then
        return new;
      end if;
    end if;
    raise exception 'La republicación todavía no está disponible.' using errcode = '55000', hint = 'feature_disabled';
  end if;
  -- 2. Decisión de Mobau en curso: la valida moderate_product_proposal.
  if tg_op = 'UPDATE' and (select public.mobau_moderating(new.id)) then
    return new;
  end if;
  -- 3. Solo mientras la propuesta está abierta (retirarla o cerrarla no exige estado).
  if new.status not in ('draft', 'submitted', 'changes_requested') then
    return new;
  end if;
  v_uid := (select auth.uid());
  v_dist := case when v_uid is null then new.distributor_id
                 else mobau_private.resolve_verified_distributor(v_uid) end;
  select p.distributor_id, p.publication_status, p.retired_at, p.trashed_at into v_p
    from public.products p where p.id = new.product_id;
  if not found or v_p.distributor_id is distinct from v_dist then
    raise exception 'No encontramos el producto en tu empresa.' using errcode = '42501', hint = 'product_not_found';
  end if;
  v_state := mobau_private.product_lifecycle_state(v_p.publication_status, v_p.retired_at, v_p.trashed_at);
  if v_state = 'legacy_retired' then
    raise exception 'Este producto está pendiente de revisión por Mobau.' using errcode = '55000', hint = 'legacy_pending_review';
  end if;
  if v_state is distinct from 'retired' then
    raise exception 'Solo se puede solicitar republicar un producto retirado.' using errcode = '55000', hint = 'republish_requires_retired';
  end if;
  return new;
end;
$$;

comment on function mobau_private.product_proposals_lifecycle_gate() is
  '41-04: puerta de las propuestas republish (interruptor, empresa y estado). Trigger 05 de product_proposals. Sin EXECUTE de cliente.';
alter function mobau_private.product_proposals_lifecycle_gate() owner to postgres;
revoke all on function mobau_private.product_proposals_lifecycle_gate() from public, anon, authenticated, service_role;

create trigger trg_product_proposals_05_lifecycle_gate
  before insert or update on public.product_proposals
  for each row execute function mobau_private.product_proposals_lifecycle_gate();

-- ---------- 4. distribuidor, autor y tipo (38c-04 + republish) ----------
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

  if new.proposal_kind is null or new.proposal_kind not in ('create', 'update', 'republish') then
    raise exception 'Tipo de propuesta no válido: %. Usa create (producto nuevo), update (cambio) o republish (republicar un retirado).', new.proposal_kind
      using errcode = '23514';
  end if;

  if new.proposal_kind = 'create' then
    if new.product_id is not null then
      raise exception 'Una propuesta de producto nuevo no puede indicar un producto existente.' using errcode = '23514';
    end if;
  else
    -- update y (41-04) republish: producto existente de la propia empresa.
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

-- ---------- 5. copia del envío (41-01 + republish) ----------
create or replace function public.snapshot_product_on_submit()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_product jsonb;
  v_price jsonb;
begin
  if new.proposal_kind in ('update', 'republish') then
    -- 41-04: republish guarda la misma copia (producto y precio) para
    -- detectar al aprobar cualquier cambio posterior al envío.
    -- 41-01: lista explícita de las 22 columnas de catálogo. Este trigger se
    -- ejecuta con los permisos de quien envía y, desde 41-01, anon y
    -- authenticated solo tienen SELECT por columna en products: to_jsonb(p)
    -- (fila completa) exigiría también las columnas de ciclo de vida. La copia
    -- conserva exactamente las mismas claves que antes de 41-01.
    select to_jsonb(s) into v_product
      from (select p.id, p.name, p.distributor_id, p.brand, p.category_id, p.subcategory, p.use_context, p.space,
                   p.availability, p.description, p.measurements, p.materials, p.finishes, p.lead_time, p.icon,
                   p.technical_sheet_url, p.cad_bim_3d_url, p.image_url, p.created_at, p.status, p.updated_at, p.publication_status
              from public.products p where p.id = new.product_id) s;
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

-- ---------- 6. moderación (40-01 + republish) ----------
-- create or replace conserva propietario y permisos.
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

  -- ===== 5b. 41-04 · republish con el interruptor apagado: aprobar se bloquea antes de
  --      cualquier escritura; rechazar o pedir cambios siguen permitidos (cierran la
  --      propuesta sin tocar el producto, plan rev3 §3) =====
  if v_p.proposal_kind = 'republish' and p_decision = 'approve' and not mobau_private.product_lifecycle_enabled() then
    raise exception 'La republicación todavía no está disponible.' using errcode = '55000', hint = 'feature_disabled';
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
    elsif v_p.proposal_kind = 'republish' then
      -- 41-04 · 9b'. Bloqueo 2/4 · producto: debe seguir retirado (no heredado
      -- ni en papelera), de la misma empresa y sin NINGÚN cambio desde el envío
      -- (las 22 columnas de la copia y la fila de precio completa).
      select * into v_cur from public.products where id = v_p.product_id for update;
      if not found or v_cur.distributor_id <> v_p.distributor_id then
        raise exception 'El producto ya no existe o no es de esta empresa: solicita cambios o rechaza.' using errcode = '55000';
      end if;
      if mobau_private.product_lifecycle_state(v_cur.publication_status, v_cur.retired_at, v_cur.trashed_at) <> 'retired' then
        raise exception 'El producto ya no está retirado: solicita cambios o rechaza.'
          using errcode = '55000', hint = 'republish_requires_retired';
      end if;
      v_snap := v_p.product_snapshot -> 'product';
      if v_snap is null then
        raise exception 'La propuesta no tiene la copia del producto del envío: solicita cambios.' using errcode = '55000';
      end if;
      v_cur_json := pg_catalog.to_jsonb(v_cur)
                    - array['retired_at', 'retired_by', 'retired_reason', 'trashed_at', 'trashed_by', 'trash_from', 'purge_after'];
      for k in select x from pg_catalog.jsonb_object_keys(v_snap || v_cur_json) as x order by x loop
        if (v_snap -> k) is distinct from (v_cur_json -> k) then
          v_conflicts := v_conflicts || pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object(
            'field', k, 'at_submit', v_snap -> k, 'current', v_cur_json -> k, 'proposed', null));
        end if;
      end loop;
      -- Bloqueo 3/4 · precio (si existe): la fila completa, igual que en la copia.
      select * into v_cur_price from public.product_prices where product_id = v_p.product_id for update;
      v_price_found := found;
      if nullif(v_p.product_snapshot -> 'price', 'null'::jsonb)
         is distinct from (case when v_price_found then pg_catalog.to_jsonb(v_cur_price) end) then
        v_conflicts := v_conflicts || pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object(
          'field', 'price',
          'at_submit', nullif(v_p.product_snapshot -> 'price', 'null'::jsonb),
          'current', case when v_price_found then pg_catalog.to_jsonb(v_cur_price) end,
          'proposed', null));
      end if;
      if pg_catalog.jsonb_array_length(v_conflicts) > 0 then
        -- Conflicto de revisión: auditado, sin aplicar nada (como en update).
        insert into public.proposal_events (proposal_id, actor_id, actor_kind, from_status, to_status, version, payload)
        values (v_p.id, v_uid, 'mobau', 'submitted', 'submitted', v_p.version,
                pg_catalog.jsonb_build_object('type', 'snapshot_conflict', 'decision', 'approve', 'conflicts', v_conflicts));
        return pg_catalog.jsonb_build_object('ok', false, 'code', 'snapshot_conflict', 'proposal_id', v_p.id, 'version', v_p.version,
          'conflicts', v_conflicts,
          'message', 'El producto o su precio cambiaron después del envío. No se puede republicar: solicita cambios o rechaza.');
      end if;
      v_product_id := v_p.product_id;
      v_category := v_cur.category_id;
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
                    when v_p.proposal_kind in ('update', 'republish') then v_cur.subcategory end;
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
      'publication_status', case when v_p.proposal_kind in ('create', 'republish') then 'published' end,
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
    elsif v_p.proposal_kind = 'republish' then
      -- 41-04: republicar = volver a publicado y limpiar la retirada en la misma
      -- sentencia (lo exige products_lifecycle_published_clean). Auditoría A.
      update public.products
         set publication_status = 'published', retired_at = null, retired_by = null, retired_reason = null
       where id = v_product_id;
      perform mobau_private.log_lifecycle_event(v_product_id, v_p.distributor_id, 'republish', 'retired', 'published',
                                                v_uid, 'mobau', v_msg);
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

-- ---------- 7. validación final ----------
DO $$
declare
  pp constant regclass := 'public.product_proposals'::regclass;
  f_gate constant regprocedure := 'mobau_private.product_proposals_lifecycle_gate()'::regprocedure;
  v_state text;
  v_hint text;
begin
  if (select md5(prosrc) from pg_proc where oid = 'public.fix_proposal_author()'::regprocedure) is distinct from 'e940852f2e658861dd0653585ce982ab'
     or (select md5(prosrc) from pg_proc where oid = 'public.snapshot_product_on_submit()'::regprocedure) is distinct from '92d5158e8454b17263942346e5487d7c'
     or (select md5(prosrc) from pg_proc where oid = 'public.moderate_product_proposal(uuid, text, text, integer)'::regprocedure) is distinct from 'aa4fac4c25f4634499532824782ee908'
     or (select md5(prosrc) from pg_proc where oid = f_gate) is distinct from 'b4a6d365255e8498a8838be5e6d5fd27' then
    raise exception '41-04: algún cuerpo de función no es el esperado';
  end if;
  if coalesce((select proacl::text from pg_proc where oid = 'public.fix_proposal_author()'::regprocedure), '-') is distinct from current_setting('mobau.v3_acl_fix')
     or coalesce((select proacl::text from pg_proc where oid = 'public.snapshot_product_on_submit()'::regprocedure), '-') is distinct from current_setting('mobau.v3_acl_snap')
     or coalesce((select proacl::text from pg_proc where oid = 'public.moderate_product_proposal(uuid, text, text, integer)'::regprocedure), '-') is distinct from current_setting('mobau.v3_acl_mod') then
    raise exception '41-04: ha cambiado la ACL de una función existente';
  end if;
  if not (select prosecdef from pg_proc where oid = f_gate)
     or not (select proconfig @> array['search_path=""'] from pg_proc where oid = f_gate)
     or (select proowner from pg_proc where oid = f_gate) <> 'postgres'::regrole
     or (select proacl::text from pg_proc where oid = f_gate) is distinct from '{postgres=X/postgres}'
     or has_function_privilege('anon', f_gate, 'EXECUTE') or has_function_privilege('authenticated', f_gate, 'EXECUTE')
     or has_function_privilege('service_role', f_gate, 'EXECUTE') then
    raise exception '41-04: la puerta tiene propiedades o permisos inesperados';
  end if;
  -- Lista exacta de los 8 triggers (nombre:tipo:función), en orden de disparo.
  if (select string_agg(t.tgname || ':' || t.tgtype || ':' || n.nspname || '.' || f.proname, ',' order by t.tgname collate "C") from pg_trigger t join pg_proc f on f.oid = t.tgfoid join pg_namespace n on n.oid = f.pronamespace where t.tgrelid = 'public.product_proposals'::regclass and not t.tgisinternal) is distinct from 'trg_product_proposals_05_lifecycle_gate:23:mobau_private.product_proposals_lifecycle_gate,trg_product_proposals_10_author:7:public.fix_proposal_author,trg_product_proposals_20_transition:19:public.transition_proposal_status,trg_product_proposals_30_validate:23:public.validate_proposal_changes,trg_product_proposals_40_snapshot:19:public.snapshot_product_on_submit,trg_product_proposals_50_updated_at:19:public.set_updated_at,trg_product_proposals_90_event_insert:5:public.log_proposal_event,trg_product_proposals_91_event_status:17:public.log_proposal_event' then
    raise exception '41-04: los triggers de product_proposals no son los 8 esperados (nombre, tipo y función)';
  end if;
  -- La puerta es el PRIMER BEFORE ROW que se dispara en INSERT y en UPDATE (orden por nombre, bytes).
  if (select t.tgname from pg_trigger t where t.tgrelid = pp and (t.tgtype & 3) = 3 and (t.tgtype & 4) = 4 order by t.tgname collate "C" limit 1)
       is distinct from 'trg_product_proposals_05_lifecycle_gate'
     or (select t.tgname from pg_trigger t where t.tgrelid = pp and (t.tgtype & 3) = 3 and (t.tgtype & 16) = 16 order by t.tgname collate "C" limit 1)
       is distinct from 'trg_product_proposals_05_lifecycle_gate' then
    raise exception '41-04: la puerta no es el primer trigger BEFORE ROW en INSERT o en UPDATE';
  end if;
  -- BEFORE ROW INSERT OR UPDATE, sin WHEN, sin lista de columnas, habilitada, en public.product_proposals, con la función privada.
  if not exists (select 1 from pg_trigger t where t.tgrelid = pp and t.tgname = 'trg_product_proposals_05_lifecycle_gate'
                    and t.tgtype = 23 and t.tgqual is null and cardinality(t.tgattr::int2[]) = 0 and t.tgenabled = 'O' and t.tgfoid = f_gate::oid)
     or (select pronamespace from pg_proc where oid = f_gate) <> 'mobau_private'::regnamespace then
    raise exception '41-04: la puerta no tiene la forma exigida';
  end if;
  -- Ningún trigger interno BEFORE (las FK son AFTER) y ninguna regla sobre la tabla.
  if exists (select 1 from pg_trigger where tgrelid = pp and tgisinternal and (tgtype & 2) = 2)
     or exists (select 1 from pg_rewrite where ev_class = pp) then
    raise exception '41-04: hay triggers internos BEFORE o reglas en product_proposals';
  end if;
  if (select count(*) from pg_constraint where conrelid = pp and conname in ('product_proposals_kind_check', 'product_proposals_kind_product', 'product_proposals_republish_empty')) <> 3
     or pg_get_constraintdef((select oid from pg_constraint where conrelid = pp and conname = 'product_proposals_kind_check')) not like '%republish%'
     or pg_get_indexdef('public.product_proposals_one_open_per_product'::regclass) not like '%republish%' then
    raise exception '41-04: restricciones o índice inesperados';
  end if;
  if (select count(*) from pg_proc where pronamespace = 'mobau_private'::regnamespace) <> 7 then
    raise exception '41-04: mobau_private debe tener 7 funciones';
  end if;
  -- Autocomprobación: con el interruptor apagado, una republish se rechaza con
  -- 55000 feature_disabled ANTES que cualquier otro trigger o restricción (el
  -- producto ni siquiera existe). La subtransacción no deja nada.
  begin
    insert into public.product_proposals (proposal_kind, product_id, distributor_id, status, proposed_changes)
    values ('republish', '__41_04_autocomprobacion__', '__41_04__', 'draft', '{}'::jsonb);
    raise exception '41-04: la republish NO se bloqueó con el interruptor apagado' using errcode = 'MB041';
  exception when sqlstate '55000' then
    get stacked diagnostics v_state = returned_sqlstate, v_hint = pg_exception_hint;
    if v_hint is distinct from 'feature_disabled' then
      raise exception '41-04: la republish se rechazó con un motivo inesperado (%: %)', v_state, v_hint;
    end if;
  end;
  if mobau_private.product_lifecycle_enabled()
     or exists (select 1 from public.product_proposals where proposal_kind = 'republish')
     or exists (select 1 from mobau_private.product_lifecycle_events) then
    raise exception '41-04: el interruptor debe seguir apagado, sin republish ni eventos';
  end if;
  if (select count(*) from pg_policies where schemaname = 'public') <> 48
     or (select count(*) from public.mobau_moderation_context) <> 0 then
    raise exception '41-04: políticas o contexto inesperados';
  end if;
  raise notice '41-04 OK: republish instalada y bloqueada (55000 feature_disabled).';
end $$;

COMMIT;
