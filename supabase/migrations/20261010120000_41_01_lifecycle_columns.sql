-- ============================================================
-- PROPUESTA NO EJECUTADA (41-01) — no ejecutar sin aprobación explícita
-- ============================================================
-- 41 · 01 · Ciclo de vida de productos: permisos por columna, columnas
--           nuevas, esquema privado, auditoría y copia de envío
-- ------------------------------------------------------------
-- Requiere 40-01 (20261008120000). TRANSACCIÓN ÚNICA: todo entre BEGIN y
-- COMMIT; si cualquier paso o comprobación falla, no queda nada.
--
-- Orden exacto (opción A):
--   ·  Bloqueo: lock_timeout 5 s y LOCK TABLE products (ACCESS EXCLUSIVE) antes
--      de todo; si no se obtiene (piloto en uso), aborta con 55P03 sin cambios.
--   0. Prechecks: estado de partida exacto (ACL de products, columnas,
--      funciones, políticas, propuestas abiertas); si algo difiere, aborta.
--   1. REVOKE SELECT de TABLA sobre public.products a anon y authenticated.
--      Va ANTES del paso 2 porque revocar un privilegio de tabla revoca
--      también ese privilegio en todas las columnas. Solo SELECT:
--      REFERENCES, TRIGGER y MAINTAIN de tabla quedan como están.
--   2. GRANT SELECT de las 22 columnas actuales, por nombre, a anon y
--      authenticated (las mismas lecturas que hoy, ahora por columna).
--   3. Comprobación intermedia: 22 columnas legibles, ningún SELECT de tabla.
--   4. ADD COLUMN de las 7 columnas de ciclo de vida (nullable, sin valor por
--      defecto: no reescribe la tabla). NINGÚN permiso de cliente.
--   5. CHECK de coherencia (5) e índices parciales (2).
--   6. Esquema mobau_private, sin USAGE para ningún rol cliente.
--   7. Tabla mobau_private.product_lifecycle_events (sin permisos de
--      cliente; RLS activada y sin políticas).
--   8. mobau_private.product_lifecycle_state(…), IMMUTABLE, sin EXECUTE de
--      cliente.
--   9. public.snapshot_product_on_submit(): la copia del envío pasa de
--      to_jsonb(p) (fila completa) a una lista explícita de las 22 columnas.
--      Es un trigger con permisos de quien envía: sin este paso, tras el
--      paso 1 un distribuidor no podría enviar una propuesta de cambio
--      (42501). Mismas claves en la copia que antes.
--  10. Validación final.
--
-- No cambia: datos (las 7 columnas quedan nulas en todas las filas),
-- políticas (48), escrituras de cliente (cerradas desde 38-B), service_role
-- (conserva SELECT de tabla, como hoy), moderate_product_proposal,
-- catalog_published_prices.
-- Rollback (orden inverso): supabase/rollback/20261010120000_41_01_lifecycle_columns.rollback.sql
-- ============================================================

BEGIN;

-- ---------- bloqueo previo ----------
-- Piloto sin uso: si en 5 s no se obtiene el bloqueo exclusivo de products,
-- la transacción aborta (55P03 lock_not_available) sin cambiar nada.
set local lock_timeout = '5s';
lock table public.products in access exclusive mode;

-- ---------- 0. prechecks ----------
DO $$
begin
  if current_user <> 'postgres' then
    raise exception '41-01: ejecutar como postgres';
  end if;
  if not exists (select 1 from supabase_migrations.schema_migrations where version = '20261008120000') then
    raise exception '41-01: falta 40-01 (20261008120000)';
  end if;
  if (select md5(prosrc) from pg_proc where oid = 'public.moderate_product_proposal(uuid, text, text, integer)'::regprocedure)
     is distinct from 'e814b477d0e078872ad085e00157c2c2' then
    raise exception '41-01: moderate_product_proposal no es la de 40-01';
  end if;
  if (select md5(prosrc) from pg_proc where oid = 'public.snapshot_product_on_submit()'::regprocedure) is distinct from '1abaafb3ac360ee79f724a92e08a7e35'
     or (select proacl::text from pg_proc where oid = 'public.snapshot_product_on_submit()'::regprocedure) is distinct from '{postgres=X/postgres,service_role=X/postgres}' then
    raise exception '41-01: snapshot_product_on_submit no es la esperada (cuerpo o permisos)';
  end if;
  if (select md5(prosrc) from pg_proc where oid = 'public.catalog_published_prices(text[], text, integer)'::regprocedure)
     is distinct from '38e5e597619fd290b2255e8d9c224453' then
    raise exception '41-01: catalog_published_prices no es la de 39-05';
  end if;
  if (select string_agg(attname, ',' order by attnum) from pg_attribute
       where attrelid = 'public.products'::regclass and attnum > 0 and not attisdropped)
     is distinct from 'id,name,distributor_id,brand,category_id,subcategory,use_context,space,availability,description,measurements,materials,finishes,lead_time,icon,technical_sheet_url,cad_bim_3d_url,image_url,created_at,status,updated_at,publication_status' then
    raise exception '41-01: las columnas de products no son las 22 esperadas';
  end if;
  if (select relacl::text from pg_class where oid = 'public.products'::regclass) is distinct from '{postgres=arwdDxtm/postgres,anon=rxtm/postgres,authenticated=rxtm/postgres,service_role=arwdDxtm/postgres}' then
    raise exception '41-01: la ACL de products no es la esperada';
  end if;
  if exists (select 1 from pg_attribute where attrelid = 'public.products'::regclass and attnum > 0 and attacl is not null) then
    raise exception '41-01: products ya tiene permisos por columna';
  end if;
  if to_regnamespace('mobau_private') is not null then
    raise exception '41-01: el esquema mobau_private ya existe';
  end if;
  if exists (select 1 from pg_constraint where conrelid = 'public.products'::regclass and conname like 'products_lifecycle_%')
     or to_regclass('public.products_retired_idx') is not null or to_regclass('public.products_trashed_idx') is not null then
    raise exception '41-01: ya existen restricciones o índices de 41';
  end if;
  if exists (select 1 from public.product_proposals where status in ('draft', 'submitted', 'changes_requested')) then
    raise exception '41-01: hay propuestas abiertas';
  end if;
  if exists (select 1 from public.mobau_moderation_context) then
    raise exception '41-01: el contexto de moderación no está vacío';
  end if;
  if (select count(*) from pg_policies where schemaname = 'public') <> 48 then
    raise exception '41-01: se esperaban 48 políticas en public';
  end if;
end $$;

-- ---------- 1. sin SELECT de tabla para anon y authenticated ----------
revoke select on table public.products from anon, authenticated;

-- ---------- 2. SELECT de las 22 columnas actuales, por nombre ----------
grant select (id, name, distributor_id, brand, category_id, subcategory,
              use_context, space, availability, description, measurements, materials,
              finishes, lead_time, icon, technical_sheet_url, cad_bim_3d_url, image_url,
              created_at, status, updated_at, publication_status)
  on table public.products to anon, authenticated;

-- ---------- 3. comprobación intermedia ----------
DO $$
begin
  if has_table_privilege('anon', 'public.products', 'SELECT') or has_table_privilege('authenticated', 'public.products', 'SELECT') then
    raise exception '41-01 paso 3: queda SELECT de tabla';
  end if;
  if (select count(*) from unnest(array['id', 'name', 'distributor_id', 'brand', 'category_id', 'subcategory', 'use_context', 'space', 'availability', 'description', 'measurements', 'materials', 'finishes', 'lead_time', 'icon', 'technical_sheet_url', 'cad_bim_3d_url', 'image_url', 'created_at', 'status', 'updated_at', 'publication_status']) c, unnest(array['anon', 'authenticated']) g
       where has_column_privilege(g, 'public.products', c, 'SELECT')) <> 44 then
    raise exception '41-01 paso 3: no son legibles las 22 columnas para anon y authenticated';
  end if;
end $$;

-- ---------- 4. columnas de ciclo de vida (sin permisos de cliente) ----------
alter table public.products
  add column retired_at     timestamptz,
  add column retired_by     uuid,
  add column retired_reason text,
  add column trashed_at     timestamptz,
  add column trashed_by     uuid,
  add column trash_from     text,
  add column purge_after    timestamptz;

comment on column public.products.retired_at is '41-01: retirada del catálogo. Sin permiso de lectura para anon ni authenticated.';
comment on column public.products.retired_by is '41-01: usuario que retiró. Nunca legible por clientes.';
comment on column public.products.retired_reason is '41-01: motivo de la retirada (1–500). Solo vía funciones de 41.';
comment on column public.products.trashed_at is '41-01: entrada en la papelera.';
comment on column public.products.trashed_by is '41-01: usuario que movió a la papelera. Nunca legible por clientes.';
comment on column public.products.trash_from is '41-01: estado de origen en la papelera (retired | draft).';
comment on column public.products.purge_after is '41-01: trashed_at + 30 días.';

-- ---------- 5. coherencia e índices ----------
alter table public.products
  add constraint products_lifecycle_published_clean
    check (publication_status <> 'published' or (retired_at is null and trashed_at is null)),
  add constraint products_lifecycle_retired_archived
    check (retired_at is null or publication_status = 'archived'),
  add constraint products_lifecycle_retired_fields
    check ((retired_at is null and retired_by is null and retired_reason is null)
        or (retired_at is not null and retired_by is not null and retired_reason is not null
            and char_length(btrim(retired_reason)) >= 1 and char_length(retired_reason) <= 500)),
  add constraint products_lifecycle_trash_fields
    check ((trashed_at is null and trashed_by is null and trash_from is null and purge_after is null)
        or (trashed_at is not null and trashed_by is not null and trash_from is not null and purge_after is not null)),
  add constraint products_lifecycle_trash_coherent
    check (trashed_at is null
        or (publication_status <> 'published' and trash_from in ('retired', 'draft')
            and purge_after = trashed_at + interval '30 days'));

create index products_retired_idx on public.products (distributor_id) where retired_at is not null;
create index products_trashed_idx on public.products (purge_after) where trashed_at is not null;

-- ---------- 6. esquema privado ----------
create schema mobau_private authorization postgres;
revoke all on schema mobau_private from public, anon, authenticated, service_role;
comment on schema mobau_private is
  '41-01: auxiliares, auditoría e interruptor del ciclo de vida. No expuesto por la API; sin USAGE para roles cliente.';

-- ---------- 7. auditoría ----------
create table mobau_private.product_lifecycle_events (
  id             bigint generated always as identity primary key,
  product_id     text not null,
  distributor_id text not null,
  action         text not null,
  from_state     text,
  to_state       text,
  actor_id       uuid,
  actor_kind     text not null,
  reason         text,
  purge_counts   jsonb,
  purge_sha256   text,
  meta           jsonb,
  created_at     timestamptz not null default now(),
  constraint product_lifecycle_events_action_check check (action in ('retire', 'republish', 'trash', 'restore', 'purge')),
  constraint product_lifecycle_events_actor_kind_check check (actor_kind in ('distributor', 'mobau'))
);
comment on table mobau_private.product_lifecycle_events is
  '41-01: auditoría del ciclo de vida (sin FK: sobrevive a la purga). Sin permisos de cliente; solo funciones de 41.';
create index product_lifecycle_events_product_idx on mobau_private.product_lifecycle_events (product_id, created_at);
create index product_lifecycle_events_recent_idx on mobau_private.product_lifecycle_events (action, created_at desc);
create index product_lifecycle_events_distributor_idx on mobau_private.product_lifecycle_events (distributor_id, product_id, created_at desc);
alter table mobau_private.product_lifecycle_events enable row level security;
revoke all on table mobau_private.product_lifecycle_events from public, anon, authenticated, service_role;
revoke all on sequence mobau_private.product_lifecycle_events_id_seq from public, anon, authenticated, service_role;

-- ---------- 8. estado lógico (origen único) ----------
create function mobau_private.product_lifecycle_state(
  p_publication_status text,
  p_retired_at         timestamptz,
  p_trashed_at         timestamptz
)
returns text
language sql
immutable
parallel safe
set search_path = ''
as $$
  select case
           when p_trashed_at is not null then 'trashed'
           when p_publication_status = 'published' then 'published'
           when p_publication_status = 'archived' and p_retired_at is not null then 'retired'
           when p_publication_status = 'archived' then 'legacy_retired'
           when p_publication_status in ('draft', 'in_review', 'changes_requested') then p_publication_status
         end
$$;
comment on function mobau_private.product_lifecycle_state(text, timestamptz, timestamptz) is
  '41-01: published | retired | legacy_retired | trashed | draft | in_review | changes_requested. Sin EXECUTE de cliente.';
revoke all on function mobau_private.product_lifecycle_state(text, timestamptz, timestamptz) from public, anon, authenticated, service_role;

-- ---------- 9. copia del envío con lista explícita ----------
-- create or replace conserva los permisos ({postgres=X/postgres,service_role=X/postgres}).
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

-- ---------- 10. validación final ----------
DO $$
declare
  ns constant regnamespace := 'mobau_private'::regnamespace;
  f_state constant regprocedure := 'mobau_private.product_lifecycle_state(text, timestamptz, timestamptz)'::regprocedure;
  f_snap constant regprocedure := 'public.snapshot_product_on_submit()'::regprocedure;
  t_ev constant regclass := 'mobau_private.product_lifecycle_events'::regclass;
begin
  -- products: permisos
  if (select relacl::text from pg_class where oid = 'public.products'::regclass) is distinct from '{postgres=arwdDxtm/postgres,anon=xtm/postgres,authenticated=xtm/postgres,service_role=arwdDxtm/postgres}' then
    raise exception '41-01: ACL de tabla de products inesperada';
  end if;
  if (select count(*) from unnest(array['id', 'name', 'distributor_id', 'brand', 'category_id', 'subcategory', 'use_context', 'space', 'availability', 'description', 'measurements', 'materials', 'finishes', 'lead_time', 'icon', 'technical_sheet_url', 'cad_bim_3d_url', 'image_url', 'created_at', 'status', 'updated_at', 'publication_status']) c, unnest(array['anon', 'authenticated']) g
       where has_column_privilege(g, 'public.products', c, 'SELECT')) <> 44
     or exists (select 1 from pg_attribute t, aclexplode(t.attacl) a
                 where t.attrelid = 'public.products'::regclass
                   and not (a.grantee in ('anon'::regrole, 'authenticated'::regrole) and a.privilege_type = 'SELECT'
                            and t.attname = any (array['id', 'name', 'distributor_id', 'brand', 'category_id', 'subcategory', 'use_context', 'space', 'availability', 'description', 'measurements', 'materials', 'finishes', 'lead_time', 'icon', 'technical_sheet_url', 'cad_bim_3d_url', 'image_url', 'created_at', 'status', 'updated_at', 'publication_status']))) then
    raise exception '41-01: permisos por columna inesperados en las 22 columnas';
  end if;
  if exists (select 1 from unnest(array['retired_at', 'retired_by', 'retired_reason', 'trashed_at', 'trashed_by', 'trash_from', 'purge_after']) c, unnest(array['anon', 'authenticated']) g
              where has_column_privilege(g, 'public.products', c, 'SELECT')
                 or has_column_privilege(g, 'public.products', c, 'INSERT')
                 or has_column_privilege(g, 'public.products', c, 'UPDATE'))
     or exists (select 1 from pg_attribute where attrelid = 'public.products'::regclass and attname = any (array['retired_at', 'retired_by', 'retired_reason', 'trashed_at', 'trashed_by', 'trash_from', 'purge_after']) and attacl is not null) then
    raise exception '41-01: alguna columna nueva tiene permisos de cliente';
  end if;
  if exists (select 1 from unnest(array['anon', 'authenticated']) g, unnest(array['SELECT', 'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE']) p
              where has_table_privilege(g, 'public.products', p))
     or has_any_column_privilege('anon', 'public.products', 'INSERT') or has_any_column_privilege('anon', 'public.products', 'UPDATE')
     or has_any_column_privilege('authenticated', 'public.products', 'INSERT') or has_any_column_privilege('authenticated', 'public.products', 'UPDATE') then
    raise exception '41-01: anon o authenticated tienen privilegios de tabla o de escritura inesperados';
  end if;
  -- products: columnas, datos y restricciones
  if (select string_agg(attname, ',' order by attnum) from pg_attribute
       where attrelid = 'public.products'::regclass and attnum > 0 and not attisdropped)
     is distinct from 'id,name,distributor_id,brand,category_id,subcategory,use_context,space,availability,description,measurements,materials,finishes,lead_time,icon,technical_sheet_url,cad_bim_3d_url,image_url,created_at,status,updated_at,publication_status,retired_at,retired_by,retired_reason,trashed_at,trashed_by,trash_from,purge_after' then
    raise exception '41-01: columnas de products inesperadas';
  end if;
  if exists (select 1 from public.products
              where retired_at is not null or retired_by is not null or retired_reason is not null or trashed_at is not null
                 or trashed_by is not null or trash_from is not null or purge_after is not null) then
    raise exception '41-01: alguna fila tiene datos de ciclo de vida';
  end if;
  if (select count(*) from pg_constraint where conrelid = 'public.products'::regclass and conname like 'products_lifecycle_%' and convalidated) <> 5
     or to_regclass('public.products_retired_idx') is null or to_regclass('public.products_trashed_idx') is null then
    raise exception '41-01: faltan restricciones o índices';
  end if;
  -- esquema privado
  if has_schema_privilege('anon', ns, 'USAGE') or has_schema_privilege('authenticated', ns, 'USAGE')
     or has_schema_privilege('service_role', ns, 'USAGE')
     or exists (select 1 from pg_namespace n, aclexplode(n.nspacl) a where n.oid = ns and a.grantee <> 'postgres'::regrole) then
    raise exception '41-01: mobau_private accesible para algún rol cliente';
  end if;
  if exists (select 1 from unnest(array['anon', 'authenticated', 'service_role']) g, unnest(array['SELECT', 'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE']) p
              where has_table_privilege(g, t_ev, p))
     or not (select relrowsecurity from pg_class where oid = t_ev)
     or exists (select 1 from pg_policies where schemaname = 'mobau_private')
     or exists (select 1 from mobau_private.product_lifecycle_events) then
    raise exception '41-01: tabla de auditoría con permisos, sin RLS, con políticas o con filas';
  end if;
  if exists (select 1 from unnest(array['anon', 'authenticated', 'service_role']) g, unnest(array['USAGE', 'SELECT', 'UPDATE']) p
              where has_sequence_privilege(g, 'mobau_private.product_lifecycle_events_id_seq', p)) then
    raise exception '41-01: secuencia de auditoría con permisos de cliente';
  end if;
  -- funciones
  if (select md5(prosrc) from pg_proc where oid = f_state) is distinct from '199586f7d19826b0d4338672f0560244'
     or (select prosecdef or provolatile <> 'i' or not (proconfig @> array['search_path=""']) or proowner <> 'postgres'::regrole from pg_proc where oid = f_state)
     or has_function_privilege('anon', f_state, 'EXECUTE') or has_function_privilege('authenticated', f_state, 'EXECUTE')
     or has_function_privilege('service_role', f_state, 'EXECUTE')
     or exists (select 1 from pg_proc, aclexplode(proacl) a where oid = f_state and a.grantee <> 'postgres'::regrole) then
    raise exception '41-01: product_lifecycle_state con definición o permisos inesperados';
  end if;
  if (select count(*) from pg_proc where pronamespace = ns) <> 1 then
    raise exception '41-01: mobau_private debe tener una sola función';
  end if;
  if (select md5(prosrc) from pg_proc where oid = f_snap) is distinct from 'c92b110bbe7d742854379ac64746b484'
     or (select proacl::text from pg_proc where oid = f_snap) is distinct from '{postgres=X/postgres,service_role=X/postgres}'
     or (select prosecdef from pg_proc where oid = f_snap)
     or not (select proconfig @> array['search_path=""'] from pg_proc where oid = f_snap) then
    raise exception '41-01: snapshot_product_on_submit con definición o permisos inesperados';
  end if;
  if (select md5(prosrc) from pg_proc where oid = 'public.moderate_product_proposal(uuid, text, text, integer)'::regprocedure) is distinct from 'e814b477d0e078872ad085e00157c2c2'
     or (select md5(prosrc) from pg_proc where oid = 'public.catalog_published_prices(text[], text, integer)'::regprocedure) is distinct from '38e5e597619fd290b2255e8d9c224453' then
    raise exception '41-01: ha cambiado una función que no debía cambiar';
  end if;
  if (select count(*) from pg_policies where schemaname = 'public') <> 48 then
    raise exception '41-01: ha cambiado el número de políticas';
  end if;
  raise notice '41-01 OK: SELECT por columna (22), 7 columnas sin permisos de cliente, mobau_private cerrado, copia de envío explícita.';
end $$;

COMMIT;
