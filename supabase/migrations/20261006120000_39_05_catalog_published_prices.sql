-- ============================================================
-- PROPUESTA NO EJECUTADA (39-05) — no ejecutar sin aprobación explícita
-- ============================================================
-- 39 · 05 · Superficie segura de precios para el catálogo
-- ------------------------------------------------------------
-- Requiere 39-04. Solo AÑADE una función; no cambia políticas, permisos ni
-- datos existentes. Es el primer paso del paquete de precios:
--   39-05 (esta) → script.js usa esta función → verificación del catálogo
--   → 39-06 (privacidad de product_prices).
--
--   public.catalog_published_prices(
--     p_product_ids text[]  default null,   -- null = todos (catálogo); máx. 200
--     p_after       text    default null,   -- paginación por product_id (> p_after); máx. 200 caracteres
--     p_limit       integer default 1000)   -- 1..1000 filas por llamada
--   → table (product_id, price_amount, currency, price_status,
--            includes_itbis, itbis_rate, es_demo)
--
-- «published» en el nombre se refiere al PRODUCTO: solo devuelve filas de
-- productos con publication_status = 'published' y price_status válido
-- (published, quote_required, pending_confirmation, unavailable).
--   * price_status = 'published' → devuelve price_amount.
--   * cualquier otro estado      → devuelve el estado y price_amount = NULL
--     (el importe guardado nunca sale).
--   * es_demo = (price_source = 'demo'), calculado aquí (false si no hay
--     fuente). Nunca devuelve price_source, price_reference,
--     price_reference_date ni price_note.
-- Un producto sin fila de precio no aparece (el cliente lo trata como
-- «bajo cotización», igual que hoy).
--
-- SECURITY DEFINER (propietario postgres) porque, tras 39-06, el usuario no
-- puede leer product_prices directamente. search_path vacío. EXECUTE solo
-- para authenticated; además exige sesión (auth.uid()). Los parámetros solo
-- filtran por id y paginan: no aceptan columnas, estados, SQL ni filtros
-- libres. Ejecutar completo.
-- ============================================================

BEGIN;

-- ---------- prechecks ----------
DO $$
begin
  if current_user <> 'postgres' then
    raise exception '39-05: ejecutar como postgres';
  end if;
  if not exists (select 1 from supabase_migrations.schema_migrations where version = '20261005130300') then
    raise exception '39-05: falta 39-04 (20261005130300)';
  end if;
  if exists (select 1 from pg_proc where pronamespace = 'public'::regnamespace and proname = 'catalog_published_prices') then
    raise exception '39-05: catalog_published_prices ya existe';
  end if;
  if (select count(*) from pg_policies where schemaname = 'public') <> 47 then
    raise exception '39-05: se esperaban 47 políticas en public';
  end if;
end $$;

create function public.catalog_published_prices(
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

comment on function public.catalog_published_prices(text[], text, integer) is
  '39-05: precios de productos publicados, sin columnas internas. Importe solo si price_status = published. es_demo sustituye a price_source. Solo authenticated.';

-- Supabase concede EXECUTE por defecto a anon y authenticated: se retira a
-- public y anon.
revoke all on function public.catalog_published_prices(text[], text, integer) from public, anon;
grant execute on function public.catalog_published_prices(text[], text, integer) to authenticated;

-- ---------- validación final ----------
DO $$
declare
  f constant regprocedure := 'public.catalog_published_prices(text[], text, integer)'::regprocedure;
begin
  if not (select prosecdef from pg_proc where oid = f)
     or not exists (select 1 from pg_proc where oid = f and proconfig @> array['search_path=""'])
     or (select proowner from pg_proc where oid = f) <> 'postgres'::regrole then
    raise exception '39-05: debe ser SECURITY DEFINER, con search_path vacío y propietario postgres';
  end if;
  if has_function_privilege('anon', f, 'EXECUTE') or not has_function_privilege('authenticated', f, 'EXECUTE')
     or exists (select 1 from pg_proc, aclexplode(proacl) a where oid = f and a.grantee = 0 and a.privilege_type = 'EXECUTE') then
    raise exception '39-05: permisos de ejecución inesperados (solo authenticated)';
  end if;
  if (select count(*) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'catalog_published_prices') <> 1 then
    raise exception '39-05: debe existir una sola firma';
  end if;
  if (select array_to_string(proargnames[4:10], ',') from pg_proc where oid = f)
     <> 'product_id,price_amount,currency,price_status,includes_itbis,itbis_rate,es_demo'
     or (select pg_catalog.cardinality(proargnames) from pg_proc where oid = f) <> 10 then
    raise exception '39-05: las columnas devueltas no son las 7 aprobadas';
  end if;
  if (select count(*) from pg_policies where schemaname = 'public') <> 47 then
    raise exception '39-05: el número de políticas ha cambiado';
  end if;
  raise notice '39-05 OK: catalog_published_prices disponible para authenticated (7 columnas).';
end $$;

COMMIT;
