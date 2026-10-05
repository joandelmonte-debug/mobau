-- ============================================================
-- PROPUESTA NO EJECUTADA (38-C) — no ejecutar sin aprobación explícita
-- ============================================================
-- 38-C · 01 · ROLLBACK · Elimina product_proposals y proposal_events
-- ------------------------------------------------------------
-- Orden: revertir antes 38-C 03 (políticas/permisos) y 38-C 02
-- (funciones/triggers). Este rollback se niega a continuar si:
--   * quedan políticas o triggers propios de 38-C sobre estas tablas;
--   * hay alguna fila en cualquiera de las dos tablas (son evidencia:
--     exportarlas antes y decidir aparte; este script nunca borra datos).
-- No toca ninguna otra tabla. Ejecutar completo (BEGIN … COMMIT).
-- ============================================================

BEGIN;

DO $$
begin
  if to_regclass('public.product_proposals') is null or to_regclass('public.proposal_events') is null then
    raise exception '38-C 01 rollback: alguna de las tablas no existe; no hay nada coherente que revertir';
  end if;
  if exists (select 1 from pg_policies
              where schemaname = 'public' and tablename in ('product_proposals', 'proposal_events')) then
    raise exception '38-C 01 rollback: quedan políticas; revertir antes 38-C 03';
  end if;
  if exists (select 1 from pg_trigger
              where not tgisinternal
                and tgrelid in ('public.product_proposals'::regclass, 'public.proposal_events'::regclass)) then
    raise exception '38-C 01 rollback: quedan triggers; revertir antes 38-C 02';
  end if;
  if exists (select 1 from public.product_proposals) or exists (select 1 from public.proposal_events) then
    raise exception '38-C 01 rollback: las tablas tienen filas; exportarlas y decidir aparte (no se borran datos)';
  end if;
end $$;

drop table public.proposal_events;
drop table public.product_proposals;

DO $$
begin
  if to_regclass('public.product_proposals') is not null or to_regclass('public.proposal_events') is not null then
    raise exception '38-C 01 rollback: las tablas siguen existiendo';
  end if;
  if (select count(*) from pg_policies where schemaname = 'public') <> 40 then
    raise exception '38-C 01 rollback: el número de políticas de public no es 40';
  end if;
  raise notice '38-C 01 rollback OK: tablas eliminadas; ninguna otra tabla tocada.';
end $$;

COMMIT;
