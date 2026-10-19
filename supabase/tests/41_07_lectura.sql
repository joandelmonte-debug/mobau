-- 41-07-L · LECTURA DE ESTADO (solo SELECT, ninguna escritura).
-- Misma consulta que compara el ensayo E7 (q_state). Uso: antes de 41-07,
-- después de su COMMIT y ante cualquier respuesta ambigua, para saber el
-- estado real antes de afirmar nada. Líneas: a interruptor · b funciones de
-- entrada (firma:acl:md5) · c mobau_private · d restricciones de papelera ·
-- e comentario purge_after · f políticas · g migraciones · h datos (n / md5).
with sig(s) as (
  values ('public.my_products_lifecycle()'), ('public.my_product_lifecycle_events(text)'),
         ('public.distributor_retire_product(text, text, timestamp with time zone)'),
         ('public.distributor_trash_product(text, timestamp with time zone)'),
         ('public.distributor_restore_product(text, timestamp with time zone)'),
         ('public.distributor_purge_product(text, text, timestamp with time zone)'),
         ('public.mobau_product_lifecycle(text, text, text, timestamp with time zone)'),
         ('public.mobau_purge_product(text, text, text, boolean, timestamp with time zone)'),
         ('public.mobau_product_references(text)'),
         ('public.mobau_product_lifecycle_view(text)'),
         ('public.mobau_lifecycle_history(text)')
), l(k, v) as (
  select 'a:interruptor enabled', coalesce((select enabled::text from mobau_private.product_lifecycle_settings where id = 1), 'sin fila')
  union all select 'b:funciones de entrada (firma:acl:md5)', (select string_agg(sig.s || ':' || coalesce((select coalesce(p.proacl::text, 'null') || ':' || md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure(sig.s)), 'no existe'), ' | ' order by sig.s) from sig)
  union all select 'c:mobau_private (firma:acl:md5)', (select string_agg(p.proname || '(' || pg_get_function_identity_arguments(p.oid) || '):' || coalesce(p.proacl::text, 'null') || ':' || md5(p.prosrc), ' | ' order by p.proname, pg_get_function_identity_arguments(p.oid)) from pg_proc p where p.pronamespace = 'mobau_private'::regnamespace)
  union all select 'd:restricciones products_lifecycle_*', (select string_agg(conname || ':' || pg_get_constraintdef(oid), ' | ' order by conname) from pg_constraint where conrelid = 'public.products'::regclass and conname like 'products_lifecycle_%')
  union all select 'e:comentario purge_after', coalesce(col_description('public.products'::regclass, (select attnum from pg_attribute where attrelid = 'public.products'::regclass and attname = 'purge_after')), '-')
  union all select 'f:políticas public', (select count(*)::text from pg_policies where schemaname = 'public')
  union all select 'g:migraciones registradas', (select count(*)::text || ' / ' || max(version) from supabase_migrations.schema_migrations)
  union all select 'h:datos products', (select count(*)::text || ' / ' || md5(coalesce(string_agg(x::text, '|' order by x::text), '')) from public.products x)
  union all select 'h:datos product_prices', (select count(*)::text || ' / ' || md5(coalesce(string_agg(x::text, '|' order by x::text), '')) from public.product_prices x)
  union all select 'h:datos product_proposals', (select count(*)::text || ' / ' || md5(coalesce(string_agg(x::text, '|' order by x::text), '')) from public.product_proposals x)
  union all select 'h:datos proposal_events', (select count(*)::text || ' / ' || md5(coalesce(string_agg(x::text, '|' order by x::text), '')) from public.proposal_events x)
  union all select 'h:datos product_lifecycle_events', (select count(*)::text || ' / ' || md5(coalesce(string_agg(x::text, '|' order by x::text), '')) from mobau_private.product_lifecycle_events x)
  union all select 'h:datos mobau_admins', (select count(*)::text || ' / ' || md5(coalesce(string_agg(x::text, '|' order by x::text), '')) from public.mobau_admins x)
  union all select 'h:datos distributors', (select count(*)::text || ' / ' || md5(coalesce(string_agg(x::text, '|' order by x::text), '')) from public.distributors x)
  union all select 'h:datos projects / project_products / rfqs', (select count(*)::text from public.projects) || ' / ' || (select count(*)::text from public.project_products) || ' / ' || (select count(*)::text from public.rfqs)
)
select string_agg(k || ' = ' || v, E'\n' order by k) from l;
