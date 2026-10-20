-- ============================================================
-- RECUPERACIÓN NO EJECUTADA (SEG-01 · inversa de O2 + O4) — no ejecutar sin aprobación explícita
-- ============================================================
-- Devuelve a anon y authenticated TRUNCATE, REFERENCES y TRIGGER en las 8
-- tablas y MAINTAIN en las mismas tablas donde lo tenían (11 para anon, 13
-- para authenticated), y restaura los privilegios por defecto de postgres tal
-- como se leyeron el 2026-10-20: tablas y funciones de public abiertas, y
-- EXECUTE para PUBLIC en funciones nuevas. Compara privilegios efectivos, no
-- el orden del texto de las ACL.
-- Registro: tras confirmar el COMMIT, se registra como migración nueva con
-- versión y nombre propios; la fila de SEG-01 no se borra.
-- Ejecutar completo.
-- ============================================================

BEGIN;

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

COMMIT;
