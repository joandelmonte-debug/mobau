-- ============================================================
-- PROPUESTA NO EJECUTADA (recuperación de 46-06) — no ejecutar sin aprobación explícita
-- ============================================================
-- Quita el trigger y la función de 46-06. No toca datos: las notas existentes se conservan.
-- Si se aplica, se registra como migración NUEVA tras confirmar su COMMIT.
-- Ejecutar completo.
-- ============================================================

BEGIN;

DO $$
begin
  if current_user <> 'postgres' then
    raise exception 'recuperación 46-06: ejecutar como postgres';
  end if;
  if not exists (select 1 from pg_trigger where tgrelid = 'public.project_products'::regclass and tgname = 'trg_project_products_20_note') then
    raise exception 'recuperación 46-06: el trigger no existe; no se toca nada';
  end if;
end $$;

drop trigger trg_project_products_20_note on public.project_products;
drop function public.project_products_note_guard();

DO $$
begin
  if exists (select 1 from pg_trigger where tgrelid = 'public.project_products'::regclass and tgname = 'trg_project_products_20_note')
     or to_regprocedure('public.project_products_note_guard()') is not null then
    raise exception 'recuperación 46-06: no quedó como se esperaba';
  end if;
end $$;

COMMIT;
