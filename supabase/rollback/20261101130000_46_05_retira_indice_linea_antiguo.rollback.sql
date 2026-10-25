-- ============================================================
-- PROPUESTA NO EJECUTADA (recuperación de 46-05) — no ejecutar sin aprobación explícita
-- ============================================================
-- Vuelve a crear el índice único antiguo (proyecto + producto + acabado)
-- SOLO si no hay dos líneas del mismo producto y acabado en un proyecto
-- (si las hay, se detiene: no borra ni fusiona líneas).
-- Si se aplica, se registra como migración NUEVA tras confirmar su COMMIT.
-- Ejecutar completo.
-- ============================================================

BEGIN;

DO $$
begin
  if current_user <> 'postgres' then
    raise exception 'recuperación 46-05: ejecutar como postgres';
  end if;
  if exists (select 1 from pg_indexes where schemaname = 'public' and indexname = 'project_products_line_unique') then
    raise exception 'recuperación 46-05: el índice antiguo ya existe; no se toca nada';
  end if;
  if exists (select 1 from public.project_products
              group by project_id, product_id, coalesce(finish_code, '') having count(*) > 1) then
    raise exception 'recuperación 46-05: hay líneas con configuraciones distintas del mismo producto y acabado; no se toca nada';
  end if;
end $$;

create unique index project_products_line_unique
  on public.project_products (project_id, product_id, coalesce(finish_code, ''));

DO $$
begin
  if (select indexdef from pg_indexes where schemaname = 'public' and indexname = 'project_products_line_unique')
       is distinct from 'CREATE UNIQUE INDEX project_products_line_unique ON public.project_products USING btree (project_id, product_id, COALESCE(finish_code, ''''::text))' then
    raise exception 'recuperación 46-05: el índice no quedó como se esperaba';
  end if;
end $$;

COMMIT;
