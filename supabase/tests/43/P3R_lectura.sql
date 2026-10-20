-- 43 · CC1 · lectura de antes y después de P3-R (solo SELECT). No escribe nada.
-- Las dos lecturas deben coincidir en todas las filas.
select 'migraciones (número / última)' k, (select count(*)::text || ' / ' || max(version) from supabase_migrations.schema_migrations) v
union all select 'D4 registrada', (select count(*)::text from supabase_migrations.schema_migrations where version = '20261020130100')
union all select 'objetos de D4 (columnas / función / restricción / trigger)',
  (select count(*)::text from information_schema.columns where table_schema = 'public' and table_name = 'professional_profiles' and column_name in ('first_name', 'last_name'))
  || ' / ' || (to_regprocedure('public.professional_profiles_sync_name()') is not null)::text
  || ' / ' || (select count(*)::text from pg_constraint where conname = 'professional_profiles_name_parts_check')
  || ' / ' || (select count(*)::text from pg_trigger where tgname = 'trg_professional_profiles_sync_name')
union all select 'copia de nombres existe', (to_regclass('mobau_private.professional_name_parts_backup') is not null)::text
union all select 'mobau_private (objetos y permisos)', md5(coalesce((select string_agg(relname || relkind::text || coalesce(relacl::text, ''), '|' order by relname)
                   from pg_class where relnamespace = 'mobau_private'::regnamespace), ''))
union all select 'perfiles profesionales (filas / huella)', (select count(*)::text from public.professional_profiles) || ' / '
  || md5(coalesce((select string_agg(user_id::text || professional_name || coalesce(phone, '-') || updated_at::text, '|' order by user_id) from public.professional_profiles), ''))
union all select 'restos de P3-R', (select count(*)::text from public.professional_profiles where professional_name like '%P3R%' or professional_name like 'Ensayo %')
union all select 'huella completa (public + mobau_private)', md5(
      coalesce((select string_agg(tablename || policyname || permissive || cmd || roles::text || coalesce(qual, '') || coalesce(with_check, ''), '|' order by tablename, policyname)
                from pg_policies where schemaname in ('public', 'mobau_private')), '')
   || coalesce((select string_agg(p.oid::regprocedure::text || md5(p.prosrc) || coalesce(p.proacl::text, ''), '|' order by p.oid::regprocedure::text)
                from pg_proc p where p.pronamespace = 'public'::regnamespace), '')
   || coalesce((select string_agg(table_name || '.' || column_name || ':' || data_type || ':' || coalesce(column_default, ''), '|' order by table_name, ordinal_position)
                from information_schema.columns where table_schema = 'public'), '')
   || coalesce((select string_agg(conrelid::regclass::text || conname || pg_get_constraintdef(oid), '|' order by conrelid::regclass::text, conname)
                from pg_constraint where connamespace = 'public'::regnamespace), '')
   || coalesce((select string_agg(tgrelid::regclass::text || tgname, '|' order by tgrelid::regclass::text, tgname)
                from pg_trigger where not tgisinternal and tgrelid in (select oid from pg_class where relnamespace = 'public'::regnamespace)), '')
   || coalesce((select string_agg(relname || coalesce(relacl::text, ''), '|' order by relname)
                from pg_class where relnamespace = 'public'::regnamespace and relkind = 'r'), '')
   || coalesce((select string_agg(relname || relkind::text || coalesce(relacl::text, ''), '|' order by relname)
                from pg_class where relnamespace = 'mobau_private'::regnamespace), '')
   || coalesce((select string_agg(id::text || status || owner_user_id::text || name || updated_at::text, '|' order by id) from public.projects), '')
   || coalesce((select string_agg(id::text || quantity::text || coalesce(unit, '-'), '|' order by id) from public.project_products), '')
   || coalesce((select string_agg(id::text || status, '|' order by id) from public.rfqs), '')
   || coalesce((select string_agg(id::text || plan || role || plan_source || subscription_status, '|' order by id) from public.profiles), '')
   || coalesce((select string_agg(user_id::text || professional_name || coalesce(phone, '-') || updated_at::text, '|' order by user_id) from public.professional_profiles), '')
   || (select count(*)::text from public.moodboards)
   || (select count(*)::text || max(version) from supabase_migrations.schema_migrations));
