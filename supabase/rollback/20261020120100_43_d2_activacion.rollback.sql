-- ============================================================
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
