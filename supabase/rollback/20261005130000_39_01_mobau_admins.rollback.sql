-- ============================================================
-- PROPUESTA NO EJECUTADA (39) — no ejecutar sin aprobación explícita
-- ============================================================
-- 39 · 01 · ROLLBACK · Quita la autorización de administración
-- ------------------------------------------------------------
-- Se niega si 39-02, 39-03 o 39-04 siguen aplicadas (dependen de estas
-- funciones). Borra mobau_admins: si tiene filas, se pierde el registro de
-- altas y bajas, así que también se niega si no está vacía. Borra
-- mobau_moderation_context (siempre vacía fuera de una decisión).
-- Ejecutar completo (BEGIN … COMMIT).
-- ============================================================

BEGIN;

DO $$
begin
  if to_regclass('public.mobau_admins') is null then
    raise exception '39-01 rollback: 39-01 no está aplicada';
  end if;
  if exists (select 1 from pg_policies where schemaname = 'public'
              and policyname in ('product_proposals_select_mobau', 'proposal_events_select_mobau', 'products_select_mobau')) then
    raise exception '39-01 rollback: 39-02 sigue aplicada (revertir 39-02 antes)';
  end if;
  if to_regprocedure('public.moderate_product_proposal(uuid, text, text, integer)') is not null then
    raise exception '39-01 rollback: 39-04 sigue aplicada (revertir 39-04 antes)';
  end if;
  if exists (select 1 from pg_proc where pronamespace = 'public'::regnamespace
              and proname in ('transition_proposal_status', 'validate_proposal_changes', 'log_proposal_event', 'products_before_insert')
              and (prosrc like '%mobau_moderating%' or prosrc like '%is_mobau_admin%'
                   or prosrc like '%mobau_moderation_%')) then
    raise exception '39-01 rollback: 39-03 sigue aplicada (revertir 39-03 antes)';
  end if;
  if (select count(*) from public.mobau_admins) <> 0 then
    raise exception '39-01 rollback: mobau_admins tiene filas; conservar el registro o vaciarlo con autorización explícita';
  end if;
end $$;

drop function public.mobau_moderating(uuid);
drop function public.mobau_moderation_proposal_id();
drop function public.mobau_admin_session();
drop function public.is_mobau_admin();
drop table public.mobau_moderation_context;
drop table public.mobau_admins;

DO $$
begin
  if to_regclass('public.mobau_admins') is not null
     or to_regclass('public.mobau_moderation_context') is not null
     or to_regprocedure('public.is_mobau_admin()') is not null
     or to_regprocedure('public.mobau_moderation_proposal_id()') is not null then
    raise exception '39-01 rollback: quedan objetos de 39-01';
  end if;
  if (select count(*) from pg_policies where schemaname = 'public') <> 44 then
    raise exception '39-01 rollback: se esperaban 44 políticas';
  end if;
  raise notice '39-01 rollback OK.';
end $$;

COMMIT;
