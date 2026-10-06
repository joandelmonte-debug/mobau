-- ============================================================
-- PROPUESTA NO EJECUTADA (39-05) — no ejecutar sin aprobación explícita
-- ============================================================
-- 39 · 05 · ROLLBACK · Superficie segura de precios publicados
-- ------------------------------------------------------------
-- Quita catalog_published_prices. Se niega si 39-06 sigue aplicada: con la
-- tabla privada y sin esta función, profesionales y catálogo se quedarían
-- sin precios. Antes de ejecutarlo, script.js debe haber vuelto a la versión
-- que lee product_prices directamente (esto no se puede comprobar desde la
-- base de datos: es un paso del plan). Ejecutar completo.
-- ============================================================

BEGIN;

DO $$
begin
  if to_regprocedure('public.catalog_published_prices(text[], text, integer)') is null then
    raise exception '39-05 rollback: 39-05 no está aplicada';
  end if;
  if exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'product_prices'
              and policyname in ('product_prices_select_own', 'product_prices_select_mobau')) then
    raise exception '39-05 rollback: 39-06 sigue aplicada (revertir 39-06 antes)';
  end if;
end $$;

drop function public.catalog_published_prices(text[], text, integer);

DO $$
begin
  if exists (select 1 from pg_proc where pronamespace = 'public'::regnamespace and proname = 'catalog_published_prices') then
    raise exception '39-05 rollback: la función sigue existiendo';
  end if;
  raise notice '39-05 rollback OK.';
end $$;

COMMIT;
