-- ============================================================
-- 39 · Huella de solo lectura (antes, durante y después del despliegue)
-- ------------------------------------------------------------
-- Solo SELECT: no escribe nada. Funciona antes de 39 (los objetos de 39
-- aparecen como 'no existe') y después. Se ejecuta en cada punto de
-- control del plan y se compara línea a línea.
--
-- Líneas que deben ser IDÉNTICAS en todas las ejecuciones:
--   tabla:*            (product_proposals sin la columna nueva)
--   politicas:previas  (las de antes de 39, sin product_prices)
--   permisos:*         (sin las tablas nuevas de 39 ni product_prices)
--   funciones:previas  (todas menos las 4 que reemplaza 39-03, las 5 nuevas
--                       y catalog_published_prices)
--   triggers:public, constraints:previas, indices:public
-- Líneas que cambian solo por 39 (valores esperados en 39-DESPLIEGUE.md):
--   39:*, constraints:product_proposals, columnas:product_proposals
-- Líneas que cambian por 39 y por el paquete de precios:
--   politicas:public (todas)  (47 → 48 con 39-06)
--   migraciones registradas   (+1 con 39-05 y +1 con 39-06)
-- Líneas propias del paquete de precios (cambian solo por 39-05 / 39-06):
--   precios:*  (función catalog_published_prices; políticas, permisos de
--               tabla, permisos de columna y RLS de product_prices)
--
-- Paquete de precios: desde esta versión, product_prices y la función de
-- 39-05 se miden SOLO en sus líneas precios:*, y se excluyen de
-- politicas:previas, permisos:* y funciones:previas. Por eso politicas:previas
-- y permisos:* NO son comparables con las huellas anteriores a esta versión:
-- hay que tomar una nueva línea base antes de aplicar 39-05.
-- ============================================================

with
datos as (
  select 'tabla:products' as k, count(*)::text || ' / ' || md5(coalesce(string_agg(x::text, '|' order by x::text), '')) as v from public.products x
  union all select 'tabla:product_prices', count(*)::text || ' / ' || md5(coalesce(string_agg(x::text, '|' order by x::text), '')) from public.product_prices x
  union all select 'tabla:distributors', count(*)::text || ' / ' || md5(coalesce(string_agg(x::text, '|' order by x::text), '')) from public.distributors x
  union all select 'tabla:distributor_profiles', count(*)::text || ' / ' || md5(coalesce(string_agg(x::text, '|' order by x::text), '')) from public.distributor_profiles x
  union all select 'tabla:product_proposals (sin created_product_id)', count(*)::text || ' / ' || md5(coalesce(string_agg((to_jsonb(x) - 'created_product_id')::text, '|' order by x.id), '')) from public.product_proposals x
  union all select 'tabla:proposal_events', count(*)::text || ' / ' || md5(coalesce(string_agg(x::text, '|' order by x::text), '')) from public.proposal_events x
  union all select 'tabla:profiles', count(*)::text || ' / ' || md5(coalesce(string_agg(x::text, '|' order by x::text), '')) from public.profiles x
  union all select 'tabla:categories', count(*)::text || ' / ' || md5(coalesce(string_agg(x::text, '|' order by x::text), '')) from public.categories x
  union all select 'tabla:projects', count(*)::text || ' / ' || md5(coalesce(string_agg(x::text, '|' order by x::text), '')) from public.projects x
  union all select 'tabla:project_products', count(*)::text || ' / ' || md5(coalesce(string_agg(x::text, '|' order by x::text), '')) from public.project_products x
  union all select 'tabla:rfqs', count(*)::text || ' / ' || md5(coalesce(string_agg(x::text, '|' order by x::text), '')) from public.rfqs x
),
obj39 as (
  select '39:tabla mobau_admins (filas)' as k,
         case when to_regclass('public.mobau_admins') is null then 'no existe'
              else (xpath('/row/n/text()', query_to_xml('select count(*) as n from public.mobau_admins', false, true, '')))[1]::text end as v
  union all
  select '39:tabla mobau_moderation_context (filas)',
         case when to_regclass('public.mobau_moderation_context') is null then 'no existe'
              else (xpath('/row/n/text()', query_to_xml('select count(*) as n from public.mobau_moderation_context', false, true, '')))[1]::text end
  union all
  select '39:tablas nuevas: rls / propietario / acl',
         coalesce((select string_agg(c.relname || ':' || c.relrowsecurity::text || ':' || c.relowner::regrole::text || ':' || coalesce(c.relacl::text, '-'), ' ' order by c.relname)
                     from pg_class c where c.oid in (to_regclass('public.mobau_admins'), to_regclass('public.mobau_moderation_context'))), 'no existen')
  union all
  select '39:funciones nuevas y reemplazadas: secdef / search_path / propietario / exec anon / exec authenticated / md5(prosrc)',
         coalesce((select string_agg(p.proname || ':' || p.prosecdef::text || ':' || coalesce(array_to_string(p.proconfig, ';'), '-') || ':' || p.proowner::regrole::text
                                     || ':' || has_function_privilege('anon', p.oid, 'EXECUTE')::text || ':' || has_function_privilege('authenticated', p.oid, 'EXECUTE')::text
                                     || ':' || md5(p.prosrc), ' ' order by p.proname)
                     from pg_proc p where p.pronamespace = 'public'::regnamespace
                      and p.proname in ('is_mobau_admin', 'mobau_admin_session', 'mobau_moderation_proposal_id', 'mobau_moderating',
                                        'moderate_product_proposal', 'transition_proposal_status', 'validate_proposal_changes',
                                        'log_proposal_event', 'products_before_insert')), '-')
  union all
  select '39:politicas de lectura mobau',
         coalesce((select count(*)::text || ' / ' || string_agg(policyname || ':' || cmd || ':' || roles::text || ':' || qual, ' ' order by policyname)
                     from pg_policies where schemaname = 'public' and policyname in ('product_proposals_select_mobau', 'proposal_events_select_mobau', 'products_select_mobau')), '0')
  union all
  select '39:columna created_product_id',
         coalesce((select data_type || ':' || is_nullable from information_schema.columns
                    where table_schema = 'public' and table_name = 'product_proposals' and column_name = 'created_product_id'), 'no existe')
  union all
  select '39:authenticated puede escribir created_product_id',
         case when exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'product_proposals' and column_name = 'created_product_id')
              then has_column_privilege('authenticated', 'public.product_proposals', 'created_product_id', 'INSERT,UPDATE')::text else 'no existe' end
),
pol as (
  select 'politicas:public (todas)' as k,
         count(*)::text || ' / ' || md5(coalesce(string_agg(concat_ws('#', tablename, policyname, permissive, roles::text, cmd, qual, with_check), '|' order by tablename, policyname), '')) as v
    from pg_policies where schemaname = 'public'
  union all
  select 'politicas:previas (sin las 3 de 39 ni product_prices)',
         count(*)::text || ' / ' || md5(coalesce(string_agg(concat_ws('#', tablename, policyname, permissive, roles::text, cmd, qual, with_check), '|' order by tablename, policyname), ''))
    from pg_policies where schemaname = 'public' and tablename <> 'product_prices'
     and policyname not in ('product_proposals_select_mobau', 'proposal_events_select_mobau', 'products_select_mobau')
),
precios as (
  select 'precios:función catalog_published_prices: secdef / search_path / propietario / exec public / exec anon / exec authenticated / columnas / md5(prosrc)' as k,
         coalesce((select string_agg(p.prosecdef::text || ' / ' || coalesce(array_to_string(p.proconfig, ';'), '-') || ' / ' || p.proowner::regrole::text
                                     || ' / ' || exists (select 1 from aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a where a.grantee = 0 and a.privilege_type = 'EXECUTE')::text
                                     || ' / ' || has_function_privilege('anon', p.oid, 'EXECUTE')::text || ' / ' || has_function_privilege('authenticated', p.oid, 'EXECUTE')::text
                                     || ' / ' || array_to_string(p.proargnames, ',') || ' / ' || md5(p.prosrc), ' ')
                     from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'catalog_published_prices'), 'no existe') as v
  union all
  select 'precios:product_prices políticas (nombre:cmd:roles) / md5 definición',
         count(*)::text || ' / ' || coalesce(string_agg(policyname || ':' || cmd || ':' || roles::text, ' ' order by policyname), '-')
         || ' / ' || md5(coalesce(string_agg(concat_ws('#', policyname, permissive, roles::text, cmd, qual, with_check), '|' order by policyname), ''))
    from pg_policies where schemaname = 'public' and tablename = 'product_prices'
  union all
  select 'precios:product_prices permisos de tabla anon',
         coalesce(string_agg(privilege_type, ',' order by privilege_type), '-')
    from information_schema.role_table_grants where table_schema = 'public' and table_name = 'product_prices' and grantee = 'anon'
  union all
  select 'precios:product_prices permisos de tabla authenticated',
         coalesce(string_agg(privilege_type, ',' order by privilege_type), '-')
    from information_schema.role_table_grants where table_schema = 'public' and table_name = 'product_prices' and grantee = 'authenticated'
  union all
  select 'precios:product_prices permisos de tabla service_role',
         coalesce(string_agg(privilege_type, ',' order by privilege_type), '-')
    from information_schema.role_table_grants where table_schema = 'public' and table_name = 'product_prices' and grantee = 'service_role'
  union all
  select 'precios:product_prices permisos de columna anon/authenticated',
         count(*)::text || ' / ' || md5(coalesce(string_agg(concat_ws('#', grantee, column_name, privilege_type), '|' order by grantee, column_name, privilege_type), ''))
    from information_schema.column_privileges
   where table_schema = 'public' and table_name = 'product_prices' and grantee in ('anon', 'authenticated')
  union all
  select 'precios:product_prices rls / force rls',
         relrowsecurity::text || ' / ' || relforcerowsecurity::text
    from pg_class where oid = 'public.product_prices'::regclass
),
perm as (
  select 'permisos:tabla anon/authenticated/service_role (sin tablas de 39 ni product_prices)' as k,
         count(*)::text || ' / ' || md5(coalesce(string_agg(concat_ws('#', grantee, table_name, privilege_type), '|' order by grantee, table_name, privilege_type), '')) as v
    from information_schema.role_table_grants
   where table_schema = 'public' and grantee in ('anon', 'authenticated', 'service_role')
     and table_name not in ('mobau_admins', 'mobau_moderation_context', 'product_prices')
  union all
  select 'permisos:columna anon/authenticated (sin tablas de 39 ni product_prices)',
         count(*)::text || ' / ' || md5(coalesce(string_agg(concat_ws('#', grantee, table_name, column_name, privilege_type), '|' order by grantee, table_name, column_name, privilege_type), ''))
    from information_schema.column_privileges
   where table_schema = 'public' and grantee in ('anon', 'authenticated')
     and table_name not in ('mobau_admins', 'mobau_moderation_context', 'product_prices')
     and not (table_name = 'product_proposals' and column_name = 'created_product_id')
),
esq as (
  select 'funciones:previas (sin las 9 de 39 ni catalog_published_prices)' as k,
         count(*)::text || ' / ' || md5(coalesce(string_agg(p.proname || ':' || p.prosecdef::text || ':' || coalesce(array_to_string(p.proconfig, ';'), '-')
                                                            || ':' || coalesce(p.proacl::text, '-') || ':' || md5(pg_get_functiondef(p.oid)), '|' order by p.proname), '')) as v
    from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind = 'f'
     and p.proname not in ('is_mobau_admin', 'mobau_admin_session', 'mobau_moderation_proposal_id', 'mobau_moderating',
                           'moderate_product_proposal', 'transition_proposal_status', 'validate_proposal_changes',
                           'log_proposal_event', 'products_before_insert', 'catalog_published_prices')
  union all
  select 'triggers:public',
         count(*)::text || ' / ' || md5(coalesce(string_agg(pg_get_triggerdef(t.oid), '|' order by t.tgrelid::regclass::text, t.tgname), ''))
    from pg_trigger t join pg_class c on c.oid = t.tgrelid
   where not t.tgisinternal and c.relnamespace = 'public'::regnamespace
  union all
  select 'constraints:previas (sin product_proposals ni tablas de 39)',
         count(*)::text || ' / ' || md5(coalesce(string_agg(conrelid::regclass::text || '#' || conname || '#' || pg_get_constraintdef(oid), '|' order by conrelid::regclass::text, conname), ''))
    from pg_constraint
   where connamespace = 'public'::regnamespace
     and conrelid not in (coalesce(to_regclass('public.product_proposals')::oid, 0::oid), coalesce(to_regclass('public.mobau_admins')::oid, 0::oid),
                          coalesce(to_regclass('public.mobau_moderation_context')::oid, 0::oid))
  union all
  select 'constraints:product_proposals',
         count(*)::text || ' / ' || string_agg(conname, ',' order by conname)
    from pg_constraint where conrelid = 'public.product_proposals'::regclass
  union all
  select 'constraints:product_prices (sin restos de prueba)',
         count(*)::text || ' / ' || string_agg(conname, ',' order by conname)
    from pg_constraint where conrelid = 'public.product_prices'::regclass
  union all
  select 'indices:public (sin tablas de 39)',
         count(*)::text || ' / ' || md5(coalesce(string_agg(indexdef, '|' order by tablename, indexname), ''))
    from pg_indexes where schemaname = 'public' and tablename not in ('mobau_admins', 'mobau_moderation_context')
  union all
  select 'columnas:product_proposals',
         count(*)::text || ' / ' || string_agg(column_name, ',' order by ordinal_position)
    from information_schema.columns where table_schema = 'public' and table_name = 'product_proposals'
  union all
  select 'migraciones registradas',
         count(*)::text || ' / última: ' || max(version)
    from supabase_migrations.schema_migrations
  union all
  select 'propuestas por estado',
         coalesce((select string_agg(status || '=' || n, ', ' order by status) from (select status, count(*) n from public.product_proposals group by status) s), 'ninguna')
  union all
  select 'eventos con actor mobau y actor_id (decisiones de Mobau)',
         (select count(*) from public.proposal_events where actor_kind = 'mobau' and actor_id is not null)::text
  union all
  select 'restos de prueba rls39 (productos, distribuidores, propuestas)',
         ((select count(*) from public.products where id like 'rls39%')
          + (select count(*) from public.distributors where id like 'rls39%')
          + (select count(*) from public.product_proposals where id::text like '00000000-0000-4000-8000-000000039%'))::text
)
select k, v from datos
union all select k, v from obj39
union all select k, v from pol
union all select k, v from precios
union all select k, v from perm
union all select k, v from esq;
