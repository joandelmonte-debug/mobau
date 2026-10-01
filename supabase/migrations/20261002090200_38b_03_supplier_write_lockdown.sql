-- ============================================================
-- PROPUESTA NO EJECUTADA (38-B) — no ejecutar sin aprobación explícita
-- ============================================================
-- 38-B · 03 · Bloqueo de escrituras de distribuidor
-- ------------------------------------------------------------
-- TRANSACCIÓN ATÓMICA: todo el archivo va entre BEGIN y COMMIT y se
-- ejecuta completo, de una vez. No partirlo ni ejecutarlo por
-- fragmentos. Si cualquier comprobación o sentencia falla, se revierte
-- todo (función, permisos, REVOKE y políticas). Si falla, NO se
-- continúa con 04.
--
-- Requiere 38-B · 01 y 02.
--
-- 1) products y product_prices: ninguna escritura desde el cliente
--    durante 38-B (ni distribuidores ni nadie). Se retiran los
--    permisos INSERT/UPDATE de anon y authenticated; revocar el
--    privilegio de tabla retira también los permisos por columna. Las
--    políticas *_own_verified se conservan intactas (sin permiso de
--    escritura no tienen efecto) para que el rollback sea un GRANT.
--    La carga inicial y la moderación se hacen desde Supabase.
--    Tras cada REVOKE se comprueba el permiso EFECTIVO con
--    has_table_privilege / has_column_privilege /
--    has_any_column_privilege: si queda alguno, se aborta todo. No se
--    confía en el grantor ni en information_schema.
--
-- 2) projects, project_products y rfqs: un perfil con
--    role = 'supplier' no puede insertar ni actualizar. Se hace con
--    políticas RESTRICTIVE, que se combinan con AND con las actuales:
--    no cambian nada para quien no es distribuidor.
--    DELETE no se toca: un distribuidor conserva el borrado de sus
--    propios datos existentes, con las mismas condiciones de hoy
--    (proyecto propio archivado / línea de proyecto propio activo).
--    Un UPDATE bloqueado por la parte USING afecta a 0 filas sin error.
--
-- profiles.role no es modificable por el usuario (phase0: authenticated
-- solo puede actualizar profiles.name), así que is_supplier() no se
-- puede eludir cambiando el propio rol.
--
-- Quién puede aplicar esta migración: un rol de administración de
-- Supabase capaz de retirar los permisos actuales de products y
-- product_prices (p. ej. postgres). Al empezar se muestran, solo como
-- auditoría (NOTICE), el rol ejecutor, si es superusuario y los
-- propietarios de ambas tablas; no se aborta por esa inferencia. La
-- capacidad práctica queda demostrada por el resultado efectivo
-- posterior al REVOKE: si cualquier permiso de escritura sigue siendo
-- efectivo, se aborta y se revierte toda la transacción.
--
-- Rollback: supabase/rollback/20261002090200_38b_03_supplier_write_lockdown.rollback.sql
-- ============================================================

BEGIN;

-- ---------- validaciones previas ----------
do $$
declare
  v_pol record;
begin
  -- Auditoría (no aborta): rol ejecutor, superusuario y propietarios.
  -- La garantía real es la comprobación de permisos efectivos tras cada REVOKE.
  raise notice '38-B 03 auditoría: current_user=%, superusuario=%, propietario products=%, propietario product_prices=%',
    current_user,
    (select rolsuper from pg_roles where rolname = current_user),
    (select pg_get_userbyid(relowner) from pg_class where oid = 'public.products'::regclass),
    (select pg_get_userbyid(relowner) from pg_class where oid = 'public.product_prices'::regclass);

  -- 38-B 01 aplicado (se comprueba también UPDATE de publication_status)
  if not exists (select 1 from information_schema.columns
                  where table_schema = 'public' and table_name = 'products' and column_name = 'publication_status') then
    raise exception '38-B 03: falta products.publication_status (aplicar antes 38-B 01)';
  end if;

  -- is_supplier() todavía no existe
  if exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
              where n.nspname = 'public' and p.proname = 'is_supplier') then
    raise exception '38-B 03: public.is_supplier() ya existe';
  end if;

  -- Ninguna de las cinco políticas objetivo existe
  if exists (select 1 from pg_policies
              where schemaname = 'public'
                and policyname in ('projects_supplier_no_insert', 'projects_supplier_no_update',
                                   'project_products_supplier_no_insert', 'project_products_supplier_no_update',
                                   'rfqs_supplier_no_insert')) then
    raise exception '38-B 03: alguna de las políticas restrictivas objetivo ya existe';
  end if;

  -- RLS activa en las tablas de cliente
  if exists (select 1 from pg_class
              where oid in ('public.projects'::regclass, 'public.project_products'::regclass, 'public.rfqs'::regclass)
                and not relrowsecurity) then
    raise exception '38-B 03: RLS no está activa en projects, project_products o rfqs';
  end if;

  -- Políticas permisivas que necesitan los profesionales (nombre, operación y modo)
  for v_pol in
    select * from (values
      ('projects', 'proyectos_select', 'SELECT'),
      ('projects', 'proyectos_insert', 'INSERT'),
      ('projects', 'proyectos_update', 'UPDATE'),
      ('projects', 'proyectos_delete', 'DELETE'),
      ('project_products', 'project_products_select', 'SELECT'),
      ('project_products', 'project_products_insert', 'INSERT'),
      ('project_products', 'project_products_update', 'UPDATE'),
      ('project_products', 'project_products_delete', 'DELETE'),
      ('rfqs', 'rfqs_select', 'SELECT'),
      ('rfqs', 'rfqs_insert', 'INSERT')
    ) as t(tablename, policyname, cmd)
  loop
    if not exists (select 1 from pg_policies
                    where schemaname = 'public' and tablename = v_pol.tablename
                      and policyname = v_pol.policyname and cmd = v_pol.cmd and permissive = 'PERMISSIVE') then
      raise exception '38-B 03: falta la política permisiva %.% (%)', v_pol.tablename, v_pol.policyname, v_pol.cmd;
    end if;
  end loop;
end $$;

-- Copia de las políticas actuales (para comprobar al final que ninguna cambió)
create temp table mobau_38b03_policies_before on commit drop as
  select tablename::text, policyname::text, cmd, permissive, roles::text as roles, qual, with_check
    from pg_policies
   where schemaname = 'public'
     and tablename in ('projects', 'project_products', 'rfqs', 'rfq_distributors');

-- ---------- función y permisos ----------
-- ¿La sesión actual es una cuenta de distribuidor?
create function public.is_supplier()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.profiles p
    where p.id = (select auth.uid()) and p.role = 'supplier'
  );
$$;

comment on function public.is_supplier() is
  '38-B: true si el usuario autenticado tiene profiles.role = supplier. Solo para políticas RLS.';

-- Supabase concede EXECUTE por defecto en el esquema public: se limita a authenticated
revoke all on function public.is_supplier() from public;
revoke all on function public.is_supplier() from anon;
grant execute on function public.is_supplier() to authenticated;

-- ---------- REVOKE: productos ----------
revoke insert, update on public.products from anon, authenticated;

-- Permiso efectivo tras el REVOKE de products (tabla, cualquier columna y cada columna)
do $$
declare
  v_role text; v_priv text; v_col text;
begin
  foreach v_role in array array['anon', 'authenticated'] loop
    foreach v_priv in array array['INSERT', 'UPDATE'] loop
      if has_table_privilege(v_role, 'public.products', v_priv)
         or has_any_column_privilege(v_role, 'public.products', v_priv) then
        raise exception '38-B 03: % conserva % efectivo sobre products', v_role, v_priv;
      end if;
      for v_col in
        select attname from pg_attribute
         where attrelid = 'public.products'::regclass and attnum > 0 and not attisdropped
      loop
        if has_column_privilege(v_role, 'public.products', v_col, v_priv) then
          raise exception '38-B 03: % conserva % efectivo sobre products.%', v_role, v_priv, v_col;
        end if;
      end loop;
    end loop;
  end loop;
end $$;

-- ---------- REVOKE: precios ----------
revoke insert, update on public.product_prices from anon, authenticated;

-- Permiso efectivo tras el REVOKE de product_prices
do $$
declare
  v_role text; v_priv text; v_col text;
begin
  foreach v_role in array array['anon', 'authenticated'] loop
    foreach v_priv in array array['INSERT', 'UPDATE'] loop
      if has_table_privilege(v_role, 'public.product_prices', v_priv)
         or has_any_column_privilege(v_role, 'public.product_prices', v_priv) then
        raise exception '38-B 03: % conserva % efectivo sobre product_prices', v_role, v_priv;
      end if;
      for v_col in
        select attname from pg_attribute
         where attrelid = 'public.product_prices'::regclass and attnum > 0 and not attisdropped
      loop
        if has_column_privilege(v_role, 'public.product_prices', v_col, v_priv) then
          raise exception '38-B 03: % conserva % efectivo sobre product_prices.%', v_role, v_priv, v_col;
        end if;
      end loop;
    end loop;
  end loop;
end $$;

-- ---------- políticas restrictivas ----------
-- distribuidor: sin altas ni cambios en proyectos, líneas ni solicitudes
create policy projects_supplier_no_insert
  on public.projects as restrictive
  for insert to authenticated
  with check (not (select public.is_supplier()));

create policy projects_supplier_no_update
  on public.projects as restrictive
  for update to authenticated
  using (not (select public.is_supplier()))
  with check (not (select public.is_supplier()));

create policy project_products_supplier_no_insert
  on public.project_products as restrictive
  for insert to authenticated
  with check (not (select public.is_supplier()));

create policy project_products_supplier_no_update
  on public.project_products as restrictive
  for update to authenticated
  using (not (select public.is_supplier()))
  with check (not (select public.is_supplier()));

create policy rfqs_supplier_no_insert
  on public.rfqs as restrictive
  for insert to authenticated
  with check (not (select public.is_supplier()));

-- ---------- validaciones finales ----------
do $$
declare
  v_pol record;
  n_restrictive int;
  n_changed int;
begin
  -- Las cinco políticas nuevas: RESTRICTIVE, solo authenticated, operación correcta
  for v_pol in
    select * from (values
      ('projects', 'projects_supplier_no_insert', 'INSERT'),
      ('projects', 'projects_supplier_no_update', 'UPDATE'),
      ('project_products', 'project_products_supplier_no_insert', 'INSERT'),
      ('project_products', 'project_products_supplier_no_update', 'UPDATE'),
      ('rfqs', 'rfqs_supplier_no_insert', 'INSERT')
    ) as t(tablename, policyname, cmd)
  loop
    if not exists (select 1 from pg_policies
                    where schemaname = 'public' and tablename = v_pol.tablename
                      and policyname = v_pol.policyname and cmd = v_pol.cmd and permissive = 'RESTRICTIVE'
                      and roles @> array['authenticated']::name[]
                      and roles <@ array['authenticated']::name[]) then
      raise exception '38-B 03: % no existe con la forma esperada (RESTRICTIVE, authenticated, %)', v_pol.policyname, v_pol.cmd;
    end if;
  end loop;

  -- Exactamente esas cinco restrictivas en las tablas de cliente
  select count(*) into n_restrictive
    from pg_policies
   where schemaname = 'public' and permissive = 'RESTRICTIVE'
     and tablename in ('projects', 'project_products', 'rfqs', 'rfq_distributors');
  if n_restrictive <> 5 then
    raise exception '38-B 03: se esperaban exactamente 5 políticas restrictivas; hay %', n_restrictive;
  end if;

  -- Ninguna política previa se eliminó ni se modificó
  select count(*) into n_changed from (
    (select * from mobau_38b03_policies_before
     except
     select tablename::text, policyname::text, cmd, permissive, roles::text, qual, with_check
       from pg_policies
      where schemaname = 'public' and tablename in ('projects', 'project_products', 'rfqs', 'rfq_distributors'))
    union all
    (select tablename::text, policyname::text, cmd, permissive, roles::text, qual, with_check
       from pg_policies
      where schemaname = 'public' and tablename in ('projects', 'project_products', 'rfqs', 'rfq_distributors')
        and policyname not in ('projects_supplier_no_insert', 'projects_supplier_no_update',
                               'project_products_supplier_no_insert', 'project_products_supplier_no_update',
                               'rfqs_supplier_no_insert')
     except
     select * from mobau_38b03_policies_before)
  ) d;
  if n_changed <> 0 then
    raise exception '38-B 03: alguna política previa de projects/project_products/rfqs/rfq_distributors cambió (% diferencias)', n_changed;
  end if;

  -- is_supplier(): SECURITY DEFINER, STABLE, EXECUTE solo authenticated (abortan)
  if not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                  where n.nspname = 'public' and p.proname = 'is_supplier'
                    and p.prosecdef and p.provolatile = 's') then
    raise exception '38-B 03: is_supplier() no es SECURITY DEFINER + STABLE';
  end if;
  -- search_path: solo aviso flexible (no aborta por diferencias de serialización de proconfig);
  -- se revisa en el postcheck con pg_get_functiondef
  if not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace,
                      unnest(coalesce(p.proconfig, array[]::text[])) c
                  where n.nspname = 'public' and p.proname = 'is_supplier' and c like 'search_path=%') then
    raise notice '38-B 03 aviso: no se encontró search_path en proconfig de is_supplier(); revisar con pg_get_functiondef';
  end if;
  if has_function_privilege('anon', 'public.is_supplier()', 'execute') then
    raise exception '38-B 03: anon conserva EXECUTE sobre is_supplier()';
  end if;
  if not has_function_privilege('authenticated', 'public.is_supplier()', 'execute') then
    raise exception '38-B 03: authenticated no tiene EXECUTE sobre is_supplier()';
  end if;
  if exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace,
                  aclexplode(p.proacl) a
              where n.nspname = 'public' and p.proname = 'is_supplier'
                and a.grantee = 0 and a.privilege_type = 'EXECUTE') then
    raise exception '38-B 03: PUBLIC conserva EXECUTE sobre is_supplier()';
  end if;

  -- Escritura de productos y precios: efectivamente falsa para anon y authenticated
  if has_any_column_privilege('anon', 'public.products', 'INSERT')
     or has_any_column_privilege('anon', 'public.products', 'UPDATE')
     or has_any_column_privilege('authenticated', 'public.products', 'INSERT')
     or has_any_column_privilege('authenticated', 'public.products', 'UPDATE')
     or has_column_privilege('authenticated', 'public.products', 'status', 'UPDATE')
     or has_column_privilege('authenticated', 'public.products', 'publication_status', 'UPDATE')
     or has_any_column_privilege('anon', 'public.product_prices', 'INSERT')
     or has_any_column_privilege('anon', 'public.product_prices', 'UPDATE')
     or has_any_column_privilege('authenticated', 'public.product_prices', 'INSERT')
     or has_any_column_privilege('authenticated', 'public.product_prices', 'UPDATE') then
    raise exception '38-B 03: queda algún permiso de escritura efectivo en products o product_prices';
  end if;
end $$;

COMMIT;
