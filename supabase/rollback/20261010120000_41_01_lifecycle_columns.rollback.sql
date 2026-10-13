-- ============================================================
-- PROPUESTA NO EJECUTADA (rollback 41-01) — no ejecutar sin aprobación explícita
-- ============================================================
-- Bloqueo previo como en 41-01 (lock_timeout 5 s; si no, 55P03 sin cambios).
-- Deshace 41-01 en orden inverso. Requiere que 41-02 esté revertida y que
-- no haya ningún dato de ciclo de vida (ninguna fila con columnas de 41 ni
-- eventos de auditoría). Transacción única.
--   0. Prechecks.
--   9→ snapshot_product_on_submit vuelve al cuerpo de 38-C 04 (MD5 1abaafb3ac360ee79f724a92e08a7e35).
--   8→ quita mobau_private.product_lifecycle_state.
--   7→ quita la tabla de auditoría (y su secuencia e índices).
--   6→ quita el esquema mobau_private (RESTRICT: falla si queda algo).
--   5→ quita índices y restricciones de 41.
--   4→ quita las 7 columnas.
--   2→ REVOKE SELECT de las 22 columnas a anon y authenticated.
--   1→ GRANT SELECT de tabla a anon y authenticated.
--  10→ Validación: ACL de products idéntica a la de antes de 41-01
--      ({postgres=arwdDxtm/postgres,anon=rxtm/postgres,authenticated=rxtm/postgres,service_role=arwdDxtm/postgres}), sin permisos por columna.
-- ============================================================

BEGIN;

-- ---------- bloqueo previo ----------
-- Piloto sin uso: si en 5 s no se obtiene el bloqueo exclusivo de products,
-- la transacción aborta (55P03 lock_not_available) sin cambiar nada.
set local lock_timeout = '5s';
lock table public.products in access exclusive mode;

DO $$
begin
  if current_user <> 'postgres' then
    raise exception 'rollback 41-01: ejecutar como postgres';
  end if;
  if to_regclass('public.catalog_products') is not null or to_regprocedure('public.catalog_version()') is not null
     or (select md5(prosrc) from pg_proc where oid = 'public.catalog_published_prices(text[], text, integer)'::regprocedure) is distinct from '38e5e597619fd290b2255e8d9c224453' then
    raise exception 'rollback 41-01: revertir antes 41-02';
  end if;
  if (select md5(prosrc) from pg_proc where oid = 'public.snapshot_product_on_submit()'::regprocedure) is distinct from 'c92b110bbe7d742854379ac64746b484' then
    raise exception 'rollback 41-01: snapshot_product_on_submit no es la de 41-01';
  end if;
  if exists (select 1 from public.products
              where retired_at is not null or retired_by is not null or retired_reason is not null or trashed_at is not null
                 or trashed_by is not null or trash_from is not null or purge_after is not null) then
    raise exception 'rollback 41-01: hay productos con datos de ciclo de vida; no se puede revertir';
  end if;
  if exists (select 1 from mobau_private.product_lifecycle_events) then
    raise exception 'rollback 41-01: hay eventos de ciclo de vida; no se puede revertir';
  end if;
  if (select count(*) from pg_proc where pronamespace = 'mobau_private'::regnamespace) <> 1
     or (select count(*) from pg_class where relnamespace = 'mobau_private'::regnamespace and relkind in ('r', 'v', 'm', 'p', 'f')) <> 1 then
    raise exception 'rollback 41-01: mobau_private contiene objetos que 41-01 no creó (aplicada alguna migración posterior)';
  end if;
end $$;

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
    select to_jsonb(p) into v_product from public.products p where p.id = new.product_id;
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

drop function mobau_private.product_lifecycle_state(text, timestamptz, timestamptz);
drop table mobau_private.product_lifecycle_events;
drop schema mobau_private;

drop index public.products_trashed_idx;
drop index public.products_retired_idx;
alter table public.products
  drop constraint products_lifecycle_trash_coherent,
  drop constraint products_lifecycle_trash_fields,
  drop constraint products_lifecycle_retired_fields,
  drop constraint products_lifecycle_retired_archived,
  drop constraint products_lifecycle_published_clean;
alter table public.products
  drop column purge_after,
  drop column trash_from,
  drop column trashed_by,
  drop column trashed_at,
  drop column retired_reason,
  drop column retired_by,
  drop column retired_at;

revoke select (id, name, distributor_id, brand, category_id, subcategory,
              use_context, space, availability, description, measurements, materials,
              finishes, lead_time, icon, technical_sheet_url, cad_bim_3d_url, image_url,
              created_at, status, updated_at, publication_status)
  on table public.products from anon, authenticated;
grant select on table public.products to anon, authenticated;

DO $$
begin
  if (select relacl::text from pg_class where oid = 'public.products'::regclass) is distinct from '{postgres=arwdDxtm/postgres,anon=rxtm/postgres,authenticated=rxtm/postgres,service_role=arwdDxtm/postgres}' then
    raise exception 'rollback 41-01: la ACL de products no ha vuelto a la de antes';
  end if;
  if exists (select 1 from pg_attribute where attrelid = 'public.products'::regclass and attnum > 0 and coalesce(cardinality(attacl), 0) > 0) then
    raise exception 'rollback 41-01: quedan permisos por columna';
  end if;
  if (select string_agg(attname, ',' order by attnum) from pg_attribute
       where attrelid = 'public.products'::regclass and attnum > 0 and not attisdropped) is distinct from 'id,name,distributor_id,brand,category_id,subcategory,use_context,space,availability,description,measurements,materials,finishes,lead_time,icon,technical_sheet_url,cad_bim_3d_url,image_url,created_at,status,updated_at,publication_status' then
    raise exception 'rollback 41-01: columnas de products inesperadas';
  end if;
  if to_regnamespace('mobau_private') is not null
     or exists (select 1 from pg_constraint where conrelid = 'public.products'::regclass and conname like 'products_lifecycle_%') then
    raise exception 'rollback 41-01: quedan objetos de 41';
  end if;
  if (select md5(prosrc) from pg_proc where oid = 'public.snapshot_product_on_submit()'::regprocedure) is distinct from '1abaafb3ac360ee79f724a92e08a7e35'
     or (select proacl::text from pg_proc where oid = 'public.snapshot_product_on_submit()'::regprocedure) is distinct from '{postgres=X/postgres,service_role=X/postgres}' then
    raise exception 'rollback 41-01: snapshot_product_on_submit no ha vuelto a la de 38-C 04';
  end if;
  if (select count(*) from pg_policies where schemaname = 'public') <> 48 then
    raise exception 'rollback 41-01: ha cambiado el número de políticas';
  end if;
  raise notice 'rollback 41-01 OK: products vuelve a SELECT de tabla y 22 columnas.';
end $$;

COMMIT;
