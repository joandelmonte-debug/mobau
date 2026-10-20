-- 43 · lectura complementaria para la publicación T4 + T2 (solo SELECT).
-- Se ejecuta junto a 43_lectura.sql antes de T4, después de T4, después de
-- C2 y C2-R1 y ante cualquier respuesta ambigua. No escribe nada.
select 'habilitaciones' k, (select coalesce(string_agg(left(id::text, 8) || ':' || role || ':' || plan || ':' || plan_source, ' | ' order by id::text), 'ninguna') from public.profiles where plan_source <> 'default') v
union all select 'subscription', (select count(*)::text from public.profiles where plan_source = 'subscription' or subscription_status not in ('trialing'))
union all select 'eventos de habilitación', (select count(*)::text || ' / último ' || coalesce(max(id)::text, '-') from mobau_private.plan_events)
union all select 'handle_new_user md5', (select md5(prosrc) from pg_proc where oid = 'public.handle_new_user()'::regprocedure)
union all select 'políticas RESTRICTIVE de T4', (select count(*)::text from pg_policies where schemaname = 'public' and permissive = 'RESTRICTIVE' and policyname in
                   ('projects_plan_insert', 'projects_plan_update', 'projects_studio_own_insert', 'projects_studio_own_update',
                    'project_products_plan_insert', 'project_products_plan_update', 'project_products_plan_delete', 'rfqs_plan_insert'))
union all select 'trigger con bloqueo de fila', (select (prosrc ~ 'for update of pr' and prosrc ~ 'for update of s')::text from pg_proc where oid = 'public.enforce_active_project_limit()'::regprocedure)
union all select 'e2a655c1 activos / archivados', (select count(*) filter (where status = 'active')::text || ' / ' || count(*) filter (where status = 'archived')::text
                   from public.projects where owner_user_id::text like 'e2a655c1%')
union all select 'restos de pruebas (C2-R1, P2)', (select count(*)::text from public.projects where name like 'C2-R1%' or name like 'P2 %' or name like '% (P2)')
union all select 'huella de datos (proyectos, líneas, solicitudes)', md5(coalesce((select string_agg(id::text || status || owner_user_id::text || name, '|' order by id) from public.projects), '')
                   || coalesce((select string_agg(id::text || quantity::text || coalesce(unit, '-'), '|' order by id) from public.project_products), '')
                   || coalesce((select string_agg(id::text || status, '|' order by id) from public.rfqs), ''));
