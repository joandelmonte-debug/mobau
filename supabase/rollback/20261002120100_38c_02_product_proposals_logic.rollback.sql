-- ============================================================
-- PROPUESTA NO EJECUTADA (38-C) — no ejecutar sin aprobación explícita
-- ============================================================
-- 38-C · 02 · ROLLBACK · Elimina los triggers y funciones de propuestas
-- ------------------------------------------------------------
-- Orden: revertir antes 38-C 03. Si quedaran políticas que dan acceso de
-- cliente, quitar los triggers dejaría las tablas abiertas sin validación,
-- así que este rollback se niega a continuar en ese caso.
-- No borra ninguna fila ni toca las tablas (eso es el rollback de 01) ni
-- la función compartida public.set_updated_at(). Ejecutar completo.
-- ============================================================

BEGIN;

DO $$
begin
  if to_regclass('public.product_proposals') is null then
    raise exception '38-C 02 rollback: no existe product_proposals';
  end if;
  if exists (select 1 from pg_policies where schemaname = 'public' and tablename in ('product_proposals', 'proposal_events')) then
    raise exception '38-C 02 rollback: quedan políticas sobre las tablas de propuestas; revertir antes 38-C 03';
  end if;
  if has_table_privilege('authenticated', 'public.product_proposals', 'INSERT,UPDATE,DELETE')
     or has_any_column_privilege('authenticated', 'public.product_proposals', 'INSERT,UPDATE') then
    raise exception '38-C 02 rollback: authenticated conserva permisos de escritura; revertir antes 38-C 03';
  end if;
end $$;

drop trigger trg_product_proposals_91_event_status on public.product_proposals;
drop trigger trg_product_proposals_90_event_insert on public.product_proposals;
drop trigger trg_product_proposals_50_updated_at on public.product_proposals;
drop trigger trg_product_proposals_40_snapshot on public.product_proposals;
drop trigger trg_product_proposals_30_validate on public.product_proposals;
drop trigger trg_product_proposals_20_transition on public.product_proposals;
drop trigger trg_product_proposals_10_author on public.product_proposals;

drop function public.log_proposal_event();
drop function public.snapshot_product_on_submit();
drop function public.transition_proposal_status();
drop function public.validate_proposal_changes();
drop function public.fix_proposal_author();

DO $$
begin
  if exists (select 1 from pg_trigger
              where not tgisinternal
                and tgrelid in ('public.product_proposals'::regclass, 'public.proposal_events'::regclass)) then
    raise exception '38-C 02 rollback: quedan triggers sobre las tablas de propuestas';
  end if;
  if exists (select 1 from pg_proc
              where pronamespace = 'public'::regnamespace
                and proname in ('fix_proposal_author', 'validate_proposal_changes', 'transition_proposal_status',
                                'snapshot_product_on_submit', 'log_proposal_event')) then
    raise exception '38-C 02 rollback: quedan funciones de 38-C 02';
  end if;
  if to_regprocedure('public.set_updated_at()') is null then
    raise exception '38-C 02 rollback: public.set_updated_at() ha desaparecido (no debía tocarse)';
  end if;
  raise notice '38-C 02 rollback OK: triggers y funciones eliminados; tablas y datos intactos.';
end $$;

COMMIT;
