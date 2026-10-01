-- ============================================================
-- PROPUESTA NO EJECUTADA (38-B) — no ejecutar sin aprobación explícita
-- ============================================================
-- 38-B · 02 · Visibilidad de productos y precios
-- ------------------------------------------------------------
-- TRANSACCIÓN ATÓMICA: todo el archivo va entre BEGIN y COMMIT y se
-- ejecuta completo, de una vez. No partirlo ni ejecutarlo por
-- fragmentos. Si cualquier comprobación o sentencia falla, no queda
-- ningún estado parcial de visibilidad. Si falla, NO se continúa con
-- 03 ni 04.
--
-- Requiere 38-B · 01 (publication_status).
--
-- products (SELECT):
--   * publication_status = 'published'      -> anon y authenticated
--   * cualquier otro estado                  -> solo el distribuidor
--     verificado propietario
--     (distributor_id = my_verified_distributor_id())
--   * nunca visible para otros distribuidores, profesionales ni anon.
--   Las dos políticas son PERMISSIVE (se combinan con OR):
--     visible  <=>  publicado  OR  (authenticated AND propio y verificado)
--   Por eso cualquier otra política SELECT permisiva sobre products
--   abriría visibilidad: la migración valida, antes y después, el número
--   y los nombres exactos de las políticas SELECT y aborta si no cuadran.
--   La segunda es solo para authenticated: anon no tiene EXECUTE sobre
--   my_verified_distributor_id(), y para él basta la primera.
--   Moderación manual: el editor SQL y el Table Editor de Supabase usan
--   un rol con BYPASSRLS; no se añade ninguna política de administración
--   para el cliente.
--
-- product_prices (SELECT): hereda exactamente la visibilidad de su
-- producto. La subconsulta sobre products se evalúa con la RLS del
-- usuario que consulta, así que un precio solo existe para quien puede
-- ver el producto. Sigue siendo solo para authenticated (anon no tenía
-- ni tiene acceso a precios): nunca es más permisiva que products.
--
-- "Política SELECT" en las comprobaciones = cmd SELECT o ALL (una
-- política FOR ALL también se aplica a las lecturas).
--
-- Rollback: supabase/rollback/20261002090100_38b_02_products_visibility.rollback.sql
-- ============================================================

BEGIN;

-- ---------- comprobaciones previas: estado inicial exacto ----------
do $$
declare
  n_prod int; v_prod text;
  n_price int; v_price text;
begin
  select count(*), min(policyname) into n_prod, v_prod
    from pg_policies
   where schemaname = 'public' and tablename = 'products' and cmd in ('SELECT', 'ALL');
  if n_prod <> 1 or v_prod <> 'catalogo_lectura_publica_productos' then
    raise exception '38-B 02: products debe tener exactamente 1 política SELECT (catalogo_lectura_publica_productos); encontradas % (%)',
      n_prod, coalesce(v_prod, 'ninguna');
  end if;

  select count(*), min(policyname) into n_price, v_price
    from pg_policies
   where schemaname = 'public' and tablename = 'product_prices' and cmd in ('SELECT', 'ALL');
  if n_price <> 1 or v_price <> 'product_prices_select_authenticated' then
    raise exception '38-B 02: product_prices debe tener exactamente 1 política SELECT (product_prices_select_authenticated); encontradas % (%)',
      n_price, coalesce(v_price, 'ninguna');
  end if;

  if not exists (select 1 from information_schema.columns
                  where table_schema = 'public' and table_name = 'products' and column_name = 'publication_status') then
    raise exception '38-B 02: falta products.publication_status (aplicar antes 38-B 01)';
  end if;
end $$;

-- ---------- sustitución de políticas de products ----------
drop policy catalogo_lectura_publica_productos on public.products;

create policy products_select_published
  on public.products
  for select
  to anon, authenticated
  using (publication_status = 'published');

create policy products_select_own_distributor
  on public.products
  for select
  to authenticated
  using (distributor_id = (select public.my_verified_distributor_id()));

-- ---------- actualización de la política de product_prices ----------
alter policy product_prices_select_authenticated
  on public.product_prices
  to authenticated
  using (exists (select 1 from public.products p where p.id = product_prices.product_id));

-- ---------- comprobaciones finales: estado resultante exacto ----------
do $$
declare
  n_prod int; n_price int;
begin
  select count(*) into n_prod
    from pg_policies
   where schemaname = 'public' and tablename = 'products' and cmd in ('SELECT', 'ALL');
  if n_prod <> 2 then
    raise exception '38-B 02: products debe quedar con exactamente 2 políticas SELECT; hay %', n_prod;
  end if;

  if not exists (select 1 from pg_policies
                  where schemaname = 'public' and tablename = 'products'
                    and policyname = 'products_select_published' and cmd = 'SELECT' and permissive = 'PERMISSIVE'
                    -- roles como conjunto (sin depender del orden del array): exactamente {anon, authenticated}
                    and roles @> array['anon', 'authenticated']::name[]
                    and roles <@ array['anon', 'authenticated']::name[]) then
    raise exception '38-B 02: falta products_select_published (SELECT, PERMISSIVE, anon y authenticated)';
  end if;

  if not exists (select 1 from pg_policies
                  where schemaname = 'public' and tablename = 'products'
                    and policyname = 'products_select_own_distributor' and cmd = 'SELECT' and permissive = 'PERMISSIVE'
                    -- roles como conjunto: exactamente {authenticated}
                    and roles @> array['authenticated']::name[]
                    and roles <@ array['authenticated']::name[]) then
    raise exception '38-B 02: falta products_select_own_distributor (SELECT, PERMISSIVE, solo authenticated)';
  end if;

  if exists (select 1 from pg_policies
              where schemaname = 'public' and tablename = 'products' and policyname = 'catalogo_lectura_publica_productos') then
    raise exception '38-B 02: catalogo_lectura_publica_productos sigue existiendo';
  end if;

  select count(*) into n_price
    from pg_policies
   where schemaname = 'public' and tablename = 'product_prices' and cmd in ('SELECT', 'ALL');
  if n_price <> 1 then
    raise exception '38-B 02: product_prices debe quedar con exactamente 1 política SELECT; hay %', n_price;
  end if;

  if not exists (select 1 from pg_policies
                  where schemaname = 'public' and tablename = 'product_prices'
                    and policyname = 'product_prices_select_authenticated' and cmd = 'SELECT' and permissive = 'PERMISSIVE'
                    -- roles como conjunto: exactamente {authenticated}
                    and roles @> array['authenticated']::name[]
                    and roles <@ array['authenticated']::name[]
                    -- Guardrail estructural mínimo: la migración valida estructura y dependencia
                    -- declarada de products; la semántica exacta del filtro EXISTS se verifica
                    -- mediante pruebas RLS por rol antes de aprobar el despliegue.
                    and qual like '%products%') then
    raise exception '38-B 02: product_prices_select_authenticated no tiene la forma esperada (solo authenticated, condicionada a products)';
  end if;
end $$;

COMMIT;
