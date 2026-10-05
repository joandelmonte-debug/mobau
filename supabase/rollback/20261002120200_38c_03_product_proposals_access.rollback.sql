-- ============================================================
-- PROPUESTA NO EJECUTADA (38-C) — no ejecutar sin aprobación explícita
-- ============================================================
-- 38-C · 03 · ROLLBACK · Cierra de nuevo las tablas de propuestas
-- ------------------------------------------------------------
-- Elimina las 4 políticas de 38-C 03 y retira todos los permisos de
-- anon y authenticated sobre product_proposals y proposal_events
-- (revocar el permiso de tabla retira también los de columna). Las tablas
-- quedan como tras 38-C 02: RLS activada, sin políticas, sin acceso de
-- cliente. No borra ninguna fila ni toca triggers, funciones ni otras
-- tablas. Ejecutar completo (BEGIN … COMMIT).
-- ============================================================

BEGIN;

DO $$
begin
  if to_regclass('public.product_proposals') is null or to_regclass('public.proposal_events') is null then
    raise exception '38-C 03 rollback: faltan las tablas de propuestas';
  end if;
  if (select count(*) from pg_policies
       where schemaname = 'public'
         and policyname in ('product_proposals_select_own', 'product_proposals_insert_own',
                            'product_proposals_update_own', 'proposal_events_select_own')) <> 4 then
    raise exception '38-C 03 rollback: no están las 4 políticas de 38-C 03';
  end if;
end $$;

drop policy proposal_events_select_own on public.proposal_events;
drop policy product_proposals_update_own on public.product_proposals;
drop policy product_proposals_insert_own on public.product_proposals;
drop policy product_proposals_select_own on public.product_proposals;

revoke all on table public.product_proposals from public, anon, authenticated;
revoke all on table public.proposal_events from public, anon, authenticated;

DO $$
declare
  r text;
  t text;
begin
  if exists (select 1 from pg_policies where schemaname = 'public' and tablename in ('product_proposals', 'proposal_events')) then
    raise exception '38-C 03 rollback: quedan políticas sobre las tablas de propuestas';
  end if;
  foreach t in array array['public.product_proposals', 'public.proposal_events'] loop
    foreach r in array array['anon', 'authenticated'] loop
      if has_table_privilege(r, t, 'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER')
         or has_any_column_privilege(r, t, 'SELECT,INSERT,UPDATE,REFERENCES') then
        raise exception '38-C 03 rollback: % conserva permisos sobre %', r, t;
      end if;
    end loop;
  end loop;
  if (select count(*) from pg_policies where schemaname = 'public') <> 40 then
    raise exception '38-C 03 rollback: se esperaban 40 políticas en public';
  end if;
  raise notice '38-C 03 rollback OK: tablas cerradas de nuevo; triggers, funciones y datos intactos.';
end $$;

COMMIT;
