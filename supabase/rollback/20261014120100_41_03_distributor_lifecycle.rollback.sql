-- ============================================================
-- PROPUESTA NO EJECUTADA (rollback 41-03) — no ejecutar sin aprobación explícita
-- ============================================================
-- Deshace 41-03. Se niega si:
--   · 41-04 o 41-05 siguen instaladas (revertirlas antes);
--   · el interruptor está encendido o alguna función tiene EXECUTE de cliente
--     (41-06 aplicada: revertirla antes);
--   · hay eventos de ciclo de vida o productos con datos de retirada/papelera
--     (hubo uso real: no se revierte; se corrige hacia delante).
-- Quita las 5 funciones de entrada, los 4 auxiliares y el interruptor.
-- ============================================================

BEGIN;

set local lock_timeout = '5s';

-- ---------- 0. prechecks ----------
DO $$
begin
  if current_user <> 'postgres' then
    raise exception 'rollback 41-03: ejecutar como postgres';
  end if;
  if to_regprocedure('mobau_private.product_proposals_lifecycle_gate()') is not null
     or to_regprocedure('public.mobau_product_lifecycle(text, text, text, timestamp with time zone)') is not null then
    raise exception 'rollback 41-03: 41-04 o 41-05 siguen instaladas; revertirlas antes';
  end if;
  if to_regclass('mobau_private.product_lifecycle_settings') is null then
    raise exception 'rollback 41-03: 41-03 no está instalada';
  end if;
  if mobau_private.product_lifecycle_enabled() then
    raise exception 'rollback 41-03: el interruptor está encendido (revertir 41-06 antes)';
  end if;
  if exists (select 1 from pg_proc p, aclexplode(p.proacl) a
              where p.oid in (to_regprocedure('public.my_products_lifecycle()'), to_regprocedure('public.my_product_lifecycle_events(text)'),
                              to_regprocedure('public.distributor_retire_product(text, text, timestamp with time zone)'),
                              to_regprocedure('public.distributor_trash_product(text, timestamp with time zone)'),
                              to_regprocedure('public.distributor_restore_product(text, timestamp with time zone)'))
                and a.grantee <> 'postgres'::regrole) then
    raise exception 'rollback 41-03: alguna función tiene EXECUTE de cliente (revertir 41-06 antes)';
  end if;
  if exists (select 1 from mobau_private.product_lifecycle_events) then
    raise exception 'rollback 41-03: hay eventos de ciclo de vida; no se revierte';
  end if;
  if exists (select 1 from public.products
              where retired_at is not null or trashed_at is not null or retired_by is not null or trashed_by is not null) then
    raise exception 'rollback 41-03: hay productos retirados o en papelera; no se revierte';
  end if;
end $$;

-- ---------- 1. funciones de entrada ----------
drop function public.distributor_restore_product(text, timestamptz);
drop function public.distributor_trash_product(text, timestamptz);
drop function public.distributor_retire_product(text, text, timestamptz);
drop function public.my_product_lifecycle_events(text);
drop function public.my_products_lifecycle();

-- ---------- 2. auxiliares ----------
drop function mobau_private.log_lifecycle_event(text, text, text, text, text, uuid, text, text, jsonb, text, jsonb);
drop function mobau_private.product_allowed_actions(text, boolean, timestamptz, text);
drop function mobau_private.product_has_open_proposal(text);
drop function mobau_private.product_lifecycle_enabled();

-- ---------- 3. interruptor ----------
drop table mobau_private.product_lifecycle_settings;

-- ---------- 4. validación final ----------
DO $$
begin
  if to_regclass('mobau_private.product_lifecycle_settings') is not null
     or to_regprocedure('public.my_products_lifecycle()') is not null
     or to_regprocedure('public.my_product_lifecycle_events(text)') is not null
     or to_regprocedure('public.distributor_retire_product(text, text, timestamp with time zone)') is not null
     or to_regprocedure('public.distributor_trash_product(text, timestamp with time zone)') is not null
     or to_regprocedure('public.distributor_restore_product(text, timestamp with time zone)') is not null then
    raise exception 'rollback 41-03: queda algún objeto de 41-03';
  end if;
  if (select count(*) from pg_proc where pronamespace = 'mobau_private'::regnamespace) <> 2
     or to_regprocedure('mobau_private.resolve_verified_distributor(uuid)') is null
     or (select count(*) from pg_class where relnamespace = 'mobau_private'::regnamespace and relkind = 'r') <> 1 then
    raise exception 'rollback 41-03: mobau_private debe quedar como tras 41-03a (2 funciones, 1 tabla)';
  end if;
  if (select count(*) from pg_policies where schemaname = 'public') <> 48 then
    raise exception 'rollback 41-03: ha cambiado el número de políticas';
  end if;
  raise notice 'rollback 41-03 OK: interruptor, auxiliares y funciones del distribuidor retirados.';
end $$;

COMMIT;
