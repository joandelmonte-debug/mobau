-- ============================================================
-- PROPUESTA NO EJECUTADA (46-06 · protección servidor de la nota técnica de línea) — no ejecutar sin aprobación explícita
-- ============================================================
-- Punto 46 · nota técnica de línea (project_products.notes, texto libre opcional del profesional).
-- Hasta ahora «solo lectura en proyectos archivados» y el límite de 1000 caracteres eran solo de interfaz.
--   * Trigger BEFORE UPDATE OF notes en project_products (función nueva, sin tocar políticas ni otros triggers):
--       - rechaza cambiar notes si el proyecto de la línea está archivado (42501, hint line_note_archived);
--       - rechaza un valor NUEVO de más de 1000 caracteres (23514, hint line_note_too_long).
--   * Solo actúa cuando notes CAMBIA: las notas existentes no se truncan ni se borran, y actualizar otras columnas
--     (cantidad, unidad…) de una línea con una nota antigua más larga sigue funcionando.
--   * No afecta a insert, delete, quantity ni al envío de solicitudes (no escriben notes).
-- Si se aplica, se registra como migración NUEVA tras confirmar su COMMIT.
-- Ejecutar completo.
-- ============================================================

BEGIN;

DO $$
declare
  v_prev int := 1;
  v_self int := 0;
begin
  if current_user <> 'postgres' then
    raise exception '46-06: ejecutar como postgres';
  end if;
  -- El registro de migraciones solo existe en Production; en un entorno sin él no hay nada que comprobar.
  if to_regclass('supabase_migrations.schema_migrations') is not null then
    execute $q$select count(*) filter (where version = '20261101130000'), count(*) filter (where version = '20261101140000')
               from supabase_migrations.schema_migrations$q$ into v_prev, v_self;
    if v_prev <> 1 or v_self <> 0 then
      raise exception '46-06: el registro de migraciones no es el esperado (46-05 registrada y 46-06 sin registrar)';
    end if;
  end if;
  if not exists (select 1 from pg_attribute where attrelid = 'public.project_products'::regclass and attname = 'notes' and not attisdropped)
     or exists (select 1 from pg_trigger where tgrelid = 'public.project_products'::regclass and tgname = 'trg_project_products_20_note')
     or to_regprocedure('public.project_products_note_guard()') is not null then
    raise exception '46-06: el estado de partida no es el esperado';
  end if;
end $$;

create function public.project_products_note_guard() returns trigger
  language plpgsql set search_path = '' as $$
declare
  v_status text;
begin
  if new.notes is not distinct from old.notes then
    return new;
  end if;
  select p.status into v_status from public.projects p where p.id = new.project_id;
  if v_status = 'archived' then
    raise exception 'La nota de una línea de un proyecto archivado no se puede modificar.'
      using errcode = '42501', hint = 'line_note_archived';
  end if;
  if new.notes is not null and pg_catalog.char_length(new.notes) > 1000 then
    raise exception 'La nota técnica admite como máximo 1000 caracteres.'
      using errcode = '23514', hint = 'line_note_too_long';
  end if;
  return new;
end $$;

revoke all on function public.project_products_note_guard() from public, anon, authenticated;

create trigger trg_project_products_20_note
  before update of notes on public.project_products
  for each row execute function public.project_products_note_guard();

DO $$
begin
  if not exists (select 1 from pg_trigger where tgrelid = 'public.project_products'::regclass and tgname = 'trg_project_products_20_note' and not tgisinternal)
     or to_regprocedure('public.project_products_note_guard()') is null then
    raise exception '46-06: el trigger no quedó como se esperaba';
  end if;
end $$;

COMMIT;
