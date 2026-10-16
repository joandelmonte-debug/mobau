-- ============================================================
-- PROPUESTA NO EJECUTADA (41-07 · recuperación) — no ejecutar sin aprobación explícita
-- ============================================================
-- 41 · 07 · RECUPERACIÓN: vuelve a V3 + 41-06 (código y permisos), SIN
-- borrar datos ni auditoría. Una transacción, como postgres. Es una
-- migración nueva hacia delante (opción R-B): si se ejecuta de verdad, se
-- registra aparte DESPUÉS de su COMMIT; 41-07 sigue registrada.
-- Generada por herramientas/generar_41_07.py: los cuerpos son copia literal
-- de 41-03 y 41-05 (MD5 de cada cuerpo comprobado contra V3).
--
--   1. Datos compatibles con 41-01 (sin borrar nada): las papeleras nuevas
--      (purge_after null) reciben purge_after = trashed_at + 30 días, el
--      valor que exige 41-01. Consecuencia con las reglas de V3: lo que lleve
--      más de 30 días en la papelera ya no lo puede restaurar la empresa
--      (sí Mobau). Los productos restaurados a «publicado» siguen publicados
--      (válidos en V3). Se actualiza su updated_at (trigger existente).
--   2. Restricciones y comentario de 41-01, literales.
--   3. Funciones de V3, literales; se eliminan las dos funciones nuevas y los
--      tres auxiliares de 41-07 (sin datos propios).
--   4. Permisos de 41-06: EXECUTE de authenticated en las 9 de entrada
--      (vuelve distributor_retire_product).
-- NO cambia: el interruptor, la auditoría (los eventos de 41-07, incluidas
-- las eliminaciones de la empresa y su meta {name}, se conservan),
-- supabase_migrations, políticas ni otras tablas.
-- Tras ejecutarla, la interfaz debe volver a D3 (e989542) o, si sigue la
-- nueva, sus acciones nuevas fallan sin efecto (función inexistente).
-- ============================================================

BEGIN;

set local lock_timeout = '5s';

DO $pre41_07r$
begin
  if current_user <> 'postgres' then
    raise exception '41-07 recuperación: ejecutar como postgres';
  end if;
  if to_regprocedure('public.distributor_purge_product(text, text, timestamp with time zone)') is null
     or to_regprocedure('public.mobau_lifecycle_history(text)') is null
     or to_regprocedure('mobau_private.product_allowed_actions(text, boolean, timestamp with time zone, text, boolean, text)') is null
     or to_regprocedure('mobau_private.product_lifecycle_flags(text, text)') is null
     or to_regprocedure('mobau_private.purge_product_rows(text)') is null
     or to_regprocedure('mobau_private.product_allowed_actions(text, boolean, timestamp with time zone, text)') is not null then
    raise exception '41-07 recuperación: el punto de partida no es 41-07';
  end if;
end $pre41_07r$;

-- ---------- 1. datos compatibles con 41-01 (sin borrar nada) ----------
lock table public.products in access exclusive mode;
update public.products
   set purge_after = trashed_at + interval '30 days'
 where trashed_at is not null and purge_after is distinct from trashed_at + interval '30 days';

-- ---------- 2. restricciones y comentario de 41-01 ----------
alter table public.products
  drop constraint products_lifecycle_trash_fields,
  drop constraint products_lifecycle_trash_coherent,
  add constraint products_lifecycle_trash_fields
    check ((trashed_at is null and trashed_by is null and trash_from is null and purge_after is null)
        or (trashed_at is not null and trashed_by is not null and trash_from is not null and purge_after is not null)),
  add constraint products_lifecycle_trash_coherent
    check (trashed_at is null
        or (publication_status <> 'published' and trash_from in ('retired', 'draft')
            and purge_after = trashed_at + interval '30 days'));
comment on column public.products.purge_after is '41-01: trashed_at + 30 días.';

-- ---------- 3. funciones de V3 (literales de 41-03 y 41-05) ----------
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

create or replace function public.mobau_product_lifecycle_view(p_product_id text)
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

drop function public.my_products_lifecycle();

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

drop function public.my_product_lifecycle_events(text);

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

create or replace function public.distributor_trash_product(
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

create or replace function public.distributor_restore_product(
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

create or replace function public.mobau_product_lifecycle(
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

create or replace function public.mobau_purge_product(
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

drop function public.distributor_purge_product(text, text, timestamptz);
drop function public.mobau_lifecycle_history(text);
drop function mobau_private.product_allowed_actions(text, boolean, timestamptz, text, boolean, text);
drop function mobau_private.product_lifecycle_flags(text, text);
drop function mobau_private.purge_product_rows(text);

-- ---------- 4. permisos de V3 + 41-06 ----------
revoke all on function mobau_private.product_allowed_actions(text, boolean, timestamptz, text) from public, anon, authenticated, service_role;
revoke all on function public.my_products_lifecycle() from public, anon, authenticated, service_role;
revoke all on function public.my_product_lifecycle_events(text) from public, anon, authenticated, service_role;
grant execute on function public.my_products_lifecycle() to authenticated;
grant execute on function public.my_product_lifecycle_events(text) to authenticated;
grant execute on function public.distributor_retire_product(text, text, timestamptz) to authenticated;

-- ---------- 5. validación final ----------
DO $post41_07r$
declare
  f record;
begin
  for f in
    select * from (values
      ('mobau_private.product_allowed_actions(text, boolean, timestamp with time zone, text)', 'debc094a59fbdc2f8268dd0c65edc367', '{postgres=X/postgres}'),
      ('public.my_products_lifecycle()', '238308a02c5d2a4f956424c00b953aa2', '{postgres=X/postgres,authenticated=X/postgres}'),
      ('public.my_product_lifecycle_events(text)', '9f4f092494d29521d0159f29c9c94b40', '{postgres=X/postgres,authenticated=X/postgres}'),
      ('public.distributor_retire_product(text, text, timestamp with time zone)', '616219991f4be91055dc4f83124d3998', '{postgres=X/postgres,authenticated=X/postgres}'),
      ('public.distributor_trash_product(text, timestamp with time zone)', 'cb687302bb76e5c56f39c9998efb4b3e', '{postgres=X/postgres,authenticated=X/postgres}'),
      ('public.distributor_restore_product(text, timestamp with time zone)', 'fb3cbc10d5dc5ac5a8b89d6d1ee94372', '{postgres=X/postgres,authenticated=X/postgres}'),
      ('public.mobau_product_lifecycle(text, text, text, timestamp with time zone)', 'b0f0225f53ad326a35e5c3faf00ec566', '{postgres=X/postgres,authenticated=X/postgres}'),
      ('public.mobau_purge_product(text, text, text, boolean, timestamp with time zone)', '3421e8c5dec7015db2888c1d685d0f8c', '{postgres=X/postgres,authenticated=X/postgres}'),
      ('public.mobau_product_references(text)', '5ac9822c1abcc9c5949df5029e3e0686', '{postgres=X/postgres,authenticated=X/postgres}'),
      ('public.mobau_product_lifecycle_view(text)', '79d9aec3f54087bef4f3f9e38a9bc47f', '{postgres=X/postgres,authenticated=X/postgres}')
    ) as x(sig, body_md5, acl)
  loop
    if to_regprocedure(f.sig) is null
       or (select md5(prosrc) from pg_proc where oid = to_regprocedure(f.sig)) is distinct from f.body_md5
       or (select proacl::text from pg_proc where oid = to_regprocedure(f.sig)) is distinct from f.acl
       or (select proowner from pg_proc where oid = to_regprocedure(f.sig)) <> 'postgres'::regrole then
      raise exception '41-07 recuperación: % no quedó como en V3 + 41-06', f.sig;
    end if;
  end loop;
  if (select count(*) from pg_proc where pronamespace = 'mobau_private'::regnamespace) <> 9
     or to_regprocedure('public.distributor_purge_product(text, text, timestamp with time zone)') is not null
     or to_regprocedure('public.mobau_lifecycle_history(text)') is not null then
    raise exception '41-07 recuperación: quedan objetos de 41-07';
  end if;
  if pg_get_constraintdef((select oid from pg_constraint where conrelid = 'public.products'::regclass
                            and conname = 'products_lifecycle_trash_coherent')) not like '%30 days%'
     or exists (select 1 from public.products where trashed_at is not null
                 and purge_after is distinct from trashed_at + interval '30 days') then
    raise exception '41-07 recuperación: restricciones o datos de papelera inesperados';
  end if;
  if (select count(*) from pg_policies where schemaname = 'public') <> 48 then
    raise exception '41-07 recuperación: ha cambiado el número de políticas';
  end if;
  raise notice '41-07 recuperación OK: código y permisos de V3 + 41-06; datos y auditoría conservados.';
end $post41_07r$;

COMMIT;
