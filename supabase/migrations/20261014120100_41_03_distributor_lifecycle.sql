-- ============================================================
-- PROPUESTA NO EJECUTADA (41-03) — no ejecutar sin aprobación explícita
-- ============================================================
-- 41 · 03 · Ciclo de vida del distribuidor, INSTALADO Y APAGADO
-- ------------------------------------------------------------
-- Requiere 41-01, 41-02 y 41-03a. Transacción única.
--
--   1. mobau_private.product_lifecycle_settings: una fila (id = 1),
--      enabled = false. RLS sin políticas; sin permisos de cliente.
--   2. Auxiliares en mobau_private (sin EXECUTE ni USAGE para clientes):
--        product_lifecycle_enabled()          interruptor
--        product_has_open_proposal(text)      propuesta abierta (PA)
--        product_allowed_actions(…)           acciones permitidas; {} apagado
--        log_lifecycle_event(…)               única escritura de auditoría
--   3. Funciones de entrada en public, SECURITY DEFINER, search_path vacío,
--      propietario postgres, SIN EXECUTE para PUBLIC, anon, authenticated ni
--      service_role (ACL exacta {postgres=X/postgres}). Se conceden solo en
--      41-06 (V4), tras verificar la interfaz servida:
--        my_products_lifecycle()                       lectura (rev5)
--        my_product_lifecycle_events(text)             lectura (rev5)
--        distributor_retire_product(text, text, timestamptz)   T1
--        distributor_trash_product(text, timestamptz)          T6 (dueño)
--        distributor_restore_product(text, timestamptz)        T7 (≤ 30 días)
--
-- Orden de validación de las tres acciones (ninguna escritura antes de que
-- pasen todas; el interruptor es lo PRIMERO):
--   1 interruptor apagado → 55000 hint feature_disabled
--   2 auth.uid() nulo     → 42501 not_authenticated
--   3 parámetros          → 22023 invalid_parameter | invalid_reason | missing_version
--   4 empresa (41-03a)    → 42501 not_verified_distributor
--   5 producto propio FOR UPDATE; ajeno = inexistente → P0002 product_not_found
--   6 versión (updated_at) → 40001 version_conflict
--   7 estado              → 55000 legacy_pending_review | in_review | invalid_state | restore_window_expired
--   8 propuesta abierta   → 55000 open_proposal (retirar y papelera)
--   9 escritura en products + evento de auditoría, en la misma transacción
-- Nunca escriben publication_status = 'published'.
--
-- my_products_lifecycle(): columnas fijas de rev5 + updated_at. updated_at se
-- devuelve SOLO como versión de concurrencia (el valor que las acciones piden
-- en p_expected_updated_at); no añade datos de actores ni cambia las demás
-- columnas permitidas. Nunca devuelve retired_by, trashed_by ni ningún uuid.
-- Rollback: supabase/rollback/20261014120100_41_03_distributor_lifecycle.rollback.sql
-- ============================================================

BEGIN;

-- No bloquea tablas existentes: crea una tabla en mobau_private y funciones.
set local lock_timeout = '5s';

-- ---------- 0. prechecks ----------
DO $$
begin
  if current_user <> 'postgres' then
    raise exception '41-03: ejecutar como postgres';
  end if;
  if to_regprocedure('mobau_private.resolve_verified_distributor(uuid)') is null
     or (select md5(prosrc) from pg_proc where oid = to_regprocedure('mobau_private.resolve_verified_distributor(uuid)'))
        is distinct from '1982b668e9cfb08bbf4b376cb0e29e3b'
     or (select md5(prosrc) from pg_proc where oid = 'public.my_verified_distributor_id()'::regprocedure)
        is distinct from 'c4c85af9dc9fde6d93f9fb25a56d1b87' then
    raise exception '41-03: falta 41-03a';
  end if;
  if to_regclass('mobau_private.product_lifecycle_events') is null
     or to_regprocedure('mobau_private.product_lifecycle_state(text, timestamp with time zone, timestamp with time zone)') is null then
    raise exception '41-03: falta 41-01';
  end if;
  if to_regclass('mobau_private.product_lifecycle_settings') is not null
     or to_regprocedure('public.my_products_lifecycle()') is not null
     or to_regprocedure('public.my_product_lifecycle_events(text)') is not null
     or to_regprocedure('public.distributor_retire_product(text, text, timestamp with time zone)') is not null
     or to_regprocedure('public.distributor_trash_product(text, timestamp with time zone)') is not null
     or to_regprocedure('public.distributor_restore_product(text, timestamp with time zone)') is not null then
    raise exception '41-03: algún objeto de 41-03 ya existe';
  end if;
  if exists (select 1 from mobau_private.product_lifecycle_events) then
    raise exception '41-03: la auditoría de ciclo de vida no está vacía';
  end if;
  if exists (select 1 from public.products
              where retired_at is not null or trashed_at is not null or retired_by is not null or trashed_by is not null) then
    raise exception '41-03: hay productos con datos de ciclo de vida';
  end if;
  if (select md5(prosrc) from pg_proc where oid = 'public.moderate_product_proposal(uuid, text, text, integer)'::regprocedure)
     is distinct from 'e814b477d0e078872ad085e00157c2c2' then
    raise exception '41-03: moderate_product_proposal no es la de 40-01';
  end if;
  if (select count(*) from pg_policies where schemaname = 'public') <> 48 then
    raise exception '41-03: se esperaban 48 políticas';
  end if;
end $$;

-- ---------- 1. interruptor ----------
create table mobau_private.product_lifecycle_settings (
  id         smallint primary key default 1,
  enabled    boolean not null default false,
  changed_at timestamptz not null default now(),
  changed_by uuid,
  note       text,
  constraint product_lifecycle_settings_single_row check (id = 1),
  constraint product_lifecycle_settings_note_length check (note is null or char_length(note) <= 500)
);
comment on table mobau_private.product_lifecycle_settings is
  '41-03: interruptor del ciclo de vida (una fila). Solo lo cambia una migración (41-06 o su inverso). Sin permisos de cliente.';
insert into mobau_private.product_lifecycle_settings (id, enabled, note)
values (1, false, '41-03: instalado apagado');
alter table mobau_private.product_lifecycle_settings enable row level security;
revoke all on table mobau_private.product_lifecycle_settings from public, anon, authenticated, service_role;

-- ---------- 2. auxiliares (mobau_private) ----------
create function mobau_private.product_lifecycle_enabled()
returns boolean
language sql
stable
set search_path = ''
as $$
  -- 41-03: sin fila o con enabled = false → apagado.
  select coalesce((select s.enabled from mobau_private.product_lifecycle_settings s where s.id = 1), false);
$$;

create function mobau_private.product_has_open_proposal(p_product_id text)
returns boolean
language sql
stable
set search_path = ''
as $$
  -- 41-03 (D3): cualquier propuesta abierta del producto (update o republish).
  select exists (select 1 from public.product_proposals pr
                  where pr.product_id = p_product_id
                    and pr.status in ('draft', 'submitted', 'changes_requested'));
$$;

create function mobau_private.product_allowed_actions(
  p_state             text,
  p_has_open_proposal boolean,
  p_purge_after       timestamptz,
  p_actor             text
)
returns text[]
language sql
stable
set search_path = ''
as $$
  -- 41-03: origen único de las acciones que la interfaz puede pintar.
  -- Apagado → ninguna. Propuesta desconocida (null) cuenta como abierta.
  select case
    when not mobau_private.product_lifecycle_enabled() then '{}'::text[]
    when p_actor = 'distributor' then
      case
        when p_state = 'published' and not coalesce(p_has_open_proposal, true) then array['retire']::text[]
        when p_state = 'retired' and not coalesce(p_has_open_proposal, true) then array['request_republish', 'trash']::text[]
        when p_state = 'draft' and not coalesce(p_has_open_proposal, true) then array['trash']::text[]
        when p_state = 'trashed' and p_purge_after is not null and pg_catalog.now() < p_purge_after then array['restore']::text[]
        else '{}'::text[]
      end
    when p_actor = 'mobau' then
      case
        when p_state = 'published' and not coalesce(p_has_open_proposal, true) then array['retire']::text[]
        when p_state in ('retired', 'draft') and not coalesce(p_has_open_proposal, true) then array['trash']::text[]
        when p_state = 'trashed' then array['restore', 'purge']::text[]
        else '{}'::text[]
      end
    else '{}'::text[]
  end;
$$;

create function mobau_private.log_lifecycle_event(
  p_product_id     text,
  p_distributor_id text,
  p_action         text,
  p_from_state     text,
  p_to_state       text,
  p_actor_id       uuid,
  p_actor_kind     text,
  p_reason         text,
  p_purge_counts   jsonb default null,
  p_purge_sha256   text default null,
  p_meta           jsonb default null
)
returns bigint
language sql
volatile
set search_path = ''
as $$
  -- 41-03: única escritura en la auditoría (nivel A, sin contenido del producto).
  insert into mobau_private.product_lifecycle_events
    (product_id, distributor_id, action, from_state, to_state, actor_id, actor_kind, reason, purge_counts, purge_sha256, meta)
  values (p_product_id, p_distributor_id, p_action, p_from_state, p_to_state, p_actor_id, p_actor_kind, p_reason,
          p_purge_counts, p_purge_sha256, p_meta)
  returning id;
$$;

revoke all on function mobau_private.product_lifecycle_enabled() from public, anon, authenticated, service_role;
revoke all on function mobau_private.product_has_open_proposal(text) from public, anon, authenticated, service_role;
revoke all on function mobau_private.product_allowed_actions(text, boolean, timestamptz, text) from public, anon, authenticated, service_role;
revoke all on function mobau_private.log_lifecycle_event(text, text, text, text, text, uuid, text, text, jsonb, text, jsonb)
  from public, anon, authenticated, service_role;

-- ---------- 3a. lecturas del distribuidor (sin EXECUTE hasta 41-06) ----------
create function public.my_products_lifecycle()
returns table (
  id                 text,
  name               text,
  publication_status text,
  lifecycle_state    text,
  allowed_actions    text[],
  has_open_proposal  boolean,
  retired_at         timestamptz,
  retired_reason     text,
  retired_by_kind    text,
  trashed_at         timestamptz,
  purge_after        timestamptz,
  updated_at         timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_uid uuid := (select auth.uid());
  v_dist text;
begin
  -- 41-03 (rev5): la empresa sale siempre de auth.uid(); sin parámetros.
  if v_uid is null then
    raise exception 'Necesitas iniciar sesión.' using errcode = '42501', hint = 'not_authenticated';
  end if;
  v_dist := mobau_private.resolve_verified_distributor(v_uid);
  if v_dist is null then
    return;   -- sin empresa verificada: conjunto vacío, sin error ni pista
  end if;
  return query
    -- Conversiones explícitas: RETURN QUERY exige los tipos exactos de RETURNS TABLE.
    select p.id::text, p.name::text, p.publication_status::text,
           s.state,
           mobau_private.product_allowed_actions(s.state, s.open_proposal, p.purge_after, 'distributor'),
           s.open_proposal,
           p.retired_at, p.retired_reason,
           case when p.retired_at is null then null::text
                else (select e.actor_kind from mobau_private.product_lifecycle_events e
                       where e.product_id = p.id and e.distributor_id = v_dist and e.action = 'retire'
                       order by e.created_at desc, e.id desc
                       limit 1) end,
           p.trashed_at, p.purge_after, p.updated_at::timestamptz
      from public.products p
      cross join lateral (select mobau_private.product_lifecycle_state(p.publication_status, p.retired_at, p.trashed_at) as state,
                                 mobau_private.product_has_open_proposal(p.id) as open_proposal) s
     where p.distributor_id = v_dist
     order by p.updated_at desc, p.id;
end;
$$;

comment on function public.my_products_lifecycle() is
  '41-03: productos de la propia empresa (auth.uid). Columnas fijas rev5 + updated_at, que es solo la versión de concurrencia que piden las acciones. Sin uuids ni actores. Sin EXECUTE de cliente hasta 41-06.';

create function public.my_product_lifecycle_events(p_product_id text default null)
returns table (
  product_id text,
  action     text,
  from_state text,
  to_state   text,
  actor_kind text,
  reason     text,
  created_at timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_uid uuid := (select auth.uid());
  v_dist text;
begin
  -- 41-03 (rev5): el parámetro solo reduce dentro de la propia empresa;
  -- un id ajeno y uno inexistente dan la misma respuesta (0 filas).
  if v_uid is null then
    raise exception 'Necesitas iniciar sesión.' using errcode = '42501', hint = 'not_authenticated';
  end if;
  if p_product_id is not null
     and (pg_catalog.btrim(p_product_id) = '' or pg_catalog.char_length(p_product_id) > 200) then
    raise exception 'Identificador de producto no válido.' using errcode = '22023', hint = 'invalid_parameter';
  end if;
  v_dist := mobau_private.resolve_verified_distributor(v_uid);
  if v_dist is null then
    return;
  end if;
  return query
    select e.product_id, e.action,
           case when e.action = 'purge' then null::text else e.from_state end,
           case when e.action = 'purge' then null::text else e.to_state end,
           e.actor_kind,
           case when e.action = 'purge' then null::text else e.reason end,
           e.created_at
      from mobau_private.product_lifecycle_events e
     where e.distributor_id = v_dist
       and (p_product_id is null or e.product_id = p_product_id)
     order by e.created_at desc, e.id desc;
end;
$$;

-- ---------- 3b. acciones del distribuidor (sin EXECUTE hasta 41-06) ----------
create function public.distributor_retire_product(
  p_product_id          text,
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
  v_uid uuid := (select auth.uid());
  v_reason text := pg_catalog.btrim(coalesce(p_reason, ''));
  v_dist text;
  v_p public.products%rowtype;
  v_state text;
  v_now timestamptz := pg_catalog.now();
  v_updated timestamptz;
begin
  -- 1. Interruptor: lo primero, antes de cualquier lectura o escritura.
  if not mobau_private.product_lifecycle_enabled() then
    raise exception 'Esta acción todavía no está disponible.' using errcode = '55000', hint = 'feature_disabled';
  end if;
  -- 2. Sesión
  if v_uid is null then
    raise exception 'Necesitas iniciar sesión.' using errcode = '42501', hint = 'not_authenticated';
  end if;
  -- 3. Parámetros
  if p_product_id is null or pg_catalog.btrim(p_product_id) = '' or pg_catalog.char_length(p_product_id) > 200 then
    raise exception 'Identificador de producto no válido.' using errcode = '22023', hint = 'invalid_parameter';
  end if;
  if v_reason = '' or pg_catalog.char_length(v_reason) > 500 then
    raise exception 'Indica el motivo de la retirada (1 a 500 caracteres).' using errcode = '22023', hint = 'invalid_reason';
  end if;
  if p_expected_updated_at is null then
    raise exception 'Falta la versión del producto que estás viendo.' using errcode = '22023', hint = 'missing_version';
  end if;
  -- 4. Empresa verificada (regla única 41-03a)
  v_dist := mobau_private.resolve_verified_distributor(v_uid);
  if v_dist is null then
    raise exception 'Tu empresa no está verificada.' using errcode = '42501', hint = 'not_verified_distributor';
  end if;
  -- 5. Producto propio, bloqueado (ajeno = inexistente)
  select * into v_p from public.products p where p.id = p_product_id and p.distributor_id = v_dist for update;
  if not found then
    raise exception 'No encontramos el producto.' using errcode = 'P0002', hint = 'product_not_found';
  end if;
  -- 6. Versión
  if v_p.updated_at is distinct from p_expected_updated_at then
    raise exception 'El producto cambió desde que lo abriste. Vuelve a cargarlo.' using errcode = '40001', hint = 'version_conflict';
  end if;
  -- 7. Estado: solo publicado
  v_state := mobau_private.product_lifecycle_state(v_p.publication_status, v_p.retired_at, v_p.trashed_at);
  if v_state = 'legacy_retired' then
    raise exception 'Este producto está pendiente de revisión por Mobau.' using errcode = '55000', hint = 'legacy_pending_review';
  end if;
  if v_state is distinct from 'published' then
    raise exception 'Solo se puede retirar un producto publicado.' using errcode = '55000', hint = 'invalid_state';
  end if;
  -- 8. Propuesta abierta (D3)
  if mobau_private.product_has_open_proposal(v_p.id) then
    raise exception 'El producto tiene una propuesta abierta.' using errcode = '55000', hint = 'open_proposal';
  end if;
  -- 9. Escritura: retirado (archived + retired_*); el trigger de 38-B fija status.
  update public.products
     set publication_status = 'archived', retired_at = v_now, retired_by = v_uid, retired_reason = v_reason
   where id = v_p.id
  returning updated_at into v_updated;
  perform mobau_private.log_lifecycle_event(v_p.id, v_dist, 'retire', 'published', 'retired', v_uid, 'distributor', v_reason);
  return pg_catalog.jsonb_build_object('ok', true, 'product_id', v_p.id, 'lifecycle_state', 'retired', 'updated_at', v_updated);
end;
$$;

create function public.distributor_trash_product(
  p_product_id          text,
  p_expected_updated_at timestamptz
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_dist text;
  v_p public.products%rowtype;
  v_state text;
  v_now timestamptz := pg_catalog.now();
  v_updated timestamptz;
begin
  -- 1. Interruptor
  if not mobau_private.product_lifecycle_enabled() then
    raise exception 'Esta acción todavía no está disponible.' using errcode = '55000', hint = 'feature_disabled';
  end if;
  -- 2. Sesión
  if v_uid is null then
    raise exception 'Necesitas iniciar sesión.' using errcode = '42501', hint = 'not_authenticated';
  end if;
  -- 3. Parámetros
  if p_product_id is null or pg_catalog.btrim(p_product_id) = '' or pg_catalog.char_length(p_product_id) > 200 then
    raise exception 'Identificador de producto no válido.' using errcode = '22023', hint = 'invalid_parameter';
  end if;
  if p_expected_updated_at is null then
    raise exception 'Falta la versión del producto que estás viendo.' using errcode = '22023', hint = 'missing_version';
  end if;
  -- 4. Empresa
  v_dist := mobau_private.resolve_verified_distributor(v_uid);
  if v_dist is null then
    raise exception 'Tu empresa no está verificada.' using errcode = '42501', hint = 'not_verified_distributor';
  end if;
  -- 5. Producto propio, bloqueado
  select * into v_p from public.products p where p.id = p_product_id and p.distributor_id = v_dist for update;
  if not found then
    raise exception 'No encontramos el producto.' using errcode = 'P0002', hint = 'product_not_found';
  end if;
  -- 6. Versión
  if v_p.updated_at is distinct from p_expected_updated_at then
    raise exception 'El producto cambió desde que lo abriste. Vuelve a cargarlo.' using errcode = '40001', hint = 'version_conflict';
  end if;
  -- 7. Estado: solo retirado o borrador (nunca publicado directamente: N11)
  v_state := mobau_private.product_lifecycle_state(v_p.publication_status, v_p.retired_at, v_p.trashed_at);
  if v_state = 'legacy_retired' then
    raise exception 'Este producto está pendiente de revisión por Mobau.' using errcode = '55000', hint = 'legacy_pending_review';
  end if;
  if v_state in ('in_review', 'changes_requested') then
    raise exception 'El producto está en revisión.' using errcode = '55000', hint = 'in_review';
  end if;
  if v_state not in ('retired', 'draft') then
    raise exception 'Solo se puede mover a la papelera un producto retirado o en borrador.' using errcode = '55000', hint = 'invalid_state';
  end if;
  -- 8. Propuesta abierta
  if mobau_private.product_has_open_proposal(v_p.id) then
    raise exception 'El producto tiene una propuesta abierta.' using errcode = '55000', hint = 'open_proposal';
  end if;
  -- 9. Escritura: papelera con plazo de 30 días
  update public.products
     set trashed_at = v_now, trashed_by = v_uid, trash_from = v_state, purge_after = v_now + interval '30 days'
   where id = v_p.id
  returning updated_at into v_updated;
  perform mobau_private.log_lifecycle_event(v_p.id, v_dist, 'trash', v_state, 'trashed', v_uid, 'distributor', null);
  return pg_catalog.jsonb_build_object('ok', true, 'product_id', v_p.id, 'lifecycle_state', 'trashed', 'updated_at', v_updated,
                                       'purge_after', v_now + interval '30 days');
end;
$$;

create function public.distributor_restore_product(
  p_product_id          text,
  p_expected_updated_at timestamptz
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_dist text;
  v_p public.products%rowtype;
  v_state text;
  v_to text;
  v_updated timestamptz;
begin
  -- 1. Interruptor
  if not mobau_private.product_lifecycle_enabled() then
    raise exception 'Esta acción todavía no está disponible.' using errcode = '55000', hint = 'feature_disabled';
  end if;
  -- 2. Sesión
  if v_uid is null then
    raise exception 'Necesitas iniciar sesión.' using errcode = '42501', hint = 'not_authenticated';
  end if;
  -- 3. Parámetros
  if p_product_id is null or pg_catalog.btrim(p_product_id) = '' or pg_catalog.char_length(p_product_id) > 200 then
    raise exception 'Identificador de producto no válido.' using errcode = '22023', hint = 'invalid_parameter';
  end if;
  if p_expected_updated_at is null then
    raise exception 'Falta la versión del producto que estás viendo.' using errcode = '22023', hint = 'missing_version';
  end if;
  -- 4. Empresa
  v_dist := mobau_private.resolve_verified_distributor(v_uid);
  if v_dist is null then
    raise exception 'Tu empresa no está verificada.' using errcode = '42501', hint = 'not_verified_distributor';
  end if;
  -- 5. Producto propio, bloqueado
  select * into v_p from public.products p where p.id = p_product_id and p.distributor_id = v_dist for update;
  if not found then
    raise exception 'No encontramos el producto.' using errcode = 'P0002', hint = 'product_not_found';
  end if;
  -- 6. Versión
  if v_p.updated_at is distinct from p_expected_updated_at then
    raise exception 'El producto cambió desde que lo abriste. Vuelve a cargarlo.' using errcode = '40001', hint = 'version_conflict';
  end if;
  -- 7. Estado: en papelera y dentro del plazo de 30 días
  v_state := mobau_private.product_lifecycle_state(v_p.publication_status, v_p.retired_at, v_p.trashed_at);
  if v_state is distinct from 'trashed' then
    raise exception 'El producto no está en la papelera.' using errcode = '55000', hint = 'invalid_state';
  end if;
  if pg_catalog.now() >= v_p.purge_after then
    raise exception 'El plazo para restaurar este producto terminó. Contacta con Mobau.' using errcode = '55000', hint = 'restore_window_expired';
  end if;
  -- 8. Escritura: solo se vacían los campos de papelera. Nunca publica:
  --    vuelve a retirado (con sus retired_* originales) o a borrador.
  v_to := v_p.trash_from;
  update public.products
     set trashed_at = null, trashed_by = null, trash_from = null, purge_after = null
   where id = v_p.id
  returning updated_at into v_updated;
  perform mobau_private.log_lifecycle_event(v_p.id, v_dist, 'restore', 'trashed', v_to, v_uid, 'distributor', null);
  return pg_catalog.jsonb_build_object('ok', true, 'product_id', v_p.id, 'lifecycle_state', v_to, 'updated_at', v_updated);
end;
$$;

-- Ninguna función de entrada es ejecutable por clientes hasta 41-06.
revoke all on function public.my_products_lifecycle() from public, anon, authenticated, service_role;
revoke all on function public.my_product_lifecycle_events(text) from public, anon, authenticated, service_role;
revoke all on function public.distributor_retire_product(text, text, timestamptz) from public, anon, authenticated, service_role;
revoke all on function public.distributor_trash_product(text, timestamptz) from public, anon, authenticated, service_role;
revoke all on function public.distributor_restore_product(text, timestamptz) from public, anon, authenticated, service_role;

-- ---------- 4. validación final ----------
DO $$
declare
  t_set constant regclass := 'mobau_private.product_lifecycle_settings'::regclass;
  f record;
begin
  -- interruptor
  if (select count(*) from mobau_private.product_lifecycle_settings) <> 1
     or (select enabled from mobau_private.product_lifecycle_settings where id = 1)
     or mobau_private.product_lifecycle_enabled() then
    raise exception '41-03: el interruptor debe quedar en una fila y apagado';
  end if;
  if not (select relrowsecurity from pg_class where oid = t_set)
     or exists (select 1 from pg_policies where schemaname = 'mobau_private')
     or exists (select 1 from unnest(array['anon', 'authenticated', 'service_role']) g, unnest(array['SELECT', 'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE']) p
                 where has_table_privilege(g, t_set, p)) then
    raise exception '41-03: el interruptor tiene permisos de cliente, políticas o no tiene RLS';
  end if;
  -- funciones: cuerpo, propiedades y permisos exactos
  for f in
    select * from (values
      ('mobau_private.product_lifecycle_enabled()', '070bbe66427c67b1315c4ea1d0097f85', false),
      ('mobau_private.product_has_open_proposal(text)', 'bfe313ce3436862b415a813d967288a7', false),
      ('mobau_private.product_allowed_actions(text, boolean, timestamp with time zone, text)', 'debc094a59fbdc2f8268dd0c65edc367', false),
      ('mobau_private.log_lifecycle_event(text, text, text, text, text, uuid, text, text, jsonb, text, jsonb)', 'a57570b8fb64aed5c05ca39ff3ad5be5', false),
      ('public.my_products_lifecycle()', '238308a02c5d2a4f956424c00b953aa2', true),
      ('public.my_product_lifecycle_events(text)', '9f4f092494d29521d0159f29c9c94b40', true),
      ('public.distributor_retire_product(text, text, timestamp with time zone)', '616219991f4be91055dc4f83124d3998', true),
      ('public.distributor_trash_product(text, timestamp with time zone)', 'cb687302bb76e5c56f39c9998efb4b3e', true),
      ('public.distributor_restore_product(text, timestamp with time zone)', 'fb3cbc10d5dc5ac5a8b89d6d1ee94372', true)
    ) as x(sig, body_md5, definer)
  loop
    if to_regprocedure(f.sig) is null then
      raise exception '41-03: falta %', f.sig;
    end if;
    if (select md5(prosrc) from pg_proc where oid = to_regprocedure(f.sig)) is distinct from f.body_md5
       or (select prosecdef from pg_proc where oid = to_regprocedure(f.sig)) <> f.definer
       or not (select proconfig @> array['search_path=""'] from pg_proc where oid = to_regprocedure(f.sig))
       or (select proowner from pg_proc where oid = to_regprocedure(f.sig)) <> 'postgres'::regrole
       or (select proacl::text from pg_proc where oid = to_regprocedure(f.sig)) is distinct from '{postgres=X/postgres}'
       or has_function_privilege('anon', to_regprocedure(f.sig), 'EXECUTE')
       or has_function_privilege('authenticated', to_regprocedure(f.sig), 'EXECUTE')
       or has_function_privilege('service_role', to_regprocedure(f.sig), 'EXECUTE') then
      raise exception '41-03: % con cuerpo, propiedades o permisos inesperados', f.sig;
    end if;
  end loop;
  if (select count(*) from pg_proc where pronamespace = 'mobau_private'::regnamespace) <> 6 then
    raise exception '41-03: mobau_private debe tener 6 funciones';
  end if;
  if has_schema_privilege('anon', 'mobau_private', 'USAGE') or has_schema_privilege('authenticated', 'mobau_private', 'USAGE')
     or has_schema_privilege('service_role', 'mobau_private', 'USAGE') then
    raise exception '41-03: mobau_private accesible para un rol cliente';
  end if;
  -- apagado: ninguna acción para nadie
  if mobau_private.product_allowed_actions('published', false, null, 'distributor') <> '{}'::text[]
     or mobau_private.product_allowed_actions('trashed', false, pg_catalog.now() + interval '1 day', 'mobau') <> '{}'::text[] then
    raise exception '41-03: con el interruptor apagado no debe haber acciones';
  end if;
  if exists (select 1 from mobau_private.product_lifecycle_events)
     or exists (select 1 from public.products where retired_at is not null or trashed_at is not null) then
    raise exception '41-03: no debe haber eventos ni datos de ciclo de vida';
  end if;
  if (select md5(prosrc) from pg_proc where oid = 'public.moderate_product_proposal(uuid, text, text, integer)'::regprocedure)
     is distinct from 'e814b477d0e078872ad085e00157c2c2'
     or (select count(*) from pg_policies where schemaname = 'public') <> 48 then
    raise exception '41-03: ha cambiado algo que no debía cambiar';
  end if;
  raise notice '41-03 OK: interruptor apagado; 5 funciones de entrada sin EXECUTE; 4 auxiliares privados.';
end $$;

COMMIT;
