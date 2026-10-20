-- ============================================================
-- RECUPERACIÓN NO EJECUTADA (43-D1 · inversa de T1) — no ejecutar sin aprobación explícita
-- ============================================================
-- Devuelve plans y profiles al estado de partida y elimina
-- my_professional_access() y mobau_private.plan_events. Requiere que T4 ya
-- esté revertida. Se niega si hay alguna habilitación (plan_source distinto
-- de 'default') o algún evento de habilitación: primero hay que revertir T3
-- con su SQL autorizado, para no perder la auditoría sin decidirlo.
-- ============================================================

BEGIN;

DO $$
begin
  if current_user <> 'postgres' then
    raise exception '43-R1: ejecutar como postgres';
  end if;
  if exists (select 1 from pg_policies where schemaname = 'public' and policyname in ('projects_plan_insert', 'projects_plan_update', 'projects_studio_own_insert', 'projects_studio_own_update',
             'project_products_plan_insert', 'project_products_plan_update', 'project_products_plan_delete', 'rfqs_plan_insert'))
     or (select md5(prosrc) from pg_proc where oid = 'public.catalog_published_prices(text[], text, integer)'::regprocedure) <> '366f275cf85ec6c10956cecfbbc92ed5' then
    raise exception '43-R1: T4 sigue aplicada; revertir T4 antes';
  end if;
  if exists (select 1 from public.profiles where plan_source <> 'default') or exists (select 1 from mobau_private.plan_events) then
    raise exception '43-R1: hay habilitaciones o eventos de habilitación; revertir T3 antes';
  end if;
end $$;

drop function public.my_professional_access();
drop table mobau_private.plan_events;
alter table public.profiles drop column plan_note;
alter table public.profiles drop column plan_granted_at;
alter table public.profiles drop column plan_source;
alter table public.plans drop column includes_professional_tools;
update public.plans set name = 'Prueba gratuita', trial_days = 14 where id = 'free_trial';
update public.plans set name = 'Profesional Fundador' where id = 'individual_founder';
update public.plans set name = 'Estudio Fundador' where id = 'studio_founder';

DO $$
begin
  if (select string_agg(id || ':' || name || ':' || max_active_projects || ':' || max_users || ':' || coalesce(trial_days::text, 'null'), '|' order by id) from public.plans)
     <> 'free_trial:Prueba gratuita:1:1:14|individual_founder:Profesional Fundador:1:1:null|studio_founder:Estudio Fundador:5:3:null' then
    raise exception '43-R1: plans no volvió al estado de partida';
  end if;
  if exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'profiles' and column_name in ('plan_source', 'plan_granted_at', 'plan_note'))
     or to_regprocedure('public.my_professional_access()') is not null or to_regclass('mobau_private.plan_events') is not null then
    raise exception '43-R1: quedan objetos de T1';
  end if;
end $$;

COMMIT;
