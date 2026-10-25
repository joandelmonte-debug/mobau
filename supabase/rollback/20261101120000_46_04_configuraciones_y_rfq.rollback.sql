-- ============================================================
-- PROPUESTA NO EJECUTADA (recuperación de 46-04) — no ejecutar sin aprobación explícita
-- ============================================================
-- Deshace 46-04 SOLO si:
--   * el índice antiguo existe (46-05 sin aplicar o ya recuperada), y
--   * ninguna línea tiene configuración (si no, se perderían elecciones), y
--   * ninguna RFQ tiene copia (si no, se perdería lo solicitado).
-- Devuelve product_reference_counts a su texto anterior (MD5 69f5ee71…).
-- Sin CASCADE. Si se aplica, se registra como migración NUEVA tras confirmar su COMMIT.
-- Ejecutar completo.
-- ============================================================

BEGIN;

create function pg_temp.r4604b(t text, a text, b text) returns text language plpgsql as $$
begin
  if (length(t) - length(replace(t, a, ''))) <> length(a) then
    raise exception 'recuperación 46-04: el fragmento no aparece exactamente una vez: %', left(a, 80);
  end if;
  return replace(t, a, b);
end $$;

DO $$
begin
  if current_user <> 'postgres' then
    raise exception 'recuperación 46-04: ejecutar como postgres';
  end if;
  if not exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'project_products' and column_name = 'configuration') then
    raise exception 'recuperación 46-04: no existe project_products.configuration; no se toca nada';
  end if;
  if not exists (select 1 from pg_indexes where schemaname = 'public' and indexname = 'project_products_line_unique') then
    raise exception 'recuperación 46-04: falta el índice antiguo (recupera antes 46-05); no se toca nada';
  end if;
  if exists (select 1 from public.project_products where configuration is not null) then
    raise exception 'recuperación 46-04: hay líneas con configuración que se perderían; no se toca nada';
  end if;
  if exists (select 1 from public.rfqs where lines_snapshot is not null) then
    raise exception 'recuperación 46-04: hay RFQ con copia de lo solicitado que se perdería; no se toca nada';
  end if;
  if (select md5(prosrc) from pg_proc where oid = 'mobau_private.product_reference_counts(text)'::regprocedure) <> '6a9b5efb565babc8e06016d58dd99288' then
    raise exception 'recuperación 46-04: product_reference_counts no es la de 46-04; no se toca nada';
  end if;
end $$;

-- 1. Triggers
drop trigger trg_rfqs_10_lines_snapshot on public.rfqs;
drop trigger trg_project_products_10_configuration on public.project_products;

-- 2. product_reference_counts a su texto anterior
DO $$
declare
  d text := pg_get_functiondef('mobau_private.product_reference_counts(text)'::regprocedure);
begin
  d := pg_temp.r4604b(d, $a$  v_unknown text[] := '{}'::text[];
  v_cfg bigint;
  v_snap bigint;
begin
$a$, $a$  v_unknown text[] := '{}'::text[];
begin
$a$);
  d := pg_temp.r4604b(d, $a$  end loop;
  -- 46-04: las configuraciones guardadas y las copias de RFQ (jsonb, sin
  -- clave ajena) también cuentan como referencias: bloquean la purga.
  select count(*) into v_cfg from public.project_products pp
   where pp.config_snapshot is not null
     and pg_catalog.jsonb_path_exists(pp.config_snapshot, '$.items[*] ? (@.product_id == $p)', pg_catalog.jsonb_build_object('p', p_product_id));
  select count(*) into v_snap from public.rfqs r
   where r.lines_snapshot is not null
     and pg_catalog.jsonb_path_exists(r.lines_snapshot, '$.**.product_id ? (@ == $p)', pg_catalog.jsonb_build_object('p', p_product_id));
  v_other := v_other + v_cfg + v_snap;
  return pg_catalog.jsonb_build_object(
    'configured_lines', v_cfg,
    'rfq_snapshots', v_snap,
$a$, $a$  end loop;
  return pg_catalog.jsonb_build_object(
$a$);
  execute d;
end $$;

-- 3. Índice y funciones
drop index public.project_products_config_line_unique;
drop function public.rfqs_lines_snapshot();
drop function public.project_products_configuration();
drop function public.project_request_lines(uuid);
drop function public.project_line_states(uuid);
drop function public.line_configuration_structure(jsonb);
drop function public.line_configuration_resolve(text, jsonb);
drop function public.line_configuration_normalized(jsonb);

-- 4. Columnas (sus permisos por columna desaparecen con ellas)
alter table public.rfqs drop constraint rfqs_lines_snapshot_shape;
alter table public.rfqs drop column lines_snapshot;
alter table public.project_products
  drop constraint project_products_configuration_shape,
  drop constraint project_products_config_key_format,
  drop constraint project_products_config_key_consistent;
alter table public.project_products
  drop column config_snapshot,
  drop column config_key,
  drop column configuration;

-- 5. Comprobaciones finales
DO $$
begin
  if (select md5(prosrc) from pg_proc where oid = 'mobau_private.product_reference_counts(text)'::regprocedure) <> '69f5ee71cbed763b505986669083c09c' then
    raise exception 'recuperación 46-04: product_reference_counts no volvió a su texto anterior';
  end if;
  if exists (select 1 from information_schema.columns where table_schema = 'public'
               and ((table_name = 'project_products' and column_name in ('configuration', 'config_key', 'config_snapshot'))
                    or (table_name = 'rfqs' and column_name = 'lines_snapshot')))
     or exists (select 1 from pg_trigger where not tgisinternal and tgrelid in ('public.project_products'::regclass, 'public.rfqs'::regclass))
     or exists (select 1 from pg_proc where pronamespace = 'public'::regnamespace
                  and proname in ('line_configuration_normalized', 'line_configuration_resolve', 'line_configuration_structure',
                                  'project_line_states', 'project_request_lines', 'project_products_configuration', 'rfqs_lines_snapshot'))
     or not exists (select 1 from pg_indexes where schemaname = 'public' and indexname = 'project_products_line_unique') then
    raise exception 'recuperación 46-04: el estado final no es el esperado';
  end if;
end $$;

COMMIT;
