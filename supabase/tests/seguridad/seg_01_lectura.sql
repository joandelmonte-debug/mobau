-- SEG-01 · lectura de privilegios (solo SELECT). Antes y después del ensayo,
-- de la aplicación y ante cualquier respuesta ambigua. No escribe nada.
select 'migraciones' k, (select count(*)::text || ' / ' || max(version) from supabase_migrations.schema_migrations) v
union all select 'SEG-01 registrada', (select count(*)::text from supabase_migrations.schema_migrations where version = '20261020180000')
union all select 'privilegios en las 8 tablas (anon | authenticated)', (select string_agg(c.relname || ' ' ||
      coalesce((select string_agg(left(p, 2), '' order by p) from unnest(array['SELECT', 'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER', 'MAINTAIN']) p where has_table_privilege('anon', c.oid, p)), '-') || ' | ' ||
      coalesce((select string_agg(left(p, 2), '' order by p) from unnest(array['SELECT', 'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER', 'MAINTAIN']) p where has_table_privilege('authenticated', c.oid, p)), '-'), ' ; ' order by c.relname)
   from pg_class c where c.oid in ('public.categories'::regclass, 'public.plans'::regclass, 'public.professional_profiles'::regclass, 'public.projects'::regclass,
                                   'public.project_products'::regclass, 'public.rfqs'::regclass, 'public.rfq_distributors'::regclass, 'public.studios'::regclass))
union all select 'tablas con TRUNCATE para anon o authenticated', coalesce((select string_agg(c.relname, ', ' order by c.relname) from pg_class c
   where c.relnamespace = 'public'::regnamespace and c.relkind = 'r' and (has_table_privilege('anon', c.oid, 'TRUNCATE') or has_table_privilege('authenticated', c.oid, 'TRUNCATE'))), 'ninguna')
union all select 'tablas con MAINTAIN (anon | authenticated)', coalesce((select string_agg(c.relname, ',' order by c.relname) from pg_class c
   where c.relnamespace = 'public'::regnamespace and c.relkind in ('r', 'v', 'm', 'p') and has_table_privilege('anon', c.oid, 'MAINTAIN')), 'ninguna') || ' | ' ||
   coalesce((select string_agg(c.relname, ',' order by c.relname) from pg_class c
   where c.relnamespace = 'public'::regnamespace and c.relkind in ('r', 'v', 'm', 'p') and has_table_privilege('authenticated', c.oid, 'MAINTAIN')), 'ninguna')
union all select 'privilegios por defecto de postgres', coalesce((select string_agg(coalesce(n.nspname, '(global)') || '/' || d.defaclobjtype::text || ': '
      || coalesce((select string_agg(case when x.grantee = 0 then 'PUBLIC' else x.grantee::regrole::text end || '=' || x.privilege_type, ',' order by x.grantee, x.privilege_type) from aclexplode(d.defaclacl) x), ''), ' ; ' order by n.nspname nulls first, d.defaclobjtype::text)
   from pg_default_acl d left join pg_namespace n on n.oid = d.defaclnamespace where d.defaclrole = 'postgres'::regrole), 'ninguno')
union all select 'funciones SECURITY DEFINER ejecutables por anon', (select count(*)::text from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prosecdef and has_function_privilege('anon', p.oid, 'EXECUTE'))
union all select 'restos del ensayo', (to_regclass('public.zz_seg01_prueba') is not null)::text || ' / ' || (to_regprocedure('public.zz_seg01_fn()') is not null)::text
union all select 'huella semántica completa', md5(
      coalesce((select string_agg(c.relname || ':' || r || ':' || coalesce((select string_agg(p, ',' order by p) from unnest(array['SELECT', 'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER', 'MAINTAIN']) p where has_table_privilege(r, c.oid, p)), '-'), '|' order by c.relname, r)
                from pg_class c, unnest(array['anon', 'authenticated', 'service_role']) r
               where c.relnamespace = 'public'::regnamespace and c.relkind in ('r', 'v', 'm', 'p')), '')
   || coalesce((select string_agg(a.attname || ':' || r || ':' || has_column_privilege(r, 'public.project_products'::regclass, a.attname, 'UPDATE')::text, '|' order by a.attname, r)
                from pg_attribute a, unnest(array['anon', 'authenticated']) r
               where a.attrelid = 'public.project_products'::regclass and a.attnum > 0 and not a.attisdropped), '')
   || coalesce((select string_agg(d.defaclrole::regrole::text || ':' || d.defaclnamespace::text || ':' || d.defaclobjtype::text || ':'
                       || coalesce((select string_agg(x.grantee::text || '=' || x.privilege_type, ',' order by x.grantee, x.privilege_type) from aclexplode(d.defaclacl) x), ''), '|'
                       order by d.defaclrole::regrole::text, d.defaclnamespace, d.defaclobjtype::text)
                from pg_default_acl d), '')
   || coalesce((select string_agg(f.oid::regprocedure::text || ':' || coalesce((select string_agg(x.grantee::text || '=' || x.privilege_type, ',' order by x.grantee, x.privilege_type) from aclexplode(f.proacl) x), 'por-defecto'), '|' order by f.oid::regprocedure::text)
                from pg_proc f where f.pronamespace = 'public'::regnamespace), '')
   || coalesce((select string_agg(tablename || policyname || permissive || cmd || roles::text || coalesce(qual, '') || coalesce(with_check, ''), '|' order by tablename, policyname)
                from pg_policies where schemaname = 'public'), '')
   || coalesce((select string_agg(id::text || status || owner_user_id::text || name || updated_at::text, '|' order by id) from public.projects), '')
   || coalesce((select string_agg(id::text || quantity::text || coalesce(unit, '-'), '|' order by id) from public.project_products), '')
   || coalesce((select string_agg(id::text || status, '|' order by id) from public.rfqs), '')
   || coalesce((select string_agg(id::text || plan || role || plan_source || subscription_status, '|' order by id) from public.profiles), '')
   || (select count(*)::text || max(version) from supabase_migrations.schema_migrations));
