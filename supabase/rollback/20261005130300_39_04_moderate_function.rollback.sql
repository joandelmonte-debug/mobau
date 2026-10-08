-- ============================================================
-- PROPUESTA NO EJECUTADA (39) — no ejecutar sin aprobación explícita
-- ============================================================
-- 39 · 04 · ROLLBACK · Quita la función de decisión
-- ------------------------------------------------------------
-- Quita moderate_product_proposal. No deshace decisiones ya tomadas: las
-- propuestas, productos, precios, subcategorías y eventos quedan como
-- están. Se niega si hay decisiones de Mobau registradas, para no dejar
-- datos aplicados sin la función que los explica; en ese caso, revertir
-- requiere una decisión explícita. Ejecutar completo.
-- ============================================================

BEGIN;

DO $$
begin
  if to_regprocedure('public.moderate_product_proposal(uuid, text, text, integer)') is null then
    raise exception '39-04 rollback: 39-04 no está aplicada';
  end if;
  if exists (select 1 from public.product_proposals where status in ('approved', 'rejected', 'changes_requested') and reviewed_by is not null)
     or exists (select 1 from public.proposal_events where actor_kind = 'mobau' and actor_id is not null) then
    raise exception '39-04 rollback: ya hay decisiones de Mobau registradas; revertir requiere decisión explícita';
  end if;
end $$;

drop function public.moderate_product_proposal(uuid, text, text, integer);

DO $$
begin
  if to_regprocedure('public.moderate_product_proposal(uuid, text, text, integer)') is not null then
    raise exception '39-04 rollback: la función sigue existiendo';
  end if;
  raise notice '39-04 rollback OK.';
end $$;

COMMIT;
