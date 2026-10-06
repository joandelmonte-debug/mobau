-- ============================================================
-- PROPUESTA NO EJECUTADA (39-06) — no ejecutar sin aprobación explícita
-- ============================================================
-- 39 · 06 · Privacidad de product_prices (riesgos R1 y R2)
-- ------------------------------------------------------------
-- Requiere 39-05 (catalog_published_prices) y que script.js ya use esa
-- función (paso del plan; no se puede comprobar desde la base de datos).
-- Sustituye la lectura «cualquier autenticado ve el precio de todo producto
-- visible» por:
--   * distribuidor verificado: solo los precios de SUS productos (todas las
--     columnas, incluidos importes no publicados y campos internos);
--   * admin de Mobau con aal2: todos los precios (para moderar);
--   * profesional autenticado: ninguna fila directa; estado e importe
--     publicado le llegan solo por catalog_published_prices (39-05);
--   * anon: sin ningún permiso sobre la tabla.
-- postgres (y por tanto moderate_product_proposal y catalog_published_prices,
-- SECURITY DEFINER de postgres con BYPASSRLS) no se ve afectado.
--
-- INSERT/UPDATE: fuera de alcance (D4). Ningún cliente tiene permiso de tabla
-- para escribir (38-B); product_prices_insert_own/update_own no se tocan.
-- Ejecutar completo.
-- ============================================================

BEGIN;

-- ---------- prechecks ----------
DO $$
begin
  if current_user <> 'postgres' then
    raise exception '39-06: ejecutar como postgres';
  end if;
  if not exists (select 1 from supabase_migrations.schema_migrations where version = '20261005130300') then
    raise exception '39-06: falta 39-04 (20261005130300)';
  end if;
  if to_regprocedure('public.is_mobau_admin()') is null or to_regprocedure('public.my_verified_distributor_id()') is null then
    raise exception '39-06: faltan is_mobau_admin() o my_verified_distributor_id()';
  end if;
  if not exists (select 1 from supabase_migrations.schema_migrations where version = '20261006120000')
     or to_regprocedure('public.catalog_published_prices(text[], text, integer)') is null then
    raise exception '39-06: falta 39-05 (catalog_published_prices): aplicar 39-05 y desplegar script.js antes';
  end if;
  if not (select relrowsecurity from pg_class where oid = 'public.product_prices'::regclass) then
    raise exception '39-06: product_prices debe tener RLS activada';
  end if;
  if (select string_agg(policyname, ',' order by policyname) from pg_policies
       where schemaname = 'public' and tablename = 'product_prices')
     <> 'product_prices_insert_own,product_prices_select_authenticated,product_prices_update_own' then
    raise exception '39-06: las políticas de product_prices no son las esperadas';
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'product_prices'
                  and policyname = 'product_prices_select_authenticated' and cmd = 'SELECT' and roles = '{authenticated}') then
    raise exception '39-06: product_prices_select_authenticated no es la esperada';
  end if;
  if (select count(*) from pg_policies where schemaname = 'public') <> 47 then
    raise exception '39-06: se esperaban 47 políticas en public';
  end if;
  if has_table_privilege('authenticated', 'public.product_prices', 'INSERT,UPDATE,DELETE,TRUNCATE')
     or has_any_column_privilege('authenticated', 'public.product_prices', 'INSERT,UPDATE') then
    raise exception '39-06: authenticated tiene escrituras en product_prices (no esperado desde 38-B)';
  end if;
end $$;

-- ---------- lectura ----------
drop policy product_prices_select_authenticated on public.product_prices;

-- Distribuidor verificado: solo precios de sus productos.
create policy product_prices_select_own
  on public.product_prices
  for select
  to authenticated
  using (exists (select 1 from public.products p
                  where p.id = product_prices.product_id
                    and p.distributor_id = (select public.my_verified_distributor_id())));

-- Admin de Mobau con aal2: todos los precios (moderación).
create policy product_prices_select_mobau
  on public.product_prices
  for select
  to authenticated
  using ((select public.is_mobau_admin()));

-- ---------- permisos ----------
-- anon: ninguno. authenticated: solo SELECT (las filas las filtra RLS).
revoke all on table public.product_prices from public, anon;
revoke references, trigger on table public.product_prices from authenticated;

-- ---------- validación final ----------
DO $$
begin
  if (select string_agg(policyname, ',' order by policyname) from pg_policies
       where schemaname = 'public' and tablename = 'product_prices')
     <> 'product_prices_insert_own,product_prices_select_mobau,product_prices_select_own,product_prices_update_own' then
    raise exception '39-06: políticas finales de product_prices inesperadas';
  end if;
  if (select count(*) from pg_policies where schemaname = 'public' and tablename = 'product_prices' and cmd = 'SELECT') <> 2
     or exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'product_prices'
                 and cmd = 'SELECT' and roles <> '{authenticated}') then
    raise exception '39-06: las lecturas deben ser solo las 2 nuevas, para authenticated';
  end if;
  if (select count(*) from pg_policies where schemaname = 'public') <> 48 then
    raise exception '39-06: se esperaban 48 políticas en public (47 - 1 + 2)';
  end if;
  if has_table_privilege('anon', 'public.product_prices', 'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER')
     or has_any_column_privilege('anon', 'public.product_prices', 'SELECT,INSERT,UPDATE,REFERENCES') then
    raise exception '39-06: anon conserva permisos sobre product_prices';
  end if;
  if not has_table_privilege('authenticated', 'public.product_prices', 'SELECT')
     or has_table_privilege('authenticated', 'public.product_prices', 'INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER')
     or has_any_column_privilege('authenticated', 'public.product_prices', 'INSERT,UPDATE,REFERENCES') then
    raise exception '39-06: authenticated debe tener solo SELECT sobre product_prices';
  end if;
  if not (select relrowsecurity from pg_class where oid = 'public.product_prices'::regclass) then
    raise exception '39-06: RLS desactivada en product_prices';
  end if;
  raise notice '39-06 OK: product_prices solo para su distribuidor y para admin con aal2; anon sin permisos; catálogo vía 39-05.';
end $$;

COMMIT;
