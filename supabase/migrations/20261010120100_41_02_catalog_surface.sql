-- ============================================================
-- PROPUESTA NO EJECUTADA (41-02) — no ejecutar sin aprobación explícita
-- ============================================================
-- 41 · 02 · Superficie pública del catálogo
-- ------------------------------------------------------------
-- Requiere 41-01. Transacción única. Orden:
--   0. Prechecks.
--   1. Vista public.catalog_products (security_invoker, security_barrier):
--      las 21 columnas de PRODUCT_COLUMNS (script.js) de los productos
--      publicados y activos. Se evalúa con los permisos y la RLS de quien
--      consulta: solo usa columnas que anon y authenticated ya pueden leer
--      (las 21 + publication_status). NO puede usar columnas de ciclo de vida
--      (anon no tiene permiso): la garantía de que un publicado no está
--      retirado ni en papelera la dan las CHECK de 41-01.
--      SELECT solo a anon y authenticated (se retiran los privilegios por
--      defecto de Supabase, incluidos INSERT/UPDATE/DELETE de vista).
--   2. public.catalog_version(): SECURITY INVOKER, STABLE, search_path vacío;
--      md5 de id:updated_at de catalog_products + categorías + distribuidores
--      (las columnas que cachea el catálogo). EXECUTE a anon y authenticated.
--   3. catalog_published_prices: misma firma, mismas columnas y misma ACL;
--      solo añade defensa redundante (activo, no retirado, no en papelera).
--   4. Validación final.
-- No cambia: products, permisos de products, políticas (48), datos.
-- Rollback: supabase/rollback/20261010120100_41_02_catalog_surface.rollback.sql (antes, revertir la interfaz
-- que use la vista: paso del plan, no comprobable desde la base de datos).
-- ============================================================

BEGIN;

-- Ventana V2: no esperar más de 5 s a bloqueos ajenos (aborta con 55P03 sin
-- cambios) e impedir escrituras concurrentes en products y product_prices
-- mientras se crea y se valida la superficie. Las lecturas siguen.
set local lock_timeout = '5s';
lock table public.products, public.product_prices in share mode;

-- ---------- 0. prechecks ----------
DO $$
begin
  if current_user <> 'postgres' then
    raise exception '41-02: ejecutar como postgres';
  end if;
  if to_regnamespace('mobau_private') is null
     or (select count(*) from pg_attribute where attrelid = 'public.products'::regclass and attname in ('retired_at', 'trashed_at') and not attisdropped) <> 2
     or (select md5(prosrc) from pg_proc where oid = 'public.snapshot_product_on_submit()'::regprocedure) is distinct from 'c92b110bbe7d742854379ac64746b484'
     or (select relacl::text from pg_class where oid = 'public.products'::regclass) is distinct from '{postgres=arwdDxtm/postgres,anon=xtm/postgres,authenticated=xtm/postgres,service_role=arwdDxtm/postgres}' then
    raise exception '41-02: falta 41-01';
  end if;
  if (select md5(prosrc) from pg_proc where oid = 'public.catalog_published_prices(text[], text, integer)'::regprocedure) is distinct from '38e5e597619fd290b2255e8d9c224453'
     or (select proacl::text from pg_proc where oid = 'public.catalog_published_prices(text[], text, integer)'::regprocedure) is distinct from '{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}' then
    raise exception '41-02: catalog_published_prices no es la de 39-05 (cuerpo o permisos)';
  end if;
  if to_regclass('public.catalog_products') is not null or to_regprocedure('public.catalog_version()') is not null then
    raise exception '41-02: catalog_products o catalog_version ya existen';
  end if;
  if (select count(*) from pg_policies where schemaname = 'public') <> 48 then
    raise exception '41-02: se esperaban 48 políticas en public';
  end if;
end $$;

-- ---------- 1. vista pública ----------
create view public.catalog_products
  with (security_invoker = true, security_barrier = true)
as
select p.id, p.name, p.brand, p.distributor_id, p.category_id, p.subcategory, p.use_context,
       p.space, p.availability, p.description, p.measurements, p.materials, p.finishes, p.lead_time,
       p.icon, p.image_url, p.technical_sheet_url, p.cad_bim_3d_url, p.status, p.created_at, p.updated_at
  from public.products p
 where p.publication_status = 'published'
   and p.status = 'active';

comment on view public.catalog_products is
  '41-02: catálogo público (publicado y activo), 21 columnas de PRODUCT_COLUMNS. security_invoker: RLS y permisos de quien consulta. Solo SELECT para anon y authenticated.';
revoke all on table public.catalog_products from public, anon, authenticated, service_role;
grant select on table public.catalog_products to anon, authenticated;

-- ---------- 2. sello del catálogo ----------
create function public.catalog_version()
returns text
language sql
stable
security invoker
set search_path = ''
as $$
  select pg_catalog.md5(
           coalesce((select pg_catalog.string_agg(c.id || ':' || (extract(epoch from c.updated_at))::text, '|' order by c.id)
                       from public.catalog_products c), '')
           || '#' ||
           coalesce((select pg_catalog.string_agg(pg_catalog.concat_ws(':', k.id, k.name, k.subcategories::text), '|' order by k.id)
                       from public.categories k), '')
           || '#' ||
           coalesce((select pg_catalog.string_agg(pg_catalog.concat_ws(':', d.id, d.name, d.location, d.description, d.categories::text,
                                                                      d.contact_email, d.contact_phone, d.website,
                                                                      (extract(epoch from d.created_at))::text), '|' order by d.id)
                       from public.distributors d), '')
         )
$$;
comment on function public.catalog_version() is
  '41-02: sello (md5) de los datos públicos del catálogo. SECURITY INVOKER: solo ve lo que ya ve quien llama. anon y authenticated.';
revoke all on function public.catalog_version() from public, anon, authenticated, service_role;
grant execute on function public.catalog_version() to anon, authenticated;

-- ---------- 3. precios: defensa redundante ----------
-- create or replace conserva la ACL ({postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}).
create or replace function public.catalog_published_prices(
  p_product_ids text[]  default null,
  p_after       text    default null,
  p_limit       integer default 1000
)
returns table (
  product_id     text,
  price_amount   numeric,
  currency       text,
  price_status   text,
  includes_itbis boolean,
  itbis_rate     numeric,
  es_demo        boolean
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if (select auth.uid()) is null then
    raise exception 'Inicia sesión para consultar precios.' using errcode = '42501';
  end if;
  if p_limit is null or p_limit < 1 or p_limit > 1000 then
    raise exception 'p_limit debe estar entre 1 y 1000.' using errcode = '22023';
  end if;
  if p_product_ids is not null and pg_catalog.cardinality(p_product_ids) > 200 then
    raise exception 'Como máximo 200 productos por consulta.' using errcode = '22023';
  end if;
  if p_after is not null and pg_catalog.char_length(p_after) > 200 then
    raise exception 'p_after no puede superar 200 caracteres.'
      using errcode = '22023';
  end if;

  return query
    select pp.product_id,
           case when pp.price_status = 'published' then pp.price_amount end,
           pp.currency,
           pp.price_status,
           pp.includes_itbis,
           pp.itbis_rate,
           coalesce(pp.price_source = 'demo', false)
      from public.product_prices pp
      join public.products p on p.id = pp.product_id
     where p.publication_status = 'published'
       -- 41-02: defensa redundante (las CHECK de 41-01 y el espejo de status ya
       -- lo garantizan): nunca un producto inactivo, retirado o en papelera.
       and p.status = 'active'
       and p.retired_at is null
       and p.trashed_at is null
       and pp.price_status in ('published', 'quote_required', 'pending_confirmation', 'unavailable')
       and (p_product_ids is null or pp.product_id = any (p_product_ids))
       and (p_after is null or pp.product_id > p_after)
     order by pp.product_id
     limit p_limit;
end;
$$;

-- ---------- 4. validación final ----------
DO $$
declare
  v constant regclass := 'public.catalog_products'::regclass;
  f_ver constant regprocedure := 'public.catalog_version()'::regprocedure;
  f_cpp constant regprocedure := 'public.catalog_published_prices(text[], text, integer)'::regprocedure;
begin
  if (select relkind from pg_class where oid = v) <> 'v'
     or not (select reloptions @> array['security_invoker=true', 'security_barrier=true'] from pg_class where oid = v)
     or (select relacl::text from pg_class where oid = v) is distinct from '{postgres=arwdDxtm/postgres,anon=r/postgres,authenticated=r/postgres}' then
    raise exception '41-02: catalog_products con opciones o permisos inesperados';
  end if;
  if (select string_agg(attname, ',' order by attnum) from pg_attribute where attrelid = v and attnum > 0 and not attisdropped)
     is distinct from 'id,name,brand,distributor_id,category_id,subcategory,use_context,space,availability,description,measurements,materials,finishes,lead_time,icon,image_url,technical_sheet_url,cad_bim_3d_url,status,created_at,updated_at' then
    raise exception '41-02: catalog_products no tiene exactamente las 21 columnas';
  end if;
  if has_table_privilege('service_role', v, 'SELECT')
     or exists (select 1 from unnest(array['anon', 'authenticated']) g, unnest(array['INSERT', 'UPDATE', 'DELETE', 'TRUNCATE']) p
                 where has_table_privilege(g, v, p)) then
    raise exception '41-02: catalog_products con privilegios de más';
  end if;
  if (select count(*) from public.catalog_products)
     <> (select count(*) from public.products where publication_status = 'published' and status = 'active') then
    raise exception '41-02: catalog_products no coincide con los productos publicados y activos';
  end if;
  if (select md5(prosrc) from pg_proc where oid = f_ver) is distinct from '1d238bb104658d9179dfc1564db0d7f9'
     or (select prosecdef or provolatile <> 's' or not (proconfig @> array['search_path=""']) from pg_proc where oid = f_ver)
     or not has_function_privilege('anon', f_ver, 'EXECUTE') or not has_function_privilege('authenticated', f_ver, 'EXECUTE')
     or has_function_privilege('service_role', f_ver, 'EXECUTE')
     or exists (select 1 from pg_proc, aclexplode(proacl) a where oid = f_ver and a.grantee = 0) then
    raise exception '41-02: catalog_version con definición o permisos inesperados';
  end if;
  if public.catalog_version() !~ '^[0-9a-f]{32}$' then
    raise exception '41-02: catalog_version no devuelve un md5';
  end if;
  if (select md5(prosrc) from pg_proc where oid = f_cpp) is distinct from '366f275cf85ec6c10956cecfbbc92ed5'
     or (select proacl::text from pg_proc where oid = f_cpp) is distinct from '{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}'
     or not (select prosecdef and proconfig @> array['search_path=""'] from pg_proc where oid = f_cpp) then
    raise exception '41-02: catalog_published_prices con definición o permisos inesperados';
  end if;
  if (select count(*) from pg_policies where schemaname = 'public') <> 48 then
    raise exception '41-02: ha cambiado el número de políticas';
  end if;
  raise notice '41-02 OK: catalog_products, catalog_version y defensa de precios.';
end $$;

COMMIT;
