-- ============================================================
-- PROPUESTA NO EJECUTADA (SEG-01 · O2 + O4 · privilegios de tabla y por defecto) — no ejecutar sin aprobación explícita
-- ============================================================
-- Punto de seguridad separado del 43 (hallazgo del 2026-10-20).
-- O2 · anon y authenticated pierden los privilegios de tabla que no pasan
--      por RLS y que la API nunca usa:
--      * TRUNCATE, REFERENCES y TRIGGER en las 8 tablas que conservan los
--        privilegios por defecto (categories, plans, professional_profiles,
--        projects, project_products, rfqs, rfq_distributors y studios);
--      * MAINTAIN (PostgreSQL 17: VACUUM, ANALYZE, REINDEX, CLUSTER, LOCK
--        TABLE) en todas las tablas de public donde lo tienen: 11 para anon
--        y 13 para authenticated (las mismas más moodboards y product_prices).
--      SELECT, INSERT, UPDATE y DELETE no cambian: RLS los sigue filtrando.
--      LOCK TABLE sigue permitido donde el rol conserva UPDATE o DELETE
--      (regla de PostgreSQL); deja de estarlo donde solo tiene SELECT.
-- O4 · Los objetos que cree postgres a partir de ahora no nacen abiertos:
--      * tablas nuevas de public: sin TRUNCATE, REFERENCES, TRIGGER ni
--        MAINTAIN para anon y authenticated;
--      * funciones nuevas de public: sin EXECUTE para anon y authenticated;
--      * funciones nuevas de postgres en cualquier esquema: sin EXECUTE para
--        PUBLIC (por defecto Postgres lo concede; sin esto, anon lo
--        heredaría). Cada migración concede EXECUTE a quien lo necesite.
--      Los valores por defecto de supabase_admin no se pueden cambiar como
--      postgres y quedan igual. Las funciones y tablas existentes no cambian.
-- No toca políticas, datos, funciones existentes, roles, planes ni habilitaciones.
-- Recuperación: rollback/20261020180000_seg_01_privilegios.rollback.sql.
-- Ejecutar completo.
-- ============================================================

BEGIN;

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

COMMIT;
