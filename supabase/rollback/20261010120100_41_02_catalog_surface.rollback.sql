-- ============================================================
-- PROPUESTA NO EJECUTADA (rollback 41-02) — no ejecutar sin aprobación explícita
-- ============================================================
-- PASO PREVIO (fuera de la base de datos): si la interfaz UI-L (que lee
-- catalog_products y catalog_version) está servida, revertirla ANTES y
-- comprobar el SHA servido. Quitar la vista con UI-L servida rompe el catálogo.
-- Orden inverso a 41-02:
--   3→ catalog_published_prices vuelve al cuerpo de 39-05 (MD5 38e5e597619fd290b2255e8d9c224453; ACL igual).
--   2→ quita catalog_version().
--   1→ quita la vista catalog_products.
-- ============================================================

BEGIN;

-- Ventana V2: no esperar más de 5 s a bloqueos ajenos (aborta con 55P03 sin
-- cambios) e impedir escrituras concurrentes en products y product_prices
-- mientras se retira y se valida la superficie. Las lecturas siguen.
set local lock_timeout = '5s';
lock table public.products, public.product_prices in share mode;

DO $$
begin
  if current_user <> 'postgres' then
    raise exception 'rollback 41-02: ejecutar como postgres';
  end if;
  if to_regclass('public.catalog_products') is null or to_regprocedure('public.catalog_version()') is null
     or (select md5(prosrc) from pg_proc where oid = 'public.catalog_published_prices(text[], text, integer)'::regprocedure) is distinct from '366f275cf85ec6c10956cecfbbc92ed5' then
    raise exception 'rollback 41-02: 41-02 no está aplicada tal como se espera';
  end if;
end $$;

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
       and pp.price_status in ('published', 'quote_required', 'pending_confirmation', 'unavailable')
       and (p_product_ids is null or pp.product_id = any (p_product_ids))
       and (p_after is null or pp.product_id > p_after)
     order by pp.product_id
     limit p_limit;
end;
$$;

drop function public.catalog_version();
drop view public.catalog_products;

DO $$
begin
  if (select md5(prosrc) from pg_proc where oid = 'public.catalog_published_prices(text[], text, integer)'::regprocedure) is distinct from '38e5e597619fd290b2255e8d9c224453'
     or (select proacl::text from pg_proc where oid = 'public.catalog_published_prices(text[], text, integer)'::regprocedure) is distinct from '{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}' then
    raise exception 'rollback 41-02: catalog_published_prices no ha vuelto a la de 39-05';
  end if;
  if to_regclass('public.catalog_products') is not null or to_regprocedure('public.catalog_version()') is not null then
    raise exception 'rollback 41-02: quedan objetos de 41-02';
  end if;
  if (select count(*) from pg_policies where schemaname = 'public') <> 48 then
    raise exception 'rollback 41-02: ha cambiado el número de políticas';
  end if;
  raise notice 'rollback 41-02 OK.';
end $$;

COMMIT;
