-- ============================================================
-- PROPUESTA NO EJECUTADA (39) — no ejecutar sin aprobación explícita
-- ============================================================
-- 39 · 02 · Lectura para la consola de moderación
-- ------------------------------------------------------------
-- Requiere 39-01. Tres políticas de LECTURA, permisivas, que se suman a
-- las existentes (44 → 47), todas condicionadas a is_mobau_admin()
-- (admin activo con aal2):
--   product_proposals  todas las propuestas (bandeja y detalle).
--   proposal_events    todo el historial (auditoría en el detalle).
--   products           todos los productos, incluidos los no publicados
--                      (comparar con el snapshot y ver el borrador creado).
-- product_prices queda cubierta sin política nueva: su política de lectura
-- actual exige que el producto sea visible para quien consulta.
-- categories y distributors ya son de lectura pública.
--
-- Ningún permiso de escritura nuevo: el admin no puede INSERT/UPDATE/DELETE
-- en ninguna tabla; todas sus escrituras irán por moderate_product_proposal
-- (39-04). Ejecutar completo (BEGIN … COMMIT).
-- ============================================================

BEGIN;

DO $$
begin
  if to_regprocedure('public.is_mobau_admin()') is null then
    raise exception '39-02: falta 39-01 (public.is_mobau_admin)';
  end if;
  if exists (select 1 from pg_policies where schemaname = 'public'
              and policyname in ('product_proposals_select_mobau', 'proposal_events_select_mobau', 'products_select_mobau')) then
    raise exception '39-02: alguna política de 39-02 ya existe';
  end if;
  if (select count(*) from pg_policies where schemaname = 'public') <> 44 then
    raise exception '39-02: se esperaban 44 políticas en public';
  end if;
end $$;

create policy product_proposals_select_mobau
  on public.product_proposals
  for select
  to authenticated
  using ((select public.is_mobau_admin()));

create policy proposal_events_select_mobau
  on public.proposal_events
  for select
  to authenticated
  using ((select public.is_mobau_admin()));

create policy products_select_mobau
  on public.products
  for select
  to authenticated
  using ((select public.is_mobau_admin()));

DO $$
begin
  if (select count(*) from pg_policies
       where schemaname = 'public' and cmd = 'SELECT' and roles = '{authenticated}' and permissive = 'PERMISSIVE'
         and policyname in ('product_proposals_select_mobau', 'proposal_events_select_mobau', 'products_select_mobau')) <> 3 then
    raise exception '39-02: faltan las 3 políticas de lectura';
  end if;
  if (select count(*) from pg_policies where schemaname = 'public') <> 47 then
    raise exception '39-02: se esperaban 47 políticas en public (44 + 3)';
  end if;
  -- Sin escrituras nuevas para clientes.
  if has_table_privilege('authenticated', 'public.products', 'INSERT,UPDATE,DELETE')
     or has_any_column_privilege('authenticated', 'public.products', 'INSERT,UPDATE')
     or has_table_privilege('authenticated', 'public.proposal_events', 'INSERT,UPDATE,DELETE') then
    raise exception '39-02: authenticated tiene escrituras inesperadas';
  end if;
  raise notice '39-02 OK: 3 políticas de lectura para admin con aal2 (47 en public).';
end $$;

COMMIT;
