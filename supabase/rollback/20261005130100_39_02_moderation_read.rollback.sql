-- ============================================================
-- PROPUESTA NO EJECUTADA (39) — no ejecutar sin aprobación explícita
-- ============================================================
-- 39 · 02 · ROLLBACK · Quita la lectura de la consola de moderación
-- ------------------------------------------------------------
-- Quita las 3 políticas (47 → 44). Se niega si 39-04 sigue aplicada (la
-- consola dejaría de poder leer lo que modera). Ejecutar completo.
-- ============================================================

BEGIN;

DO $$
begin
  if to_regprocedure('public.moderate_product_proposal(uuid, text, text, integer)') is not null then
    raise exception '39-02 rollback: 39-04 sigue aplicada (revertir 39-04 antes)';
  end if;
  if (select count(*) from pg_policies where schemaname = 'public'
       and policyname in ('product_proposals_select_mobau', 'proposal_events_select_mobau', 'products_select_mobau')) <> 3 then
    raise exception '39-02 rollback: no están las 3 políticas de 39-02';
  end if;
end $$;

drop policy products_select_mobau on public.products;
drop policy proposal_events_select_mobau on public.proposal_events;
drop policy product_proposals_select_mobau on public.product_proposals;

DO $$
begin
  if (select count(*) from pg_policies where schemaname = 'public') <> 44 then
    raise exception '39-02 rollback: se esperaban 44 políticas';
  end if;
  raise notice '39-02 rollback OK (44 políticas).';
end $$;

COMMIT;
