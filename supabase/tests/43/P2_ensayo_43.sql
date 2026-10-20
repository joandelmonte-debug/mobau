-- ============================================================
-- PROPUESTA NO EJECUTADA (43 · ensayo P2) — no ejecutar sin aprobación explícita
-- ============================================================
-- Ensayo transaccional de 43-D en producción, TODO REVERTIDO:
--   1. huellas de partida (comportamiento y completa);
--   2. T1 (preparación) → la huella de comportamiento debe ser idéntica (T1 inerte);
--   3. T4 (activación) → suite P2-S (matriz de acceso, 53 casos);
--   4. inversa de T4 (R4) → la huella de comportamiento vuelve a la de T1;
--   5. inversa de T1 (R1) → la huella completa vuelve a la de partida.
-- Termina SIEMPRE con MB990 (o con el error que lo interrumpa) y ROLLBACK:
-- no persiste nada. Efectos no transaccionales: avanzan secuencias
-- (plan_events_id_seq se crea y desaparece; projects y rfqs usan uuid) y
-- contadores de pg_stat.
-- md5: T1=7a50ed85b5561b057b205f5369679b89 T4=1482715a3557737763e27c60733b7201 suite=e3e4be5e65b96baf15f63de6a6cbcf22 R4=8660569229611f7d774c2462b95888d0 R1=c0aeb415b682b3ad91f4e2fe6864da10
-- ============================================================

BEGIN;

DO $P2W$
declare
  t1 text := $P2A$-- ============================================================
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
$P2A$;
  t4 text := $P2B$-- ============================================================
-- PROPUESTA NO EJECUTADA (43-D2 · T4 activación) — no ejecutar sin aprobación explícita
-- ============================================================
-- 43 · T4 · Activación del acceso por plan en el servidor (requiere T1).
--   1. plans: Individual 2 proyectos activos, Estudio 20 (E9). Gratis no
--      cambia (1): lo controla la RLS.
--   2. enforce_active_project_limit: sin bloqueo especial de reactivación
--      (E9) y con bloqueo de la fila del estudio o del dueño antes de contar
--      (R1). Mismo mensaje de límite.
--   3. catalog_published_prices: solo con herramientas profesionales
--      habilitadas, distribuidor verificado o administrador activo de Mobau
--      con o sin aal2 (D1, E3, E4). Sin acceso: 42501 con hint
--      plan_required o distributor_unverified; nunca filas ni estados.
--   4. Políticas RESTRICTIVE (authenticated):
--      - projects: INSERT/UPDATE exigen my_professional_access() (E5: sin
--        crear, editar, archivar ni reactivar en Gratis). DELETE no cambia
--        (E5b: Gratis puede eliminar archivados propios; las solicitudes lo
--        impiden por la clave foránea, como hoy).
--      - projects: studio_id nulo o el estudio propio (R2).
--      - project_products: INSERT/UPDATE/DELETE exigen my_professional_access().
--      - rfqs: INSERT exige my_professional_access().
--      SELECT no cambia: los datos propios se conservan en solo lectura.
-- No toca distribuidor ni Mobau fuera de la regla de precios, ni Auth.
-- Ejecutar completo.
-- ============================================================

BEGIN;

DO $$
begin
  if current_user <> 'postgres' then
    raise exception '43-T4: ejecutar como postgres';
  end if;
  if to_regprocedure('public.my_professional_access()') is null
     or not exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'profiles' and column_name = 'plan_source')
     or not exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'plans' and column_name = 'includes_professional_tools') then
    raise exception '43-T4: falta T1';
  end if;
  if (select string_agg(id || ':' || max_active_projects || ':' || includes_professional_tools, '|' order by id) from public.plans)
     <> 'free_trial:1:false|individual_founder:1:true|studio_founder:5:true' then
    raise exception '43-T4: los planes no tienen los valores esperados tras T1';
  end if;
  if (select md5(prosrc) from pg_proc where oid = 'public.catalog_published_prices(text[], text, integer)'::regprocedure) <> '366f275cf85ec6c10956cecfbbc92ed5'
     or (select md5(prosrc) from pg_proc where oid = 'public.enforce_active_project_limit()'::regprocedure) <> '40e11d31467d9719f439ab5be096a92a' then
    raise exception '43-T4: catalog_published_prices o enforce_active_project_limit no son las versiones de partida';
  end if;
  if exists (select 1 from pg_policies where schemaname = 'public' and policyname in
             ('projects_plan_insert', 'projects_plan_update', 'projects_studio_own_insert', 'projects_studio_own_update',
              'project_products_plan_insert', 'project_products_plan_update', 'project_products_plan_delete', 'rfqs_plan_insert')) then
    raise exception '43-T4: ya existe alguna política de T4';
  end if;
  if (select count(*) from pg_policies where schemaname = 'public' and tablename in ('projects', 'project_products', 'rfqs')) <> 17 then
    raise exception '43-T4: el número de políticas de partida en projects/project_products/rfqs no es 17';
  end if;
end $$;

-- ---------- 1. límites (E9) ----------
update public.plans set max_active_projects = 2 where id = 'individual_founder';
update public.plans set max_active_projects = 20 where id = 'studio_founder';

-- ---------- 2. trigger de límite (E9, R1) ----------
CREATE OR REPLACE FUNCTION public.enforce_active_project_limit()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_limit int;
  v_current_count int;
begin
  if new.status <> 'active' then
    return new;
  end if;

  -- 43 (E9): la reactivación cuenta igual que la creación; no hay bloqueo
  -- especial cuando el límite es 1.
  -- 43 (R1): se bloquea la fila del estudio o del dueño ANTES de contar, para
  -- que dos operaciones simultáneas no superen el límite.
  if new.studio_id is not null then
    select pl.max_active_projects into v_limit
      from public.studios s join public.plans pl on pl.id = s.plan
     where s.id = new.studio_id
       for update of s;
    select count(*) into v_current_count
      from public.projects p
     where p.studio_id = new.studio_id and p.status = 'active'
       and p.id <> coalesce(new.id, '00000000-0000-0000-0000-000000000000'::uuid);
  else
    select pl.max_active_projects into v_limit
      from public.profiles pr join public.plans pl on pl.id = pr.plan
     where pr.id = new.owner_user_id
       for update of pr;
    select count(*) into v_current_count
      from public.projects p
     where p.owner_user_id = new.owner_user_id and p.studio_id is null and p.status = 'active'
       and p.id <> coalesce(new.id, '00000000-0000-0000-0000-000000000000'::uuid);
  end if;

  if v_current_count >= v_limit then
    raise exception 'Límite de proyectos activos alcanzado (%). Archiva un proyecto existente o cambia de plan.', v_limit;
  end if;

  return new;
end;
$function$;

-- ---------- 3. precios por plan (D1, E3, E4) ----------
CREATE OR REPLACE FUNCTION public.catalog_published_prices(p_product_ids text[] DEFAULT NULL::text[], p_after text DEFAULT NULL::text, p_limit integer DEFAULT 1000)
 RETURNS TABLE(product_id text, price_amount numeric, currency text, price_status text, includes_itbis boolean, itbis_rate numeric, es_demo boolean)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if (select auth.uid()) is null then
    raise exception 'Inicia sesión para consultar precios.' using errcode = '42501';
  end if;
  -- 43: precios solo con herramientas profesionales habilitadas, distribuidor
  -- verificado (E3) o administrador activo de Mobau, con o sin aal2 (E4). Sin
  -- acceso no se devuelve ninguna fila ni ningún estado.
  if not (public.my_professional_access()
          or public.my_verified_distributor_id() is not null
          or exists (select 1 from public.mobau_admins a
                      where a.user_id = (select auth.uid()) and a.revoked_at is null)) then
    if exists (select 1 from public.profiles pr where pr.id = (select auth.uid()) and pr.role = 'supplier') then
      raise exception 'Verás los precios publicados cuando Mobau verifique tu empresa.'
        using errcode = '42501', hint = 'distributor_unverified';
    end if;
    raise exception 'El acceso a precios está incluido en los planes Individual y Estudio.'
      using errcode = '42501', hint = 'plan_required';
  end if;
  if p_limit is null or p_limit < 1 or p_limit > 1000 then
    raise exception 'p_limit debe estar entre 1 y 1000.' using errcode = '22023';
  end if;
  if p_product_ids is not null and pg_catalog.cardinality(p_product_ids) > 200 then
    raise exception 'Como máximo 200 productos por consulta.' using errcode = '22023';
  end if;
  if p_after is not null and pg_catalog.char_length(p_after) > 200 then
    raise exception 'p_after no puede superar 200 caracteres.'
      using errcode = '22023';
  end if;

  return query
    select pp.product_id,
           case when pp.price_status = 'published' then pp.price_amount end,
           pp.currency,
           pp.price_status,
           pp.includes_itbis,
           pp.itbis_rate,
           coalesce(pp.price_source = 'demo', false)
      from public.product_prices pp
      join public.products p on p.id = pp.product_id
     where p.publication_status = 'published'
       -- 41-02: defensa redundante (las CHECK de 41-01 y el espejo de status ya
       -- lo garantizan): nunca un producto inactivo, retirado o en papelera.
       and p.status = 'active'
       and p.retired_at is null
       and p.trashed_at is null
       and pp.price_status in ('published', 'quote_required', 'pending_confirmation', 'unavailable')
       and (p_product_ids is null or pp.product_id = any (p_product_ids))
       and (p_after is null or pp.product_id > p_after)
     order by pp.product_id
     limit p_limit;
end;
$function$;

-- ---------- 4. políticas RESTRICTIVE ----------
create policy projects_plan_insert on public.projects as restrictive for insert to authenticated
  with check ((select public.my_professional_access()));
create policy projects_plan_update on public.projects as restrictive for update to authenticated
  using ((select public.my_professional_access()))
  with check ((select public.my_professional_access()));
create policy projects_studio_own_insert on public.projects as restrictive for insert to authenticated
  with check (studio_id is null
              or studio_id = (select pr.studio_id from public.profiles pr where pr.id = (select auth.uid())));
create policy projects_studio_own_update on public.projects as restrictive for update to authenticated
  using (studio_id is null
         or studio_id = (select pr.studio_id from public.profiles pr where pr.id = (select auth.uid())))
  with check (studio_id is null
              or studio_id = (select pr.studio_id from public.profiles pr where pr.id = (select auth.uid())));
create policy project_products_plan_insert on public.project_products as restrictive for insert to authenticated
  with check ((select public.my_professional_access()));
create policy project_products_plan_update on public.project_products as restrictive for update to authenticated
  using ((select public.my_professional_access()))
  with check ((select public.my_professional_access()));
create policy project_products_plan_delete on public.project_products as restrictive for delete to authenticated
  using ((select public.my_professional_access()));
create policy rfqs_plan_insert on public.rfqs as restrictive for insert to authenticated
  with check ((select public.my_professional_access()));

-- ---------- comprobaciones ----------
DO $$
begin
  if (select string_agg(id || ':' || max_active_projects, '|' order by id) from public.plans)
     <> 'free_trial:1|individual_founder:2|studio_founder:20' then
    raise exception '43-T4: límites no aplicados';
  end if;
  if (select count(*) from pg_policies where schemaname = 'public' and tablename in ('projects', 'project_products', 'rfqs')) <> 25
     or (select count(*) from pg_policies where schemaname = 'public' and permissive = 'RESTRICTIVE' and policyname in
         ('projects_plan_insert', 'projects_plan_update', 'projects_studio_own_insert', 'projects_studio_own_update',
          'project_products_plan_insert', 'project_products_plan_update', 'project_products_plan_delete', 'rfqs_plan_insert')) <> 8 then
    raise exception '43-T4: políticas no creadas como se esperaba';
  end if;
  if (select proacl::text from pg_proc where oid = 'public.catalog_published_prices(text[], text, integer)'::regprocedure)
     <> '{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}'
     or (select proacl::text from pg_proc where oid = 'public.enforce_active_project_limit()'::regprocedure)
     <> '{postgres=X/postgres,service_role=X/postgres}' then
    raise exception '43-T4: permisos de las funciones cambiados';
  end if;
  if (select prosrc from pg_proc where oid = 'public.enforce_active_project_limit()'::regprocedure) !~ 'for update of pr'
     or (select prosrc from pg_proc where oid = 'public.enforce_active_project_limit()'::regprocedure) ~ 'v_owner_max' then
    raise exception '43-T4: trigger de límite no actualizado';
  end if;
end $$;

COMMIT;
$P2B$;
  sx text := $P2C$-- ============================================================
-- PROPUESTA NO EJECUTADA (43 · suite P2) — no ejecutar sin aprobación explícita
-- ============================================================
-- Suite de la matriz de acceso de 43-D. Requiere T1 y T4 aplicadas (dentro
-- del ensayo P2 o, después, sobre el servidor actualizado). Rol postgres;
-- JWT simulado como en 39/41. Cada caso es una subtransacción que se deshace
-- (MB001); sus preparativos (habilitación simulada, estudio temporal,
-- distribuidor sin verificar, admin revocado) viven solo dentro del caso.
-- Al final, MB999 con el resultado. Cuentas (E8): e2a655c1 (Individual),
-- 743270cd (Gratis sin datos), 5b4f13c8 (Gratis con datos); distribuidor
-- 392a9eb4 y Mobau a8fe42e8 solo como actores de lectura, sin modificarlos
-- fuera de casos revertidos.
-- Formato de expect en 'exec': SQLSTATE (5) o SQLSTATE[hint] exactos.
-- ============================================================

DO $P2S$
declare
  v_i uuid; v_f uuid; v_g uuid; v_s uuid; v_m uuid; v_s_dist text;
  p_i_act uuid := '3e533da7-1083-4295-a1de-15bfe6673bf3';
  p_i_arch_free uuid := 'd13a3629-774a-4a06-89bb-9748ff2238b5';
  p_i_arch_free2 uuid := '957dc93c-143b-47d6-9700-a59a56eae5ff';
  p_i_arch_free3 uuid := 'ee137494-4eaf-447b-9245-72556c15b801';
  p_i_arch_rfq uuid := 'b08d8ecb-70e7-494f-b9c2-22ec05b20c07';
  p_g_act uuid := '7bece1b3-81b8-4086-8d22-22c06a1295f0';
  v_studio uuid := '00000000-0000-0000-0000-00000000043a';
  v_prod text; n_prices bigint; n_other bigint; n_own_prices bigint; n_all_prices bigint;
  n_g_proj bigint; n_g_lines bigint; n_i_rfqs bigint; data0 text;
  grant_i text; grant_f_req text; grant_f_sub text; grant_s text;
  ins_proj constant text := 'insert into public.projects (owner_user_id, name, studio_id) values (%L, %L, %s)';
  ins_rfq constant text := 'insert into public.rfqs (project_id, requester_user_id, requester_name, requester_email) values (%L, %L, %L, %L)';
  data_fp constant text := 'select md5(coalesce((select string_agg(id::text || status || coalesce(studio_id::text, ''-'') || owner_user_id::text || name, ''|'' order by id) from public.projects), '''')'
                           || ' || coalesce((select string_agg(id::text || quantity::text || coalesce(unit, ''-'') || selected_for_rfq::text, ''|'' order by id) from public.project_products), '''')'
                           || ' || coalesce((select string_agg(id::text || status, ''|'' order by id) from public.rfqs), '''')'
                           || ' || coalesce((select string_agg(id::text || plan || role || plan_source || subscription_status, ''|'' order by id) from public.profiles), ''''))';
  r jsonb := '[]'::jsonb; t record; i int;
  v_got text; v_n bigint; v_ok boolean; v_stmt text; v_hint text;
  n_total int := 0; n_ok int := 0;
begin
  select id into v_i from public.profiles where id::text like 'e2a655c1%';
  select id into v_f from public.profiles where id::text like '743270cd%';
  select id into v_g from public.profiles where id::text like '5b4f13c8%';
  select id into v_s from public.profiles where id::text like '392a9eb4%';
  select id into v_m from public.profiles where id::text like 'a8fe42e8%';
  select distributor_id into v_s_dist from public.distributor_profiles where user_id = v_s and verification_status = 'verified';
  -- Producto publicado que no está en ninguno de los dos proyectos donde se añaden líneas.
  select c.id into v_prod from public.catalog_products c
   where not exists (select 1 from public.project_products l where l.product_id = c.id and l.project_id in (p_i_act, p_g_act))
   order by c.id limit 1;
  if v_i is null or v_f is null or v_g is null or v_s is null or v_m is null or v_s_dist is null or v_prod is null then
    raise exception 'MOBAU_43_P2_SUITE: faltan actores o datos de partida' using errcode = 'MB998';
  end if;
  if to_regprocedure('public.my_professional_access()') is null
     or not exists (select 1 from pg_policies where policyname = 'projects_plan_insert') then
    raise exception 'MOBAU_43_P2_SUITE: T1 y T4 no están aplicadas' using errcode = 'MB998';
  end if;
  if exists (select 1 from public.studios) or exists (select 1 from public.profiles where plan_source <> 'default')
     or exists (select 1 from mobau_private.plan_events) then
    raise exception 'MOBAU_43_P2_SUITE: hay estudios, habilitaciones o eventos de partida inesperados' using errcode = 'MB998';
  end if;
  if (select count(*) from public.projects where id in (p_i_act, p_i_arch_free, p_i_arch_free2, p_i_arch_free3, p_i_arch_rfq, p_g_act)) <> 6
     or (select status from public.projects where id = p_i_act) <> 'active'
     or (select status from public.projects where id = p_g_act) <> 'active'
     or (select count(*) from public.projects where owner_user_id = v_i and status = 'active') <> 1
     or exists (select 1 from public.rfqs where project_id in (p_i_arch_free, p_i_arch_free2, p_i_arch_free3))
     or not exists (select 1 from public.rfqs where project_id = p_i_arch_rfq) then
    raise exception 'MOBAU_43_P2_SUITE: los proyectos de prueba no están como se leyeron' using errcode = 'MB998';
  end if;

  -- Valores esperados, calculados como postgres con la misma condición de la función.
  select count(*), count(*) filter (where p.distributor_id <> v_s_dist) into n_prices, n_other
    from public.product_prices pp join public.products p on p.id = pp.product_id
   where p.publication_status = 'published' and p.status = 'active' and p.retired_at is null and p.trashed_at is null
     and pp.price_status in ('published', 'quote_required', 'pending_confirmation', 'unavailable');
  select count(*) into n_own_prices from public.product_prices pp join public.products p on p.id = pp.product_id where p.distributor_id = v_s_dist;
  select count(*) into n_all_prices from public.product_prices;
  select count(*) into n_g_proj from public.projects where owner_user_id = v_g;
  select count(*) into n_g_lines from public.project_products l join public.projects p on p.id = l.project_id where p.owner_user_id = v_g;
  select count(*) into n_i_rfqs from public.rfqs where requester_user_id = v_i;
  execute data_fp into data0;

  grant_i := format('update public.profiles set plan = %L, plan_source = %L, plan_granted_at = now(), plan_note = %L where id = %L',
                    'individual_founder', 'manual_pilot', 'Ensayo P2 (revertido)', v_i);
  grant_f_req := format('update public.profiles set plan = %L where id = %L', 'individual_founder', v_f);
  grant_f_sub := format('update public.profiles set plan = %L, plan_source = %L where id = %L', 'individual_founder', 'subscription', v_f);
  grant_s := format('update public.profiles set plan = %L, plan_source = %L where id = %L', 'individual_founder', 'manual_pilot', v_s);

  for t in
    select * from (values
      -- ========== A · precios del catálogo ==========
      ('A01 sin sesión: la función no es ejecutable por anon', 'anon', null::text, null::text, null::text[],
         array['select count(*) from public.catalog_published_prices()'], 'exec', '42501'),
      ('A02 Gratis con datos → 42501[plan_required], ninguna fila ni estado', 'authenticated', v_g::text, 'aal1', null,
         array['select count(*) from public.catalog_published_prices()'], 'exec', '42501[plan_required]'),
      ('A03 Gratis sin datos → 42501[plan_required]', 'authenticated', v_f::text, 'aal1', null,
         array['select count(*) from public.catalog_published_prices()'], 'exec', '42501[plan_required]'),
      ('A04 plan solicitado sin habilitar (individual_founder + default) → 42501[plan_required]', 'authenticated', v_f::text, 'aal1', array[grant_f_req],
         array['select count(*) from public.catalog_published_prices()'], 'exec', '42501[plan_required]'),
      ('A05 suscripción reservada (subscription) todavía no concede → 42501[plan_required]', 'authenticated', v_f::text, 'aal1', array[grant_f_sub],
         array['select count(*) from public.catalog_published_prices()'], 'exec', '42501[plan_required]'),
      ('A06 Individual habilitado (manual_pilot) → todas las filas publicadas', 'authenticated', v_i::text, 'aal1', array[grant_i],
         array['select count(*) from public.catalog_published_prices()'], 'count', n_prices::text),
      ('A07 distribuidor verificado → todas las filas, también de otras empresas (D4)', 'authenticated', v_s::text, 'aal1', null,
         array[format('select count(*) from public.catalog_published_prices() c join public.products p on p.id = c.product_id where p.distributor_id <> %L', v_s_dist)],
         'count', n_other::text),
      ('A08 distribuidor sin verificar → 42501[distributor_unverified] (E3)', 'authenticated', v_s::text, 'aal1',
         array[format('update public.distributor_profiles set verification_status = %L where user_id = %L', 'pending_verification', v_s)],
         array['select count(*) from public.catalog_published_prices()'], 'exec', '42501[distributor_unverified]'),
      ('A09 Mobau con aal2 → todas las filas', 'authenticated', v_m::text, 'aal2', null,
         array['select count(*) from public.catalog_published_prices()'], 'count', n_prices::text),
      ('A10 Mobau sin aal2 → todas las filas (E4)', 'authenticated', v_m::text, 'aal1', null,
         array['select count(*) from public.catalog_published_prices()'], 'count', n_prices::text),
      ('A11 Mobau revocado → 42501[plan_required]', 'authenticated', v_m::text, 'aal2',
         array[format('update public.mobau_admins set revoked_at = now() where user_id = %L', v_m)],
         array['select count(*) from public.catalog_published_prices()'], 'exec', '42501[plan_required]'),
      ('A12 Gratis no lee product_prices directamente (sin cambio)', 'authenticated', v_g::text, 'aal1', null,
         array['select count(*) from public.product_prices'], 'count', '0'),
      ('A13 Individual habilitado tampoco lee product_prices directamente (solo la función)', 'authenticated', v_i::text, 'aal1', array[grant_i],
         array['select count(*) from public.product_prices'], 'count', '0'),
      -- ========== B · función de acceso y datos de plan ==========
      ('B01 my_professional_access() Gratis = false', 'authenticated', v_g::text, 'aal1', null,
         array['select public.my_professional_access()::text'], 'text', 'false'),
      ('B02 my_professional_access() Individual habilitado = true', 'authenticated', v_i::text, 'aal1', array[grant_i],
         array['select public.my_professional_access()::text'], 'text', 'true'),
      ('B03 plan solicitado sin habilitar = false', 'authenticated', v_f::text, 'aal1', array[grant_f_req],
         array['select public.my_professional_access()::text'], 'text', 'false'),
      ('B04 distribuidor con plan habilitado = false (rol supplier excluido)', 'authenticated', v_s::text, 'aal1', array[grant_s],
         array['select public.my_professional_access()::text'], 'text', 'false'),
      ('B05 anon no ejecuta my_professional_access()', 'anon', null, null, null,
         array['select public.my_professional_access()'], 'exec', '42501'),
      ('B06 el cliente no escribe su plan_source', 'authenticated', v_g::text, 'aal1', null,
         array[format('update public.profiles set plan_source = %L where id = %L', 'manual_pilot', v_g)], 'exec', '42501'),
      ('B07 el cliente no escribe su plan', 'authenticated', v_g::text, 'aal1', null,
         array[format('update public.profiles set plan = %L where id = %L', 'individual_founder', v_g)], 'exec', '42501'),
      ('B08 el cliente no cambia plans (RLS sin política de escritura)', 'authenticated', v_g::text, 'aal1', null,
         array['update public.plans set includes_professional_tools = true where id = ''free_trial'''], 'rows', 'ok rows=0'),
      ('B09 el cliente no lee la auditoría de habilitaciones', 'authenticated', v_g::text, 'aal1', null,
         array['select count(*) from mobau_private.plan_events'], 'exec', '42501'),
      -- ========== C · Gratis con datos (E5/E5b) ==========
      ('C01 Gratis lee sus proyectos (solo lectura)', 'authenticated', v_g::text, 'aal1', null,
         array[format('select count(*) from public.projects where owner_user_id = %L', v_g)], 'count', n_g_proj::text),
      ('C02 Gratis lee sus líneas', 'authenticated', v_g::text, 'aal1', null,
         array[format('select count(*) from public.project_products l join public.projects p on p.id = l.project_id where p.owner_user_id = %L', v_g)], 'count', n_g_lines::text),
      ('C03 Gratis sin proyectos no crea uno → 42501 (política de plan)', 'authenticated', v_f::text, 'aal1', null,
         array[format(ins_proj, v_f, 'P2 Gratis', 'null')], 'exec', '42501'),
      ('C04 Gratis con 1 activo no crea otro → P0001 (el trigger, BEFORE, actúa antes que la RLS)', 'authenticated', v_g::text, 'aal1', null,
         array[format(ins_proj, v_g, 'P2 Gratis 2', 'null')], 'exec', 'P0001'),
      ('C05 Gratis no edita su proyecto', 'authenticated', v_g::text, 'aal1', null,
         array[format('update public.projects set name = name || %L where id = %L', ' (P2)', p_g_act)], 'rows', 'ok rows=0'),
      ('C06 Gratis no archiva su proyecto', 'authenticated', v_g::text, 'aal1', null,
         array[format('update public.projects set status = %L where id = %L', 'archived', p_g_act)], 'rows', 'ok rows=0'),
      ('C07 Gratis no añade líneas', 'authenticated', v_g::text, 'aal1', null,
         array[format('insert into public.project_products (project_id, product_id, quantity, unit) values (%L, %L, 1, %L)', p_g_act, v_prod, 'ud.')], 'exec', '42501'),
      ('C08 Gratis no edita líneas', 'authenticated', v_g::text, 'aal1', null,
         array[format('update public.project_products set quantity = quantity + 1 where project_id = %L', p_g_act)], 'rows', 'ok rows=0'),
      ('C09 Gratis no borra líneas', 'authenticated', v_g::text, 'aal1', null,
         array[format('delete from public.project_products where project_id = %L', p_g_act)], 'rows', 'ok rows=0'),
      ('C10 Gratis no envía solicitudes', 'authenticated', v_g::text, 'aal1', null,
         array[format(ins_rfq, p_g_act, v_g, 'P2', 'p2@example.test')], 'exec', '42501'),
      ('C11 Gratis (cuenta Individual sin habilitar) lee su historial de solicitudes', 'authenticated', v_i::text, 'aal1', null,
         array[format('select count(*) from public.rfqs where requester_user_id = %L', v_i)], 'count', n_i_rfqs::text),
      ('C12 Gratis elimina un archivado propio sin solicitudes; sus líneas se borran en cascada (E5b)', 'authenticated', v_i::text, 'aal1', null,
         array[format('delete from public.projects where id = %L', p_i_arch_free), 'reset role',
               format('select (select count(*) from public.projects where id = %L) + (select count(*) from public.project_products where project_id = %L)', p_i_arch_free, p_i_arch_free)],
         'count', '0'),
      ('C13 Gratis no elimina un archivado con solicitudes → 23503 (se respetan las solicitudes)', 'authenticated', v_i::text, 'aal1', null,
         array[format('delete from public.projects where id = %L', p_i_arch_rfq)], 'exec', '23503'),
      ('C14 Gratis no elimina un proyecto activo (sin cambio)', 'authenticated', v_g::text, 'aal1', null,
         array[format('delete from public.projects where id = %L', p_g_act)], 'rows', 'ok rows=0'),
      -- ========== D · Individual habilitado (E9) ==========
      ('D01 Individual con 1 activo crea un segundo', 'authenticated', v_i::text, 'aal1', array[grant_i],
         array[format(ins_proj, v_i, 'P2 Individual 2', 'null')], 'rows', 'ok rows=1'),
      ('D02 Individual no crea un tercero activo → P0001', 'authenticated', v_i::text, 'aal1', array[grant_i],
         array[format(ins_proj, v_i, 'P2 Individual 2', 'null'), format(ins_proj, v_i, 'P2 Individual 3', 'null')], 'exec', 'P0001'),
      ('D03 Individual reactiva un archivado dentro del cupo (sin el bloqueo antiguo)', 'authenticated', v_i::text, 'aal1', array[grant_i],
         array[format('update public.projects set status = %L where id = %L', 'active', p_i_arch_free2)], 'rows', 'ok rows=1'),
      ('D04 Individual no reactiva por encima del cupo → P0001', 'authenticated', v_i::text, 'aal1', array[grant_i],
         array[format('update public.projects set status = %L where id = %L', 'active', p_i_arch_free2),
               format('update public.projects set status = %L where id = %L', 'active', p_i_arch_free3)], 'exec', 'P0001'),
      ('D05 Individual edita su proyecto', 'authenticated', v_i::text, 'aal1', array[grant_i],
         array[format('update public.projects set name = name || %L where id = %L', ' (P2)', p_i_act)], 'rows', 'ok rows=1'),
      ('D06 Individual archiva su proyecto', 'authenticated', v_i::text, 'aal1', array[grant_i],
         array[format('update public.projects set status = %L where id = %L', 'archived', p_i_act)], 'rows', 'ok rows=1'),
      ('D07 Individual añade una línea con un producto publicado', 'authenticated', v_i::text, 'aal1', array[grant_i],
         array[format('insert into public.project_products (project_id, product_id, quantity, unit) values (%L, %L, 1, %L)', p_i_act, v_prod, 'ud.')], 'rows', 'ok rows=1'),
      ('D08 Individual envía una solicitud de su proyecto activo', 'authenticated', v_i::text, 'aal1', array[grant_i],
         array[format(ins_rfq, p_i_act, v_i, 'P2', 'p2@example.test')], 'rows', 'ok rows=1'),
      -- ========== E · studio_id (R2) ==========
      ('E01 nadie crea un proyecto en el estudio de otra persona → 42501', 'authenticated', v_i::text, 'aal1',
         array[grant_i, format('insert into public.studios (id, name) values (%L, %L)', v_studio, 'Estudio ensayo P2')],
         array[format(ins_proj, v_i, 'P2 en otro estudio', quote_literal(v_studio))], 'exec', '42501'),
      ('E02 nadie mueve un proyecto propio al estudio de otra persona → 42501', 'authenticated', v_i::text, 'aal1',
         array[grant_i, format('insert into public.studios (id, name) values (%L, %L)', v_studio, 'Estudio ensayo P2')],
         array[format('update public.projects set studio_id = %L where id = %L', v_studio, p_i_act)], 'exec', '42501'),
      ('E03 sí en el estudio propio (el trigger cuenta por estudio y bloquea su fila)', 'authenticated', v_i::text, 'aal1',
         array[grant_i, format('insert into public.studios (id, name) values (%L, %L)', v_studio, 'Estudio ensayo P2'),
               format('update public.profiles set studio_id = %L where id = %L', v_studio, v_i)],
         array[format(ins_proj, v_i, 'P2 en mi estudio', quote_literal(v_studio))], 'rows', 'ok rows=1'),
      -- ========== F · trigger (R1, E9) ==========
      ('F01 el trigger bloquea la fila antes de contar y no tiene el bloqueo antiguo de reactivación', '-', null, null, null,
         array['select count(*) from pg_proc where oid = ''public.enforce_active_project_limit()''::regprocedure'
               || ' and prosrc ~ ''for update of s'' and prosrc ~ ''for update of pr'' and prosrc !~ ''v_owner_max'''], 'count', '1'),
      -- ========== G · distribuidor y Mobau sin cambios ==========
      -- G01: su proyecto activo histórico hace que el trigger (BEFORE) rechace
      -- primero con P0001; la RLS (proveedor, plan) también lo rechazaría. Es
      -- el comportamiento de hoy, sin cambio.
      ('G01 distribuidor no crea proyectos (sin cambio: P0001 del trigger, antes que la RLS)', 'authenticated', v_s::text, 'aal1', null,
         array[format(ins_proj, v_s, 'P2 distribuidor', 'null')], 'exec', 'P0001'),
      ('G02 distribuidor lee sus propios precios (sin cambio)', 'authenticated', v_s::text, 'aal1', null,
         array['select count(*) from public.product_prices'], 'count', n_own_prices::text),
      ('G03 Mobau con aal2 lee todos los precios en moderación (sin cambio)', 'authenticated', v_m::text, 'aal2', null,
         array['select count(*) from public.product_prices'], 'count', n_all_prices::text),
      ('G04 Mobau sin aal2 no lee product_prices directamente (sin cambio)', 'authenticated', v_m::text, 'aal1', null,
         array['select count(*) from public.product_prices'], 'count', '0'),
      -- ========== Z · fuera de los casos ==========
      ('Z01 sin restos: datos idénticos, sin estudios, habilitaciones ni eventos', '-', null, null, null,
         array[format('select count(*) where (%s) = %L and not exists (select 1 from public.studios)'
                      || ' and not exists (select 1 from public.profiles where plan_source <> ''default'')'
                      || ' and not exists (select 1 from mobau_private.plan_events)'
                      || ' and (select verification_status from public.distributor_profiles where user_id = %L) = ''verified'''
                      || ' and (select revoked_at from public.mobau_admins where user_id = %L) is null',
                      data_fp, data0, v_s, v_m)], 'count', '1')
    ) as c(name, role, sub, aal, setup, sql, kind, expect)
  loop
    v_got := null;
    begin
      if t.setup is not null then
        foreach v_stmt in array t.setup loop execute v_stmt; end loop;
      end if;
      if t.role <> '-' then execute format('set local role %I', t.role); end if;
      perform set_config('request.jwt.claim.sub', coalesce(t.sub, ''), true);
      perform set_config('request.jwt.claim.role', '', true);
      perform set_config('request.jwt.claims',
        case when t.sub is null then '' else json_build_object('sub', t.sub, 'role', t.role, 'aal', t.aal)::text end, true);
      for i in 1 .. array_length(t.sql, 1) loop
        if i < array_length(t.sql, 1) then
          execute t.sql[i];
        elsif t.kind = 'count' then
          execute t.sql[i] into v_n; v_got := v_n::text;
        elsif t.kind = 'text' then
          execute t.sql[i] into v_got;
        else
          execute t.sql[i]; get diagnostics v_n = row_count; v_got := 'ok rows=' || v_n;
        end if;
      end loop;
      raise exception using errcode = 'MB001';
    exception
      when sqlstate 'MB001' then null;
      when others then
        get stacked diagnostics v_hint = pg_exception_hint;
        v_got := sqlstate || ' [' || coalesce(v_hint, '') || '] ' || left(sqlerrm, 160);
    end;
    v_ok := case
      when t.kind = 'exec' and t.expect ~ '^[0-9A-Z]{5}\[' then left(v_got, length(t.expect) + 1) = substr(t.expect, 1, 5) || ' ' || substr(t.expect, 6)
      when t.kind = 'exec' and t.expect ~ '^[0-9A-Z]{5}$' then left(v_got, 6) = t.expect || ' '
      else v_got = t.expect
    end;
    n_total := n_total + 1;
    if v_ok then n_ok := n_ok + 1; end if;
    r := r || jsonb_build_object('prueba', t.name, 'esperado', t.expect, 'obtenido', v_got, 'ok', coalesce(v_ok, false));
  end loop;

  raise exception 'MOBAU_43_P2_SUITE total=% ok=% fallos=% :: %', n_total, n_ok, n_total - n_ok, r::text
    using errcode = 'MB999';
end $P2S$;
$P2C$;
  r4 text := $P2D$-- ============================================================
-- RECUPERACIÓN NO EJECUTADA (43-D2 · inversa de T4) — no ejecutar sin aprobación explícita
-- ============================================================
-- Devuelve el servidor al estado de T1 (preparación): elimina las 8 políticas
-- RESTRICTIVE de T4, restaura catalog_published_prices y
-- enforce_active_project_limit con sus cuerpos de partida exactos
-- (comprobados por md5(prosrc)) y vuelve a los límites 1 y 5. No borra datos.
-- Si se ejecuta de verdad, se aplica como migración nueva y se registra
-- aparte tras su COMMIT. Antes, devolver la web a una versión que no dependa
-- del control por plan en el servidor.
-- ============================================================

BEGIN;

DO $$
begin
  if current_user <> 'postgres' then
    raise exception '43-R4: ejecutar como postgres';
  end if;
  if (select count(*) from pg_policies where schemaname = 'public' and policyname in
      ('projects_plan_insert', 'projects_plan_update', 'projects_studio_own_insert', 'projects_studio_own_update',
       'project_products_plan_insert', 'project_products_plan_update', 'project_products_plan_delete', 'rfqs_plan_insert')) <> 8 then
    raise exception '43-R4: T4 no está aplicada (faltan políticas)';
  end if;
end $$;

drop policy projects_plan_insert on public.projects;
drop policy projects_plan_update on public.projects;
drop policy projects_studio_own_insert on public.projects;
drop policy projects_studio_own_update on public.projects;
drop policy project_products_plan_insert on public.project_products;
drop policy project_products_plan_update on public.project_products;
drop policy project_products_plan_delete on public.project_products;
drop policy rfqs_plan_insert on public.rfqs;

update public.plans set max_active_projects = 1 where id = 'individual_founder';
update public.plans set max_active_projects = 5 where id = 'studio_founder';

CREATE OR REPLACE FUNCTION public.catalog_published_prices(p_product_ids text[] DEFAULT NULL::text[], p_after text DEFAULT NULL::text, p_limit integer DEFAULT 1000)
 RETURNS TABLE(product_id text, price_amount numeric, currency text, price_status text, includes_itbis boolean, itbis_rate numeric, es_demo boolean)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if (select auth.uid()) is null then
    raise exception 'Inicia sesión para consultar precios.' using errcode = '42501';
  end if;
  if p_limit is null or p_limit < 1 or p_limit > 1000 then
    raise exception 'p_limit debe estar entre 1 y 1000.' using errcode = '22023';
  end if;
  if p_product_ids is not null and pg_catalog.cardinality(p_product_ids) > 200 then
    raise exception 'Como máximo 200 productos por consulta.' using errcode = '22023';
  end if;
  if p_after is not null and pg_catalog.char_length(p_after) > 200 then
    raise exception 'p_after no puede superar 200 caracteres.'
      using errcode = '22023';
  end if;

  return query
    select pp.product_id,
           case when pp.price_status = 'published' then pp.price_amount end,
           pp.currency,
           pp.price_status,
           pp.includes_itbis,
           pp.itbis_rate,
           coalesce(pp.price_source = 'demo', false)
      from public.product_prices pp
      join public.products p on p.id = pp.product_id
     where p.publication_status = 'published'
       -- 41-02: defensa redundante (las CHECK de 41-01 y el espejo de status ya
       -- lo garantizan): nunca un producto inactivo, retirado o en papelera.
       and p.status = 'active'
       and p.retired_at is null
       and p.trashed_at is null
       and pp.price_status in ('published', 'quote_required', 'pending_confirmation', 'unavailable')
       and (p_product_ids is null or pp.product_id = any (p_product_ids))
       and (p_after is null or pp.product_id > p_after)
     order by pp.product_id
     limit p_limit;
end;
$function$;

DO $do$
begin
  execute $hd$CREATE OR REPLACE FUNCTION public.enforce_active_project_limit()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$$hd$
    || pg_catalog.replace($rb$
declare
  v_limit int;
  v_current_count int;
  v_is_reactivation boolean;
  v_owner_max int;
begin
  if new.status <> 'active' then
    return new;
  end if;

  v_is_reactivation := (TG_OP = 'UPDATE' and old.status = 'archived' and new.status = 'active');

  -- Bloquea toda reactivación cuando el plan del dueño (o del estudio,
  -- si el proyecto pertenece a uno) permite un único proyecto activo.
  if v_is_reactivation then
    if new.studio_id is not null then
      select pl.max_active_projects into v_owner_max
      from public.studios s join public.plans pl on pl.id = s.plan
      where s.id = new.studio_id;
    else
      select pl.max_active_projects into v_owner_max
      from public.profiles pr join public.plans pl on pl.id = pr.plan
      where pr.id = new.owner_user_id;
    end if;

    if v_owner_max = 1 then
      raise exception 'Los proyectos archivados no se pueden reactivar en tu plan actual. Crea un proyecto nuevo en su lugar.';
    end if;
  end if;

  if new.studio_id is not null then
    select pl.max_active_projects into v_limit
    from public.studios s join public.plans pl on pl.id = s.plan
    where s.id = new.studio_id;
    select count(*) into v_current_count
    from public.projects p
    where p.studio_id = new.studio_id and p.status = 'active'
      and p.id <> coalesce(new.id, '00000000-0000-0000-0000-000000000000'::uuid);
  else
    select pl.max_active_projects into v_limit
    from public.profiles pr join public.plans pl on pl.id = pr.plan
    where pr.id = new.owner_user_id;
    select count(*) into v_current_count
    from public.projects p
    where p.owner_user_id = new.owner_user_id and p.studio_id is null and p.status = 'active'
      and p.id <> coalesce(new.id, '00000000-0000-0000-0000-000000000000'::uuid);
  end if;

  if v_current_count >= v_limit then
    raise exception 'Límite de proyectos activos alcanzado (%). Archiva un proyecto existente o cambia de plan.', v_limit;
  end if;

  return new;
end;
$rb$, E'\n', E'\r\n')
    || '$function$';
end $do$;

DO $$
begin
  if (select md5(prosrc) from pg_proc where oid = 'public.catalog_published_prices(text[], text, integer)'::regprocedure) <> '366f275cf85ec6c10956cecfbbc92ed5'
     or (select md5(prosrc) from pg_proc where oid = 'public.enforce_active_project_limit()'::regprocedure) <> '40e11d31467d9719f439ab5be096a92a' then
    raise exception '43-R4: las funciones no quedaron idénticas a las de partida';
  end if;
  if (select count(*) from pg_policies where schemaname = 'public' and tablename in ('projects', 'project_products', 'rfqs')) <> 17 then
    raise exception '43-R4: no quedaron las 17 políticas de partida';
  end if;
  if (select string_agg(id || ':' || max_active_projects, '|' order by id) from public.plans) <> 'free_trial:1|individual_founder:1|studio_founder:5' then
    raise exception '43-R4: límites no restaurados';
  end if;
  if (select proacl::text from pg_proc where oid = 'public.catalog_published_prices(text[], text, integer)'::regprocedure)
     <> '{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}' then
    raise exception '43-R4: permisos de catalog_published_prices cambiados';
  end if;
end $$;

COMMIT;
$P2D$;
  r1 text := $P2E$-- ============================================================
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
$P2E$;
  fp_a text; beh_a text; beh_t1 text; beh_t4 text; beh_r4 text; fp_b text; suite_msg text;
  b int; e int; v text;
begin
  if md5(t1) <> '7a50ed85b5561b057b205f5369679b89' or md5(t4) <> '1482715a3557737763e27c60733b7201' or md5(sx) <> 'e3e4be5e65b96baf15f63de6a6cbcf22'
     or md5(r4) <> '8660569229611f7d774c2462b95888d0' or md5(r1) <> 'c0aeb415b682b3ad91f4e2fe6864da10' then
    raise exception 'MB997: algún texto recibido no coincide con su archivo' using errcode = 'MB997';
  end if;

  execute 'select ' || $q$pg_catalog.md5(pg_catalog.md5((select md5(prosrc) || proacl::text from pg_proc where oid = 'public.catalog_published_prices(text[], text, integer)'::regprocedure) || (select md5(prosrc) || proacl::text from pg_proc where oid = 'public.enforce_active_project_limit()'::regprocedure) || coalesce((select string_agg(tablename || policyname || permissive || cmd || roles::text || coalesce(qual, '') || coalesce(with_check, ''), '|' order by tablename, policyname)     from pg_policies where schemaname = 'public' and tablename in ('projects', 'project_products', 'rfqs')), '') || (select string_agg(id || ':' || max_active_projects || ':' || max_users, '|' order by id) from public.plans) || (select string_agg(tgname || pg_get_triggerdef(oid), '|' order by tgname) from pg_trigger where tgrelid = 'public.projects'::regclass and not tgisinternal)) || (select json_agg(p order by p.id)::text from public.plans p) || (select string_agg(table_name || '.' || column_name || ':' || data_type || ':' || coalesce(column_default, ''), '|' order by table_name, ordinal_position)     from information_schema.columns where table_schema = 'public' and table_name in ('plans', 'profiles')) || coalesce((select string_agg(n.nspname || '.' || p.proname || md5(p.prosrc) || coalesce(p.proacl::text, ''), '|' order by n.nspname, p.proname)     from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname in ('public', 'mobau_private')), '') || (select count(*)::text from pg_policies where schemaname in ('public', 'mobau_private')) || coalesce(to_regclass('mobau_private.plan_events')::text, 'sin-plan_events') || md5(coalesce((select string_agg(id::text || status || coalesce(studio_id::text, '-') || owner_user_id::text || name || updated_at::text, '|' order by id) from public.projects), '')     || coalesce((select string_agg(id::text || quantity::text || coalesce(unit, '-') || selected_for_rfq::text, '|' order by id) from public.project_products), '')     || coalesce((select string_agg(id::text || status, '|' order by id) from public.rfqs), '')     || coalesce((select string_agg(id::text || plan || role || subscription_status, '|' order by id) from public.profiles), '')     || coalesce((select string_agg(id::text, '|' order by id) from public.studios), '')))$q$ into fp_a;
  execute 'select ' || $q$pg_catalog.md5((select md5(prosrc) || proacl::text from pg_proc where oid = 'public.catalog_published_prices(text[], text, integer)'::regprocedure) || (select md5(prosrc) || proacl::text from pg_proc where oid = 'public.enforce_active_project_limit()'::regprocedure) || coalesce((select string_agg(tablename || policyname || permissive || cmd || roles::text || coalesce(qual, '') || coalesce(with_check, ''), '|' order by tablename, policyname)     from pg_policies where schemaname = 'public' and tablename in ('projects', 'project_products', 'rfqs')), '') || (select string_agg(id || ':' || max_active_projects || ':' || max_users, '|' order by id) from public.plans) || (select string_agg(tgname || pg_get_triggerdef(oid), '|' order by tgname) from pg_trigger where tgrelid = 'public.projects'::regclass and not tgisinternal))$q$ into beh_a;

  foreach v in array array[t1] loop
    b := strpos(v, E'\nBEGIN;\n'); e := strpos(v, E'\nCOMMIT;\n');
    execute substr(v, b + 8, e - (b + 8));
  end loop;
  execute 'select ' || $q$pg_catalog.md5((select md5(prosrc) || proacl::text from pg_proc where oid = 'public.catalog_published_prices(text[], text, integer)'::regprocedure) || (select md5(prosrc) || proacl::text from pg_proc where oid = 'public.enforce_active_project_limit()'::regprocedure) || coalesce((select string_agg(tablename || policyname || permissive || cmd || roles::text || coalesce(qual, '') || coalesce(with_check, ''), '|' order by tablename, policyname)     from pg_policies where schemaname = 'public' and tablename in ('projects', 'project_products', 'rfqs')), '') || (select string_agg(id || ':' || max_active_projects || ':' || max_users, '|' order by id) from public.plans) || (select string_agg(tgname || pg_get_triggerdef(oid), '|' order by tgname) from pg_trigger where tgrelid = 'public.projects'::regclass and not tgisinternal))$q$ into beh_t1;

  b := strpos(t4, E'\nBEGIN;\n'); e := strpos(t4, E'\nCOMMIT;\n');
  execute substr(t4, b + 8, e - (b + 8));
  execute 'select ' || $q$pg_catalog.md5((select md5(prosrc) || proacl::text from pg_proc where oid = 'public.catalog_published_prices(text[], text, integer)'::regprocedure) || (select md5(prosrc) || proacl::text from pg_proc where oid = 'public.enforce_active_project_limit()'::regprocedure) || coalesce((select string_agg(tablename || policyname || permissive || cmd || roles::text || coalesce(qual, '') || coalesce(with_check, ''), '|' order by tablename, policyname)     from pg_policies where schemaname = 'public' and tablename in ('projects', 'project_products', 'rfqs')), '') || (select string_agg(id || ':' || max_active_projects || ':' || max_users, '|' order by id) from public.plans) || (select string_agg(tgname || pg_get_triggerdef(oid), '|' order by tgname) from pg_trigger where tgrelid = 'public.projects'::regclass and not tgisinternal))$q$ into beh_t4;

  begin
    execute sx;
    suite_msg := 'la suite terminó sin MB999 (anómalo)';
  exception
    when sqlstate 'MB999' then suite_msg := sqlerrm;
    when others then suite_msg := 'SUITE INTERRUMPIDA ' || sqlstate || ': ' || sqlerrm;
  end;

  b := strpos(r4, E'\nBEGIN;\n'); e := strpos(r4, E'\nCOMMIT;\n');
  execute substr(r4, b + 8, e - (b + 8));
  execute 'select ' || $q$pg_catalog.md5((select md5(prosrc) || proacl::text from pg_proc where oid = 'public.catalog_published_prices(text[], text, integer)'::regprocedure) || (select md5(prosrc) || proacl::text from pg_proc where oid = 'public.enforce_active_project_limit()'::regprocedure) || coalesce((select string_agg(tablename || policyname || permissive || cmd || roles::text || coalesce(qual, '') || coalesce(with_check, ''), '|' order by tablename, policyname)     from pg_policies where schemaname = 'public' and tablename in ('projects', 'project_products', 'rfqs')), '') || (select string_agg(id || ':' || max_active_projects || ':' || max_users, '|' order by id) from public.plans) || (select string_agg(tgname || pg_get_triggerdef(oid), '|' order by tgname) from pg_trigger where tgrelid = 'public.projects'::regclass and not tgisinternal))$q$ into beh_r4;

  b := strpos(r1, E'\nBEGIN;\n'); e := strpos(r1, E'\nCOMMIT;\n');
  execute substr(r1, b + 8, e - (b + 8));
  execute 'select ' || $q$pg_catalog.md5(pg_catalog.md5((select md5(prosrc) || proacl::text from pg_proc where oid = 'public.catalog_published_prices(text[], text, integer)'::regprocedure) || (select md5(prosrc) || proacl::text from pg_proc where oid = 'public.enforce_active_project_limit()'::regprocedure) || coalesce((select string_agg(tablename || policyname || permissive || cmd || roles::text || coalesce(qual, '') || coalesce(with_check, ''), '|' order by tablename, policyname)     from pg_policies where schemaname = 'public' and tablename in ('projects', 'project_products', 'rfqs')), '') || (select string_agg(id || ':' || max_active_projects || ':' || max_users, '|' order by id) from public.plans) || (select string_agg(tgname || pg_get_triggerdef(oid), '|' order by tgname) from pg_trigger where tgrelid = 'public.projects'::regclass and not tgisinternal)) || (select json_agg(p order by p.id)::text from public.plans p) || (select string_agg(table_name || '.' || column_name || ':' || data_type || ':' || coalesce(column_default, ''), '|' order by table_name, ordinal_position)     from information_schema.columns where table_schema = 'public' and table_name in ('plans', 'profiles')) || coalesce((select string_agg(n.nspname || '.' || p.proname || md5(p.prosrc) || coalesce(p.proacl::text, ''), '|' order by n.nspname, p.proname)     from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname in ('public', 'mobau_private')), '') || (select count(*)::text from pg_policies where schemaname in ('public', 'mobau_private')) || coalesce(to_regclass('mobau_private.plan_events')::text, 'sin-plan_events') || md5(coalesce((select string_agg(id::text || status || coalesce(studio_id::text, '-') || owner_user_id::text || name || updated_at::text, '|' order by id) from public.projects), '')     || coalesce((select string_agg(id::text || quantity::text || coalesce(unit, '-') || selected_for_rfq::text, '|' order by id) from public.project_products), '')     || coalesce((select string_agg(id::text || status, '|' order by id) from public.rfqs), '')     || coalesce((select string_agg(id::text || plan || role || subscription_status, '|' order by id) from public.profiles), '')     || coalesce((select string_agg(id::text, '|' order by id) from public.studios), '')))$q$ into fp_b;

  raise exception 'MOBAU_43_P2 t1_inerte=% t4_cambia=% r4_vuelve_a_t1=% final_identico=% huella_partida=% huella_final=% :: %',
    (beh_t1 = beh_a), (beh_t4 <> beh_t1), (beh_r4 = beh_t1), (fp_b = fp_a), fp_a, fp_b, suite_msg
    using errcode = 'MB990';
end $P2W$;

ROLLBACK;
