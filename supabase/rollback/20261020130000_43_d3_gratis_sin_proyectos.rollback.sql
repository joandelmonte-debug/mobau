-- ============================================================
-- RECUPERACIÓN NO EJECUTADA (43 · R-D3, inversa de D3) — no ejecutar sin aprobación explícita
-- ============================================================
-- Retira las 4 políticas de D3. Vuelve el estado de T4: una cuenta sin plan
-- vuelve a poder leer sus proyectos, líneas y solicitudes (sin editarlos).
-- Antes de ejecutarla, la web no debe depender de D3: la interfaz de CC1 no
-- muestra nada de proyectos a Gratis, así que puede quedarse publicada.
-- No toca datos. Ejecutar completo.
-- ============================================================

BEGIN;

DO $$
begin
  if current_user <> 'postgres' then
    raise exception '43-RD3: ejecutar como postgres';
  end if;
  if (select count(*) from pg_policies where schemaname = 'public' and policyname in
      ('projects_plan_select', 'projects_plan_delete', 'project_products_plan_select', 'rfqs_plan_select')) <> 4 then
    raise exception '43-RD3: D3 no está aplicada (faltan políticas)';
  end if;
end $$;

drop policy projects_plan_select on public.projects;
drop policy projects_plan_delete on public.projects;
drop policy project_products_plan_select on public.project_products;
drop policy rfqs_plan_select on public.rfqs;

DO $$
begin
  if (select count(*) from pg_policies where schemaname = 'public' and tablename in ('projects', 'project_products', 'rfqs')) <> 25 then
    raise exception '43-RD3: no quedaron las 25 políticas de T4';
  end if;
end $$;

COMMIT;
