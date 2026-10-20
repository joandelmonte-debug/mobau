-- ============================================================
-- PROPUESTA NO EJECUTADA (43-D3 · CC1 · Gratis sin proyectos · OPCIÓN B) — no ejecutar sin aprobación explícita
-- ============================================================
-- 43 · CC1 · Sin herramientas profesionales no se leen ni se eliminan
-- proyectos, líneas ni solicitudes, tampoco con la API directa (sustituye
-- E5/E5b). Requiere T4 aplicada y registrada (20261020120100).
--   * RESTRICTIVE SELECT (authenticated) con my_professional_access() en
--     projects, project_products y rfqs.
--   * RESTRICTIVE DELETE (authenticated) con my_professional_access() en
--     projects (project_products ya lo tiene desde T4; rfqs no tiene DELETE).
-- No borra ni modifica datos: los de una cuenta sin plan se conservan
-- ocultos y vuelven a verse cuando recupera las herramientas profesionales.
-- OPCIÓN B: la restricción solo se aplica a las cuentas profesionales
-- (role individual o studio_member). Distribuidor (supplier) y Mobau (admin)
-- quedan exactamente como hoy: el distribuidor sigue viendo su proyecto
-- histórico. Si no se encuentra el perfil, se restringe (falla cerrado).
-- Efecto indirecto: moodboards (políticas basadas en ver el proyecto) queda
-- cerrada para quien no tiene plan. Distribuidor y Mobau no tienen hoy
-- ningún camino de lectura en estas tablas (comprobado el 2026-10-20).
-- Ejecutar completo.
-- ============================================================

BEGIN;

DO $$
begin
  if current_user <> 'postgres' then
    raise exception '43-D3: ejecutar como postgres';
  end if;
  if not exists (select 1 from supabase_migrations.schema_migrations where version = '20261020120100')
     or to_regprocedure('public.my_professional_access()') is null then
    raise exception '43-D3: T4 no está aplicada y registrada';
  end if;
  if (select count(*) from pg_policies where schemaname = 'public' and tablename in ('projects', 'project_products', 'rfqs')) <> 25 then
    raise exception '43-D3: el número de políticas de partida en projects/project_products/rfqs no es 25';
  end if;
  if exists (select 1 from pg_policies where schemaname = 'public' and policyname in
             ('projects_plan_select', 'projects_plan_delete', 'project_products_plan_select', 'rfqs_plan_select')) then
    raise exception '43-D3: ya existe alguna política de D3';
  end if;
end $$;

create policy projects_plan_select on public.projects as restrictive for select to authenticated
  using ((select public.my_professional_access())
         or not coalesce((select pr.role in ('individual', 'studio_member') from public.profiles pr where pr.id = (select auth.uid())), true));
create policy projects_plan_delete on public.projects as restrictive for delete to authenticated
  using ((select public.my_professional_access())
         or not coalesce((select pr.role in ('individual', 'studio_member') from public.profiles pr where pr.id = (select auth.uid())), true));
create policy project_products_plan_select on public.project_products as restrictive for select to authenticated
  using ((select public.my_professional_access())
         or not coalesce((select pr.role in ('individual', 'studio_member') from public.profiles pr where pr.id = (select auth.uid())), true));
create policy rfqs_plan_select on public.rfqs as restrictive for select to authenticated
  using ((select public.my_professional_access())
         or not coalesce((select pr.role in ('individual', 'studio_member') from public.profiles pr where pr.id = (select auth.uid())), true));

DO $$
begin
  if (select count(*) from pg_policies where schemaname = 'public' and tablename in ('projects', 'project_products', 'rfqs')) <> 29
     or (select count(*) from pg_policies where schemaname = 'public' and permissive = 'RESTRICTIVE' and policyname in
         ('projects_plan_select', 'projects_plan_delete', 'project_products_plan_select', 'rfqs_plan_select')) <> 4 then
    raise exception '43-D3: políticas no creadas como se esperaba';
  end if;
end $$;

COMMIT;
