-- ============================================================
-- PROPUESTA NO EJECUTADA (44-04 · REFERENCES y TRIGGER en products) — no ejecutar sin aprobación explícita
-- ============================================================
-- Corrección de seguridad, separada de 44-03 (se autoriza, aplica y
-- recupera por su cuenta; no depende de ella).
-- Estado comprobado (solo SELECT, 2026-10-22):
--   * products.relacl = {postgres=arwdDxtm/postgres,anon=xt/postgres,
--     authenticated=xt/postgres,service_role=arwdDxtm/postgres}
--   * anon y authenticated tienen REFERENCES y TRIGGER por concesión
--     directa de postgres, sin opción de concesión; no vienen de PUBLIC
--     (sin entrada PUBLIC en la tabla ni en columnas) ni de herencia (no son
--     miembros de ningún rol). Ninguna columna tiene REFERENCES propio.
--   * No hacen falta: no pueden crear objetos en public (sin CREATE), las 6
--     claves ajenas hacia products son de tablas de postgres (la comprobación
--     se hace con el dueño) y los 4 triggers de products son de postgres.
-- Retira solo esos dos privilegios a esos dos roles. No toca SELECT, INSERT,
-- UPDATE, DELETE (por columna), RLS, políticas ni otras tablas.
-- Recuperación: rollback/20261023120100_44_04_permisos_products.rollback.sql.
-- ============================================================

BEGIN;

DO $$
begin
  if current_user <> 'postgres' then
    raise exception '44-04: ejecutar como postgres';
  end if;
  if exists (select 1 from supabase_migrations.schema_migrations where version = '20261023120100') then
    raise exception '44-04: ya está registrada';
  end if;
  if (select relacl::text from pg_class where oid = 'public.products'::regclass)
     <> '{postgres=arwdDxtm/postgres,anon=xt/postgres,authenticated=xt/postgres,service_role=arwdDxtm/postgres}' then
    raise exception '44-04: los permisos de tabla de products no son los esperados';
  end if;
  perform set_config('mobau.p44d_columnas', md5(coalesce((
    select string_agg(a.attname || ':' || coalesce(a.attacl::text, '-'), '|' order by a.attnum)
      from pg_attribute a where a.attrelid = 'public.products'::regclass and a.attnum > 0 and not a.attisdropped), '')), true);
  perform set_config('mobau.p44d_politicas', md5(coalesce((
    select string_agg(policyname || ':' || cmd || ':' || roles::text || ':' || coalesce(qual, '-') || ':' || coalesce(with_check, '-'), '|' order by policyname)
      from pg_policies where schemaname = 'public' and tablename = 'products'), '')), true);
end $$;

revoke references, trigger on table public.products from anon, authenticated;

DO $$
begin
  if (select relacl::text from pg_class where oid = 'public.products'::regclass)
     <> '{postgres=arwdDxtm/postgres,service_role=arwdDxtm/postgres}'
     or exists (select 1 from unnest(array['anon', 'authenticated']) r, unnest(array['REFERENCES', 'TRIGGER']) p
                 where has_table_privilege(r, 'public.products', p)) then
    raise exception '44-04: REFERENCES o TRIGGER siguen concedidos';
  end if;
  if md5(coalesce((
       select string_agg(a.attname || ':' || coalesce(a.attacl::text, '-'), '|' order by a.attnum)
         from pg_attribute a where a.attrelid = 'public.products'::regclass and a.attnum > 0 and not a.attisdropped), ''))
       <> current_setting('mobau.p44d_columnas')
     or md5(coalesce((
       select string_agg(policyname || ':' || cmd || ':' || roles::text || ':' || coalesce(qual, '-') || ':' || coalesce(with_check, '-'), '|' order by policyname)
         from pg_policies where schemaname = 'public' and tablename = 'products'), ''))
       <> current_setting('mobau.p44d_politicas')
     or not (select relrowsecurity from pg_class where oid = 'public.products'::regclass) then
    raise exception '44-04: cambiaron permisos por columna, políticas o RLS de products';
  end if;
end $$;

COMMIT;
