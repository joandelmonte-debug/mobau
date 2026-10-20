-- ============================================================
-- PROPUESTA NO EJECUTADA (43-D1 · T1 preparación) — no ejecutar sin aprobación explícita
-- ============================================================
-- 43 · T1 · Preparación del acceso por plan. SIN efecto sobre lo que nadie
-- puede hacer: nada de lo que se crea o cambia aquí lo lee hoy el servidor
-- ni la web.
--   * plans: columna includes_professional_tools (false; true en Individual
--     y Estudio), nombres visibles «Gratis», «Individual», «Estudio» (la web
--     pide plans.name pero no lo muestra) y free_trial sin vencimiento
--     (trial_days = null; ningún código lo lee). NO toca max_active_projects
--     (lo lee el trigger): eso va en T4.
--   * profiles: plan_source ('default' | 'manual_pilot' | 'subscription'),
--     plan_granted_at, plan_note. El cliente no puede escribirlas (solo
--     tiene UPDATE(name)); esta migración no concede permisos nuevos.
--   * mobau_private.plan_events: auditoría de habilitaciones (RLS sin
--     políticas, sin permisos de cliente).
--   * public.my_professional_access(): INVOKER, solo authenticated. Nadie
--     la usa hasta T4.
-- E1: se conserva el identificador free_trial (= Gratis). No se toca el
-- trigger de alta de Auth (handle_new_user).
-- Ejecutar completo.
-- ============================================================

BEGIN;

DO $$
begin
  if current_user <> 'postgres' then
    raise exception '43-T1: ejecutar como postgres';
  end if;
  if (select max(version) from supabase_migrations.schema_migrations) <> '20261016120000' then
    raise exception '43-T1: la última migración registrada no es 20261016120000';
  end if;
  if (select string_agg(id || ':' || name || ':' || max_active_projects || ':' || max_users || ':' || coalesce(trial_days::text, 'null'), '|' order by id) from public.plans)
     <> 'free_trial:Prueba gratuita:1:1:14|individual_founder:Profesional Fundador:1:1:null|studio_founder:Estudio Fundador:5:3:null' then
    raise exception '43-T1: los planes no tienen los valores de partida esperados';
  end if;
  if exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'plans' and column_name = 'includes_professional_tools')
     or exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'profiles' and column_name in ('plan_source', 'plan_granted_at', 'plan_note'))
     or to_regprocedure('public.my_professional_access()') is not null
     or to_regclass('mobau_private.plan_events') is not null then
    raise exception '43-T1: ya existe alguno de los objetos de T1';
  end if;
end $$;

-- ---------- plans ----------
alter table public.plans add column includes_professional_tools boolean not null default false;
update public.plans set name = 'Gratis', trial_days = null where id = 'free_trial';
update public.plans set name = 'Individual', includes_professional_tools = true where id = 'individual_founder';
update public.plans set name = 'Estudio', includes_professional_tools = true where id = 'studio_founder';

-- ---------- profiles: origen de la habilitación ----------
alter table public.profiles add column plan_source text not null default 'default'
  constraint profiles_plan_source_check check (plan_source in ('default', 'manual_pilot', 'subscription'));
alter table public.profiles add column plan_granted_at timestamptz;
alter table public.profiles add column plan_note text
  constraint profiles_plan_note_length check (plan_note is null or char_length(plan_note) <= 500);

-- ---------- auditoría de habilitaciones (privada) ----------
create table mobau_private.plan_events (
  id bigserial primary key,
  user_id uuid not null,
  from_plan text,
  to_plan text not null,
  from_source text,
  to_source text not null,
  note text not null check (char_length(btrim(note)) between 1 and 500),
  actor text not null default current_user,
  created_at timestamptz not null default now()
);
alter table mobau_private.plan_events enable row level security;
revoke all on table mobau_private.plan_events from public, anon, authenticated, service_role;
revoke all on sequence mobau_private.plan_events_id_seq from public, anon, authenticated, service_role;

-- ---------- acceso a las herramientas profesionales ----------
create function public.my_professional_access()
returns boolean
language sql
stable
security invoker
set search_path = ''
as $$
  -- 43: precios, selección, proyectos, presupuestos y solicitudes. Solo el
  -- plan efectivo (profiles.plan, que el cliente no puede escribir) con una
  -- habilitación válida. 'subscription' se añadirá con la integración de
  -- pagos; requested_plan (navegador o metadatos) nunca cuenta.
  select coalesce((
    select pl.includes_professional_tools
           and pr.plan_source = 'manual_pilot'
           and pr.role in ('individual', 'studio_member')
      from public.profiles pr
      join public.plans pl on pl.id = pr.plan
     where pr.id = (select auth.uid())), false);
$$;
revoke all on function public.my_professional_access() from public, anon, authenticated, service_role;
grant execute on function public.my_professional_access() to authenticated;

-- ---------- comprobaciones ----------
DO $$
begin
  if (select string_agg(id || ':' || name || ':' || max_active_projects || ':' || coalesce(trial_days::text, 'null') || ':' || includes_professional_tools, '|' order by id) from public.plans)
     <> 'free_trial:Gratis:1:null:false|individual_founder:Individual:1:null:true|studio_founder:Estudio:5:null:true' then
    raise exception '43-T1: plans no quedó como se esperaba';
  end if;
  if exists (select 1 from public.profiles where plan_source <> 'default') then
    raise exception '43-T1: algún perfil no quedó en default';
  end if;
  if has_column_privilege('authenticated', 'public.profiles', 'plan_source', 'UPDATE')
     or has_column_privilege('authenticated', 'public.profiles', 'plan', 'UPDATE') then
    raise exception '43-T1: el cliente podría escribir plan o plan_source';
  end if;
  if has_function_privilege('anon', 'public.my_professional_access()', 'EXECUTE')
     or not has_function_privilege('authenticated', 'public.my_professional_access()', 'EXECUTE') then
    raise exception '43-T1: permisos de my_professional_access() inesperados';
  end if;
  if has_table_privilege('authenticated', 'mobau_private.plan_events', 'SELECT') then
    raise exception '43-T1: plan_events legible por el cliente';
  end if;
end $$;

COMMIT;
