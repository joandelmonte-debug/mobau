-- ============================================================
-- PROPUESTA NO EJECUTADA (38-B) — no ejecutar sin aprobación explícita
-- ============================================================
-- 38-B · Moderación manual de productos (editor SQL de Supabase)
-- ------------------------------------------------------------
-- Solo para el equipo de Mobau, desde el panel de Supabase (rol con
-- BYPASSRLS). Ningún rol de cliente puede ejecutar estos cambios:
-- publication_status no tiene permisos de escritura para anon ni
-- authenticated.
--
-- Reglas:
--   * Cambia SIEMPRE publication_status; nunca products.status a mano
--     (es un espejo y el trigger lo recalcula).
--   * Un producto por sentencia, por su id (sustituye <PRODUCT_ID>).
--   * Ejecuta cada bloque entero: el SELECT final confirma el resultado.
-- ============================================================

-- 0) Ver el estado actual de un producto
select id, name, distributor_id, publication_status, status, updated_at
from public.products
where id = '<PRODUCT_ID>';

-- 1) Pasar a revisión (in_review)
update public.products set publication_status = 'in_review' where id = '<PRODUCT_ID>';
select id, publication_status, status from public.products where id = '<PRODUCT_ID>';
-- esperado: in_review / archived (no visible en el catálogo)

-- 2) Solicitar cambios (changes_requested)
update public.products set publication_status = 'changes_requested' where id = '<PRODUCT_ID>';
select id, publication_status, status from public.products where id = '<PRODUCT_ID>';
-- esperado: changes_requested / archived (no visible en el catálogo)

-- 3) Publicar (published)
update public.products set publication_status = 'published' where id = '<PRODUCT_ID>';
select id, publication_status, status from public.products where id = '<PRODUCT_ID>';
-- esperado: published / active (visible en el catálogo)

-- 4) Archivar (archived)
update public.products set publication_status = 'archived' where id = '<PRODUCT_ID>';
select id, publication_status, status from public.products where id = '<PRODUCT_ID>';
-- esperado: archived / archived (no visible en el catálogo)

-- 5) Verificación global: status debe reflejar siempre publication_status
select publication_status, status, count(*) as productos
from public.products
group by publication_status, status
order by publication_status, status;
-- esperado: solo combinaciones published/active y <otro estado>/archived

select count(*) as incoherentes
from public.products
where (publication_status = 'published') <> (status = 'active');
-- esperado: 0
