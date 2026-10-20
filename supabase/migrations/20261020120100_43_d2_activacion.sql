-- ============================================================
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
