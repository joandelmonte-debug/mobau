-- ============================================================
-- PROPUESTA NO EJECUTADA (46-05 · retira el índice único antiguo de líneas) — no ejecutar sin aprobación explícita
-- ============================================================
-- Punto 46 · bloque 3, segundo paso. Solo después de que la web compatible
-- (búsqueda de la línea por producto + acabado + configuración) esté
-- publicada en Production: con la web anterior, quitar este índice podría
-- dejar que una línea sin configuración se guardara junto a otra
-- configurada sin encontrarla.
--   * Quita project_products_line_unique (proyecto + producto + acabado).
--   * Queda project_products_config_line_unique (+ config_key, de 46-04):
--     el mismo producto y acabado admite configuraciones distintas; sin
--     configuración sigue siendo una sola línea.
-- Si se aplica, se registra como migración NUEVA tras confirmar su COMMIT.
-- Ejecutar completo.
-- ============================================================

BEGIN;

DO $$
begin
  if current_user <> 'postgres' then
    raise exception '46-05: ejecutar como postgres';
  end if;
  if not exists (select 1 from supabase_migrations.schema_migrations where version = '20261101120000')
     or exists (select 1 from supabase_migrations.schema_migrations where version = '20261101130000') then
    raise exception '46-05: el registro de migraciones no es el esperado (46-04 registrada y 46-05 sin registrar)';
  end if;
  if (select indexdef from pg_indexes where schemaname = 'public' and indexname = 'project_products_line_unique')
       is distinct from 'CREATE UNIQUE INDEX project_products_line_unique ON public.project_products USING btree (project_id, product_id, COALESCE(finish_code, ''''::text))' then
    raise exception '46-05: el índice antiguo no es el esperado';
  end if;
  if (select indexdef from pg_indexes where schemaname = 'public' and indexname = 'project_products_config_line_unique')
       is distinct from 'CREATE UNIQUE INDEX project_products_config_line_unique ON public.project_products USING btree (project_id, product_id, COALESCE(finish_code, ''''::text), config_key)' then
    raise exception '46-05: falta el índice de 46-04';
  end if;
end $$;

drop index public.project_products_line_unique;

DO $$
begin
  if exists (select 1 from pg_indexes where schemaname = 'public' and indexname = 'project_products_line_unique')
     or not exists (select 1 from pg_indexes where schemaname = 'public' and indexname = 'project_products_config_line_unique') then
    raise exception '46-05: los índices no quedaron como se esperaba';
  end if;
end $$;

COMMIT;
