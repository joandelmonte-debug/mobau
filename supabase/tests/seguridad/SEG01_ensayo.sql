-- ============================================================
-- PROPUESTA NO EJECUTADA (SEG-01 · ensayo revertido de O2 + O4 y su recuperación) — no ejecutar sin aprobación explícita
-- ============================================================
-- Generado por generar_seg01.py. En una sola transacción que SIEMPRE termina
-- con MB990 (nada persiste):
--   1. huella de partida y 22 sondas (web, TRUNCATE y LOCK TABLE) (base);
--   2. SEG-01 -> huella, sondas (tras), MAINTAIN y prueba de tabla y función nuevas;
--   3. recuperación -> huella, sondas (rec) y la misma prueba.
-- Éxito: «SEG01E cambia=true identico=true web_igual=true truncate=true
--         sin_maintain=true lock=true nuevos_cerrados=true nuevos_recuperados=true».
-- Ejecutar completo, con el control MD5.
-- ============================================================

BEGIN;

DO $S01E$
declare
  t_m text := $MB$
DO $$
declare
  t regclass;
  p text;
begin
  if current_user <> 'postgres' then
    raise exception 'SEG-01: ejecutar como postgres';
  end if;
  foreach t in array array['public.categories', 'public.plans', 'public.professional_profiles', 'public.projects',
                           'public.project_products', 'public.rfqs', 'public.rfq_distributors', 'public.studios']::regclass[] loop
    foreach p in array array['TRUNCATE', 'REFERENCES', 'TRIGGER'] loop
      if not has_table_privilege('anon', t, p) or not has_table_privilege('authenticated', t, p) then
        raise exception 'SEG-01: el estado de partida no es el leído (% sin % para anon o authenticated)', t, p;
      end if;
    end loop;
  end loop;
  if (select string_agg(c.relname, ',' order by c.relname) from pg_class c
       where c.relnamespace = 'public'::regnamespace and c.relkind in ('r', 'v', 'm', 'p') and has_table_privilege('anon', c.oid, 'MAINTAIN'))
     is distinct from 'categories,distributors,plans,products,professional_profiles,profiles,project_products,projects,rfq_distributors,rfqs,studios'
     or (select string_agg(c.relname, ',' order by c.relname) from pg_class c
       where c.relnamespace = 'public'::regnamespace and c.relkind in ('r', 'v', 'm', 'p') and has_table_privilege('authenticated', c.oid, 'MAINTAIN'))
     is distinct from 'categories,distributors,moodboards,plans,product_prices,products,professional_profiles,profiles,project_products,projects,rfq_distributors,rfqs,studios' then
    raise exception 'SEG-01: las tablas con MAINTAIN para anon o authenticated no son las leídas';
  end if;
  if exists (select 1 from pg_default_acl where defaclrole = 'postgres'::regrole and defaclnamespace = 0) then
    raise exception 'SEG-01: ya existen privilegios por defecto globales de postgres';
  end if;
  if not exists (select 1 from pg_default_acl d, aclexplode(d.defaclacl) a
                  where d.defaclrole = 'postgres'::regrole and d.defaclnamespace = 'public'::regnamespace and d.defaclobjtype = 'r'
                    and a.grantee = 'anon'::regrole and a.privilege_type = 'MAINTAIN')
     or not exists (select 1 from pg_default_acl d, aclexplode(d.defaclacl) a
                  where d.defaclrole = 'postgres'::regrole and d.defaclnamespace = 'public'::regnamespace and d.defaclobjtype = 'f'
                    and a.grantee = 'anon'::regrole and a.privilege_type = 'EXECUTE') then
    raise exception 'SEG-01: los privilegios por defecto de public no son los leídos';
  end if;
  -- Todo lo que no debe cambiar: los privilegios de anon y authenticated que no se retiran
  -- y todos los de service_role.
  perform set_config('mobau.seg01_resto', md5(
      (select string_agg(c.relname || ':' || r || ':' || coalesce((select string_agg(p2, ',' order by p2)
              from unnest(array['SELECT', 'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER', 'MAINTAIN']) p2
             where has_table_privilege(r, c.oid, p2)
               and not (r <> 'service_role' and (p2 = 'MAINTAIN' or (p2 in ('TRUNCATE', 'REFERENCES', 'TRIGGER') and c.relname in
                    ('categories', 'plans', 'professional_profiles', 'projects', 'project_products', 'rfqs', 'rfq_distributors', 'studios'))))), '-'),
              '|' order by c.relname, r)
         from pg_class c, unnest(array['anon', 'authenticated', 'service_role']) r
        where c.relnamespace = 'public'::regnamespace and c.relkind in ('r', 'v', 'm', 'p'))
   || (select string_agg(a.attname || ':' || has_column_privilege('authenticated', 'public.project_products'::regclass, a.attname, 'UPDATE')::text, '|' order by a.attname)
         from pg_attribute a where a.attrelid = 'public.project_products'::regclass and a.attnum > 0 and not a.attisdropped)), true);
end $$;

-- O2
revoke truncate, references, trigger
  on table public.categories, public.plans, public.professional_profiles, public.projects,
           public.project_products, public.rfqs, public.rfq_distributors, public.studios
  from anon, authenticated;
revoke maintain
  on table public.categories, public.distributors, public.plans, public.products, public.professional_profiles,
           public.profiles, public.project_products, public.projects, public.rfq_distributors, public.rfqs, public.studios
  from anon;
revoke maintain
  on table public.categories, public.distributors, public.moodboards, public.plans, public.product_prices, public.products,
           public.professional_profiles, public.profiles, public.project_products, public.projects, public.rfq_distributors,
           public.rfqs, public.studios
  from authenticated;

-- O4
alter default privileges for role postgres in schema public
  revoke truncate, references, trigger, maintain on tables from anon, authenticated;
alter default privileges for role postgres in schema public
  revoke execute on functions from anon, authenticated;
alter default privileges for role postgres
  revoke execute on functions from public;

DO $$
declare
  t regclass;
  r text;
  p text;
begin
  foreach t in array array['public.categories', 'public.plans', 'public.professional_profiles', 'public.projects',
                           'public.project_products', 'public.rfqs', 'public.rfq_distributors', 'public.studios']::regclass[] loop
    foreach r in array array['anon', 'authenticated'] loop
      foreach p in array array['TRUNCATE', 'REFERENCES', 'TRIGGER'] loop
        if has_table_privilege(r, t, p) then
          raise exception 'SEG-01: % conserva % en %', r, p, t;
        end if;
      end loop;
    end loop;
  end loop;
  if exists (select 1 from pg_class c, unnest(array['anon', 'authenticated']) r2
              where c.relnamespace = 'public'::regnamespace and c.relkind in ('r', 'v', 'm', 'p') and has_table_privilege(r2, c.oid, 'MAINTAIN')) then
    raise exception 'SEG-01: anon o authenticated conservan MAINTAIN en alguna tabla de public';
  end if;
  if md5(
      (select string_agg(c.relname || ':' || r2 || ':' || coalesce((select string_agg(p2, ',' order by p2)
              from unnest(array['SELECT', 'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER', 'MAINTAIN']) p2
             where has_table_privilege(r2, c.oid, p2)
               and not (r2 <> 'service_role' and (p2 = 'MAINTAIN' or (p2 in ('TRUNCATE', 'REFERENCES', 'TRIGGER') and c.relname in
                    ('categories', 'plans', 'professional_profiles', 'projects', 'project_products', 'rfqs', 'rfq_distributors', 'studios'))))), '-'),
              '|' order by c.relname, r2)
         from pg_class c, unnest(array['anon', 'authenticated', 'service_role']) r2
        where c.relnamespace = 'public'::regnamespace and c.relkind in ('r', 'v', 'm', 'p'))
   || (select string_agg(a.attname || ':' || has_column_privilege('authenticated', 'public.project_products'::regclass, a.attname, 'UPDATE')::text, '|' order by a.attname)
         from pg_attribute a where a.attrelid = 'public.project_products'::regclass and a.attnum > 0 and not a.attisdropped))
     <> current_setting('mobau.seg01_resto') then
    raise exception 'SEG-01: ha cambiado algún privilegio que no debía cambiar';
  end if;
  if exists (select 1 from pg_default_acl d, aclexplode(d.defaclacl) a
              where d.defaclrole = 'postgres'::regrole and d.defaclnamespace = 'public'::regnamespace and d.defaclobjtype = 'r'
                and a.grantee in ('anon'::regrole, 'authenticated'::regrole) and a.privilege_type in ('TRUNCATE', 'REFERENCES', 'TRIGGER', 'MAINTAIN'))
     or exists (select 1 from pg_default_acl d, aclexplode(d.defaclacl) a
              where d.defaclrole = 'postgres'::regrole and d.defaclnamespace = 'public'::regnamespace and d.defaclobjtype = 'f'
                and a.grantee in ('anon'::regrole, 'authenticated'::regrole))
     or not exists (select 1 from pg_default_acl where defaclrole = 'postgres'::regrole and defaclnamespace = 0 and defaclobjtype = 'f')
     or exists (select 1 from pg_default_acl d, aclexplode(d.defaclacl) a
              where d.defaclrole = 'postgres'::regrole and d.defaclnamespace = 0 and d.defaclobjtype = 'f' and a.grantee = 0) then
    raise exception 'SEG-01: los privilegios por defecto no quedaron como se esperaba';
  end if;
  if not exists (select 1 from pg_default_acl d, aclexplode(d.defaclacl) a
                  where d.defaclrole = 'postgres'::regrole and d.defaclnamespace = 'public'::regnamespace and d.defaclobjtype = 'f'
                    and a.grantee = 'service_role'::regrole and a.privilege_type = 'EXECUTE')
     or (select count(*) from pg_default_acl d, aclexplode(d.defaclacl) a
          where d.defaclrole = 'postgres'::regrole and d.defaclnamespace = 'public'::regnamespace and d.defaclobjtype = 'r'
            and a.grantee = 'service_role'::regrole) <> 8 then
    raise exception 'SEG-01: service_role ha perdido algún privilegio por defecto';
  end if;
end $$;
$MB$;
  t_r text := $RB$
DO $$
begin
  if current_user <> 'postgres' then
    raise exception 'SEG-01R: ejecutar como postgres';
  end if;
  if has_table_privilege('anon', 'public.projects', 'TRUNCATE')
     or has_table_privilege('authenticated', 'public.moodboards', 'MAINTAIN')
     or not exists (select 1 from pg_default_acl where defaclrole = 'postgres'::regrole and defaclnamespace = 0 and defaclobjtype = 'f') then
    raise exception 'SEG-01R: SEG-01 no está aplicada';
  end if;
end $$;

grant truncate, references, trigger
  on table public.categories, public.plans, public.professional_profiles, public.projects,
           public.project_products, public.rfqs, public.rfq_distributors, public.studios
  to anon, authenticated;
grant maintain
  on table public.categories, public.distributors, public.plans, public.products, public.professional_profiles,
           public.profiles, public.project_products, public.projects, public.rfq_distributors, public.rfqs, public.studios
  to anon;
grant maintain
  on table public.categories, public.distributors, public.moodboards, public.plans, public.product_prices, public.products,
           public.professional_profiles, public.profiles, public.project_products, public.projects, public.rfq_distributors,
           public.rfqs, public.studios
  to authenticated;

alter default privileges for role postgres in schema public
  grant truncate, references, trigger, maintain on tables to anon, authenticated;
alter default privileges for role postgres in schema public
  grant execute on functions to anon, authenticated;
alter default privileges for role postgres
  grant execute on functions to public;

DO $$
declare
  t regclass;
  r text;
  p text;
begin
  foreach t in array array['public.categories', 'public.plans', 'public.professional_profiles', 'public.projects',
                           'public.project_products', 'public.rfqs', 'public.rfq_distributors', 'public.studios']::regclass[] loop
    foreach r in array array['anon', 'authenticated'] loop
      foreach p in array array['SELECT', 'INSERT', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER', 'MAINTAIN'] loop
        if not has_table_privilege(r, t, p) then
          raise exception 'SEG-01R: % no tiene % en %', r, p, t;
        end if;
      end loop;
    end loop;
  end loop;
  if (select string_agg(c.relname, ',' order by c.relname) from pg_class c
       where c.relnamespace = 'public'::regnamespace and c.relkind in ('r', 'v', 'm', 'p') and has_table_privilege('anon', c.oid, 'MAINTAIN'))
     is distinct from 'categories,distributors,plans,products,professional_profiles,profiles,project_products,projects,rfq_distributors,rfqs,studios'
     or (select string_agg(c.relname, ',' order by c.relname) from pg_class c
       where c.relnamespace = 'public'::regnamespace and c.relkind in ('r', 'v', 'm', 'p') and has_table_privilege('authenticated', c.oid, 'MAINTAIN'))
     is distinct from 'categories,distributors,moodboards,plans,product_prices,products,professional_profiles,profiles,project_products,projects,rfq_distributors,rfqs,studios' then
    raise exception 'SEG-01R: las tablas con MAINTAIN no volvieron a las leídas';
  end if;
  if exists (select 1 from pg_default_acl d, aclexplode(d.defaclacl) a
              where d.defaclrole = 'postgres'::regrole and d.defaclnamespace = 0 and d.defaclobjtype = 'f')
     and not exists (select 1 from pg_default_acl d, aclexplode(d.defaclacl) a
              where d.defaclrole = 'postgres'::regrole and d.defaclnamespace = 0 and d.defaclobjtype = 'f' and a.grantee = 0) then
    raise exception 'SEG-01R: las funciones nuevas siguen sin EXECUTE para PUBLIC';
  end if;
  if (select count(*) from pg_default_acl d, aclexplode(d.defaclacl) a
       where d.defaclrole = 'postgres'::regrole and d.defaclnamespace = 'public'::regnamespace and d.defaclobjtype = 'r'
         and a.grantee in ('anon'::regrole, 'authenticated'::regrole)) <> 16
     or (select count(*) from pg_default_acl d, aclexplode(d.defaclacl) a
       where d.defaclrole = 'postgres'::regrole and d.defaclnamespace = 'public'::regnamespace and d.defaclobjtype = 'f'
         and a.grantee in ('anon'::regrole, 'authenticated'::regrole) and a.privilege_type = 'EXECUTE') <> 2 then
    raise exception 'SEG-01R: los privilegios por defecto de public no volvieron a los leídos';
  end if;
end $$;
$RB$;
  h0 text; h1 text; h2 text;
  v_ind uuid; v_gra uuid := '46ea4397-f881-4db8-89e7-f164293a1143'; v_proj uuid; v_prod text;
  v_got text; v_seq text; v_n bigint;
  s_base text; s_tras text; s_rec text; n_tras text; n_rec text;
  w_base text; w_tras text; w_rec text; v_sin_m boolean;
begin
  if md5(t_m) <> 'dcace6e8850da15dd4565c56489092fa' or md5(t_r) <> '4b1c9a06f1b6a024b72f98715d68858c' then
    raise exception 'MOBAU_SEG01E: algún texto incrustado no coincide con su MD5' using errcode = 'MB997';
  end if;
  select id into v_ind from public.profiles where id::text like 'e2a655c1%' and plan = 'individual_founder' and plan_source = 'manual_pilot';
  select id into v_proj from public.projects where owner_user_id = v_ind and status = 'active' order by created_at limit 1;
  select p.id into v_prod from public.products p
   where p.publication_status = 'published' and not exists (select 1 from public.project_products pp where pp.project_id = v_proj and pp.product_id = p.id)
   order by p.id limit 1;
  if current_user <> 'postgres' or v_ind is null or v_proj is null or v_prod is null
     or not exists (select 1 from public.profiles where id = v_gra and plan = 'free_trial')
     or exists (select 1 from supabase_migrations.schema_migrations where version = '20261020180000')
     or not has_table_privilege('anon', 'public.projects', 'TRUNCATE')
     or exists (select 1 from pg_default_acl where defaclrole = 'postgres'::regrole and defaclnamespace = 0)
     or to_regclass('public.zz_seg01_prueba') is not null or to_regprocedure('public.zz_seg01_fn()') is not null then
    raise exception 'MOBAU_SEG01E: estado de partida inesperado' using errcode = 'MB998';
  end if;

  h0 := md5(
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
  s_base := '';
  v_got := null; v_seq := '';
  begin
    execute 'set local lock_timeout = ''2s''';
    execute format('set local role %I', 'anon');
    perform set_config('request.jwt.claim.sub', coalesce(null::text, ''), true);
    perform set_config('request.jwt.claims', case when null::text is null then '' else json_build_object('sub', null::text, 'role', 'anon', 'aal', 'aal1')::text end, true);
    execute 'select count(*) from public.categories' into v_n; v_got := v_n::text;
    raise exception using errcode = 'MB001';
  exception
    when sqlstate 'MB001' then null;
    when others then v_got := sqlstate;
  end;
  s_base := s_base || 'P01=' || coalesce(v_got, '-') || '|';
  v_got := null; v_seq := '';
  begin
    execute 'set local lock_timeout = ''2s''';
    execute format('set local role %I', 'anon');
    perform set_config('request.jwt.claim.sub', coalesce(null::text, ''), true);
    perform set_config('request.jwt.claims', case when null::text is null then '' else json_build_object('sub', null::text, 'role', 'anon', 'aal', 'aal1')::text end, true);
    execute 'select count(*) from public.plans' into v_n; v_got := v_n::text;
    raise exception using errcode = 'MB001';
  exception
    when sqlstate 'MB001' then null;
    when others then v_got := sqlstate;
  end;
  s_base := s_base || 'P02=' || coalesce(v_got, '-') || '|';
  v_got := null; v_seq := '';
  begin
    execute 'set local lock_timeout = ''2s''';
    execute format('set local role %I', 'anon');
    perform set_config('request.jwt.claim.sub', coalesce(null::text, ''), true);
    perform set_config('request.jwt.claims', case when null::text is null then '' else json_build_object('sub', null::text, 'role', 'anon', 'aal', 'aal1')::text end, true);
    execute 'select count(*) from public.catalog_products' into v_n; v_got := v_n::text;
    raise exception using errcode = 'MB001';
  exception
    when sqlstate 'MB001' then null;
    when others then v_got := sqlstate;
  end;
  s_base := s_base || 'P03=' || coalesce(v_got, '-') || '|';
  v_got := null; v_seq := '';
  begin
    execute 'set local lock_timeout = ''2s''';
    execute format('set local role %I', 'anon');
    perform set_config('request.jwt.claim.sub', coalesce(null::text, ''), true);
    perform set_config('request.jwt.claims', case when null::text is null then '' else json_build_object('sub', null::text, 'role', 'anon', 'aal', 'aal1')::text end, true);
    execute 'select count(*) from public.projects' into v_n; v_got := v_n::text;
    raise exception using errcode = 'MB001';
  exception
    when sqlstate 'MB001' then null;
    when others then v_got := sqlstate;
  end;
  s_base := s_base || 'P04=' || coalesce(v_got, '-') || '|';
  v_got := null; v_seq := '';
  begin
    execute 'set local lock_timeout = ''2s''';
    execute format('set local role %I', 'anon');
    perform set_config('request.jwt.claim.sub', coalesce(null::text, ''), true);
    perform set_config('request.jwt.claims', case when null::text is null then '' else json_build_object('sub', null::text, 'role', 'anon', 'aal', 'aal1')::text end, true);
    execute 'select count(*) from public.professional_profiles' into v_n; v_got := v_n::text;
    raise exception using errcode = 'MB001';
  exception
    when sqlstate 'MB001' then null;
    when others then v_got := sqlstate;
  end;
  s_base := s_base || 'P05=' || coalesce(v_got, '-') || '|';
  v_got := null; v_seq := '';
  begin
    execute 'set local lock_timeout = ''2s''';
    execute format('set local role %I', 'authenticated');
    perform set_config('request.jwt.claim.sub', coalesce(v_ind::text, ''), true);
    perform set_config('request.jwt.claims', case when v_ind::text is null then '' else json_build_object('sub', v_ind::text, 'role', 'authenticated', 'aal', 'aal1')::text end, true);
    execute 'select count(*) from public.projects' into v_n; v_got := v_n::text;
    raise exception using errcode = 'MB001';
  exception
    when sqlstate 'MB001' then null;
    when others then v_got := sqlstate;
  end;
  s_base := s_base || 'P06=' || coalesce(v_got, '-') || '|';
  v_got := null; v_seq := '';
  begin
    execute 'set local lock_timeout = ''2s''';
    execute format('set local role %I', 'authenticated');
    perform set_config('request.jwt.claim.sub', coalesce(v_ind::text, ''), true);
    perform set_config('request.jwt.claims', case when v_ind::text is null then '' else json_build_object('sub', v_ind::text, 'role', 'authenticated', 'aal', 'aal1')::text end, true);
    execute 'select count(*) from public.project_products' into v_n; v_got := v_n::text;
    raise exception using errcode = 'MB001';
  exception
    when sqlstate 'MB001' then null;
    when others then v_got := sqlstate;
  end;
  s_base := s_base || 'P07=' || coalesce(v_got, '-') || '|';
  v_got := null; v_seq := '';
  begin
    execute 'set local lock_timeout = ''2s''';
    execute format('set local role %I', 'authenticated');
    perform set_config('request.jwt.claim.sub', coalesce(v_ind::text, ''), true);
    perform set_config('request.jwt.claims', case when v_ind::text is null then '' else json_build_object('sub', v_ind::text, 'role', 'authenticated', 'aal', 'aal1')::text end, true);
    execute 'select count(*) from public.rfqs' into v_n; v_got := v_n::text;
    raise exception using errcode = 'MB001';
  exception
    when sqlstate 'MB001' then null;
    when others then v_got := sqlstate;
  end;
  s_base := s_base || 'P08=' || coalesce(v_got, '-') || '|';
  v_got := null; v_seq := '';
  begin
    execute 'set local lock_timeout = ''2s''';
    execute format('set local role %I', 'authenticated');
    perform set_config('request.jwt.claim.sub', coalesce(v_ind::text, ''), true);
    perform set_config('request.jwt.claims', case when v_ind::text is null then '' else json_build_object('sub', v_ind::text, 'role', 'authenticated', 'aal', 'aal1')::text end, true);
    execute 'select count(*) from public.professional_profiles' into v_n; v_got := v_n::text;
    raise exception using errcode = 'MB001';
  exception
    when sqlstate 'MB001' then null;
    when others then v_got := sqlstate;
  end;
  s_base := s_base || 'P09=' || coalesce(v_got, '-') || '|';
  v_got := null; v_seq := '';
  begin
    execute 'set local lock_timeout = ''2s''';
    execute format('set local role %I', 'authenticated');
    perform set_config('request.jwt.claim.sub', coalesce(v_ind::text, ''), true);
    perform set_config('request.jwt.claims', case when v_ind::text is null then '' else json_build_object('sub', v_ind::text, 'role', 'authenticated', 'aal', 'aal1')::text end, true);
    execute 'select count(*) from public.plans' into v_n; v_got := v_n::text;
    raise exception using errcode = 'MB001';
  exception
    when sqlstate 'MB001' then null;
    when others then v_got := sqlstate;
  end;
  s_base := s_base || 'P10=' || coalesce(v_got, '-') || '|';
  v_got := null; v_seq := '';
  begin
    execute 'set local lock_timeout = ''2s''';
    execute format('set local role %I', 'authenticated');
    perform set_config('request.jwt.claim.sub', coalesce(v_ind::text, ''), true);
    perform set_config('request.jwt.claims', case when v_ind::text is null then '' else json_build_object('sub', v_ind::text, 'role', 'authenticated', 'aal', 'aal1')::text end, true);
    execute 'select count(*) from public.categories' into v_n; v_got := v_n::text;
    raise exception using errcode = 'MB001';
  exception
    when sqlstate 'MB001' then null;
    when others then v_got := sqlstate;
  end;
  s_base := s_base || 'P11=' || coalesce(v_got, '-') || '|';
  v_got := null; v_seq := '';
  begin
    execute 'set local lock_timeout = ''2s''';
    execute format('set local role %I', 'authenticated');
    perform set_config('request.jwt.claim.sub', coalesce(v_ind::text, ''), true);
    perform set_config('request.jwt.claims', case when v_ind::text is null then '' else json_build_object('sub', v_ind::text, 'role', 'authenticated', 'aal', 'aal1')::text end, true);
    execute format('update public.projects set name = name where id = %L', v_proj); get diagnostics v_n = row_count; v_got := 'rows=' || v_n;
    raise exception using errcode = 'MB001';
  exception
    when sqlstate 'MB001' then null;
    when others then v_got := sqlstate;
  end;
  s_base := s_base || 'P12=' || coalesce(v_got, '-') || '|';
  v_got := null; v_seq := '';
  begin
    execute 'set local lock_timeout = ''2s''';
    execute format('set local role %I', 'authenticated');
    perform set_config('request.jwt.claim.sub', coalesce(v_ind::text, ''), true);
    perform set_config('request.jwt.claims', case when v_ind::text is null then '' else json_build_object('sub', v_ind::text, 'role', 'authenticated', 'aal', 'aal1')::text end, true);
    execute format('insert into public.project_products (project_id, product_id, quantity, unit) values (%L, %L, 1, %L)', v_proj, v_prod, 'ud.'); get diagnostics v_n = row_count; v_seq := v_seq || v_n::text || '/';
    execute format('update public.project_products set quantity = 2 where project_id = %L and product_id = %L', v_proj, v_prod); get diagnostics v_n = row_count; v_seq := v_seq || v_n::text || '/';
    execute format('delete from public.project_products where project_id = %L and product_id = %L', v_proj, v_prod); get diagnostics v_n = row_count; v_seq := v_seq || v_n::text || '/';
    v_got := v_seq;
    raise exception using errcode = 'MB001';
  exception
    when sqlstate 'MB001' then null;
    when others then v_got := sqlstate;
  end;
  s_base := s_base || 'P13=' || coalesce(v_got, '-') || '|';
  v_got := null; v_seq := '';
  begin
    execute 'set local lock_timeout = ''2s''';
    execute format('set local role %I', 'authenticated');
    perform set_config('request.jwt.claim.sub', coalesce(v_ind::text, ''), true);
    perform set_config('request.jwt.claims', case when v_ind::text is null then '' else json_build_object('sub', v_ind::text, 'role', 'authenticated', 'aal', 'aal1')::text end, true);
    execute format('update public.professional_profiles set phone = phone where user_id = %L', v_ind); get diagnostics v_n = row_count; v_got := 'rows=' || v_n;
    raise exception using errcode = 'MB001';
  exception
    when sqlstate 'MB001' then null;
    when others then v_got := sqlstate;
  end;
  s_base := s_base || 'P14=' || coalesce(v_got, '-') || '|';
  v_got := null; v_seq := '';
  begin
    execute 'set local lock_timeout = ''2s''';
    execute format('set local role %I', 'authenticated');
    perform set_config('request.jwt.claim.sub', coalesce(v_gra::text, ''), true);
    perform set_config('request.jwt.claims', case when v_gra::text is null then '' else json_build_object('sub', v_gra::text, 'role', 'authenticated', 'aal', 'aal1')::text end, true);
    execute 'select count(*) from public.projects' into v_n; v_got := v_n::text;
    raise exception using errcode = 'MB001';
  exception
    when sqlstate 'MB001' then null;
    when others then v_got := sqlstate;
  end;
  s_base := s_base || 'P15=' || coalesce(v_got, '-') || '|';
  v_got := null; v_seq := '';
  begin
    execute 'set local lock_timeout = ''2s''';
    execute format('set local role %I', 'authenticated');
    perform set_config('request.jwt.claim.sub', coalesce(v_gra::text, ''), true);
    perform set_config('request.jwt.claims', case when v_gra::text is null then '' else json_build_object('sub', v_gra::text, 'role', 'authenticated', 'aal', 'aal1')::text end, true);
    execute 'select count(*) from public.project_products' into v_n; v_got := v_n::text;
    raise exception using errcode = 'MB001';
  exception
    when sqlstate 'MB001' then null;
    when others then v_got := sqlstate;
  end;
  s_base := s_base || 'P16=' || coalesce(v_got, '-') || '|';
  v_got := null; v_seq := '';
  begin
    execute 'set local lock_timeout = ''2s''';
    execute format('set local role %I', 'anon');
    perform set_config('request.jwt.claim.sub', coalesce(null::text, ''), true);
    perform set_config('request.jwt.claims', case when null::text is null then '' else json_build_object('sub', null::text, 'role', 'anon', 'aal', 'aal1')::text end, true);
    execute 'truncate public.rfq_distributors'; v_got := 'ok';
    raise exception using errcode = 'MB001';
  exception
    when sqlstate 'MB001' then null;
    when others then v_got := sqlstate;
  end;
  s_base := s_base || 'T01=' || coalesce(v_got, '-') || '|';
  v_got := null; v_seq := '';
  begin
    execute 'set local lock_timeout = ''2s''';
    execute format('set local role %I', 'authenticated');
    perform set_config('request.jwt.claim.sub', coalesce(v_ind::text, ''), true);
    perform set_config('request.jwt.claims', case when v_ind::text is null then '' else json_build_object('sub', v_ind::text, 'role', 'authenticated', 'aal', 'aal1')::text end, true);
    execute 'truncate public.rfq_distributors'; v_got := 'ok';
    raise exception using errcode = 'MB001';
  exception
    when sqlstate 'MB001' then null;
    when others then v_got := sqlstate;
  end;
  s_base := s_base || 'T02=' || coalesce(v_got, '-') || '|';
  v_got := null; v_seq := '';
  begin
    execute 'set local lock_timeout = ''2s''';
    execute format('set local role %I', 'anon');
    perform set_config('request.jwt.claim.sub', coalesce(null::text, ''), true);
    perform set_config('request.jwt.claims', case when null::text is null then '' else json_build_object('sub', null::text, 'role', 'anon', 'aal', 'aal1')::text end, true);
    execute 'lock table public.distributors in access exclusive mode'; v_got := 'ok';
    raise exception using errcode = 'MB001';
  exception
    when sqlstate 'MB001' then null;
    when others then v_got := sqlstate;
  end;
  s_base := s_base || 'L01=' || coalesce(v_got, '-') || '|';
  v_got := null; v_seq := '';
  begin
    execute 'set local lock_timeout = ''2s''';
    execute format('set local role %I', 'authenticated');
    perform set_config('request.jwt.claim.sub', coalesce(v_ind::text, ''), true);
    perform set_config('request.jwt.claims', case when v_ind::text is null then '' else json_build_object('sub', v_ind::text, 'role', 'authenticated', 'aal', 'aal1')::text end, true);
    execute 'lock table public.product_prices in access exclusive mode'; v_got := 'ok';
    raise exception using errcode = 'MB001';
  exception
    when sqlstate 'MB001' then null;
    when others then v_got := sqlstate;
  end;
  s_base := s_base || 'L02=' || coalesce(v_got, '-') || '|';
  v_got := null; v_seq := '';
  begin
    execute 'set local lock_timeout = ''2s''';
    execute format('set local role %I', 'authenticated');
    perform set_config('request.jwt.claim.sub', coalesce(v_ind::text, ''), true);
    perform set_config('request.jwt.claims', case when v_ind::text is null then '' else json_build_object('sub', v_ind::text, 'role', 'authenticated', 'aal', 'aal1')::text end, true);
    execute 'lock table public.moodboards in access exclusive mode'; v_got := 'ok';
    raise exception using errcode = 'MB001';
  exception
    when sqlstate 'MB001' then null;
    when others then v_got := sqlstate;
  end;
  s_base := s_base || 'L03=' || coalesce(v_got, '-') || '|';
  v_got := null; v_seq := '';
  begin
    execute 'set local lock_timeout = ''2s''';
    execute format('set local role %I', 'anon');
    perform set_config('request.jwt.claim.sub', coalesce(null::text, ''), true);
    perform set_config('request.jwt.claims', case when null::text is null then '' else json_build_object('sub', null::text, 'role', 'anon', 'aal', 'aal1')::text end, true);
    execute 'lock table public.projects in access exclusive mode'; v_got := 'ok';
    raise exception using errcode = 'MB001';
  exception
    when sqlstate 'MB001' then null;
    when others then v_got := sqlstate;
  end;
  s_base := s_base || 'L04=' || coalesce(v_got, '-') || '|';

  execute t_m;
  h1 := md5(
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
  v_sin_m := not exists (select 1 from pg_class c, unnest(array['anon', 'authenticated']) r2
                          where c.relnamespace = 'public'::regnamespace and c.relkind in ('r', 'v', 'm', 'p') and has_table_privilege(r2, c.oid, 'MAINTAIN'));
  s_tras := '';
  v_got := null; v_seq := '';
  begin
    execute 'set local lock_timeout = ''2s''';
    execute format('set local role %I', 'anon');
    perform set_config('request.jwt.claim.sub', coalesce(null::text, ''), true);
    perform set_config('request.jwt.claims', case when null::text is null then '' else json_build_object('sub', null::text, 'role', 'anon', 'aal', 'aal1')::text end, true);
    execute 'select count(*) from public.categories' into v_n; v_got := v_n::text;
    raise exception using errcode = 'MB001';
  exception
    when sqlstate 'MB001' then null;
    when others then v_got := sqlstate;
  end;
  s_tras := s_tras || 'P01=' || coalesce(v_got, '-') || '|';
  v_got := null; v_seq := '';
  begin
    execute 'set local lock_timeout = ''2s''';
    execute format('set local role %I', 'anon');
    perform set_config('request.jwt.claim.sub', coalesce(null::text, ''), true);
    perform set_config('request.jwt.claims', case when null::text is null then '' else json_build_object('sub', null::text, 'role', 'anon', 'aal', 'aal1')::text end, true);
    execute 'select count(*) from public.plans' into v_n; v_got := v_n::text;
    raise exception using errcode = 'MB001';
  exception
    when sqlstate 'MB001' then null;
    when others then v_got := sqlstate;
  end;
  s_tras := s_tras || 'P02=' || coalesce(v_got, '-') || '|';
  v_got := null; v_seq := '';
  begin
    execute 'set local lock_timeout = ''2s''';
    execute format('set local role %I', 'anon');
    perform set_config('request.jwt.claim.sub', coalesce(null::text, ''), true);
    perform set_config('request.jwt.claims', case when null::text is null then '' else json_build_object('sub', null::text, 'role', 'anon', 'aal', 'aal1')::text end, true);
    execute 'select count(*) from public.catalog_products' into v_n; v_got := v_n::text;
    raise exception using errcode = 'MB001';
  exception
    when sqlstate 'MB001' then null;
    when others then v_got := sqlstate;
  end;
  s_tras := s_tras || 'P03=' || coalesce(v_got, '-') || '|';
  v_got := null; v_seq := '';
  begin
    execute 'set local lock_timeout = ''2s''';
    execute format('set local role %I', 'anon');
    perform set_config('request.jwt.claim.sub', coalesce(null::text, ''), true);
    perform set_config('request.jwt.claims', case when null::text is null then '' else json_build_object('sub', null::text, 'role', 'anon', 'aal', 'aal1')::text end, true);
    execute 'select count(*) from public.projects' into v_n; v_got := v_n::text;
    raise exception using errcode = 'MB001';
  exception
    when sqlstate 'MB001' then null;
    when others then v_got := sqlstate;
  end;
  s_tras := s_tras || 'P04=' || coalesce(v_got, '-') || '|';
  v_got := null; v_seq := '';
  begin
    execute 'set local lock_timeout = ''2s''';
    execute format('set local role %I', 'anon');
    perform set_config('request.jwt.claim.sub', coalesce(null::text, ''), true);
    perform set_config('request.jwt.claims', case when null::text is null then '' else json_build_object('sub', null::text, 'role', 'anon', 'aal', 'aal1')::text end, true);
    execute 'select count(*) from public.professional_profiles' into v_n; v_got := v_n::text;
    raise exception using errcode = 'MB001';
  exception
    when sqlstate 'MB001' then null;
    when others then v_got := sqlstate;
  end;
  s_tras := s_tras || 'P05=' || coalesce(v_got, '-') || '|';
  v_got := null; v_seq := '';
  begin
    execute 'set local lock_timeout = ''2s''';
    execute format('set local role %I', 'authenticated');
    perform set_config('request.jwt.claim.sub', coalesce(v_ind::text, ''), true);
    perform set_config('request.jwt.claims', case when v_ind::text is null then '' else json_build_object('sub', v_ind::text, 'role', 'authenticated', 'aal', 'aal1')::text end, true);
    execute 'select count(*) from public.projects' into v_n; v_got := v_n::text;
    raise exception using errcode = 'MB001';
  exception
    when sqlstate 'MB001' then null;
    when others then v_got := sqlstate;
  end;
  s_tras := s_tras || 'P06=' || coalesce(v_got, '-') || '|';
  v_got := null; v_seq := '';
  begin
    execute 'set local lock_timeout = ''2s''';
    execute format('set local role %I', 'authenticated');
    perform set_config('request.jwt.claim.sub', coalesce(v_ind::text, ''), true);
    perform set_config('request.jwt.claims', case when v_ind::text is null then '' else json_build_object('sub', v_ind::text, 'role', 'authenticated', 'aal', 'aal1')::text end, true);
    execute 'select count(*) from public.project_products' into v_n; v_got := v_n::text;
    raise exception using errcode = 'MB001';
  exception
    when sqlstate 'MB001' then null;
    when others then v_got := sqlstate;
  end;
  s_tras := s_tras || 'P07=' || coalesce(v_got, '-') || '|';
  v_got := null; v_seq := '';
  begin
    execute 'set local lock_timeout = ''2s''';
    execute format('set local role %I', 'authenticated');
    perform set_config('request.jwt.claim.sub', coalesce(v_ind::text, ''), true);
    perform set_config('request.jwt.claims', case when v_ind::text is null then '' else json_build_object('sub', v_ind::text, 'role', 'authenticated', 'aal', 'aal1')::text end, true);
    execute 'select count(*) from public.rfqs' into v_n; v_got := v_n::text;
    raise exception using errcode = 'MB001';
  exception
    when sqlstate 'MB001' then null;
    when others then v_got := sqlstate;
  end;
  s_tras := s_tras || 'P08=' || coalesce(v_got, '-') || '|';
  v_got := null; v_seq := '';
  begin
    execute 'set local lock_timeout = ''2s''';
    execute format('set local role %I', 'authenticated');
    perform set_config('request.jwt.claim.sub', coalesce(v_ind::text, ''), true);
    perform set_config('request.jwt.claims', case when v_ind::text is null then '' else json_build_object('sub', v_ind::text, 'role', 'authenticated', 'aal', 'aal1')::text end, true);
    execute 'select count(*) from public.professional_profiles' into v_n; v_got := v_n::text;
    raise exception using errcode = 'MB001';
  exception
    when sqlstate 'MB001' then null;
    when others then v_got := sqlstate;
  end;
  s_tras := s_tras || 'P09=' || coalesce(v_got, '-') || '|';
  v_got := null; v_seq := '';
  begin
    execute 'set local lock_timeout = ''2s''';
    execute format('set local role %I', 'authenticated');
    perform set_config('request.jwt.claim.sub', coalesce(v_ind::text, ''), true);
    perform set_config('request.jwt.claims', case when v_ind::text is null then '' else json_build_object('sub', v_ind::text, 'role', 'authenticated', 'aal', 'aal1')::text end, true);
    execute 'select count(*) from public.plans' into v_n; v_got := v_n::text;
    raise exception using errcode = 'MB001';
  exception
    when sqlstate 'MB001' then null;
    when others then v_got := sqlstate;
  end;
  s_tras := s_tras || 'P10=' || coalesce(v_got, '-') || '|';
  v_got := null; v_seq := '';
  begin
    execute 'set local lock_timeout = ''2s''';
    execute format('set local role %I', 'authenticated');
    perform set_config('request.jwt.claim.sub', coalesce(v_ind::text, ''), true);
    perform set_config('request.jwt.claims', case when v_ind::text is null then '' else json_build_object('sub', v_ind::text, 'role', 'authenticated', 'aal', 'aal1')::text end, true);
    execute 'select count(*) from public.categories' into v_n; v_got := v_n::text;
    raise exception using errcode = 'MB001';
  exception
    when sqlstate 'MB001' then null;
    when others then v_got := sqlstate;
  end;
  s_tras := s_tras || 'P11=' || coalesce(v_got, '-') || '|';
  v_got := null; v_seq := '';
  begin
    execute 'set local lock_timeout = ''2s''';
    execute format('set local role %I', 'authenticated');
    perform set_config('request.jwt.claim.sub', coalesce(v_ind::text, ''), true);
    perform set_config('request.jwt.claims', case when v_ind::text is null then '' else json_build_object('sub', v_ind::text, 'role', 'authenticated', 'aal', 'aal1')::text end, true);
    execute format('update public.projects set name = name where id = %L', v_proj); get diagnostics v_n = row_count; v_got := 'rows=' || v_n;
    raise exception using errcode = 'MB001';
  exception
    when sqlstate 'MB001' then null;
    when others then v_got := sqlstate;
  end;
  s_tras := s_tras || 'P12=' || coalesce(v_got, '-') || '|';
  v_got := null; v_seq := '';
  begin
    execute 'set local lock_timeout = ''2s''';
    execute format('set local role %I', 'authenticated');
    perform set_config('request.jwt.claim.sub', coalesce(v_ind::text, ''), true);
    perform set_config('request.jwt.claims', case when v_ind::text is null then '' else json_build_object('sub', v_ind::text, 'role', 'authenticated', 'aal', 'aal1')::text end, true);
    execute format('insert into public.project_products (project_id, product_id, quantity, unit) values (%L, %L, 1, %L)', v_proj, v_prod, 'ud.'); get diagnostics v_n = row_count; v_seq := v_seq || v_n::text || '/';
    execute format('update public.project_products set quantity = 2 where project_id = %L and product_id = %L', v_proj, v_prod); get diagnostics v_n = row_count; v_seq := v_seq || v_n::text || '/';
    execute format('delete from public.project_products where project_id = %L and product_id = %L', v_proj, v_prod); get diagnostics v_n = row_count; v_seq := v_seq || v_n::text || '/';
    v_got := v_seq;
    raise exception using errcode = 'MB001';
  exception
    when sqlstate 'MB001' then null;
    when others then v_got := sqlstate;
  end;
  s_tras := s_tras || 'P13=' || coalesce(v_got, '-') || '|';
  v_got := null; v_seq := '';
  begin
    execute 'set local lock_timeout = ''2s''';
    execute format('set local role %I', 'authenticated');
    perform set_config('request.jwt.claim.sub', coalesce(v_ind::text, ''), true);
    perform set_config('request.jwt.claims', case when v_ind::text is null then '' else json_build_object('sub', v_ind::text, 'role', 'authenticated', 'aal', 'aal1')::text end, true);
    execute format('update public.professional_profiles set phone = phone where user_id = %L', v_ind); get diagnostics v_n = row_count; v_got := 'rows=' || v_n;
    raise exception using errcode = 'MB001';
  exception
    when sqlstate 'MB001' then null;
    when others then v_got := sqlstate;
  end;
  s_tras := s_tras || 'P14=' || coalesce(v_got, '-') || '|';
  v_got := null; v_seq := '';
  begin
    execute 'set local lock_timeout = ''2s''';
    execute format('set local role %I', 'authenticated');
    perform set_config('request.jwt.claim.sub', coalesce(v_gra::text, ''), true);
    perform set_config('request.jwt.claims', case when v_gra::text is null then '' else json_build_object('sub', v_gra::text, 'role', 'authenticated', 'aal', 'aal1')::text end, true);
    execute 'select count(*) from public.projects' into v_n; v_got := v_n::text;
    raise exception using errcode = 'MB001';
  exception
    when sqlstate 'MB001' then null;
    when others then v_got := sqlstate;
  end;
  s_tras := s_tras || 'P15=' || coalesce(v_got, '-') || '|';
  v_got := null; v_seq := '';
  begin
    execute 'set local lock_timeout = ''2s''';
    execute format('set local role %I', 'authenticated');
    perform set_config('request.jwt.claim.sub', coalesce(v_gra::text, ''), true);
    perform set_config('request.jwt.claims', case when v_gra::text is null then '' else json_build_object('sub', v_gra::text, 'role', 'authenticated', 'aal', 'aal1')::text end, true);
    execute 'select count(*) from public.project_products' into v_n; v_got := v_n::text;
    raise exception using errcode = 'MB001';
  exception
    when sqlstate 'MB001' then null;
    when others then v_got := sqlstate;
  end;
  s_tras := s_tras || 'P16=' || coalesce(v_got, '-') || '|';
  v_got := null; v_seq := '';
  begin
    execute 'set local lock_timeout = ''2s''';
    execute format('set local role %I', 'anon');
    perform set_config('request.jwt.claim.sub', coalesce(null::text, ''), true);
    perform set_config('request.jwt.claims', case when null::text is null then '' else json_build_object('sub', null::text, 'role', 'anon', 'aal', 'aal1')::text end, true);
    execute 'truncate public.rfq_distributors'; v_got := 'ok';
    raise exception using errcode = 'MB001';
  exception
    when sqlstate 'MB001' then null;
    when others then v_got := sqlstate;
  end;
  s_tras := s_tras || 'T01=' || coalesce(v_got, '-') || '|';
  v_got := null; v_seq := '';
  begin
    execute 'set local lock_timeout = ''2s''';
    execute format('set local role %I', 'authenticated');
    perform set_config('request.jwt.claim.sub', coalesce(v_ind::text, ''), true);
    perform set_config('request.jwt.claims', case when v_ind::text is null then '' else json_build_object('sub', v_ind::text, 'role', 'authenticated', 'aal', 'aal1')::text end, true);
    execute 'truncate public.rfq_distributors'; v_got := 'ok';
    raise exception using errcode = 'MB001';
  exception
    when sqlstate 'MB001' then null;
    when others then v_got := sqlstate;
  end;
  s_tras := s_tras || 'T02=' || coalesce(v_got, '-') || '|';
  v_got := null; v_seq := '';
  begin
    execute 'set local lock_timeout = ''2s''';
    execute format('set local role %I', 'anon');
    perform set_config('request.jwt.claim.sub', coalesce(null::text, ''), true);
    perform set_config('request.jwt.claims', case when null::text is null then '' else json_build_object('sub', null::text, 'role', 'anon', 'aal', 'aal1')::text end, true);
    execute 'lock table public.distributors in access exclusive mode'; v_got := 'ok';
    raise exception using errcode = 'MB001';
  exception
    when sqlstate 'MB001' then null;
    when others then v_got := sqlstate;
  end;
  s_tras := s_tras || 'L01=' || coalesce(v_got, '-') || '|';
  v_got := null; v_seq := '';
  begin
    execute 'set local lock_timeout = ''2s''';
    execute format('set local role %I', 'authenticated');
    perform set_config('request.jwt.claim.sub', coalesce(v_ind::text, ''), true);
    perform set_config('request.jwt.claims', case when v_ind::text is null then '' else json_build_object('sub', v_ind::text, 'role', 'authenticated', 'aal', 'aal1')::text end, true);
    execute 'lock table public.product_prices in access exclusive mode'; v_got := 'ok';
    raise exception using errcode = 'MB001';
  exception
    when sqlstate 'MB001' then null;
    when others then v_got := sqlstate;
  end;
  s_tras := s_tras || 'L02=' || coalesce(v_got, '-') || '|';
  v_got := null; v_seq := '';
  begin
    execute 'set local lock_timeout = ''2s''';
    execute format('set local role %I', 'authenticated');
    perform set_config('request.jwt.claim.sub', coalesce(v_ind::text, ''), true);
    perform set_config('request.jwt.claims', case when v_ind::text is null then '' else json_build_object('sub', v_ind::text, 'role', 'authenticated', 'aal', 'aal1')::text end, true);
    execute 'lock table public.moodboards in access exclusive mode'; v_got := 'ok';
    raise exception using errcode = 'MB001';
  exception
    when sqlstate 'MB001' then null;
    when others then v_got := sqlstate;
  end;
  s_tras := s_tras || 'L03=' || coalesce(v_got, '-') || '|';
  v_got := null; v_seq := '';
  begin
    execute 'set local lock_timeout = ''2s''';
    execute format('set local role %I', 'anon');
    perform set_config('request.jwt.claim.sub', coalesce(null::text, ''), true);
    perform set_config('request.jwt.claims', case when null::text is null then '' else json_build_object('sub', null::text, 'role', 'anon', 'aal', 'aal1')::text end, true);
    execute 'lock table public.projects in access exclusive mode'; v_got := 'ok';
    raise exception using errcode = 'MB001';
  exception
    when sqlstate 'MB001' then null;
    when others then v_got := sqlstate;
  end;
  s_tras := s_tras || 'L04=' || coalesce(v_got, '-') || '|';
  n_tras := null;
  begin
    create table public.zz_seg01_prueba (id int);
    create function public.zz_seg01_fn() returns int language sql as 'select 1';
    n_tras := 'tabla anon=' || coalesce((select string_agg(p, ',' order by p) from unnest(array['SELECT', 'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER', 'MAINTAIN']) p where has_table_privilege('anon', 'public.zz_seg01_prueba', p)), '-')
          || ' auth=' || coalesce((select string_agg(p, ',' order by p) from unnest(array['SELECT', 'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER', 'MAINTAIN']) p where has_table_privilege('authenticated', 'public.zz_seg01_prueba', p)), '-')
          || ' service=' || coalesce((select count(*)::text from unnest(array['SELECT', 'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER', 'MAINTAIN']) p where has_table_privilege('service_role', 'public.zz_seg01_prueba', p)), '-')
          || ' · funcion anon=' || has_function_privilege('anon', 'public.zz_seg01_fn()', 'EXECUTE')::text
          || ' auth=' || has_function_privilege('authenticated', 'public.zz_seg01_fn()', 'EXECUTE')::text
          || ' service=' || has_function_privilege('service_role', 'public.zz_seg01_fn()', 'EXECUTE')::text;
    raise exception using errcode = 'MB001';
  exception
    when sqlstate 'MB001' then null;
    when others then n_tras := 'error ' || sqlstate || ' ' || left(sqlerrm, 120);
  end;

  execute t_r;
  h2 := md5(
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
  s_rec := '';
  v_got := null; v_seq := '';
  begin
    execute 'set local lock_timeout = ''2s''';
    execute format('set local role %I', 'anon');
    perform set_config('request.jwt.claim.sub', coalesce(null::text, ''), true);
    perform set_config('request.jwt.claims', case when null::text is null then '' else json_build_object('sub', null::text, 'role', 'anon', 'aal', 'aal1')::text end, true);
    execute 'select count(*) from public.categories' into v_n; v_got := v_n::text;
    raise exception using errcode = 'MB001';
  exception
    when sqlstate 'MB001' then null;
    when others then v_got := sqlstate;
  end;
  s_rec := s_rec || 'P01=' || coalesce(v_got, '-') || '|';
  v_got := null; v_seq := '';
  begin
    execute 'set local lock_timeout = ''2s''';
    execute format('set local role %I', 'anon');
    perform set_config('request.jwt.claim.sub', coalesce(null::text, ''), true);
    perform set_config('request.jwt.claims', case when null::text is null then '' else json_build_object('sub', null::text, 'role', 'anon', 'aal', 'aal1')::text end, true);
    execute 'select count(*) from public.plans' into v_n; v_got := v_n::text;
    raise exception using errcode = 'MB001';
  exception
    when sqlstate 'MB001' then null;
    when others then v_got := sqlstate;
  end;
  s_rec := s_rec || 'P02=' || coalesce(v_got, '-') || '|';
  v_got := null; v_seq := '';
  begin
    execute 'set local lock_timeout = ''2s''';
    execute format('set local role %I', 'anon');
    perform set_config('request.jwt.claim.sub', coalesce(null::text, ''), true);
    perform set_config('request.jwt.claims', case when null::text is null then '' else json_build_object('sub', null::text, 'role', 'anon', 'aal', 'aal1')::text end, true);
    execute 'select count(*) from public.catalog_products' into v_n; v_got := v_n::text;
    raise exception using errcode = 'MB001';
  exception
    when sqlstate 'MB001' then null;
    when others then v_got := sqlstate;
  end;
  s_rec := s_rec || 'P03=' || coalesce(v_got, '-') || '|';
  v_got := null; v_seq := '';
  begin
    execute 'set local lock_timeout = ''2s''';
    execute format('set local role %I', 'anon');
    perform set_config('request.jwt.claim.sub', coalesce(null::text, ''), true);
    perform set_config('request.jwt.claims', case when null::text is null then '' else json_build_object('sub', null::text, 'role', 'anon', 'aal', 'aal1')::text end, true);
    execute 'select count(*) from public.projects' into v_n; v_got := v_n::text;
    raise exception using errcode = 'MB001';
  exception
    when sqlstate 'MB001' then null;
    when others then v_got := sqlstate;
  end;
  s_rec := s_rec || 'P04=' || coalesce(v_got, '-') || '|';
  v_got := null; v_seq := '';
  begin
    execute 'set local lock_timeout = ''2s''';
    execute format('set local role %I', 'anon');
    perform set_config('request.jwt.claim.sub', coalesce(null::text, ''), true);
    perform set_config('request.jwt.claims', case when null::text is null then '' else json_build_object('sub', null::text, 'role', 'anon', 'aal', 'aal1')::text end, true);
    execute 'select count(*) from public.professional_profiles' into v_n; v_got := v_n::text;
    raise exception using errcode = 'MB001';
  exception
    when sqlstate 'MB001' then null;
    when others then v_got := sqlstate;
  end;
  s_rec := s_rec || 'P05=' || coalesce(v_got, '-') || '|';
  v_got := null; v_seq := '';
  begin
    execute 'set local lock_timeout = ''2s''';
    execute format('set local role %I', 'authenticated');
    perform set_config('request.jwt.claim.sub', coalesce(v_ind::text, ''), true);
    perform set_config('request.jwt.claims', case when v_ind::text is null then '' else json_build_object('sub', v_ind::text, 'role', 'authenticated', 'aal', 'aal1')::text end, true);
    execute 'select count(*) from public.projects' into v_n; v_got := v_n::text;
    raise exception using errcode = 'MB001';
  exception
    when sqlstate 'MB001' then null;
    when others then v_got := sqlstate;
  end;
  s_rec := s_rec || 'P06=' || coalesce(v_got, '-') || '|';
  v_got := null; v_seq := '';
  begin
    execute 'set local lock_timeout = ''2s''';
    execute format('set local role %I', 'authenticated');
    perform set_config('request.jwt.claim.sub', coalesce(v_ind::text, ''), true);
    perform set_config('request.jwt.claims', case when v_ind::text is null then '' else json_build_object('sub', v_ind::text, 'role', 'authenticated', 'aal', 'aal1')::text end, true);
    execute 'select count(*) from public.project_products' into v_n; v_got := v_n::text;
    raise exception using errcode = 'MB001';
  exception
    when sqlstate 'MB001' then null;
    when others then v_got := sqlstate;
  end;
  s_rec := s_rec || 'P07=' || coalesce(v_got, '-') || '|';
  v_got := null; v_seq := '';
  begin
    execute 'set local lock_timeout = ''2s''';
    execute format('set local role %I', 'authenticated');
    perform set_config('request.jwt.claim.sub', coalesce(v_ind::text, ''), true);
    perform set_config('request.jwt.claims', case when v_ind::text is null then '' else json_build_object('sub', v_ind::text, 'role', 'authenticated', 'aal', 'aal1')::text end, true);
    execute 'select count(*) from public.rfqs' into v_n; v_got := v_n::text;
    raise exception using errcode = 'MB001';
  exception
    when sqlstate 'MB001' then null;
    when others then v_got := sqlstate;
  end;
  s_rec := s_rec || 'P08=' || coalesce(v_got, '-') || '|';
  v_got := null; v_seq := '';
  begin
    execute 'set local lock_timeout = ''2s''';
    execute format('set local role %I', 'authenticated');
    perform set_config('request.jwt.claim.sub', coalesce(v_ind::text, ''), true);
    perform set_config('request.jwt.claims', case when v_ind::text is null then '' else json_build_object('sub', v_ind::text, 'role', 'authenticated', 'aal', 'aal1')::text end, true);
    execute 'select count(*) from public.professional_profiles' into v_n; v_got := v_n::text;
    raise exception using errcode = 'MB001';
  exception
    when sqlstate 'MB001' then null;
    when others then v_got := sqlstate;
  end;
  s_rec := s_rec || 'P09=' || coalesce(v_got, '-') || '|';
  v_got := null; v_seq := '';
  begin
    execute 'set local lock_timeout = ''2s''';
    execute format('set local role %I', 'authenticated');
    perform set_config('request.jwt.claim.sub', coalesce(v_ind::text, ''), true);
    perform set_config('request.jwt.claims', case when v_ind::text is null then '' else json_build_object('sub', v_ind::text, 'role', 'authenticated', 'aal', 'aal1')::text end, true);
    execute 'select count(*) from public.plans' into v_n; v_got := v_n::text;
    raise exception using errcode = 'MB001';
  exception
    when sqlstate 'MB001' then null;
    when others then v_got := sqlstate;
  end;
  s_rec := s_rec || 'P10=' || coalesce(v_got, '-') || '|';
  v_got := null; v_seq := '';
  begin
    execute 'set local lock_timeout = ''2s''';
    execute format('set local role %I', 'authenticated');
    perform set_config('request.jwt.claim.sub', coalesce(v_ind::text, ''), true);
    perform set_config('request.jwt.claims', case when v_ind::text is null then '' else json_build_object('sub', v_ind::text, 'role', 'authenticated', 'aal', 'aal1')::text end, true);
    execute 'select count(*) from public.categories' into v_n; v_got := v_n::text;
    raise exception using errcode = 'MB001';
  exception
    when sqlstate 'MB001' then null;
    when others then v_got := sqlstate;
  end;
  s_rec := s_rec || 'P11=' || coalesce(v_got, '-') || '|';
  v_got := null; v_seq := '';
  begin
    execute 'set local lock_timeout = ''2s''';
    execute format('set local role %I', 'authenticated');
    perform set_config('request.jwt.claim.sub', coalesce(v_ind::text, ''), true);
    perform set_config('request.jwt.claims', case when v_ind::text is null then '' else json_build_object('sub', v_ind::text, 'role', 'authenticated', 'aal', 'aal1')::text end, true);
    execute format('update public.projects set name = name where id = %L', v_proj); get diagnostics v_n = row_count; v_got := 'rows=' || v_n;
    raise exception using errcode = 'MB001';
  exception
    when sqlstate 'MB001' then null;
    when others then v_got := sqlstate;
  end;
  s_rec := s_rec || 'P12=' || coalesce(v_got, '-') || '|';
  v_got := null; v_seq := '';
  begin
    execute 'set local lock_timeout = ''2s''';
    execute format('set local role %I', 'authenticated');
    perform set_config('request.jwt.claim.sub', coalesce(v_ind::text, ''), true);
    perform set_config('request.jwt.claims', case when v_ind::text is null then '' else json_build_object('sub', v_ind::text, 'role', 'authenticated', 'aal', 'aal1')::text end, true);
    execute format('insert into public.project_products (project_id, product_id, quantity, unit) values (%L, %L, 1, %L)', v_proj, v_prod, 'ud.'); get diagnostics v_n = row_count; v_seq := v_seq || v_n::text || '/';
    execute format('update public.project_products set quantity = 2 where project_id = %L and product_id = %L', v_proj, v_prod); get diagnostics v_n = row_count; v_seq := v_seq || v_n::text || '/';
    execute format('delete from public.project_products where project_id = %L and product_id = %L', v_proj, v_prod); get diagnostics v_n = row_count; v_seq := v_seq || v_n::text || '/';
    v_got := v_seq;
    raise exception using errcode = 'MB001';
  exception
    when sqlstate 'MB001' then null;
    when others then v_got := sqlstate;
  end;
  s_rec := s_rec || 'P13=' || coalesce(v_got, '-') || '|';
  v_got := null; v_seq := '';
  begin
    execute 'set local lock_timeout = ''2s''';
    execute format('set local role %I', 'authenticated');
    perform set_config('request.jwt.claim.sub', coalesce(v_ind::text, ''), true);
    perform set_config('request.jwt.claims', case when v_ind::text is null then '' else json_build_object('sub', v_ind::text, 'role', 'authenticated', 'aal', 'aal1')::text end, true);
    execute format('update public.professional_profiles set phone = phone where user_id = %L', v_ind); get diagnostics v_n = row_count; v_got := 'rows=' || v_n;
    raise exception using errcode = 'MB001';
  exception
    when sqlstate 'MB001' then null;
    when others then v_got := sqlstate;
  end;
  s_rec := s_rec || 'P14=' || coalesce(v_got, '-') || '|';
  v_got := null; v_seq := '';
  begin
    execute 'set local lock_timeout = ''2s''';
    execute format('set local role %I', 'authenticated');
    perform set_config('request.jwt.claim.sub', coalesce(v_gra::text, ''), true);
    perform set_config('request.jwt.claims', case when v_gra::text is null then '' else json_build_object('sub', v_gra::text, 'role', 'authenticated', 'aal', 'aal1')::text end, true);
    execute 'select count(*) from public.projects' into v_n; v_got := v_n::text;
    raise exception using errcode = 'MB001';
  exception
    when sqlstate 'MB001' then null;
    when others then v_got := sqlstate;
  end;
  s_rec := s_rec || 'P15=' || coalesce(v_got, '-') || '|';
  v_got := null; v_seq := '';
  begin
    execute 'set local lock_timeout = ''2s''';
    execute format('set local role %I', 'authenticated');
    perform set_config('request.jwt.claim.sub', coalesce(v_gra::text, ''), true);
    perform set_config('request.jwt.claims', case when v_gra::text is null then '' else json_build_object('sub', v_gra::text, 'role', 'authenticated', 'aal', 'aal1')::text end, true);
    execute 'select count(*) from public.project_products' into v_n; v_got := v_n::text;
    raise exception using errcode = 'MB001';
  exception
    when sqlstate 'MB001' then null;
    when others then v_got := sqlstate;
  end;
  s_rec := s_rec || 'P16=' || coalesce(v_got, '-') || '|';
  v_got := null; v_seq := '';
  begin
    execute 'set local lock_timeout = ''2s''';
    execute format('set local role %I', 'anon');
    perform set_config('request.jwt.claim.sub', coalesce(null::text, ''), true);
    perform set_config('request.jwt.claims', case when null::text is null then '' else json_build_object('sub', null::text, 'role', 'anon', 'aal', 'aal1')::text end, true);
    execute 'truncate public.rfq_distributors'; v_got := 'ok';
    raise exception using errcode = 'MB001';
  exception
    when sqlstate 'MB001' then null;
    when others then v_got := sqlstate;
  end;
  s_rec := s_rec || 'T01=' || coalesce(v_got, '-') || '|';
  v_got := null; v_seq := '';
  begin
    execute 'set local lock_timeout = ''2s''';
    execute format('set local role %I', 'authenticated');
    perform set_config('request.jwt.claim.sub', coalesce(v_ind::text, ''), true);
    perform set_config('request.jwt.claims', case when v_ind::text is null then '' else json_build_object('sub', v_ind::text, 'role', 'authenticated', 'aal', 'aal1')::text end, true);
    execute 'truncate public.rfq_distributors'; v_got := 'ok';
    raise exception using errcode = 'MB001';
  exception
    when sqlstate 'MB001' then null;
    when others then v_got := sqlstate;
  end;
  s_rec := s_rec || 'T02=' || coalesce(v_got, '-') || '|';
  v_got := null; v_seq := '';
  begin
    execute 'set local lock_timeout = ''2s''';
    execute format('set local role %I', 'anon');
    perform set_config('request.jwt.claim.sub', coalesce(null::text, ''), true);
    perform set_config('request.jwt.claims', case when null::text is null then '' else json_build_object('sub', null::text, 'role', 'anon', 'aal', 'aal1')::text end, true);
    execute 'lock table public.distributors in access exclusive mode'; v_got := 'ok';
    raise exception using errcode = 'MB001';
  exception
    when sqlstate 'MB001' then null;
    when others then v_got := sqlstate;
  end;
  s_rec := s_rec || 'L01=' || coalesce(v_got, '-') || '|';
  v_got := null; v_seq := '';
  begin
    execute 'set local lock_timeout = ''2s''';
    execute format('set local role %I', 'authenticated');
    perform set_config('request.jwt.claim.sub', coalesce(v_ind::text, ''), true);
    perform set_config('request.jwt.claims', case when v_ind::text is null then '' else json_build_object('sub', v_ind::text, 'role', 'authenticated', 'aal', 'aal1')::text end, true);
    execute 'lock table public.product_prices in access exclusive mode'; v_got := 'ok';
    raise exception using errcode = 'MB001';
  exception
    when sqlstate 'MB001' then null;
    when others then v_got := sqlstate;
  end;
  s_rec := s_rec || 'L02=' || coalesce(v_got, '-') || '|';
  v_got := null; v_seq := '';
  begin
    execute 'set local lock_timeout = ''2s''';
    execute format('set local role %I', 'authenticated');
    perform set_config('request.jwt.claim.sub', coalesce(v_ind::text, ''), true);
    perform set_config('request.jwt.claims', case when v_ind::text is null then '' else json_build_object('sub', v_ind::text, 'role', 'authenticated', 'aal', 'aal1')::text end, true);
    execute 'lock table public.moodboards in access exclusive mode'; v_got := 'ok';
    raise exception using errcode = 'MB001';
  exception
    when sqlstate 'MB001' then null;
    when others then v_got := sqlstate;
  end;
  s_rec := s_rec || 'L03=' || coalesce(v_got, '-') || '|';
  v_got := null; v_seq := '';
  begin
    execute 'set local lock_timeout = ''2s''';
    execute format('set local role %I', 'anon');
    perform set_config('request.jwt.claim.sub', coalesce(null::text, ''), true);
    perform set_config('request.jwt.claims', case when null::text is null then '' else json_build_object('sub', null::text, 'role', 'anon', 'aal', 'aal1')::text end, true);
    execute 'lock table public.projects in access exclusive mode'; v_got := 'ok';
    raise exception using errcode = 'MB001';
  exception
    when sqlstate 'MB001' then null;
    when others then v_got := sqlstate;
  end;
  s_rec := s_rec || 'L04=' || coalesce(v_got, '-') || '|';
  n_rec := null;
  begin
    create table public.zz_seg01_prueba (id int);
    create function public.zz_seg01_fn() returns int language sql as 'select 1';
    n_rec := 'tabla anon=' || coalesce((select string_agg(p, ',' order by p) from unnest(array['SELECT', 'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER', 'MAINTAIN']) p where has_table_privilege('anon', 'public.zz_seg01_prueba', p)), '-')
          || ' auth=' || coalesce((select string_agg(p, ',' order by p) from unnest(array['SELECT', 'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER', 'MAINTAIN']) p where has_table_privilege('authenticated', 'public.zz_seg01_prueba', p)), '-')
          || ' service=' || coalesce((select count(*)::text from unnest(array['SELECT', 'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER', 'MAINTAIN']) p where has_table_privilege('service_role', 'public.zz_seg01_prueba', p)), '-')
          || ' · funcion anon=' || has_function_privilege('anon', 'public.zz_seg01_fn()', 'EXECUTE')::text
          || ' auth=' || has_function_privilege('authenticated', 'public.zz_seg01_fn()', 'EXECUTE')::text
          || ' service=' || has_function_privilege('service_role', 'public.zz_seg01_fn()', 'EXECUTE')::text;
    raise exception using errcode = 'MB001';
  exception
    when sqlstate 'MB001' then null;
    when others then n_rec := 'error ' || sqlstate || ' ' || left(sqlerrm, 120);
  end;

  -- La web no cambia: todas las sondas salvo TRUNCATE (T01, T02) y LOCK (L01–L04) dan lo mismo en las tres fases.
  w_base := regexp_replace(s_base, '[TL]0[1-4]=[^|]*\|', '', 'g');
  w_tras := regexp_replace(s_tras, '[TL]0[1-4]=[^|]*\|', '', 'g');
  w_rec := regexp_replace(s_rec, '[TL]0[1-4]=[^|]*\|', '', 'g');

  raise exception 'MOBAU_SEG01E cambia=% identico=% web_igual=% truncate=% sin_maintain=% lock=% nuevos_cerrados=% nuevos_recuperados=% :: base=% · tras=% · rec=% · nuevos_tras=% · nuevos_rec=%',
    (h1 <> h0), (h2 = h0), (w_base = w_tras and w_tras = w_rec),
    (s_base ~ 'T01=ok\|T02=ok\|' and s_tras ~ 'T01=42501\|T02=42501\|' and s_rec ~ 'T01=ok\|T02=ok\|'),
    v_sin_m,
    (s_base ~ 'L01=ok\|L02=ok\|L03=ok\|L04=ok\|' and s_tras ~ 'L01=42501\|L02=42501\|L03=ok\|L04=ok\|' and s_rec ~ 'L01=ok\|L02=ok\|L03=ok\|L04=ok\|'),
    (n_tras = 'tabla anon=DELETE,INSERT,SELECT,UPDATE auth=DELETE,INSERT,SELECT,UPDATE service=8 · funcion anon=false auth=false service=true'), (n_rec = 'tabla anon=DELETE,INSERT,MAINTAIN,REFERENCES,SELECT,TRIGGER,TRUNCATE,UPDATE auth=DELETE,INSERT,MAINTAIN,REFERENCES,SELECT,TRIGGER,TRUNCATE,UPDATE service=8 · funcion anon=true auth=true service=true'),
    s_base, s_tras, s_rec, n_tras, n_rec
    using errcode = 'MB990';
end $S01E$;

COMMIT;
