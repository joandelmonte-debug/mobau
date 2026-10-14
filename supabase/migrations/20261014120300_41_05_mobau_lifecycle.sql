-- ============================================================
-- PROPUESTA NO EJECUTADA (41-05) — no ejecutar sin aprobación explícita
-- ============================================================
-- 41 · 05 · Ciclo de vida de Mobau, INSTALADO Y APAGADO
-- ------------------------------------------------------------
-- Requiere 41-04. Transacción única. No bloquea tablas: solo crea funciones.
--
-- Auxiliares (mobau_private, sin EXECUTE de cliente):
--   assert_mobau_admin()               uid + admin activo + aal2 (como 39-04)
--   product_reference_counts(text)     solo recuentos (sin ids ni datos de clientes)
-- Funciones de entrada (public, SECURITY DEFINER, search_path vacío,
-- propietario postgres, ACL exacta {postgres=X/postgres}: SIN EXECUTE para
-- PUBLIC, anon, authenticated ni service_role hasta 41-06):
--   mobau_product_lifecycle(text, text, text, timestamptz)   T2, T6, T8 (retire | trash | restore)
--   mobau_purge_product(text, text, text, boolean, timestamptz) T9, T10
--   mobau_product_references(text)                            recuentos
--   mobau_product_lifecycle_view(text)                        estado, actores, eventos, bloqueos
--
-- Orden de validación (ninguna escritura antes de que pasen todas):
--   1 interruptor apagado → 55000 feature_disabled
--   2 sesión / admin / aal2 → 42501 not_authenticated | aal2_required | not_admin
--   3 parámetros → 22023 invalid_parameter | invalid_action | invalid_reason | missing_version | confirm_mismatch
--   4 producto FOR UPDATE → P0002 product_not_found
--   5 autoaprobación (empresa del admin) → 42501 self_moderation_forbidden
--   6 versión → 40001 version_conflict
--   7 estado y bloqueos → 55000 legacy_pending_review | in_review | invalid_state | open_proposal
--                          | purge_not_due | purge_blocked_references | purge_unknown_reference
--   8 escritura + auditoría A en la misma transacción
-- La purga borra, en este orden: eventos de propuestas cerradas → propuestas
-- cerradas → precio → producto; recuentos exactos y SHA-256 del conjunto
-- borrado en la auditoría (sin contenido, precio, notas ni payloads).
-- Rollback: supabase/rollback/20261014120300_41_05_mobau_lifecycle.rollback.sql
-- ============================================================

BEGIN;

set local lock_timeout = '5s';

-- ---------- 0. prechecks ----------
DO $$
begin
  if current_user <> 'postgres' then
    raise exception '41-05: ejecutar como postgres';
  end if;
  if to_regprocedure('mobau_private.product_proposals_lifecycle_gate()') is null
     or (select md5(prosrc) from pg_proc where oid = 'public.moderate_product_proposal(uuid, text, text, integer)'::regprocedure)
        is distinct from 'aa4fac4c25f4634499532824782ee908' then
    raise exception '41-05: falta 41-04';
  end if;
  if mobau_private.product_lifecycle_enabled() then
    raise exception '41-05: el interruptor debe estar apagado';
  end if;
  if to_regprocedure('public.mobau_product_lifecycle(text, text, text, timestamp with time zone)') is not null
     or to_regprocedure('public.mobau_purge_product(text, text, text, boolean, timestamp with time zone)') is not null
     or to_regprocedure('public.mobau_product_references(text)') is not null
     or to_regprocedure('public.mobau_product_lifecycle_view(text)') is not null
     or to_regprocedure('mobau_private.assert_mobau_admin()') is not null
     or to_regprocedure('mobau_private.product_reference_counts(text)') is not null then
    raise exception '41-05: algún objeto de 41-05 ya existe';
  end if;
  if to_regprocedure('public.is_mobau_admin()') is null or to_regprocedure('public.mobau_admin_session()') is null then
    raise exception '41-05: faltan is_mobau_admin() o mobau_admin_session() (39-01)';
  end if;
  if exists (select 1 from mobau_private.product_lifecycle_events) then
    raise exception '41-05: la auditoría de ciclo de vida no está vacía';
  end if;
  if (select count(*) from pg_policies where schemaname = 'public') <> 48 then
    raise exception '41-05: se esperaban 48 políticas';
  end if;
end $$;

-- ---------- 1. auxiliares ----------
create function mobau_private.assert_mobau_admin()
returns uuid
language plpgsql
stable
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
begin
  -- 41-05: mismas reglas y mensajes que moderate_product_proposal (39-04).
  if v_uid is null then
    raise exception 'No tienes permiso para gestionar el ciclo de vida.' using errcode = '42501', hint = 'not_authenticated';
  end if;
  if not (select public.is_mobau_admin()) then
    if (select (public.mobau_admin_session() ->> 'admin')::boolean) then
      raise exception 'Verifica tu sesión con el segundo factor (MFA) para gestionar el ciclo de vida.'
        using errcode = '42501', hint = 'aal2_required';
    end if;
    raise exception 'No tienes permiso para gestionar el ciclo de vida.' using errcode = '42501', hint = 'not_admin';
  end if;
  return v_uid;
end;
$$;

create function mobau_private.product_reference_counts(p_product_id text)
returns jsonb
language plpgsql
stable
set search_path = ''
as $$
declare
  v_fk record;
  v_n bigint;
  v_other bigint := 0;
  v_unknown text[] := '{}'::text[];
begin
  -- 41-05: solo recuentos. Proyectos: cualquier línea bloquea la purga (A6).
  -- Claves ajenas a products(id): las conocidas se cuentan aparte; cualquier
  -- otra se cuenta como referencia; una clave compuesta se marca como desconocida.
  for v_fk in
    select c.conrelid::regclass as tbl, c.conkey, a.attname
      from pg_catalog.pg_constraint c
      left join pg_catalog.pg_attribute a on a.attrelid = c.conrelid and a.attnum = c.conkey[1]
     where c.contype = 'f' and c.confrelid = 'public.products'::regclass
  loop
    if pg_catalog.cardinality(v_fk.conkey) <> 1 then
      v_unknown := v_unknown || v_fk.tbl::text;
    elsif v_fk.tbl not in ('public.product_prices'::regclass, 'public.product_proposals'::regclass, 'public.project_products'::regclass) then
      execute pg_catalog.format('select count(*) from %s where %I = $1', v_fk.tbl, v_fk.attname) into v_n using p_product_id;
      v_other := v_other + v_n;
    end if;
  end loop;
  return pg_catalog.jsonb_build_object(
    'project_lines_active', (select count(*) from public.project_products pp join public.projects pr on pr.id = pp.project_id
                              where pp.product_id = p_product_id and pr.status = 'active'),
    'project_lines_archived', (select count(*) from public.project_products pp join public.projects pr on pr.id = pp.project_id
                                where pp.product_id = p_product_id and pr.status = 'archived'),
    'project_lines_total', (select count(*) from public.project_products pp where pp.product_id = p_product_id),
    'rfqs', (select count(distinct r.id) from public.rfqs r
              where r.project_id in (select pp.project_id from public.project_products pp where pp.product_id = p_product_id)),
    'open_proposals', (select count(*) from public.product_proposals pr
                        where (pr.product_id = p_product_id or pr.created_product_id = p_product_id)
                          and pr.status in ('draft', 'submitted', 'changes_requested')),
    'closed_proposals', (select count(*) from public.product_proposals pr
                          where (pr.product_id = p_product_id or pr.created_product_id = p_product_id)
                            and pr.status not in ('draft', 'submitted', 'changes_requested')),
    'other_references', v_other,
    'unknown_reference_tables', pg_catalog.to_jsonb(v_unknown));
end;
$$;

revoke all on function mobau_private.assert_mobau_admin() from public, anon, authenticated, service_role;
revoke all on function mobau_private.product_reference_counts(text) from public, anon, authenticated, service_role;

-- ---------- 2. acciones de Mobau: retirar, papelera, restaurar ----------
create function public.mobau_product_lifecycle(
  p_product_id          text,
  p_action              text,
  p_reason              text,
  p_expected_updated_at timestamptz
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_uid uuid;
  v_reason text := nullif(pg_catalog.btrim(coalesce(p_reason, '')), '');
  v_p public.products%rowtype;
  v_state text;
  v_to text;
  v_now timestamptz := pg_catalog.now();
  v_updated timestamptz;
begin
  -- 1. Interruptor: lo primero.
  if not mobau_private.product_lifecycle_enabled() then
    raise exception 'Esta acción todavía no está disponible.' using errcode = '55000', hint = 'feature_disabled';
  end if;
  -- 2. Admin activo con aal2
  v_uid := mobau_private.assert_mobau_admin();
  -- 3. Parámetros (N5: republish nunca por aquí; solo por propuesta)
  if p_product_id is null or pg_catalog.btrim(p_product_id) = '' or pg_catalog.char_length(p_product_id) > 200 then
    raise exception 'Identificador de producto no válido.' using errcode = '22023', hint = 'invalid_parameter';
  end if;
  if p_action is null or p_action not in ('retire', 'trash', 'restore') then
    raise exception 'Acción no válida: usa retire, trash o restore.' using errcode = '22023', hint = 'invalid_action';
  end if;
  if (p_action = 'retire' and v_reason is null) or pg_catalog.char_length(coalesce(v_reason, '')) > 500 then
    raise exception 'Indica el motivo (1 a 500 caracteres).' using errcode = '22023', hint = 'invalid_reason';
  end if;
  if p_expected_updated_at is null then
    raise exception 'Falta la versión del producto que estás viendo.' using errcode = '22023', hint = 'missing_version';
  end if;
  -- 4. Producto, bloqueado
  select * into v_p from public.products p where p.id = p_product_id for update;
  if not found then
    raise exception 'No encontramos el producto.' using errcode = 'P0002', hint = 'product_not_found';
  end if;
  -- 5. Autoaprobación: nunca sobre la empresa del propio admin
  if exists (select 1 from public.distributor_profiles dp where dp.user_id = v_uid and dp.distributor_id = v_p.distributor_id) then
    raise exception 'No puedes gestionar productos de tu propia empresa.' using errcode = '42501', hint = 'self_moderation_forbidden';
  end if;
  -- 6. Versión
  if v_p.updated_at is distinct from p_expected_updated_at then
    raise exception 'El producto cambió desde que lo abriste. Vuelve a cargarlo.' using errcode = '40001', hint = 'version_conflict';
  end if;
  -- 7. Estado y bloqueos
  v_state := mobau_private.product_lifecycle_state(v_p.publication_status, v_p.retired_at, v_p.trashed_at);
  if v_state = 'legacy_retired' then
    raise exception 'Este producto está pendiente de revisión individual.' using errcode = '55000', hint = 'legacy_pending_review';
  end if;
  if p_action = 'retire' then
    if v_state is distinct from 'published' then
      raise exception 'Solo se puede retirar un producto publicado.' using errcode = '55000', hint = 'invalid_state';
    end if;
  elsif p_action = 'trash' then
    if v_state in ('in_review', 'changes_requested') then
      raise exception 'El producto está en revisión.' using errcode = '55000', hint = 'in_review';
    end if;
    if v_state not in ('retired', 'draft') then
      raise exception 'Solo se puede mover a la papelera un producto retirado o en borrador.' using errcode = '55000', hint = 'invalid_state';
    end if;
  else
    if v_state is distinct from 'trashed' then
      raise exception 'El producto no está en la papelera.' using errcode = '55000', hint = 'invalid_state';
    end if;
  end if;
  if p_action in ('retire', 'trash') and mobau_private.product_has_open_proposal(v_p.id) then
    raise exception 'El producto tiene una propuesta abierta.' using errcode = '55000', hint = 'open_proposal';
  end if;
  -- 8. Escritura + auditoría (nunca publica)
  if p_action = 'retire' then
    update public.products
       set publication_status = 'archived', retired_at = v_now, retired_by = v_uid, retired_reason = v_reason
     where id = v_p.id
    returning updated_at into v_updated;
    v_to := 'retired';
  elsif p_action = 'trash' then
    update public.products
       set trashed_at = v_now, trashed_by = v_uid, trash_from = v_state, purge_after = v_now + interval '30 days'
     where id = v_p.id
    returning updated_at into v_updated;
    v_to := 'trashed';
  else
    v_to := v_p.trash_from;
    update public.products
       set trashed_at = null, trashed_by = null, trash_from = null, purge_after = null
     where id = v_p.id
    returning updated_at into v_updated;
  end if;
  perform mobau_private.log_lifecycle_event(v_p.id, v_p.distributor_id, p_action, v_state, v_to, v_uid, 'mobau', v_reason);
  return pg_catalog.jsonb_build_object('ok', true, 'product_id', v_p.id, 'lifecycle_state', v_to, 'updated_at', v_updated);
end;
$$;

-- ---------- 3. purga manual (T9 / T10) ----------
create function public.mobau_purge_product(
  p_product_id          text,
  p_confirm_id          text,
  p_reason              text,
  p_early               boolean,
  p_expected_updated_at timestamptz
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_uid uuid;
  v_reason text := nullif(pg_catalog.btrim(coalesce(p_reason, '')), '');
  v_p public.products%rowtype;
  v_state text;
  v_refs jsonb;
  v_props uuid[];
  v_n_events bigint;
  v_n_props bigint;
  v_n_prices bigint;
  v_sha text;
  v_counts jsonb;
begin
  -- 1. Interruptor
  if not mobau_private.product_lifecycle_enabled() then
    raise exception 'Esta acción todavía no está disponible.' using errcode = '55000', hint = 'feature_disabled';
  end if;
  -- 2. Admin activo con aal2
  v_uid := mobau_private.assert_mobau_admin();
  -- 3. Parámetros: id escrito igual, motivo siempre, tipo de purga explícito
  if p_product_id is null or pg_catalog.btrim(p_product_id) = '' or pg_catalog.char_length(p_product_id) > 200 then
    raise exception 'Identificador de producto no válido.' using errcode = '22023', hint = 'invalid_parameter';
  end if;
  if p_confirm_id is distinct from p_product_id then
    raise exception 'Escribe exactamente el identificador del producto para confirmar.' using errcode = '22023', hint = 'confirm_mismatch';
  end if;
  if v_reason is null or pg_catalog.char_length(v_reason) > 500 then
    raise exception 'Indica el motivo de la purga (1 a 500 caracteres).' using errcode = '22023', hint = 'invalid_reason';
  end if;
  if p_early is null then
    raise exception 'Indica si la purga es anticipada.' using errcode = '22023', hint = 'invalid_parameter';
  end if;
  if p_expected_updated_at is null then
    raise exception 'Falta la versión del producto que estás viendo.' using errcode = '22023', hint = 'missing_version';
  end if;
  -- 4. Producto, bloqueado
  select * into v_p from public.products p where p.id = p_product_id for update;
  if not found then
    raise exception 'No encontramos el producto.' using errcode = 'P0002', hint = 'product_not_found';
  end if;
  -- 5. Autoaprobación
  if exists (select 1 from public.distributor_profiles dp where dp.user_id = v_uid and dp.distributor_id = v_p.distributor_id) then
    raise exception 'No puedes gestionar productos de tu propia empresa.' using errcode = '42501', hint = 'self_moderation_forbidden';
  end if;
  -- 6. Versión
  if v_p.updated_at is distinct from p_expected_updated_at then
    raise exception 'El producto cambió desde que lo abriste. Vuelve a cargarlo.' using errcode = '40001', hint = 'version_conflict';
  end if;
  -- 7. Bloqueos (orden de v6 §6)
  v_state := mobau_private.product_lifecycle_state(v_p.publication_status, v_p.retired_at, v_p.trashed_at);
  if v_state is distinct from 'trashed' then
    raise exception 'Solo se puede purgar un producto de la papelera.' using errcode = '55000', hint = 'invalid_state';
  end if;
  if not p_early and pg_catalog.now() < v_p.purge_after then
    raise exception 'El plazo de la papelera no ha terminado: usa la purga anticipada con motivo.' using errcode = '55000', hint = 'purge_not_due';
  end if;
  if mobau_private.product_has_open_proposal(v_p.id)
     or exists (select 1 from public.product_proposals pr
                 where pr.created_product_id = v_p.id and pr.status in ('draft', 'submitted', 'changes_requested')) then
    raise exception 'El producto tiene una propuesta abierta.' using errcode = '55000', hint = 'open_proposal';
  end if;
  v_refs := mobau_private.product_reference_counts(v_p.id);
  if pg_catalog.jsonb_array_length(v_refs -> 'unknown_reference_tables') > 0 then
    raise exception 'Hay referencias al producto que no se pueden comprobar: purga bloqueada.' using errcode = '55000', hint = 'purge_unknown_reference';
  end if;
  if (v_refs ->> 'project_lines_total')::bigint > 0 or (v_refs ->> 'other_references')::bigint > 0 then
    raise exception 'El producto está en proyectos o solicitudes: purga bloqueada.' using errcode = '55000', hint = 'purge_blocked_references';
  end if;
  -- 8. Conjunto exacto a borrar, recuentos y huella (sin guardar contenido)
  select coalesce(pg_catalog.array_agg(pr.id order by pr.id), '{}'::uuid[]) into v_props
    from public.product_proposals pr
   where pr.product_id = v_p.id or pr.created_product_id = v_p.id;
  select count(*) into v_n_events from public.proposal_events e where e.proposal_id = any (v_props);
  v_n_props := pg_catalog.cardinality(v_props);
  select count(*) into v_n_prices from public.product_prices pp where pp.product_id = v_p.id;
  v_sha := pg_catalog.encode(pg_catalog.sha256(pg_catalog.convert_to(pg_catalog.concat_ws(E'\n',
             (select pg_catalog.to_jsonb(p)::text from public.products p where p.id = v_p.id),
             coalesce((select pg_catalog.to_jsonb(pp)::text from public.product_prices pp where pp.product_id = v_p.id), ''),
             coalesce((select pg_catalog.string_agg(pg_catalog.to_jsonb(pr)::text, E'\n' order by pr.id)
                         from public.product_proposals pr where pr.id = any (v_props)), ''),
             coalesce((select pg_catalog.string_agg(pg_catalog.to_jsonb(e)::text, E'\n' order by e.id)
                         from public.proposal_events e where e.proposal_id = any (v_props)), '')), 'UTF8')), 'hex');
  v_counts := pg_catalog.jsonb_build_object('proposal_events', v_n_events, 'product_proposals', v_n_props,
                                            'product_prices', v_n_prices, 'products', 1);
  -- 9. Borrado en orden y auditoría A
  delete from public.proposal_events e where e.proposal_id = any (v_props);
  delete from public.product_proposals pr where pr.id = any (v_props);
  delete from public.product_prices pp where pp.product_id = v_p.id;
  delete from public.products p where p.id = v_p.id;
  perform mobau_private.log_lifecycle_event(v_p.id, v_p.distributor_id, 'purge', 'trashed', null, v_uid, 'mobau', v_reason,
            v_counts, v_sha,
            pg_catalog.jsonb_build_object('category_id', v_p.category_id, 'subcategory', v_p.subcategory,
                                          'created_at', v_p.created_at, 'trashed_at', v_p.trashed_at,
                                          'purge_after', v_p.purge_after, 'early', p_early));
  return pg_catalog.jsonb_build_object('ok', true, 'product_id', v_p.id, 'purged_counts', v_counts);
end;
$$;

-- ---------- 4. lecturas de Mobau ----------
create function public.mobau_product_references(p_product_id text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not mobau_private.product_lifecycle_enabled() then
    raise exception 'Esta acción todavía no está disponible.' using errcode = '55000', hint = 'feature_disabled';
  end if;
  perform mobau_private.assert_mobau_admin();
  if p_product_id is null or pg_catalog.btrim(p_product_id) = '' or pg_catalog.char_length(p_product_id) > 200 then
    raise exception 'Identificador de producto no válido.' using errcode = '22023', hint = 'invalid_parameter';
  end if;
  if not exists (select 1 from public.products p where p.id = p_product_id) then
    raise exception 'No encontramos el producto.' using errcode = 'P0002', hint = 'product_not_found';
  end if;
  return pg_catalog.jsonb_build_object('product_id', p_product_id) || mobau_private.product_reference_counts(p_product_id);
end;
$$;

create function public.mobau_product_lifecycle_view(p_product_id text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_p public.products%rowtype;
  v_state text;
  v_open boolean;
  v_refs jsonb;
  v_blocks text[] := '{}'::text[];
begin
  if not mobau_private.product_lifecycle_enabled() then
    raise exception 'Esta acción todavía no está disponible.' using errcode = '55000', hint = 'feature_disabled';
  end if;
  perform mobau_private.assert_mobau_admin();
  if p_product_id is null or pg_catalog.btrim(p_product_id) = '' or pg_catalog.char_length(p_product_id) > 200 then
    raise exception 'Identificador de producto no válido.' using errcode = '22023', hint = 'invalid_parameter';
  end if;
  select * into v_p from public.products p where p.id = p_product_id;
  if not found then
    raise exception 'No encontramos el producto.' using errcode = 'P0002', hint = 'product_not_found';
  end if;
  v_state := mobau_private.product_lifecycle_state(v_p.publication_status, v_p.retired_at, v_p.trashed_at);
  v_open := mobau_private.product_has_open_proposal(v_p.id);
  v_refs := mobau_private.product_reference_counts(v_p.id);
  if v_open then v_blocks := v_blocks || 'open_proposal'::text; end if;
  if v_state = 'legacy_retired' then v_blocks := v_blocks || 'legacy_pending_review'::text; end if;
  if v_state in ('in_review', 'changes_requested') then v_blocks := v_blocks || 'in_review'::text; end if;
  if v_state = 'trashed' and pg_catalog.now() < v_p.purge_after then v_blocks := v_blocks || 'purge_not_due'::text; end if;
  if (v_refs ->> 'project_lines_total')::bigint > 0 or (v_refs ->> 'other_references')::bigint > 0 then
    v_blocks := v_blocks || 'purge_blocked_references'::text;
  end if;
  if pg_catalog.jsonb_array_length(v_refs -> 'unknown_reference_tables') > 0 then
    v_blocks := v_blocks || 'purge_unknown_reference'::text;
  end if;
  return pg_catalog.jsonb_build_object(
    'product_id', v_p.id, 'distributor_id', v_p.distributor_id, 'name', v_p.name,
    'publication_status', v_p.publication_status, 'lifecycle_state', v_state, 'updated_at', v_p.updated_at,
    'retired_at', v_p.retired_at, 'retired_by', v_p.retired_by, 'retired_reason', v_p.retired_reason,
    'trashed_at', v_p.trashed_at, 'trashed_by', v_p.trashed_by, 'trash_from', v_p.trash_from, 'purge_after', v_p.purge_after,
    'has_open_proposal', v_open,
    'allowed_actions', pg_catalog.to_jsonb(mobau_private.product_allowed_actions(v_state, v_open, v_p.purge_after, 'mobau')),
    'blocks', pg_catalog.to_jsonb(v_blocks),
    'references', v_refs,
    'events', coalesce((select pg_catalog.jsonb_agg(pg_catalog.jsonb_strip_nulls(pg_catalog.jsonb_build_object(
                          'action', e.action, 'from_state', e.from_state, 'to_state', e.to_state,
                          'actor_kind', e.actor_kind, 'actor_id', e.actor_id, 'reason', e.reason, 'created_at', e.created_at))
                          order by e.created_at desc, e.id desc)
                          from mobau_private.product_lifecycle_events e where e.product_id = v_p.id), '[]'::jsonb));
end;
$$;

revoke all on function public.mobau_product_lifecycle(text, text, text, timestamptz) from public, anon, authenticated, service_role;
revoke all on function public.mobau_purge_product(text, text, text, boolean, timestamptz) from public, anon, authenticated, service_role;
revoke all on function public.mobau_product_references(text) from public, anon, authenticated, service_role;
revoke all on function public.mobau_product_lifecycle_view(text) from public, anon, authenticated, service_role;

-- ---------- 5. validación final ----------
DO $$
declare
  f record;
begin
  for f in
    select * from (values
      ('mobau_private.assert_mobau_admin()', '00b4ff173ed799f5f57fb5b35b1f5ddf', false),
      ('mobau_private.product_reference_counts(text)', '69f5ee71cbed763b505986669083c09c', false),
      ('public.mobau_product_lifecycle(text, text, text, timestamp with time zone)', 'b0f0225f53ad326a35e5c3faf00ec566', true),
      ('public.mobau_purge_product(text, text, text, boolean, timestamp with time zone)', '3421e8c5dec7015db2888c1d685d0f8c', true),
      ('public.mobau_product_references(text)', '5ac9822c1abcc9c5949df5029e3e0686', true),
      ('public.mobau_product_lifecycle_view(text)', '79d9aec3f54087bef4f3f9e38a9bc47f', true)
    ) as x(sig, body_md5, definer)
  loop
    if to_regprocedure(f.sig) is null then
      raise exception '41-05: falta %', f.sig;
    end if;
    if (select md5(prosrc) from pg_proc where oid = to_regprocedure(f.sig)) is distinct from f.body_md5
       or (select prosecdef from pg_proc where oid = to_regprocedure(f.sig)) <> f.definer
       or not (select proconfig @> array['search_path=""'] from pg_proc where oid = to_regprocedure(f.sig))
       or (select proowner from pg_proc where oid = to_regprocedure(f.sig)) <> 'postgres'::regrole
       or (select proacl::text from pg_proc where oid = to_regprocedure(f.sig)) is distinct from '{postgres=X/postgres}'
       or has_function_privilege('anon', to_regprocedure(f.sig), 'EXECUTE')
       or has_function_privilege('authenticated', to_regprocedure(f.sig), 'EXECUTE')
       or has_function_privilege('service_role', to_regprocedure(f.sig), 'EXECUTE') then
      raise exception '41-05: % con cuerpo, propiedades o permisos inesperados', f.sig;
    end if;
  end loop;
  if (select count(*) from pg_proc where pronamespace = 'mobau_private'::regnamespace) <> 9 then
    raise exception '41-05: mobau_private debe tener 9 funciones';
  end if;
  if mobau_private.product_lifecycle_enabled() or exists (select 1 from mobau_private.product_lifecycle_events) then
    raise exception '41-05: el interruptor debe seguir apagado y sin eventos';
  end if;
  if jsonb_array_length(mobau_private.product_reference_counts('__41_05_autocomprobacion__') -> 'unknown_reference_tables') <> 0 then
    raise exception '41-05: hay claves ajenas compuestas hacia products (revisar antes de purgar)';
  end if;
  if (select count(*) from pg_policies where schemaname = 'public') <> 48 then
    raise exception '41-05: ha cambiado el número de políticas';
  end if;
  raise notice '41-05 OK: 4 funciones de Mobau sin EXECUTE; 2 auxiliares privados; interruptor apagado.';
end $$;

COMMIT;
