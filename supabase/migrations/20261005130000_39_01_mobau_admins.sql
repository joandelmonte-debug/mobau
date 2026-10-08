-- ============================================================
-- PROPUESTA NO EJECUTADA (39) — no ejecutar sin aprobación explícita
-- ============================================================
-- 39 · 01 · Autorización de administración de Mobau
-- ------------------------------------------------------------
-- Crea la lista de administradores de Mobau, el contexto privado de una
-- decisión en curso y las funciones que los leen. NO da de alta a nadie.
--
--   public.mobau_admins      cuentas autorizadas a moderar. RLS activada,
--                            sin políticas y sin permisos de cliente. Alta
--                            y baja solo desde el editor SQL (paso aparte,
--                            con autorización). Baja = revoked_at.
--   public.mobau_moderation_context
--                            «marca» de una decisión de Mobau en curso: una
--                            fila por transacción (txid), con la propuesta,
--                            el admin y el resumen del evento. Se inserta y
--                            se borra dentro de la misma transacción: nunca
--                            se confirma, así que ninguna otra sesión puede
--                            verla (MVCC). Solo la
--                            escribe moderate_product_proposal (39-04, SECURITY
--                            DEFINER) y la borra antes de terminar: fuera de
--                            esa función siempre está vacía. Sin permisos de
--                            cliente: no se puede falsificar (a diferencia de
--                            un ajuste set_config, que cualquier sesión puede
--                            fijar).
--   public.is_mobau_admin()  admin activo Y segundo factor verificado (aal2).
--                            Única fuente de autorización: no depende de
--                            profiles.role ni de raw_user_meta_data.
--   public.mobau_admin_session()  para la interfaz: si la propia cuenta es
--                            admin y si ya tiene aal2.
--   public.mobau_moderation_proposal_id()  propuesta de la decisión en curso
--                            en ESTA transacción y para ESTE admin (o null).
--   public.mobau_moderating(uuid)  (marca correcta) AND (proposal_id no nulo)
--                            AND (is_mobau_admin()). La usan los triggers 39-03.
--
-- search_path = '' en todas las funciones; funciones del sistema siempre
-- como pg_catalog.*, objetos propios como public.* y auth.*. Los operadores
-- (=, ->>, …) solo pueden resolverse en pg_catalog: con search_path vacío no
-- hay otro esquema donde buscarlos y pg_temp nunca se usa para operadores.
-- Propietario esperado de todo lo creado: postgres. Ejecutar completo.
-- ============================================================

BEGIN;

-- ---------- prechecks ----------
DO $$
begin
  if current_user <> 'postgres' then
    raise exception '39-01: ejecutar como postgres (propietario esperado de las funciones)';
  end if;
  if not exists (select 1 from supabase_migrations.schema_migrations where version = '20261005120000') then
    raise exception '39-01: falta 38-C 04 (20261005120000) en schema_migrations';
  end if;
  if to_regclass('public.mobau_admins') is not null or to_regclass('public.mobau_moderation_context') is not null then
    raise exception '39-01: alguna tabla de 39-01 ya existe';
  end if;
  if to_regprocedure('public.is_mobau_admin()') is not null
     or to_regprocedure('public.mobau_admin_session()') is not null
     or to_regprocedure('public.mobau_moderation_proposal_id()') is not null
     or to_regprocedure('public.mobau_moderating(uuid)') is not null then
    raise exception '39-01: alguna función de 39-01 ya existe';
  end if;
  if to_regprocedure('auth.uid()') is null or to_regprocedure('auth.jwt()') is null then
    raise exception '39-01: faltan auth.uid() o auth.jwt()';
  end if;
  -- Nadie de cliente puede crear o reemplazar funciones en public.
  if has_schema_privilege('anon', 'public', 'CREATE') or has_schema_privilege('authenticated', 'public', 'CREATE')
     or pg_has_role('anon', 'postgres', 'MEMBER') or pg_has_role('authenticated', 'postgres', 'MEMBER') then
    raise exception '39-01: un rol de cliente puede crear objetos en public o es miembro de postgres';
  end if;
  if (select count(*) from pg_policies where schemaname = 'public') <> 44 then
    raise exception '39-01: se esperaban 44 políticas en public';
  end if;
end $$;

-- ---------- tablas ----------
create table public.mobau_admins (
  user_id      uuid primary key references auth.users (id) on delete cascade,
  granted_at   timestamptz not null default pg_catalog.now(),
  granted_note text not null,
  revoked_at   timestamptz,
  constraint mobau_admins_note_length check (pg_catalog.char_length(pg_catalog.btrim(granted_note)) between 1 and 200),
  constraint mobau_admins_revoked_after_granted check (revoked_at is null or revoked_at >= granted_at)
);

comment on table public.mobau_admins is
  '39: cuentas autorizadas a moderar propuestas. Sin acceso de cliente. Alta/baja solo desde el editor SQL. Baja = revoked_at.';

create table public.mobau_moderation_context (
  txid        bigint primary key,
  proposal_id uuid not null,
  admin_id    uuid not null,
  event       jsonb not null default '{}'::jsonb,
  created_at  timestamptz not null default pg_catalog.now()
);

comment on table public.mobau_moderation_context is
  '39: decisión de Mobau en curso (una fila por transacción). Solo la escribe moderate_product_proposal y la vacía antes de terminar. Sin acceso de cliente.';

alter table public.mobau_admins enable row level security;
alter table public.mobau_moderation_context enable row level security;
-- Los privilegios por defecto de Supabase conceden todo a anon,
-- authenticated y service_role en tablas nuevas: se retiran explícitamente.
-- Solo el propietario (postgres) accede: el contexto lo escribe únicamente
-- moderate_product_proposal (SECURITY DEFINER) y los admins se gestionan
-- desde el editor SQL.
revoke all on table public.mobau_admins from public, anon, authenticated, service_role;
revoke all on table public.mobau_moderation_context from public, anon, authenticated, service_role;

-- ---------- funciones ----------
-- Admin activo + segundo factor verificado (aal2 en el JWT de la sesión).
create function public.is_mobau_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(
           ((select auth.uid()) is not null)
           and (coalesce((select auth.jwt()) ->> 'aal', '') = 'aal2')
           and (exists (select 1 from public.mobau_admins a
                         where a.user_id = (select auth.uid())
                           and a.revoked_at is null)),
           false);
$$;

-- Estado de la propia sesión, para que la consola sepa si debe pedir MFA.
create function public.mobau_admin_session()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select pg_catalog.jsonb_build_object(
    'admin', exists (select 1 from public.mobau_admins a
                      where a.user_id = (select auth.uid())
                        and a.revoked_at is null),
    'aal2', coalesce((select auth.jwt()) ->> 'aal', '') = 'aal2');
$$;

-- Propuesta de la decisión de Mobau en curso en esta transacción y para
-- este admin; null fuera de moderate_product_proposal.
create function public.mobau_moderation_proposal_id()
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select c.proposal_id
    from public.mobau_moderation_context c
   where c.txid = pg_catalog.txid_current_if_assigned()
     and c.admin_id = (select auth.uid());
$$;

-- (marca correcta) AND (proposal_id no nulo) AND (admin activo con aal2).
create function public.mobau_moderating(p_proposal_id uuid)
returns boolean
language sql
stable
set search_path = ''
as $$
  select coalesce(
           (p_proposal_id is not null)
           and ((select public.mobau_moderation_proposal_id()) = p_proposal_id)
           and ((select public.is_mobau_admin())),
           false);
$$;

-- Permisos: Supabase concede EXECUTE por defecto a anon y authenticated en
-- funciones nuevas. Se retira a public y anon; authenticated lo necesita
-- porque los triggers de 39-03 las llaman con el rol del usuario.
revoke all on function public.is_mobau_admin() from public, anon;
revoke all on function public.mobau_admin_session() from public, anon;
revoke all on function public.mobau_moderation_proposal_id() from public, anon;
revoke all on function public.mobau_moderating(uuid) from public, anon;
grant execute on function public.is_mobau_admin() to authenticated;
grant execute on function public.mobau_admin_session() to authenticated;
grant execute on function public.mobau_moderation_proposal_id() to authenticated;
grant execute on function public.mobau_moderating(uuid) to authenticated;

-- ---------- validación final ----------
DO $$
declare
  f text;
  t text;
begin
  foreach t in array array['public.mobau_admins', 'public.mobau_moderation_context'] loop
    if not (select relrowsecurity from pg_class where oid = t::regclass)
       or (select relowner from pg_class where oid = t::regclass) <> 'postgres'::regrole then
      raise exception '39-01: % debe tener RLS y propietario postgres', t;
    end if;
    if exists (select 1 from pg_policies where schemaname = 'public' and tablename = split_part(t, '.', 2)) then
      raise exception '39-01: % no debe tener políticas', t;
    end if;
    if has_table_privilege('anon', t, 'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER')
       or has_table_privilege('authenticated', t, 'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER')
       or has_table_privilege('service_role', t, 'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER')
       or has_any_column_privilege('anon', t, 'SELECT,INSERT,UPDATE,REFERENCES')
       or has_any_column_privilege('authenticated', t, 'SELECT,INSERT,UPDATE,REFERENCES')
       or has_any_column_privilege('service_role', t, 'SELECT,INSERT,UPDATE,REFERENCES')
       or exists (select 1 from pg_class c, aclexplode(c.relacl) a
                   where c.oid = t::regclass and a.grantee <> c.relowner) then
      raise exception '39-01: % tiene permisos para alguien distinto del propietario', t;
    end if;
  end loop;
  if (select count(*) from public.mobau_admins) <> 0 or (select count(*) from public.mobau_moderation_context) <> 0 then
    raise exception '39-01: las tablas deben quedar vacías';
  end if;
  foreach f in array array['public.is_mobau_admin()', 'public.mobau_admin_session()',
                           'public.mobau_moderation_proposal_id()', 'public.mobau_moderating(uuid)'] loop
    if not exists (select 1 from pg_proc p where p.oid = f::regprocedure
                    and p.proconfig @> array['search_path=""'] and p.proowner = 'postgres'::regrole) then
      raise exception '39-01: % debe tener search_path vacío y propietario postgres', f;
    end if;
    if has_function_privilege('anon', f, 'EXECUTE') or not has_function_privilege('authenticated', f, 'EXECUTE') then
      raise exception '39-01: permisos de ejecución inesperados en %', f;
    end if;
  end loop;
  if not (select prosecdef from pg_proc where oid = 'public.is_mobau_admin()'::regprocedure)
     or not (select prosecdef from pg_proc where oid = 'public.mobau_admin_session()'::regprocedure)
     or not (select prosecdef from pg_proc where oid = 'public.mobau_moderation_proposal_id()'::regprocedure)
     or (select prosecdef from pg_proc where oid = 'public.mobau_moderating(uuid)'::regprocedure) then
    raise exception '39-01: SECURITY DEFINER esperado en 3 funciones; mobau_moderating es INVOKER';
  end if;
  if (select count(*) from pg_policies where schemaname = 'public') <> 44 then
    raise exception '39-01: el número de políticas ha cambiado';
  end if;
  raise notice '39-01 OK: tablas vacías y cerradas; is_mobau_admin exige aal2; marca no falsificable.';
end $$;

COMMIT;
