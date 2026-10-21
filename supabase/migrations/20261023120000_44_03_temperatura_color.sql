-- ============================================================
-- PROPUESTA NO EJECUTADA (44-03 · temperatura de color opcional) — no ejecutar sin aprobación explícita
-- ============================================================
-- Punto 44 · plantilla de Iluminación.
--   * products.color_temperature (texto, opcional), en formato canónico:
--       opciones fijas    «2700» o «2700,3000» (hasta 10 valores)
--       intervalo regulable «2700-6500» (de menor a mayor)
--     El tono (cálida < 3300 K ≤ neutra ≤ 5300 K < fría) lo calcula la
--     interfaz a partir de los K; no se guarda.
--   * validate_proposal_changes (trigger 30): admite el campo y valida el
--     formato (1000–20000 K, sin repetidos, intervalo creciente). Opcional:
--     vacío o nulo es válido; nulo en un cambio elimina el valor.
--   * moderate_product_proposal: admite el campo y lo guarda al crear.
--   * snapshot_product_on_submit: la copia incluye el campo.
--   * catalog_products: añade color_temperature al final.
-- Sustituciones exactas sobre el texto vigente (MD5 de partida comprobado).
-- No toca datos, roles, planes, habilitaciones ni Storage. Ejecutar completo.
-- ============================================================

BEGIN;

create function pg_temp.r44(t text, a text, b text) returns text language plpgsql as $$
begin
  if (length(t) - length(replace(t, a, ''))) <> length(a) then
    raise exception '44-03: el fragmento no aparece exactamente una vez: %', left(a, 80);
  end if;
  return replace(t, a, b);
end $$;

DO $$
begin
  if current_user <> 'postgres' then
    raise exception '44-03: ejecutar como postgres';
  end if;
  if not exists (select 1 from supabase_migrations.schema_migrations where version = '20261022120000')
     or exists (select 1 from supabase_migrations.schema_migrations where version = '20261023120000') then
    raise exception '44-03: el registro de migraciones no es el esperado (44-02 registrada y 44-03 sin registrar)';
  end if;
  if exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'products' and column_name = 'color_temperature') then
    raise exception '44-03: ya existe la columna color_temperature';
  end if;
  if (select md5(prosrc) from pg_proc where oid = 'public.validate_proposal_changes()'::regprocedure) <> '51efef497141b8af85de4c98ea244028'
     or (select md5(prosrc) from pg_proc where oid = 'public.moderate_product_proposal(uuid, text, text, integer)'::regprocedure) <> 'f4d433d65a34755ed75c707f6783e9b7'
     or (select md5(prosrc) from pg_proc where oid = 'public.snapshot_product_on_submit()'::regprocedure) <> '24a8bef78493e7f00332b050dc8fd819'
     or md5(pg_get_viewdef('public.catalog_products'::regclass)) <> '730aac79eb3a86fcac728b8020b16234' then
    raise exception '44-03: alguna función o la vista no es la esperada';
  end if;
  perform set_config('mobau.p44c_datos', md5(
      coalesce((select string_agg(id || ':' || coalesce(publication_status, '-') || ':' || updated_at::text, '|' order by id) from public.products), '')
   || coalesce((select string_agg(id::text || ':' || status || ':' || version::text, '|' order by id) from public.product_proposals), '')), true);
end $$;

-- ---------- 1. Columna ----------
alter table public.products add column color_temperature text;
alter table public.products
  add constraint products_44_03_color_temperature check (
        color_temperature is null
     or color_temperature ~ '^[0-9]{4,5}(,[0-9]{4,5}){0,9}$'
     or (color_temperature ~ '^[0-9]{4,5}-[0-9]{4,5}$'
         and split_part(color_temperature, '-', 1)::int < split_part(color_temperature, '-', 2)::int));
grant select (color_temperature) on table public.products to anon, authenticated;

-- ---------- 2. Funciones: sustituciones exactas ----------
DO $$
declare
  d text;
begin
  d := pg_get_functiondef('public.validate_proposal_changes()'::regprocedure);
  d := pg_temp.r44(d, $a$'environment', 'light_source', 'electrical_connection'];$a$,
                      $a$'environment', 'light_source', 'electrical_connection', 'color_temperature'];$a$);
  d := pg_temp.r44(d, $a$"electrical_connection":200}';$a$,
                      $a$"electrical_connection":200, "color_temperature":60}';$a$);
  d := pg_temp.r44(d, $a$    if k = 'category_id' and not exists (select 1 from public.categories c where c.id = s) then$a$,
                      $a$    if k = 'color_temperature' and s is not null and not (
         (s ~ '^[0-9]{4,5}(,[0-9]{4,5}){0,9}$'
          and not exists (select 1 from pg_catalog.unnest(pg_catalog.string_to_array(s, ',')) t(v) where t.v::int not between 1000 and 20000)
          and (select pg_catalog.count(distinct t.v) = pg_catalog.count(*) from pg_catalog.unnest(pg_catalog.string_to_array(s, ',')) t(v)))
      or (s ~ '^[0-9]{4,5}-[0-9]{4,5}$'
          and pg_catalog.split_part(s, '-', 1)::int between 1000 and 20000
          and pg_catalog.split_part(s, '-', 2)::int between 1000 and 20000
          and pg_catalog.split_part(s, '-', 1)::int < pg_catalog.split_part(s, '-', 2)::int)) then
      raise exception 'Temperatura de color no válida: indica opciones fijas (por ejemplo 2700,3000) o un intervalo regulable de menor a mayor (por ejemplo 2700-6500), entre 1000 y 20000 K.' using errcode = '23514';
    end if;
    if k = 'category_id' and not exists (select 1 from public.categories c where c.id = s) then$a$);
  execute d;

  d := pg_get_functiondef('public.moderate_product_proposal(uuid, text, text, integer)'::regprocedure);
  d := pg_temp.r44(d, $a$'environment', 'light_source', 'electrical_connection'];$a$,
                      $a$'environment', 'light_source', 'electrical_connection', 'color_temperature'];$a$);
  d := pg_temp.r44(d, $a$light_source, electrical_connection, publication_status)$a$,
                      $a$light_source, electrical_connection, color_temperature, publication_status)$a$);
  d := pg_temp.r44(d, $a$v_changes ->> 'electrical_connection', 'published');$a$,
                      $a$v_changes ->> 'electrical_connection', v_changes ->> 'color_temperature', 'published');$a$);
  execute d;

  d := pg_get_functiondef('public.snapshot_product_on_submit()'::regprocedure);
  d := pg_temp.r44(d, $a$p.environment, p.light_source, p.electrical_connection$a$,
                      $a$p.environment, p.light_source, p.electrical_connection, p.color_temperature$a$);
  execute d;
end $$;

-- ---------- 3. Catálogo ----------
create or replace view public.catalog_products with (security_invoker = true, security_barrier = true) as
 select p.id, p.name, p.brand, p.distributor_id, p.category_id, p.subcategory, p.use_context, p.space,
        p.availability, p.description, p.measurements, p.materials, p.finishes, p.lead_time, p.icon,
        p.image_url, p.technical_sheet_url, p.cad_bim_3d_url, p.status, p.created_at, p.updated_at,
        p.reference_code,
        cov.path as cover_path,
        cov.variants ->> 'card' as cover_card_path,
        coalesce((select jsonb_agg(jsonb_build_object(
                           'code', f.code, 'name', f.name, 'reference_code', f.reference_code, 'is_default', f.is_default,
                           'image_path', fa.path, 'image_card_path', fa.variants ->> 'card')
                         order by f.sort_order, f.code)
                    from public.product_finishes f
                    left join public.product_assets fa on fa.id = f.image_asset_id and fa.status = 'aprobado'
                   where f.product_id = p.id), '[]'::jsonb) as finish_options,
        p.environment, p.light_source, p.electrical_connection,
        p.color_temperature
   from public.products p
   left join public.product_assets cov on cov.id = p.cover_asset_id and cov.status = 'aprobado'
  where p.publication_status = 'published' and p.status = 'active';
comment on view public.catalog_products is '44-03: catálogo público (publicado y activo): las 21 columnas de 41-02, las 4 de 44-01 (reference_code, cover_path, cover_card_path, finish_options), las 3 de 44-02 (environment, light_source, electrical_connection) y color_temperature. security_invoker: RLS y permisos de quien consulta. Solo SELECT para anon y authenticated.';

-- ---------- 4. Comprobación final ----------
DO $$
begin
  if strpos((select prosrc from pg_proc where oid = 'public.validate_proposal_changes()'::regprocedure), '''electrical_connection'', ''color_temperature''];') = 0
     or strpos((select prosrc from pg_proc where oid = 'public.validate_proposal_changes()'::regprocedure), 'Temperatura de color no válida') = 0
     or strpos((select prosrc from pg_proc where oid = 'public.moderate_product_proposal(uuid, text, text, integer)'::regprocedure), 'electrical_connection, color_temperature, publication_status)') = 0
     or strpos((select prosrc from pg_proc where oid = 'public.snapshot_product_on_submit()'::regprocedure), 'p.electrical_connection, p.color_temperature') = 0 then
    raise exception '44-03: las funciones no quedaron como se esperaba';
  end if;
  if not (select prosecdef from pg_proc where oid = 'public.moderate_product_proposal(uuid, text, text, integer)'::regprocedure)
     or not has_function_privilege('authenticated', 'public.moderate_product_proposal(uuid, text, text, integer)', 'EXECUTE')
     or has_function_privilege('anon', 'public.moderate_product_proposal(uuid, text, text, integer)', 'EXECUTE')
     or not has_column_privilege('anon', 'public.products', 'color_temperature', 'SELECT')
     or not has_column_privilege('authenticated', 'public.products', 'color_temperature', 'SELECT') then
    raise exception '44-03: permisos no esperados';
  end if;
  if (select reloptions::text from pg_class where oid = 'public.catalog_products'::regclass) <> '{security_invoker=true,security_barrier=true}'
     or (select relacl::text from pg_class where oid = 'public.catalog_products'::regclass) <> '{postgres=arwdDxtm/postgres,anon=r/postgres,authenticated=r/postgres}' then
    raise exception '44-03: la vista del catálogo cambió de opciones o de permisos';
  end if;
  if md5(
      coalesce((select string_agg(id || ':' || coalesce(publication_status, '-') || ':' || updated_at::text, '|' order by id) from public.products), '')
   || coalesce((select string_agg(id::text || ':' || status || ':' || version::text, '|' order by id) from public.product_proposals), ''))
     <> current_setting('mobau.p44c_datos') then
    raise exception '44-03: ha cambiado algún dato existente';
  end if;
end $$;

COMMIT;
