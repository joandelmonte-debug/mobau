-- ============================================================
-- PROPUESTA NO EJECUTADA (38-B) — no ejecutar sin aprobación explícita
-- ============================================================
-- ROLLBACK de 38-B · 01 · Estado de publicación de productos
-- ------------------------------------------------------------
-- TRANSACCIÓN ATÓMICA: ejecutar el archivo completo, de una vez; si
-- algo falla, no se deshace nada a medias.
-- Aplicar SOLO después de revertir 38-B · 02 (las políticas de
-- visibilidad dependen de publication_status).
-- products.status conserva su último valor (espejo de la última
-- moderación): un producto que estuviera en draft/in_review/
-- changes_requested queda como 'archived', es decir, oculto en el
-- catálogo actual, que filtra status = 'active'.
-- trg_products_updated_at no se toca: la migración lo deja habilitado
-- y este rollback lo mantiene así.
-- ============================================================

BEGIN;

drop trigger if exists trg_products_sync_legacy_status on public.products;
drop function if exists public.products_sync_legacy_status();
drop index if exists public.products_publication_status_idx;
alter table public.products drop constraint if exists products_publication_status_check;
alter table public.products drop column if exists publication_status;

COMMIT;
