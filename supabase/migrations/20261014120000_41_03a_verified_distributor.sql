-- ============================================================
-- PROPUESTA NO EJECUTADA (41-03a) — no ejecutar sin aprobación explícita
-- ============================================================
-- 41 · 03a · B3-C: regla única de «distribuidor verificado»
-- ------------------------------------------------------------
-- Decisión B3-C (2026-10-13): una sola regla para RLS, triggers de
-- propuestas, alta de productos, precios y funciones de ciclo de vida:
--   perfil de distribuidor 'verified' + distributor_id no nulo
--   + profiles.role = 'supplier'.
--
--   1. mobau_private.resolve_verified_distributor(uuid): la regla, en el
--      esquema privado (sin EXECUTE ni USAGE para ningún rol cliente).
--   2. public.my_verified_distributor_id(): se VERSIONA por primera vez
--      (era anterior a 38-B y no estaba en supabase/migrations/). Misma
--      firma, SECURITY DEFINER, STABLE, search_path vacío, propietario y ACL;
--      ahora delega en el auxiliar con (select auth.uid()).
--
-- Puerta B3 (precheck): 0 perfiles 'verified' con distributor_id cuyo
-- profiles.role no sea 'supplier'. Si hay alguno, aborta SIN CAMBIOS.
-- No se ajusta ningún dato ni se busca una alternativa.
--
-- Definición previa exacta (la que restaura el rollback):
--   md5(pg_get_functiondef('public.my_verified_distributor_id()')) = 845179d0ebf4a7b2708bb4638b41355b
--   md5(prosrc)                                                    = 05e1a9337e95b699fc22351e443376ec
-- Cuerpos nuevos: resolve_verified_distributor md5(prosrc) = 1982b668e9cfb08bbf4b376cb0e29e3b
--                 my_verified_distributor_id   md5(prosrc) = c4c85af9dc9fde6d93f9fb25a56d1b87
--
-- No cambia: políticas (48), distributor_profiles, profiles, is_supplier(),
-- is_mobau_admin(), datos. Para el supplier verificado real el valor es el
-- mismo (lo comprueba la validación final para todas las cuentas).
-- Rollback: supabase/rollback/20261014120000_41_03a_verified_distributor.rollback.sql
-- ============================================================

BEGIN;

-- No bloquea tablas: solo crea una función y reemplaza otra.
set local lock_timeout = '5s';

-- ---------- 0. prechecks ----------
DO $$
declare
  f_my constant regprocedure := 'public.my_verified_distributor_id()'::regprocedure;
  v_n bigint;
begin
  if current_user <> 'postgres' then
    raise exception '41-03a: ejecutar como postgres';
  end if;
  if to_regnamespace('mobau_private') is null or to_regclass('public.catalog_products') is null
     or to_regprocedure('public.catalog_version()') is null then
    raise exception '41-03a: faltan 41-01 o 41-02';
  end if;
  if md5(pg_get_functiondef(f_my)) is distinct from '845179d0ebf4a7b2708bb4638b41355b' then
    raise exception '41-03a: my_verified_distributor_id() no es la definición registrada (845179d0…)';
  end if;
  if (select proowner from pg_proc where oid = f_my) <> 'postgres'::regrole then
    raise exception '41-03a: my_verified_distributor_id() no es de postgres';
  end if;
  if to_regprocedure('mobau_private.resolve_verified_distributor(uuid)') is not null then
    raise exception '41-03a: el auxiliar ya existe';
  end if;
  if not exists (select 1 from pg_constraint c
                  where c.conrelid = 'public.distributor_profiles'::regclass and c.contype = 'p'
                    and c.conkey = array[(select attnum from pg_attribute
                                           where attrelid = 'public.distributor_profiles'::regclass and attname = 'user_id')]::int2[]) then
    raise exception '41-03a: distributor_profiles.user_id ya no es la clave primaria';
  end if;
  -- Puerta B3: ningún perfil verificado cuyo rol no sea supplier (solo recuento).
  select count(*) into v_n
    from public.distributor_profiles dp
    left join public.profiles pr on pr.id = dp.user_id
   where dp.verification_status = 'verified' and dp.distributor_id is not null
     and pr.role is distinct from 'supplier';
  if v_n <> 0 then
    raise exception '41-03a: PUERTA B3: hay % perfil(es) verificado(s) cuyo rol no es supplier. No se aplica nada.', v_n;
  end if;
  if (select count(*) from pg_policies where schemaname = 'public') <> 48 then
    raise exception '41-03a: se esperaban 48 políticas';
  end if;
  -- ACL actual, para exigir en la validación final que no cambia.
  perform set_config('mobau.v3_acl_my_verified', coalesce((select proacl::text from pg_proc where oid = f_my), '-'), true);
end $$;

-- ---------- 1. la regla, en el esquema privado ----------
create function mobau_private.resolve_verified_distributor(p_uid uuid)
returns text
language plpgsql
stable
set search_path = ''
as $$
declare
  v_n bigint;
  v_dist text;
begin
  -- 41-03a (B3-C): perfil verificado + distributor_id + role = 'supplier'.
  if p_uid is null then
    return null;
  end if;
  select pg_catalog.count(*), pg_catalog.min(dp.distributor_id) into v_n, v_dist
    from public.distributor_profiles dp
    join public.profiles pr on pr.id = dp.user_id
   where dp.user_id = p_uid
     and pr.role = 'supplier'
     and dp.verification_status = 'verified'
     and dp.distributor_id is not null;
  if v_n > 1 then
    raise exception 'Hay más de un perfil de distribuidor para esta cuenta.'
      using errcode = '55000', hint = 'multiple_distributor_profiles';
  end if;
  return v_dist;
end;
$$;

comment on function mobau_private.resolve_verified_distributor(uuid) is
  '41-03a: empresa verificada de una cuenta (verified + distributor_id + supplier). Sin EXECUTE de cliente.';
revoke all on function mobau_private.resolve_verified_distributor(uuid) from public, anon, authenticated, service_role;

-- ---------- 2. my_verified_distributor_id() versionada, delegando ----------
-- create or replace conserva propietario y ACL.
create or replace function public.my_verified_distributor_id()
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select mobau_private.resolve_verified_distributor((select auth.uid()));
$$;

-- ---------- 3. validación final ----------
DO $$
declare
  f_my constant regprocedure := 'public.my_verified_distributor_id()'::regprocedure;
  f_rs constant regprocedure := 'mobau_private.resolve_verified_distributor(uuid)'::regprocedure;
begin
  if (select md5(prosrc) from pg_proc where oid = f_my) is distinct from 'c4c85af9dc9fde6d93f9fb25a56d1b87'
     or not (select prosecdef from pg_proc where oid = f_my)
     or (select provolatile from pg_proc where oid = f_my) <> 's'
     or not (select proconfig @> array['search_path=""'] from pg_proc where oid = f_my)
     or (select proowner from pg_proc where oid = f_my) <> 'postgres'::regrole
     or (select pronargs from pg_proc where oid = f_my) <> 0
     or (select prorettype from pg_proc where oid = f_my) <> 'text'::regtype then
    raise exception '41-03a: my_verified_distributor_id() con definición inesperada';
  end if;
  if coalesce((select proacl::text from pg_proc where oid = f_my), '-') is distinct from current_setting('mobau.v3_acl_my_verified') then
    raise exception '41-03a: la ACL de my_verified_distributor_id() cambió';
  end if;
  if (select md5(prosrc) from pg_proc where oid = f_rs) is distinct from '1982b668e9cfb08bbf4b376cb0e29e3b'
     or (select prosecdef from pg_proc where oid = f_rs)
     or (select provolatile from pg_proc where oid = f_rs) <> 's'
     or not (select proconfig @> array['search_path=""'] from pg_proc where oid = f_rs)
     or (select proowner from pg_proc where oid = f_rs) <> 'postgres'::regrole
     or has_function_privilege('anon', f_rs, 'EXECUTE') or has_function_privilege('authenticated', f_rs, 'EXECUTE')
     or has_function_privilege('service_role', f_rs, 'EXECUTE')
     or exists (select 1 from pg_proc, aclexplode(proacl) a where oid = f_rs and a.grantee <> 'postgres'::regrole) then
    raise exception '41-03a: resolve_verified_distributor con definición o permisos inesperados';
  end if;
  -- Para TODAS las cuentas (profiles y distributor_profiles): regla nueva = regla anterior
  -- (la puerta B3 garantiza que no hay verificados no supplier).
  if exists (select 1
               from (select p.id as uid from public.profiles p union select dp.user_id from public.distributor_profiles dp) u
              where mobau_private.resolve_verified_distributor(u.uid)
                    is distinct from (select dp.distributor_id from public.distributor_profiles dp
                                       where dp.user_id = u.uid and dp.verification_status = 'verified'
                                         and dp.distributor_id is not null)) then
    raise exception '41-03a: la regla nueva no coincide con la anterior para alguna cuenta';
  end if;
  if (select count(*) from pg_proc where pronamespace = 'mobau_private'::regnamespace) <> 2 then
    raise exception '41-03a: mobau_private debe tener 2 funciones';
  end if;
  if has_schema_privilege('anon', 'mobau_private', 'USAGE') or has_schema_privilege('authenticated', 'mobau_private', 'USAGE')
     or has_schema_privilege('service_role', 'mobau_private', 'USAGE') then
    raise exception '41-03a: mobau_private accesible para un rol cliente';
  end if;
  if (select count(*) from pg_policies where schemaname = 'public') <> 48 then
    raise exception '41-03a: ha cambiado el número de políticas';
  end if;
  raise notice '41-03a OK: regla única de distribuidor verificado (supplier); my_verified_distributor_id() versionada.';
end $$;

COMMIT;
