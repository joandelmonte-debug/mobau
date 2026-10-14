-- ============================================================
-- PROPUESTA NO EJECUTADA (rollback 41-03a) — no ejecutar sin aprobación explícita
-- ============================================================
-- Deshace 41-03a. Requiere que 41-03 esté revertida (sus funciones usan el
-- auxiliar). No depende de datos: siempre se puede ejecutar.
--   0. Prechecks: 41-03 ausente; definiciones de 41-03a exactas.
--   1. public.my_verified_distributor_id() vuelve EXACTAMENTE a la definición
--      anterior: md5(pg_get_functiondef) = 845179d0ebf4a7b2708bb4638b41355b,
--      md5(prosrc) = 05e1a9337e95b699fc22351e443376ec. Misma ACL.
--   2. Quita mobau_private.resolve_verified_distributor(uuid).
--   3. Validación final.
-- ============================================================

BEGIN;

set local lock_timeout = '5s';

-- ---------- 0. prechecks ----------
DO $$
declare
  f_my constant regprocedure := 'public.my_verified_distributor_id()'::regprocedure;
begin
  if current_user <> 'postgres' then
    raise exception 'rollback 41-03a: ejecutar como postgres';
  end if;
  if to_regclass('mobau_private.product_lifecycle_settings') is not null
     or to_regprocedure('public.my_products_lifecycle()') is not null
     or to_regprocedure('public.distributor_retire_product(text, text, timestamp with time zone)') is not null then
    raise exception 'rollback 41-03a: 41-03 sigue instalada; revertirla antes';
  end if;
  if to_regprocedure('mobau_private.resolve_verified_distributor(uuid)') is null
     or (select md5(prosrc) from pg_proc where oid = to_regprocedure('mobau_private.resolve_verified_distributor(uuid)'))
        is distinct from '1982b668e9cfb08bbf4b376cb0e29e3b'
     or (select md5(prosrc) from pg_proc where oid = f_my)
        is distinct from 'c4c85af9dc9fde6d93f9fb25a56d1b87' then
    raise exception 'rollback 41-03a: el estado no es el que deja 41-03a';
  end if;
  perform set_config('mobau.v3_acl_my_verified', coalesce((select proacl::text from pg_proc where oid = f_my), '-'), true);
end $$;

-- ---------- 1. definición anterior exacta ----------
create or replace function public.my_verified_distributor_id()
 returns text
 language sql
 stable security definer
 set search_path to ''
as $function$
  select dp.distributor_id from public.distributor_profiles dp
  where dp.user_id = (select auth.uid())
    and dp.verification_status = 'verified' and dp.distributor_id is not null;
$function$;

-- ---------- 2. sin auxiliar ----------
drop function mobau_private.resolve_verified_distributor(uuid);

-- ---------- 3. validación final ----------
DO $$
declare
  f_my constant regprocedure := 'public.my_verified_distributor_id()'::regprocedure;
begin
  if md5(pg_get_functiondef(f_my)) is distinct from '845179d0ebf4a7b2708bb4638b41355b'
     or (select md5(prosrc) from pg_proc where oid = f_my) is distinct from '05e1a9337e95b699fc22351e443376ec' then
    raise exception 'rollback 41-03a: my_verified_distributor_id() no volvió a la definición anterior';
  end if;
  if coalesce((select proacl::text from pg_proc where oid = f_my), '-') is distinct from current_setting('mobau.v3_acl_my_verified') then
    raise exception 'rollback 41-03a: la ACL de my_verified_distributor_id() cambió';
  end if;
  if to_regprocedure('mobau_private.resolve_verified_distributor(uuid)') is not null
     or (select count(*) from pg_proc where pronamespace = 'mobau_private'::regnamespace) <> 1 then
    raise exception 'rollback 41-03a: mobau_private debe volver a tener solo la función de 41-01';
  end if;
  if (select count(*) from pg_policies where schemaname = 'public') <> 48 then
    raise exception 'rollback 41-03a: ha cambiado el número de políticas';
  end if;
  raise notice 'rollback 41-03a OK: my_verified_distributor_id() restaurada (845179d0…); auxiliar retirado.';
end $$;

COMMIT;
