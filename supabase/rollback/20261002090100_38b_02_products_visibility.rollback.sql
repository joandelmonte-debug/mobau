-- ============================================================
-- PROPUESTA NO EJECUTADA (38-B) — no ejecutar sin aprobación explícita
-- ============================================================
-- ROLLBACK de 38-B · 02 · Visibilidad de productos y precios
-- ------------------------------------------------------------
-- TRANSACCIÓN ATÓMICA: ejecutar el archivo completo, de una vez; si
-- algo falla, no queda ningún estado parcial de visibilidad.
-- Aplicar después de revertir 38-B · 04 y 03, y antes del rollback de 01.
-- Restaura exactamente las políticas anteriores (verificadas el
-- 2026-10-01):
--   catalogo_lectura_publica_productos: SELECT, roles {public}, USING (true)
--   product_prices_select_authenticated: SELECT, {authenticated}, USING (true)
-- ============================================================

BEGIN;

drop policy if exists products_select_published on public.products;
drop policy if exists products_select_own_distributor on public.products;

create policy catalogo_lectura_publica_productos
  on public.products
  for select
  to public
  using (true);

alter policy product_prices_select_authenticated
  on public.product_prices
  to authenticated
  using (true);

COMMIT;
