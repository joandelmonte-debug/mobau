-- ============================================================
-- PROPUESTA NO EJECUTADA (rollback 41-05) — no ejecutar sin aprobación explícita
-- ============================================================
-- Deshace 41-05. Se niega si:
--   · el interruptor está encendido o alguna función tiene EXECUTE de cliente
--     (41-06 aplicada: revertirla antes);
--   · hay eventos de ciclo de vida de Mobau o alguna purga (la purga no se
--     deshace: se corrige hacia delante).
-- Quita las 4 funciones de entrada y los 2 auxiliares de 41-05.
-- ============================================================

BEGIN;

set local lock_timeout = '5s';

-- ---------- 0. prechecks ----------
DO $$
begin
  if current_user <> 'postgres' then
    raise exception 'rollback 41-05: ejecutar como postgres';
  end if;
  if to_regprocedure('public.mobau_product_lifecycle(text, text, text, timestamp with time zone)') is null
     or to_regprocedure('mobau_private.product_reference_counts(text)') is null then
    raise exception 'rollback 41-05: 41-05 no está instalada';
  end if;
  if mobau_private.product_lifecycle_enabled() then
    raise exception 'rollback 41-05: el interruptor está encendido (revertir 41-06 antes)';
  end if;
  if exists (select 1 from pg_proc p, aclexplode(p.proacl) a
              where p.oid in (to_regprocedure('public.mobau_product_lifecycle(text, text, text, timestamp with time zone)'),
                              to_regprocedure('public.mobau_purge_product(text, text, text, boolean, timestamp with time zone)'),
                              to_regprocedure('public.mobau_product_references(text)'),
                              to_regprocedure('public.mobau_product_lifecycle_view(text)'))
                and a.grantee <> 'postgres'::regrole) then
    raise exception 'rollback 41-05: alguna función tiene EXECUTE de cliente (revertir 41-06 antes)';
  end if;
  if exists (select 1 from mobau_private.product_lifecycle_events where actor_kind = 'mobau' or action = 'purge') then
    raise exception 'rollback 41-05: hay acciones o purgas de Mobau; no se revierte';
  end if;
end $$;

-- ---------- 1. funciones ----------
drop function public.mobau_product_lifecycle_view(text);
drop function public.mobau_product_references(text);
drop function public.mobau_purge_product(text, text, text, boolean, timestamptz);
drop function public.mobau_product_lifecycle(text, text, text, timestamptz);
drop function mobau_private.product_reference_counts(text);
drop function mobau_private.assert_mobau_admin();

-- ---------- 2. validación final ----------
DO $$
begin
  if to_regprocedure('public.mobau_product_lifecycle(text, text, text, timestamp with time zone)') is not null
     or to_regprocedure('public.mobau_purge_product(text, text, text, boolean, timestamp with time zone)') is not null
     or to_regprocedure('public.mobau_product_references(text)') is not null
     or to_regprocedure('public.mobau_product_lifecycle_view(text)') is not null
     or (select count(*) from pg_proc where pronamespace = 'mobau_private'::regnamespace) <> 7 then
    raise exception 'rollback 41-05: queda algún objeto de 41-05';
  end if;
  if (select count(*) from pg_policies where schemaname = 'public') <> 48 then
    raise exception 'rollback 41-05: ha cambiado el número de políticas';
  end if;
  raise notice 'rollback 41-05 OK: funciones de Mobau retiradas.';
end $$;

COMMIT;
