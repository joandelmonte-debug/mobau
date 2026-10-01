-- ============================================================
-- PROPUESTA NO EJECUTADA (38-B) — no ejecutar sin aprobación explícita
-- ============================================================
-- ROLLBACK de 38-B · 04 · Garantías de líneas de proyecto y RFQ
-- ------------------------------------------------------------
-- TRANSACCIÓN ATÓMICA: ejecutar el archivo completo, de una vez; si
-- cualquier validación falla, no se deshace nada a medias.
-- Es el primer rollback del orden inverso (04 → 03 → 02 → 01).
--
-- Restaura el permiso UPDATE de tabla completo que authenticated
-- tenía sobre project_products (verificado el 2026-10-01). Revocar
-- UPDATE de tabla elimina también los permisos por columna de 38-B.
-- El grantor restaurado será el rol que ejecute el rollback; puede
-- diferir del original aunque el privilegio efectivo sea el mismo.
-- No toca las políticas ni la función de 38-B · 03, ni rfq_distributors
-- (38-B no le añade ninguna política).
-- ============================================================

BEGIN;

drop policy if exists rfqs_insert_guard on public.rfqs;
drop policy if exists project_products_only_published_insert on public.project_products;

revoke update on public.project_products from authenticated;
grant update on public.project_products to authenticated;

-- Validaciones finales
do $$
begin
  if exists (select 1 from pg_policies
              where schemaname = 'public'
                and policyname in ('project_products_only_published_insert', 'rfqs_insert_guard')) then
    raise exception 'Rollback 38-B 04: quedan políticas de 04';
  end if;

  -- UPDATE de tabla restaurado (y, por tanto, en todas las columnas)
  if not has_table_privilege('authenticated', 'public.project_products', 'UPDATE')
     or not has_column_privilege('authenticated', 'public.project_products', 'product_id', 'UPDATE') then
    raise exception 'Rollback 38-B 04: authenticated no recuperó UPDATE de tabla sobre project_products';
  end if;
end $$;

COMMIT;
