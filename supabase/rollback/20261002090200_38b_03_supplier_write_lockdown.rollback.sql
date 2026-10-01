-- ============================================================
-- PROPUESTA NO EJECUTADA (38-B) — no ejecutar sin aprobación explícita
-- ============================================================
-- ROLLBACK de 38-B · 03 · Bloqueo de escrituras de distribuidor
-- ------------------------------------------------------------
-- TRANSACCIÓN ATÓMICA: ejecutar el archivo completo, de una vez; si
-- cualquier validación falla, no se deshace nada a medias.
-- Aplicar después de revertir 38-B · 04 y antes del rollback de 02.
--
-- Restaura exactamente los permisos por columna anteriores
-- (information_schema.column_privileges, verificados el 2026-10-01):
--   products, authenticated:
--     INSERT: availability, brand, cad_bim_3d_url, category_id, description,
--             finishes, image_url, lead_time, materials, measurements, name,
--             space, subcategory, technical_sheet_url, use_context (15)
--     UPDATE: las mismas 15 + status (16)
--   product_prices, authenticated:
--     INSERT: price_amount, price_status, product_id
--     UPDATE: price_amount, price_status
--   anon: ningún permiso de escritura en ninguna de las dos tablas.
-- El grantor de los permisos restaurados será el rol que ejecute este
-- rollback; puede diferir del original aunque el privilegio efectivo
-- restaurado sea el mismo (lo comprueban las validaciones finales).
-- ============================================================

BEGIN;

-- 1) Políticas restrictivas (antes que la función de la que dependen)
drop policy if exists projects_supplier_no_insert on public.projects;
drop policy if exists projects_supplier_no_update on public.projects;
drop policy if exists project_products_supplier_no_insert on public.project_products;
drop policy if exists project_products_supplier_no_update on public.project_products;
drop policy if exists rfqs_supplier_no_insert on public.rfqs;

-- 2) Función, ya sin políticas que dependan de ella
drop function if exists public.is_supplier();

-- 3) Permisos exactos anteriores
grant insert (availability, brand, cad_bim_3d_url, category_id, description, finishes, image_url,
              lead_time, materials, measurements, name, space, subcategory, technical_sheet_url, use_context)
  on public.products to authenticated;
grant update (availability, brand, cad_bim_3d_url, category_id, description, finishes, image_url,
              lead_time, materials, measurements, name, space, status, subcategory, technical_sheet_url, use_context)
  on public.products to authenticated;

grant insert (price_amount, price_status, product_id) on public.product_prices to authenticated;
grant update (price_amount, price_status) on public.product_prices to authenticated;

-- 4) Validaciones finales
do $$
declare
  v_ins_products text[] := array['availability', 'brand', 'cad_bim_3d_url', 'category_id', 'description',
                                  'finishes', 'image_url', 'lead_time', 'materials', 'measurements', 'name',
                                  'space', 'subcategory', 'technical_sheet_url', 'use_context'];
  v_upd_products text[] := array['availability', 'brand', 'cad_bim_3d_url', 'category_id', 'description',
                                  'finishes', 'image_url', 'lead_time', 'materials', 'measurements', 'name',
                                  'space', 'status', 'subcategory', 'technical_sheet_url', 'use_context'];
  v_ins_prices text[] := array['price_amount', 'price_status', 'product_id'];
  v_upd_prices text[] := array['price_amount', 'price_status'];
  v_col text;
  n_restrictive int;
begin
  -- Políticas restrictivas de 03: cero
  select count(*) into n_restrictive
    from pg_policies
   where schemaname = 'public'
     and policyname in ('projects_supplier_no_insert', 'projects_supplier_no_update',
                        'project_products_supplier_no_insert', 'project_products_supplier_no_update',
                        'rfqs_supplier_no_insert');
  if n_restrictive <> 0 then
    raise exception 'Rollback 38-B 03: quedan % políticas restrictivas de 03', n_restrictive;
  end if;

  -- is_supplier(): inexistente
  if exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
              where n.nspname = 'public' and p.proname = 'is_supplier') then
    raise exception 'Rollback 38-B 03: public.is_supplier() sigue existiendo';
  end if;

  -- Sin permiso de tabla (los originales eran solo por columna)
  if has_table_privilege('authenticated', 'public.products', 'INSERT')
     or has_table_privilege('authenticated', 'public.products', 'UPDATE')
     or has_table_privilege('authenticated', 'public.product_prices', 'INSERT')
     or has_table_privilege('authenticated', 'public.product_prices', 'UPDATE') then
    raise exception 'Rollback 38-B 03: authenticated tiene un permiso de tabla que no tenía';
  end if;

  -- anon: sin escritura
  if has_any_column_privilege('anon', 'public.products', 'INSERT')
     or has_any_column_privilege('anon', 'public.products', 'UPDATE')
     or has_any_column_privilege('anon', 'public.product_prices', 'INSERT')
     or has_any_column_privilege('anon', 'public.product_prices', 'UPDATE') then
    raise exception 'Rollback 38-B 03: anon tiene permisos de escritura que no tenía';
  end if;

  -- authenticated: exactamente la matriz original, columna a columna
  for v_col in select attname from pg_attribute
                where attrelid = 'public.products'::regclass and attnum > 0 and not attisdropped loop
    if has_column_privilege('authenticated', 'public.products', v_col, 'INSERT') <> (v_col = any (v_ins_products)) then
      raise exception 'Rollback 38-B 03: INSERT de authenticated en products.% no coincide con la matriz original', v_col;
    end if;
    if has_column_privilege('authenticated', 'public.products', v_col, 'UPDATE') <> (v_col = any (v_upd_products)) then
      raise exception 'Rollback 38-B 03: UPDATE de authenticated en products.% no coincide con la matriz original', v_col;
    end if;
  end loop;

  for v_col in select attname from pg_attribute
                where attrelid = 'public.product_prices'::regclass and attnum > 0 and not attisdropped loop
    if has_column_privilege('authenticated', 'public.product_prices', v_col, 'INSERT') <> (v_col = any (v_ins_prices)) then
      raise exception 'Rollback 38-B 03: INSERT de authenticated en product_prices.% no coincide con la matriz original', v_col;
    end if;
    if has_column_privilege('authenticated', 'public.product_prices', v_col, 'UPDATE') <> (v_col = any (v_upd_prices)) then
      raise exception 'Rollback 38-B 03: UPDATE de authenticated en product_prices.% no coincide con la matriz original', v_col;
    end if;
  end loop;
end $$;

COMMIT;
