-- ============================================================
-- PROPUESTA NO EJECUTADA (recuperación de 46-03) — no ejecutar sin aprobación explícita
-- ============================================================
-- Deshace 46-03 SOLO si ninguna propuesta usa proposed_components (si no,
-- se perdería) y si transition_proposal_status es exactamente la de 46-03.
--   * Quita los triggers 36, 41 y 61 y sus funciones; devuelve la
--     transición a su texto anterior (MD5 3eef0e1a…); elimina la columna.
--   * No toca lo ya aplicado en las tablas de 46-01 (grupos y opciones de
--     propuestas aprobadas) ni las copias históricas (product_snapshot).
-- Sin CASCADE. Si se aplica, se registra como migración NUEVA tras confirmar su COMMIT.
-- Ejecutar completo.
-- ============================================================

BEGIN;

create function pg_temp.r4603b(t text, a text, b text) returns text language plpgsql as $$
begin
  if (length(t) - length(replace(t, a, ''))) <> length(a) then
    raise exception 'recuperación 46-03: el fragmento no aparece exactamente una vez: %', left(a, 80);
  end if;
  return replace(t, a, b);
end $$;

DO $$
begin
  if current_user <> 'postgres' then
    raise exception 'recuperación 46-03: ejecutar como postgres';
  end if;
  if not exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'product_proposals' and column_name = 'proposed_components') then
    raise exception 'recuperación 46-03: no existe proposed_components; no se toca nada';
  end if;
  if exists (select 1 from public.product_proposals where proposed_components is not null) then
    raise exception 'recuperación 46-03: hay propuestas con componentes que se perderían; no se toca nada';
  end if;
  if (select md5(prosrc) from pg_proc where oid = 'public.transition_proposal_status()'::regprocedure) <> '96691e0bf640fdf97992255d09b191d2' then
    raise exception 'recuperación 46-03: transition_proposal_status no es la de 46-03; no se toca nada';
  end if;
  if exists (select 1 from pg_depend d join pg_rewrite r on r.oid = d.objid
               join pg_attribute a on a.attrelid = d.refobjid and a.attnum = d.refobjsubid
              where d.refobjid = 'public.product_proposals'::regclass and a.attname = 'proposed_components') then
    raise exception 'recuperación 46-03: hay vistas que usan proposed_components; no se toca nada';
  end if;
end $$;

drop trigger trg_product_proposals_61_components_apply on public.product_proposals;
drop trigger trg_product_proposals_41_components_snapshot on public.product_proposals;
drop trigger trg_product_proposals_36_components on public.product_proposals;

DO $$
declare
  d text;
begin
  d := pg_get_functiondef('public.transition_proposal_status()'::regprocedure);
  d := pg_temp.r4603b(d, $a$or new.proposed_media is distinct from old.proposed_media
       or new.proposed_components is distinct from old.proposed_components then$a$,
                         $a$or new.proposed_media is distinct from old.proposed_media then$a$);
  d := pg_temp.r4603b(d, $a$and new.proposed_price_status is null and new.proposed_media is null
     and new.proposed_components is null then$a$,
                         $a$and new.proposed_price_status is null and new.proposed_media is null then$a$);
  execute d;
end $$;

drop function public.apply_proposal_components();
drop function public.snapshot_proposal_components();
drop function public.validate_proposal_components();
drop function mobau_private.component_manifest_graph_violations(text, jsonb, text);
drop function mobau_private.component_manifest_normalized(jsonb);
drop function mobau_private.component_structure_of(text);
revoke insert (proposed_components), update (proposed_components) on public.product_proposals from authenticated;
alter table public.product_proposals drop column proposed_components;

DO $$
begin
  if (select md5(prosrc) from pg_proc where oid = 'public.transition_proposal_status()'::regprocedure) <> '3eef0e1ad9a754c54fcc1ac536301b53'
     or exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'product_proposals' and column_name = 'proposed_components')
     or exists (select 1 from pg_trigger where tgrelid = 'public.product_proposals'::regclass and tgname like 'trg_product_proposals_%components%') then
    raise exception 'recuperación 46-03: el estado final no es el esperado';
  end if;
end $$;

COMMIT;
