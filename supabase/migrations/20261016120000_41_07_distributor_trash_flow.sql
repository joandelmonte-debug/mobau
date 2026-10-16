-- ============================================================
-- PROPUESTA NO EJECUTADA (41-07) — no ejecutar sin aprobación explícita
-- ============================================================
-- 41 · 07 · Flujo de productos del distribuidor (iteración 1, v2)
-- ------------------------------------------------------------
-- Requiere 41-06 aplicada y registrada. Transacción única, como postgres.
-- Bloquea public.products un instante (ALTER TABLE de dos CHECK, tabla
-- pequeña): con lock_timeout 5 s, si el piloto está en uso aborta sin cambios.
--
-- Criterio: el distribuidor controla sus productos; Mobau modera y puede
-- intervenir, pero no es un paso obligatorio para que el distribuidor borre
-- los suyos. La papelera NO caduca y no hay eliminación automática.
--
-- Tabla products (sin tocar datos ni eventos existentes)
--   · products_lifecycle_trash_fields: purge_after deja de ser obligatoria en
--     la papelera (las nuevas entradas la dejan en null).
--   · products_lifecycle_trash_coherent: desaparece «purge_after = trashed_at
--     + 30 días». Las filas existentes conservan su purge_after (histórico).
-- Distribuidor
--   · «Retirar» = distributor_trash_product (misma firma): publicado, retirado
--     o borrador → papelera en una sola transacción (eventos retire + trash).
--   · distributor_retire_product: instalada pero SIN EXECUTE para
--     authenticated (ya no existe «retirar sin papelera»).
--   · distributor_restore_product (misma firma), sin plazo, solo si la
--     papelera la hizo la propia empresa. Destino:
--       borrador → borrador;
--       retirado por la empresa sin intervención de Mobau vigente → PUBLICADO;
--       con intervención de Mobau vigente → sigue retirado por Mobau.
--     Movido a la papelera por Mobau → 55000 mobau_intervention.
--     Publicar al restaurar no salta la aprobación de contenido: el contenido
--     de products solo cambia por propuestas aprobadas por Mobau.
--   · distributor_purge_product (NUEVA): elimina definitivamente un producto
--     PROPIO de la papelera (también si lo movió Mobau). Mismas protecciones
--     que la de Mobau. Auditoría: actor 'distributor', nombre e id.
--   · my_products_lifecycle (+ trashed_by_kind, mobau_hold, restore_to) y
--     my_product_lifecycle_events (+ product_name; motivo de las
--     eliminaciones de Mobau): DROP + CREATE + GRANT a authenticated.
-- Mobau
--   · mobau_product_lifecycle: motivo obligatorio también al mover a la
--     papelera; la papelera ya no fija purge_after.
--   · mobau_purge_product (misma firma): desde publicado, retirado, borrador
--     o papelera. p_early se conserva en la firma por compatibilidad y no
--     bloquea (ya no hay plazo).
--   · mobau_product_lifecycle_view: + mobau_hold, trashed_by_kind; sin el
--     bloqueo purge_not_due.
--   · mobau_lifecycle_history(text) (NUEVA, lectura): con id, todos los
--     eventos de ese id aunque el producto ya no exista; sin id, las últimas
--     200 eliminaciones definitivas. Nombre, empresa, actor, motivo y fecha.
-- Auditoría de eliminaciones nuevas: meta = {"name": …} (nombre e id; sin
-- más contenido de la ficha). Los eventos existentes no se tocan. En el
-- historial, cada evento muestra el nombre de su propio ciclo: el actual del
-- producto o el guardado en la eliminación que cerró ese ciclo (sin nombre
-- guardado → nulo; la interfaz muestra el identificador).
-- Auxiliares (mobau_private, sin EXECUTE de cliente)
--   · product_lifecycle_flags(text, text): intervención de Mobau vigente
--     (retirada o papelera de Mobau posterior a la última republicación
--     aprobada) y autor de la última papelera. Solo cuenta eventos del ciclo
--     actual del identificador (posteriores a su última eliminación
--     definitiva) y de la empresa del producto; no depende de created_at.
--   · product_allowed_actions: firma de 6 argumentos (se elimina la de 4).
--   · purge_product_rows(text): borrado común (mismo orden, recuentos y
--     SHA-256 que 41-05).
--
-- Parada: 41_07_parada.sql (revoca también las 2 funciones nuevas).
-- Recuperación: 41_07_recuperacion.sql (vuelve a V3 + 41-06 sin borrar datos
-- ni auditoría).
-- ============================================================

BEGIN;

set local lock_timeout = '5s';

-- ---------- 0. prechecks ----------
DO $pre41_07$
declare
  f record;
begin
  if current_user <> 'postgres' then
    raise exception '41-07: ejecutar como postgres';
  end if;
  if not exists (select 1 from supabase_migrations.schema_migrations where version = '20261015120000') then
    raise exception '41-07: falta 41-06 (20261015120000)';
  end if;
  if exists (select 1 from supabase_migrations.schema_migrations where version = '20261016120000') then
    raise exception '41-07: ya registrada';
  end if;
  -- cuerpos de partida (los de V3)
  for f in
    select * from (values
      ('mobau_private.product_allowed_actions(text, boolean, timestamp with time zone, text)', 'debc094a59fbdc2f8268dd0c65edc367'),
      ('public.my_products_lifecycle()', '238308a02c5d2a4f956424c00b953aa2'),
      ('public.my_product_lifecycle_events(text)', '9f4f092494d29521d0159f29c9c94b40'),
      ('public.distributor_retire_product(text, text, timestamp with time zone)', '616219991f4be91055dc4f83124d3998'),
      ('public.distributor_trash_product(text, timestamp with time zone)', 'cb687302bb76e5c56f39c9998efb4b3e'),
      ('public.distributor_restore_product(text, timestamp with time zone)', 'fb3cbc10d5dc5ac5a8b89d6d1ee94372'),
      ('public.mobau_product_lifecycle(text, text, text, timestamp with time zone)', 'b0f0225f53ad326a35e5c3faf00ec566'),
      ('public.mobau_purge_product(text, text, text, boolean, timestamp with time zone)', '3421e8c5dec7015db2888c1d685d0f8c'),
      ('public.mobau_product_lifecycle_view(text)', '79d9aec3f54087bef4f3f9e38a9bc47f')
    ) as x(sig, body_md5)
  loop
    if to_regprocedure(f.sig) is null
       or (select md5(prosrc) from pg_proc where oid = to_regprocedure(f.sig)) is distinct from f.body_md5 then
      raise exception '41-07: % no es la de V3', f.sig;
    end if;
  end loop;
  if to_regprocedure('public.distributor_purge_product(text, text, timestamp with time zone)') is not null
     or to_regprocedure('public.mobau_lifecycle_history(text)') is not null
     or to_regprocedure('mobau_private.product_lifecycle_flags(text, text)') is not null
     or to_regprocedure('mobau_private.purge_product_rows(text)') is not null then
    raise exception '41-07: algún objeto de 41-07 ya existe';
  end if;
  if (select count(*) from pg_proc where pronamespace = 'mobau_private'::regnamespace) <> 9 then
    raise exception '41-07: mobau_private debe tener 9 funciones';
  end if;
  if (select count(*) from pg_policies where schemaname = 'public') <> 48 then
    raise exception '41-07: se esperaban 48 políticas';
  end if;
  -- restricciones de 41-01 tal como se instalaron
  if (select count(*) from pg_constraint where conrelid = 'public.products'::regclass
       and conname in ('products_lifecycle_trash_fields', 'products_lifecycle_trash_coherent')) <> 2
     or pg_get_constraintdef((select oid from pg_constraint where conrelid = 'public.products'::regclass
                               and conname = 'products_lifecycle_trash_coherent')) not like '%30 days%' then
    raise exception '41-07: las restricciones de papelera no son las de 41-01';
  end if;
end $pre41_07$;

-- ---------- 1. papelera sin caducidad (restricciones; datos intactos) ----------
lock table public.products in access exclusive mode;
alter table public.products
  drop constraint products_lifecycle_trash_fields,
  drop constraint products_lifecycle_trash_coherent,
  add constraint products_lifecycle_trash_fields
    check ((trashed_at is null and trashed_by is null and trash_from is null and purge_after is null)
        or (trashed_at is not null and trashed_by is not null and trash_from is not null)),
  add constraint products_lifecycle_trash_coherent
    check (trashed_at is null
        or (publication_status <> 'published' and trash_from in ('retired', 'draft')));
comment on column public.products.purge_after is
  '41-01: trashed_at + 30 días. Desde 41-07 la papelera no caduca: null en las entradas nuevas; las anteriores conservan su valor (histórico, sin efecto).';

-- ---------- 2. auxiliares ----------
create function mobau_private.product_lifecycle_flags(p_product_id text, p_distributor_id text)
returns table (mobau_hold boolean, trashed_by_kind text)
language sql
stable
set search_path = ''
as $$
  -- 41-07: solo eventos del ciclo actual del identificador (posteriores a su
  -- última eliminación definitiva, de cualquier empresa) y de la empresa del
  -- producto. No depende de created_at.
  -- mobau_hold: hay una retirada o papelera de Mobau posterior a la última
  -- republicación aprobada del mismo ciclo (la aprobación de Mobau levanta la
  -- intervención). trashed_by_kind: actor de la última papelera del ciclo.
  with c as (
    select coalesce((select max(x.id) from mobau_private.product_lifecycle_events x
                      where x.product_id = p_product_id and x.action = 'purge'), 0) as since_id
  )
  select exists (select 1 from mobau_private.product_lifecycle_events e
                  where e.product_id = p_product_id and e.distributor_id = p_distributor_id and e.id > c.since_id
                    and e.actor_kind = 'mobau' and e.action in ('retire', 'trash')
                    and e.id > coalesce((select max(r.id) from mobau_private.product_lifecycle_events r
                                          where r.product_id = p_product_id and r.distributor_id = p_distributor_id
                                            and r.id > c.since_id and r.action = 'republish'), 0)),
         (select t.actor_kind from mobau_private.product_lifecycle_events t
           where t.product_id = p_product_id and t.distributor_id = p_distributor_id and t.id > c.since_id
             and t.action = 'trash'
           order by t.id desc
           limit 1)
    from c;
$$;

create function mobau_private.product_allowed_actions(
  p_state             text,
  p_has_open_proposal boolean,
  p_purge_after       timestamptz,
  p_actor             text,
  p_mobau_hold        boolean,
  p_trashed_by_kind   text
)
returns text[]
language sql
stable
set search_path = ''
as $$
  -- 41-07: origen único de las acciones que la interfaz puede pintar.
  -- Apagado → ninguna. Propuesta desconocida (null) cuenta como abierta.
  -- Distribuidor: 'trash' es «Retirar» (de publicado, retirado o borrador a la
  -- papelera). Restaurar solo lo que movió la propia empresa (sin plazo).
  -- p_purge_after se conserva en la firma y ya no decide nada.
  select case
    when not mobau_private.product_lifecycle_enabled() then '{}'::text[]
    when p_actor = 'distributor' then
      case
        when p_state in ('published', 'draft') and not coalesce(p_has_open_proposal, true) then array['trash']::text[]
        when p_state = 'retired' and not coalesce(p_has_open_proposal, true) then array['request_republish', 'trash']::text[]
        when p_state = 'trashed' then
          (case when p_trashed_by_kind = 'distributor' then array['restore']::text[] else '{}'::text[] end)
          || (case when not coalesce(p_has_open_proposal, true) then array['purge']::text[] else '{}'::text[] end)
        else '{}'::text[]
      end
    when p_actor = 'mobau' then
      case
        when p_state = 'published' and not coalesce(p_has_open_proposal, true) then array['retire', 'purge']::text[]
        when p_state in ('retired', 'draft') and not coalesce(p_has_open_proposal, true) then array['trash', 'purge']::text[]
        when p_state = 'trashed' then array['restore', 'purge']::text[]
        else '{}'::text[]
      end
    else '{}'::text[]
  end;
$$;

create function mobau_private.purge_product_rows(p_product_id text)
returns table (purge_counts jsonb, purge_sha256 text)
language plpgsql
volatile
set search_path = ''
as $$
declare
  v_props uuid[];
  v_n_events bigint;
  v_n_prices bigint;
  v_sha text;
begin
  -- 41-07: el borrado de 41-05 (§8–9), sin cambios, para Mobau y distribuidor.
  -- Quien llama ya ha bloqueado el producto (FOR UPDATE) y comprobado bloqueos.
  select coalesce(pg_catalog.array_agg(pr.id order by pr.id), '{}'::uuid[]) into v_props
    from public.product_proposals pr
   where pr.product_id = p_product_id or pr.created_product_id = p_product_id;
  select count(*) into v_n_events from public.proposal_events e where e.proposal_id = any (v_props);
  select count(*) into v_n_prices from public.product_prices pp where pp.product_id = p_product_id;
  v_sha := pg_catalog.encode(pg_catalog.sha256(pg_catalog.convert_to(pg_catalog.concat_ws(E'\n',
             (select pg_catalog.to_jsonb(p)::text from public.products p where p.id = p_product_id),
             coalesce((select pg_catalog.to_jsonb(pp)::text from public.product_prices pp where pp.product_id = p_product_id), ''),
             coalesce((select pg_catalog.string_agg(pg_catalog.to_jsonb(pr)::text, E'\n' order by pr.id)
                         from public.product_proposals pr where pr.id = any (v_props)), ''),
             coalesce((select pg_catalog.string_agg(pg_catalog.to_jsonb(e)::text, E'\n' order by e.id)
                         from public.proposal_events e where e.proposal_id = any (v_props)), '')), 'UTF8')), 'hex');
  delete from public.proposal_events e where e.proposal_id = any (v_props);
  delete from public.product_proposals pr where pr.id = any (v_props);
  delete from public.product_prices pp where pp.product_id = p_product_id;
  delete from public.products p where p.id = p_product_id;
  return query select pg_catalog.jsonb_build_object('proposal_events', v_n_events,
                                                    'product_proposals', pg_catalog.cardinality(v_props),
                                                    'product_prices', v_n_prices, 'products', 1),
                      v_sha;
end;
$$;

revoke all on function mobau_private.product_lifecycle_flags(text, text) from public, anon, authenticated, service_role;
revoke all on function mobau_private.product_allowed_actions(text, boolean, timestamptz, text, boolean, text) from public, anon, authenticated, service_role;
revoke all on function mobau_private.purge_product_rows(text) from public, anon, authenticated, service_role;

-- ---------- 3. lecturas del distribuidor (cambia el tipo de retorno) ----------
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
  updated_at         timestamptz,
  trashed_by_kind    text,
  mobau_hold         boolean,
  restore_to         text
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
  -- 41-07: columnas de 41-03 (rev5) + trashed_by_kind, mobau_hold y
  -- restore_to (destino si la empresa restaura; null si no puede).
  if v_uid is null then
    raise exception 'Necesitas iniciar sesión.' using errcode = '42501', hint = 'not_authenticated';
  end if;
  v_dist := mobau_private.resolve_verified_distributor(v_uid);
  if v_dist is null then
    return;
  end if;
  return query
    select p.id::text, p.name::text, p.publication_status::text,
           s.state,
           mobau_private.product_allowed_actions(s.state, s.open_proposal, p.purge_after, 'distributor', f.mobau_hold, f.trashed_by_kind),
           s.open_proposal,
           p.retired_at, p.retired_reason,
           case when p.retired_at is null then null::text
                else (select e.actor_kind from mobau_private.product_lifecycle_events e
                       where e.product_id = p.id and e.distributor_id = v_dist and e.action = 'retire'
                         and e.id > coalesce((select max(x.id) from mobau_private.product_lifecycle_events x
                                               where x.product_id = p.id and x.action = 'purge'), 0)
                       order by e.id desc
                       limit 1) end,
           p.trashed_at, p.purge_after, p.updated_at::timestamptz,
           case when p.trashed_at is null then null::text else f.trashed_by_kind end,
           f.mobau_hold,
           case when s.state = 'trashed' and f.trashed_by_kind = 'distributor'
                then case when p.trash_from = 'retired' and not f.mobau_hold then 'published' else p.trash_from end
           end::text
      from public.products p
      cross join lateral (select mobau_private.product_lifecycle_state(p.publication_status, p.retired_at, p.trashed_at) as state,
                                 mobau_private.product_has_open_proposal(p.id) as open_proposal) s
      cross join lateral mobau_private.product_lifecycle_flags(p.id, p.distributor_id) f
     where p.distributor_id = v_dist
     order by p.updated_at desc, p.id;
end;
$$;

comment on function public.my_products_lifecycle() is
  '41-07: productos de la propia empresa (auth.uid). Columnas de 41-03 + trashed_by_kind, mobau_hold y restore_to. Sin uuids de actores.';

drop function public.my_product_lifecycle_events(text);
create function public.my_product_lifecycle_events(p_product_id text default null)
returns table (
  product_id   text,
  action       text,
  from_state   text,
  to_state     text,
  actor_kind   text,
  reason       text,
  created_at   timestamptz,
  product_name text
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
  -- 41-07: como 41-03 (rev5) + product_name (el del ciclo de cada evento: el
  -- actual del producto o el guardado en la eliminación que cerró ese ciclo)
  -- y el motivo de las eliminaciones de Mobau, que es el aviso a la empresa.
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
           case when e.action = 'purge' and e.actor_kind <> 'mobau' then null::text else e.reason end,
           e.created_at,
           coalesce(case when p.id is not null and p.distributor_id = e.distributor_id
                              and e.id > coalesce((select max(z.id) from mobau_private.product_lifecycle_events z
                                                    where z.product_id = e.product_id and z.action = 'purge'), 0)
                         then p.name end,
                    (select x.meta ->> 'name' from mobau_private.product_lifecycle_events x
                      where x.product_id = e.product_id and x.distributor_id = e.distributor_id
                        and x.action = 'purge' and x.id >= e.id
                      order by x.id
                      limit 1))::text
      from mobau_private.product_lifecycle_events e
      left join public.products p on p.id = e.product_id and p.distributor_id = v_dist
     where e.distributor_id = v_dist
       and (p_product_id is null or e.product_id = p_product_id)
     order by e.created_at desc, e.id desc;
end;
$$;

-- ---------- 4. acciones del distribuidor ----------
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
  v_from text;
  v_now timestamptz := pg_catalog.now();
  v_updated timestamptz;
begin
  -- 41-07: «Retirar». Una sola acción: si está publicado lo quita del catálogo
  -- y, en la misma transacción, lo mueve a la papelera.
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
  -- 7. Estado: publicado, retirado o borrador
  v_state := mobau_private.product_lifecycle_state(v_p.publication_status, v_p.retired_at, v_p.trashed_at);
  if v_state = 'legacy_retired' then
    raise exception 'Este producto está pendiente de revisión por Mobau.' using errcode = '55000', hint = 'legacy_pending_review';
  end if;
  if v_state in ('in_review', 'changes_requested') then
    raise exception 'El producto está en revisión.' using errcode = '55000', hint = 'in_review';
  end if;
  if v_state is null or v_state not in ('published', 'retired', 'draft') then
    raise exception 'Solo se puede retirar un producto publicado, retirado o en borrador.' using errcode = '55000', hint = 'invalid_state';
  end if;
  -- 8. Propuesta abierta
  if mobau_private.product_has_open_proposal(v_p.id) then
    raise exception 'El producto tiene una propuesta abierta.' using errcode = '55000', hint = 'open_proposal';
  end if;
  -- 9. Escritura + auditoría (nunca publica)
  if v_state = 'published' then
    update public.products
       set publication_status = 'archived', retired_at = v_now, retired_by = v_uid, retired_reason = 'Retirado por la empresa',
           trashed_at = v_now, trashed_by = v_uid, trash_from = 'retired', purge_after = null
     where id = v_p.id
    returning updated_at into v_updated;
    perform mobau_private.log_lifecycle_event(v_p.id, v_dist, 'retire', 'published', 'retired', v_uid, 'distributor', 'Retirado por la empresa');
    v_from := 'retired';
  else
    update public.products
       set trashed_at = v_now, trashed_by = v_uid, trash_from = v_state, purge_after = null
     where id = v_p.id
    returning updated_at into v_updated;
    v_from := v_state;
  end if;
  perform mobau_private.log_lifecycle_event(v_p.id, v_dist, 'trash', v_from, 'trashed', v_uid, 'distributor', null);
  return pg_catalog.jsonb_build_object('ok', true, 'product_id', v_p.id, 'lifecycle_state', 'trashed', 'from_state', v_state,
                                       'updated_at', v_updated);
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
  v_hold boolean;
  v_trashed_by text;
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
  -- 7. Estado: en papelera y movido por la propia empresa (sin plazo)
  v_state := mobau_private.product_lifecycle_state(v_p.publication_status, v_p.retired_at, v_p.trashed_at);
  if v_state is distinct from 'trashed' then
    raise exception 'El producto no está en la papelera.' using errcode = '55000', hint = 'invalid_state';
  end if;
  select f.mobau_hold, f.trashed_by_kind into v_hold, v_trashed_by
    from mobau_private.product_lifecycle_flags(v_p.id, v_p.distributor_id) f;
  if v_trashed_by is distinct from 'distributor' then
    raise exception 'Mobau movió este producto a la papelera: solo Mobau puede restaurarlo.' using errcode = '55000', hint = 'mobau_intervention';
  end if;
  -- 8. Escritura. Borrador → borrador. Retirado por la empresa sin
  --    intervención de Mobau vigente → publicado (su contenido es el último
  --    aprobado por Mobau). Con intervención vigente → sigue retirado.
  if v_p.trash_from = 'retired' and not v_hold then
    v_to := 'published';
    update public.products
       set publication_status = 'published', retired_at = null, retired_by = null, retired_reason = null,
           trashed_at = null, trashed_by = null, trash_from = null, purge_after = null
     where id = v_p.id
    returning updated_at into v_updated;
  else
    v_to := v_p.trash_from;
    update public.products
       set trashed_at = null, trashed_by = null, trash_from = null, purge_after = null
     where id = v_p.id
    returning updated_at into v_updated;
  end if;
  perform mobau_private.log_lifecycle_event(v_p.id, v_dist, 'restore', 'trashed', v_to, v_uid, 'distributor', null);
  return pg_catalog.jsonb_build_object('ok', true, 'product_id', v_p.id, 'lifecycle_state', v_to, 'updated_at', v_updated);
end;
$$;

create function public.distributor_purge_product(
  p_product_id          text,
  p_confirm_id          text,
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
  v_refs jsonb;
  v_res record;
begin
  -- 41-07: eliminación definitiva de un producto propio de la papelera, sin
  -- intervención de Mobau. Mismas protecciones que mobau_purge_product.
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
  if p_confirm_id is distinct from p_product_id then
    raise exception 'Confirma la eliminación definitiva.' using errcode = '22023', hint = 'confirm_mismatch';
  end if;
  if p_expected_updated_at is null then
    raise exception 'Falta la versión del producto que estás viendo.' using errcode = '22023', hint = 'missing_version';
  end if;
  -- 4. Empresa
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
  -- 7. Bloqueos: solo desde la papelera; propuesta abierta; referencias
  v_state := mobau_private.product_lifecycle_state(v_p.publication_status, v_p.retired_at, v_p.trashed_at);
  if v_state is distinct from 'trashed' then
    raise exception 'Solo se puede eliminar definitivamente un producto de la papelera.' using errcode = '55000', hint = 'invalid_state';
  end if;
  if mobau_private.product_has_open_proposal(v_p.id)
     or exists (select 1 from public.product_proposals pr
                 where pr.created_product_id = v_p.id and pr.status in ('draft', 'submitted', 'changes_requested')) then
    raise exception 'El producto tiene una propuesta abierta.' using errcode = '55000', hint = 'open_proposal';
  end if;
  v_refs := mobau_private.product_reference_counts(v_p.id);
  if pg_catalog.jsonb_array_length(v_refs -> 'unknown_reference_tables') > 0 then
    raise exception 'Hay referencias al producto que no se pueden comprobar.' using errcode = '55000', hint = 'purge_unknown_reference';
  end if;
  if (v_refs ->> 'project_lines_total')::bigint > 0 or (v_refs ->> 'other_references')::bigint > 0 then
    raise exception 'El producto está en proyectos o solicitudes de cotización.' using errcode = '55000', hint = 'purge_blocked_references';
  end if;
  -- 8. Borrado y auditoría (actor distributor; solo id y nombre, para identificarlo)
  select * into v_res from mobau_private.purge_product_rows(v_p.id);
  perform mobau_private.log_lifecycle_event(v_p.id, v_dist, 'purge', 'trashed', null, v_uid, 'distributor', null,
            v_res.purge_counts, v_res.purge_sha256, pg_catalog.jsonb_build_object('name', v_p.name));
  return pg_catalog.jsonb_build_object('ok', true, 'product_id', v_p.id, 'purged_counts', v_res.purge_counts);
end;
$$;

-- ---------- 5. Mobau ----------
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
  -- 3. Parámetros (N5: republish nunca por aquí; solo por propuesta).
  --    41-07: toda intervención (retirar o papelera) registra motivo.
  if p_product_id is null or pg_catalog.btrim(p_product_id) = '' or pg_catalog.char_length(p_product_id) > 200 then
    raise exception 'Identificador de producto no válido.' using errcode = '22023', hint = 'invalid_parameter';
  end if;
  if p_action is null or p_action not in ('retire', 'trash', 'restore') then
    raise exception 'Acción no válida: usa retire, trash o restore.' using errcode = '22023', hint = 'invalid_action';
  end if;
  if (p_action in ('retire', 'trash') and v_reason is null) or pg_catalog.char_length(coalesce(v_reason, '')) > 500 then
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
       set trashed_at = v_now, trashed_by = v_uid, trash_from = v_state, purge_after = null
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
  v_res record;
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
  -- 7. Bloqueos. 41-07: intervención directa sobre publicado, retirado,
  --    borrador o papelera. Sin plazo: p_early ya no bloquea (se conserva en
  --    la firma por compatibilidad con la interfaz anterior).
  v_state := mobau_private.product_lifecycle_state(v_p.publication_status, v_p.retired_at, v_p.trashed_at);
  if v_state is null or v_state not in ('published', 'retired', 'draft', 'trashed') then
    raise exception 'Este producto no se puede eliminar definitivamente en su estado actual.' using errcode = '55000', hint = 'invalid_state';
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
  -- 8. Borrado y auditoría A (+ nombre, para identificarlo en el aviso y el historial)
  select * into v_res from mobau_private.purge_product_rows(v_p.id);
  perform mobau_private.log_lifecycle_event(v_p.id, v_p.distributor_id, 'purge', v_state, null, v_uid, 'mobau', v_reason,
            v_res.purge_counts, v_res.purge_sha256, pg_catalog.jsonb_build_object('name', v_p.name));
  return pg_catalog.jsonb_build_object('ok', true, 'product_id', v_p.id, 'purged_counts', v_res.purge_counts);
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
  v_hold boolean;
  v_trashed_by text;
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
  select f.mobau_hold, f.trashed_by_kind into v_hold, v_trashed_by
    from mobau_private.product_lifecycle_flags(v_p.id, v_p.distributor_id) f;
  if v_open then v_blocks := v_blocks || 'open_proposal'::text; end if;
  if v_state = 'legacy_retired' then v_blocks := v_blocks || 'legacy_pending_review'::text; end if;
  if v_state in ('in_review', 'changes_requested') then v_blocks := v_blocks || 'in_review'::text; end if;
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
    'mobau_hold', v_hold,
    'trashed_by_kind', case when v_p.trashed_at is null then null else v_trashed_by end,
    'allowed_actions', pg_catalog.to_jsonb(mobau_private.product_allowed_actions(v_state, v_open, v_p.purge_after, 'mobau', v_hold, v_trashed_by)),
    'blocks', pg_catalog.to_jsonb(v_blocks),
    'references', v_refs,
    'events', coalesce((select pg_catalog.jsonb_agg(pg_catalog.jsonb_strip_nulls(pg_catalog.jsonb_build_object(
                          'action', e.action, 'from_state', e.from_state, 'to_state', e.to_state,
                          'actor_kind', e.actor_kind, 'actor_id', e.actor_id, 'reason', e.reason, 'created_at', e.created_at))
                          order by e.created_at desc, e.id desc)
                          from mobau_private.product_lifecycle_events e where e.product_id = v_p.id), '[]'::jsonb));
end;
$$;

create function public.mobau_lifecycle_history(p_product_id text default null)
returns table (
  product_id     text,
  product_name   text,
  distributor_id text,
  product_exists boolean,
  action         text,
  from_state     text,
  to_state       text,
  actor_kind     text,
  reason         text,
  created_at     timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
begin
  -- 41-07: historial mínimo para Mobau, también de productos ya eliminados.
  -- Con id: todos los eventos de ese id (de todos sus ciclos). Sin id: las 200
  -- eliminaciones definitivas más recientes. Sin uuids de actores ni recuentos.
  -- Nombre: el del ciclo de cada evento (ver my_product_lifecycle_events).
  if not mobau_private.product_lifecycle_enabled() then
    raise exception 'Esta acción todavía no está disponible.' using errcode = '55000', hint = 'feature_disabled';
  end if;
  perform mobau_private.assert_mobau_admin();
  if p_product_id is not null
     and (pg_catalog.btrim(p_product_id) = '' or pg_catalog.char_length(p_product_id) > 200) then
    raise exception 'Identificador de producto no válido.' using errcode = '22023', hint = 'invalid_parameter';
  end if;
  return query
    select e.product_id,
           coalesce(case when p.id is not null and p.distributor_id = e.distributor_id
                              and e.id > coalesce((select max(z.id) from mobau_private.product_lifecycle_events z
                                                    where z.product_id = e.product_id and z.action = 'purge'), 0)
                         then p.name end,
                    (select x.meta ->> 'name' from mobau_private.product_lifecycle_events x
                      where x.product_id = e.product_id and x.distributor_id = e.distributor_id
                        and x.action = 'purge' and x.id >= e.id
                      order by x.id
                      limit 1))::text,
           e.distributor_id, (p.id is not null),
           e.action, e.from_state, e.to_state, e.actor_kind, e.reason, e.created_at
      from mobau_private.product_lifecycle_events e
      left join public.products p on p.id = e.product_id
     where (p_product_id is not null and e.product_id = p_product_id)
        or (p_product_id is null and e.action = 'purge')
     order by e.created_at desc, e.id desc
     limit case when p_product_id is null then 200 end;
end;
$$;

-- La firma de 4 argumentos ya no la usa nadie.
drop function mobau_private.product_allowed_actions(text, boolean, timestamptz, text);

-- ---------- 6. permisos ----------
-- Funciones recreadas o nuevas: sin nada por defecto y EXECUTE solo para authenticated.
revoke all on function public.my_products_lifecycle() from public, anon, authenticated, service_role;
revoke all on function public.my_product_lifecycle_events(text) from public, anon, authenticated, service_role;
revoke all on function public.distributor_purge_product(text, text, timestamptz) from public, anon, authenticated, service_role;
revoke all on function public.mobau_lifecycle_history(text) from public, anon, authenticated, service_role;
grant execute on function public.my_products_lifecycle() to authenticated;
grant execute on function public.my_product_lifecycle_events(text) to authenticated;
grant execute on function public.distributor_purge_product(text, text, timestamptz) to authenticated;
grant execute on function public.mobau_lifecycle_history(text) to authenticated;
-- «Retirar sin papelera» deja de existir para el distribuidor.
revoke execute on function public.distributor_retire_product(text, text, timestamptz) from authenticated;

-- ---------- 7. validación final ----------
DO $post41_07$
declare
  f record;
begin
  for f in
    select * from (values
      ('public.my_products_lifecycle()', true),
      ('public.my_product_lifecycle_events(text)', true),
      ('public.distributor_trash_product(text, timestamp with time zone)', true),
      ('public.distributor_restore_product(text, timestamp with time zone)', true),
      ('public.distributor_purge_product(text, text, timestamp with time zone)', true),
      ('public.mobau_product_lifecycle(text, text, text, timestamp with time zone)', true),
      ('public.mobau_purge_product(text, text, text, boolean, timestamp with time zone)', true),
      ('public.mobau_product_references(text)', true),
      ('public.mobau_product_lifecycle_view(text)', true),
      ('public.mobau_lifecycle_history(text)', true),
      ('public.distributor_retire_product(text, text, timestamp with time zone)', false)
    ) as x(sig, granted)
  loop
    if to_regprocedure(f.sig) is null then
      raise exception '41-07: falta %', f.sig;
    end if;
    if not (select prosecdef from pg_proc where oid = to_regprocedure(f.sig))
       or not (select proconfig @> array['search_path=""'] from pg_proc where oid = to_regprocedure(f.sig))
       or (select proowner from pg_proc where oid = to_regprocedure(f.sig)) <> 'postgres'::regrole
       or (select proacl::text from pg_proc where oid = to_regprocedure(f.sig))
            is distinct from (case when f.granted then '{postgres=X/postgres,authenticated=X/postgres}' else '{postgres=X/postgres}' end)
       or has_function_privilege('anon', to_regprocedure(f.sig), 'EXECUTE')
       or has_function_privilege('service_role', to_regprocedure(f.sig), 'EXECUTE')
       or has_function_privilege('authenticated', to_regprocedure(f.sig), 'EXECUTE') <> f.granted then
      raise exception '41-07: % con propiedades o permisos inesperados', f.sig;
    end if;
  end loop;
  if to_regprocedure('mobau_private.product_allowed_actions(text, boolean, timestamp with time zone, text)') is not null then
    raise exception '41-07: queda la firma antigua de product_allowed_actions';
  end if;
  if (select count(*) from pg_proc where pronamespace = 'mobau_private'::regnamespace) <> 11
     or exists (select 1 from pg_proc p where p.pronamespace = 'mobau_private'::regnamespace
                 and (p.proacl is null or p.proacl::text <> '{postgres=X/postgres}'))
     or has_schema_privilege('anon', 'mobau_private', 'USAGE') or has_schema_privilege('authenticated', 'mobau_private', 'USAGE')
     or has_schema_privilege('service_role', 'mobau_private', 'USAGE') then
    raise exception '41-07: mobau_private con funciones o permisos inesperados';
  end if;
  -- reglas (solo si el interruptor está encendido; apagado devuelven {})
  if mobau_private.product_lifecycle_enabled() then
    if mobau_private.product_allowed_actions('published', false, null, 'distributor', false, null) <> array['trash']
       or mobau_private.product_allowed_actions('trashed', false, pg_catalog.now() + interval '1 day', 'distributor', false, 'distributor') <> array['restore', 'purge']
       or mobau_private.product_allowed_actions('trashed', false, pg_catalog.now() + interval '1 day', 'distributor', true, 'mobau') <> array['purge']
       or mobau_private.product_allowed_actions('trashed', false, null, 'distributor', false, 'distributor') <> array['restore', 'purge']
       or mobau_private.product_allowed_actions('trashed', false, pg_catalog.now() - interval '1 day', 'distributor', false, 'distributor') <> array['restore', 'purge']
       or mobau_private.product_allowed_actions('trashed', true, pg_catalog.now() + interval '1 day', 'distributor', false, 'distributor') <> array['restore']
       or mobau_private.product_allowed_actions('published', false, null, 'mobau', false, null) <> array['retire', 'purge']
       or mobau_private.product_allowed_actions('published', true, null, 'distributor', false, null) <> '{}'::text[] then
      raise exception '41-07: product_allowed_actions no devuelve las reglas esperadas';
    end if;
  end if;
  if (select count(*) from pg_policies where schemaname = 'public') <> 48 then
    raise exception '41-07: ha cambiado el número de políticas';
  end if;
  if pg_get_constraintdef((select oid from pg_constraint where conrelid = 'public.products'::regclass
                            and conname = 'products_lifecycle_trash_coherent')) like '%30 days%'
     or (select count(*) from pg_constraint where conrelid = 'public.products'::regclass and conname like 'products_lifecycle_%') <> 5 then
    raise exception '41-07: restricciones de papelera inesperadas';
  end if;
  raise notice '41-07 OK: Retirar → papelera sin caducidad; papelera del distribuidor; intervenciones e historial de Mobau.';
end $post41_07$;

COMMIT;
