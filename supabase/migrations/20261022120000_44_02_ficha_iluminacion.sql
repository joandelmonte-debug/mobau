-- ============================================================
-- PROPUESTA NO EJECUTADA (44-02 · interior/exterior y plantilla de iluminación) — no ejecutar sin aprobación explícita
-- ============================================================
-- Punto 44 · ajustes del formulario de producto.
--   * products: environment (interior | exterior | ambos), light_source y
--     electrical_connection (texto, máx. 200). Nulos en los productos
--     existentes: no se deducen ni se tocan datos antiguos (use_context y
--     space se conservan).
--   * validate_proposal_changes (trigger 30): admite los 3 campos nuevos;
--     marca y medidas pasan a ser obligatorias al enviar un producto nuevo y
--     no se pueden vaciar en un cambio.
--   * moderate_product_proposal: admite los 3 campos y los guarda al crear.
--   * snapshot_product_on_submit: la copia incluye los 3 campos (para
--     detectar conflictos en «Proponer cambios»).
--   * catalog_products: añade al final environment, light_source y
--     electrical_connection; mismas opciones y permisos.
-- Las funciones se modifican con sustituciones exactas sobre el texto
-- vigente (cada fragmento debe aparecer una sola vez; MD5 de partida
-- comprobado). No toca datos, roles, planes, habilitaciones ni Storage.
-- Ejecutar completo.
-- ============================================================

BEGIN;

create function pg_temp.r44(t text, a text, b text) returns text language plpgsql as $$
begin
  if (length(t) - length(replace(t, a, ''))) <> length(a) then
    raise exception '44-02: el fragmento no aparece exactamente una vez: %', left(a, 80);
  end if;
  return replace(t, a, b);
end $$;

DO $$
begin
  if current_user <> 'postgres' then
    raise exception '44-02: ejecutar como postgres';
  end if;
  if not exists (select 1 from supabase_migrations.schema_migrations where version = '20261021120000')
     or exists (select 1 from supabase_migrations.schema_migrations where version = '20261022120000') then
    raise exception '44-02: el registro de migraciones no es el esperado (44-01 registrada y 44-02 sin registrar)';
  end if;
  if exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'products'
             and column_name in ('environment', 'light_source', 'electrical_connection')) then
    raise exception '44-02: ya existe alguna columna de 44-02';
  end if;
  if (select md5(prosrc) from pg_proc where oid = 'public.validate_proposal_changes()'::regprocedure) <> 'e5597c62fdd46f5db7c6ce40b82f06a6'
     or (select md5(prosrc) from pg_proc where oid = 'public.moderate_product_proposal(uuid, text, text, integer)'::regprocedure) <> 'aa4fac4c25f4634499532824782ee908'
     or (select md5(prosrc) from pg_proc where oid = 'public.snapshot_product_on_submit()'::regprocedure) <> '92d5158e8454b17263942346e5487d7c'
     or md5(pg_get_viewdef('public.catalog_products'::regclass)) <> '0cfa7549f16aba7e65d3ade0071c3ae9' then
    raise exception '44-02: alguna función o la vista no es la esperada';
  end if;
  perform set_config('mobau.p44b_datos', md5(
      coalesce((select string_agg(id || ':' || coalesce(publication_status, '-') || ':' || updated_at::text, '|' order by id) from public.products), '')
   || coalesce((select string_agg(id::text || ':' || status || ':' || version::text, '|' order by id) from public.product_proposals), '')), true);
end $$;

-- ---------- 1. Columnas nuevas ----------
alter table public.products
  add column environment text,
  add column light_source text,
  add column electrical_connection text;
alter table public.products
  add constraint products_44_02_fields check (
        (environment is null or environment in ('interior', 'exterior', 'ambos'))
    and char_length(coalesce(light_source, '')) <= 200
    and char_length(coalesce(electrical_connection, '')) <= 200);
grant select (environment, light_source, electrical_connection) on table public.products to anon, authenticated;

-- ---------- 2. Funciones: sustituciones exactas ----------
DO $$
declare
  d text;
begin
  -- validate_proposal_changes (trigger 30)
  d := pg_get_functiondef('public.validate_proposal_changes()'::regprocedure);
  d := pg_temp.r44(d, $a$'use_context', 'space'];$a$,
                      $a$'use_context', 'space',
                                   'environment', 'light_source', 'electrical_connection'];$a$);
  d := pg_temp.r44(d, $a$"subcategory":100}';$a$,
                      $a$"subcategory":100, "light_source":200, "electrical_connection":200}';$a$);
  d := pg_temp.r44(d, $a$array['name', 'description', 'category_id', 'availability'];$a$,
                      $a$array['name', 'description', 'category_id', 'availability', 'brand', 'measurements'];$a$);
  d := pg_temp.r44(d, $a$"availability": "disponibilidad"}';$a$,
                      $a$"availability": "disponibilidad", "brand": "marca", "measurements": "medidas"}';$a$);
  d := pg_temp.r44(d, $a$if k in ('name', 'category_id', 'availability') and (s is null or$a$,
                      $a$if k in ('name', 'category_id', 'availability', 'brand', 'measurements') and (s is null or$a$);
  d := pg_temp.r44(d, $a$    if k = 'category_id' and not exists (select 1 from public.categories c where c.id = s) then$a$,
                      $a$    if k = 'environment' and s is not null and s not in ('interior', 'exterior', 'ambos') then
      raise exception 'Interior o exterior no válido: %.', s using errcode = '23514';
    end if;
    if k = 'category_id' and not exists (select 1 from public.categories c where c.id = s) then$a$);
  execute d;

  -- moderate_product_proposal
  d := pg_get_functiondef('public.moderate_product_proposal(uuid, text, text, integer)'::regprocedure);
  d := pg_temp.r44(d, $a$'use_context', 'space'];$a$,
                      $a$'use_context', 'space',
                                     'environment', 'light_source', 'electrical_connection'];$a$);
  d := pg_temp.r44(d, $a$use_context, space, publication_status)$a$,
                      $a$use_context, space, environment, light_source, electrical_connection, publication_status)$a$);
  d := pg_temp.r44(d, $a$v_changes ->> 'space', 'published');$a$,
                      $a$v_changes ->> 'space', v_changes ->> 'environment', v_changes ->> 'light_source',
              v_changes ->> 'electrical_connection', 'published');$a$);
  execute d;

  -- snapshot_product_on_submit (trigger 40)
  d := pg_get_functiondef('public.snapshot_product_on_submit()'::regprocedure);
  d := pg_temp.r44(d, $a$p.created_at, p.status, p.updated_at, p.publication_status$a$,
                      $a$p.created_at, p.status, p.updated_at, p.publication_status,
                   p.environment, p.light_source, p.electrical_connection$a$);
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
        p.environment, p.light_source, p.electrical_connection
   from public.products p
   left join public.product_assets cov on cov.id = p.cover_asset_id and cov.status = 'aprobado'
  where p.publication_status = 'published' and p.status = 'active';
comment on view public.catalog_products is '44-02: catálogo público (publicado y activo): las 21 columnas de 41-02, las 4 de 44-01 (reference_code, cover_path, cover_card_path, finish_options) y environment, light_source y electrical_connection. security_invoker: RLS y permisos de quien consulta. Solo SELECT para anon y authenticated.';

-- ---------- 4. Comprobación final ----------
DO $$
begin
  if strpos((select prosrc from pg_proc where oid = 'public.validate_proposal_changes()'::regprocedure), '''electrical_connection''];') = 0
     or strpos((select prosrc from pg_proc where oid = 'public.validate_proposal_changes()'::regprocedure), '''availability'', ''brand'', ''measurements''];') = 0
     or strpos((select prosrc from pg_proc where oid = 'public.moderate_product_proposal(uuid, text, text, integer)'::regprocedure), 'environment, light_source, electrical_connection, publication_status)') = 0
     or strpos((select prosrc from pg_proc where oid = 'public.snapshot_product_on_submit()'::regprocedure), 'p.environment, p.light_source, p.electrical_connection') = 0 then
    raise exception '44-02: las funciones no quedaron como se esperaba';
  end if;
  if not (select prosecdef from pg_proc where oid = 'public.moderate_product_proposal(uuid, text, text, integer)'::regprocedure)
     or not has_function_privilege('authenticated', 'public.moderate_product_proposal(uuid, text, text, integer)', 'EXECUTE')
     or has_function_privilege('anon', 'public.moderate_product_proposal(uuid, text, text, integer)', 'EXECUTE')
     or not has_column_privilege('anon', 'public.products', 'environment', 'SELECT')
     or not has_column_privilege('authenticated', 'public.products', 'electrical_connection', 'SELECT') then
    raise exception '44-02: permisos no esperados';
  end if;
  if (select reloptions::text from pg_class where oid = 'public.catalog_products'::regclass) <> '{security_invoker=true,security_barrier=true}'
     or (select relacl::text from pg_class where oid = 'public.catalog_products'::regclass) <> '{postgres=arwdDxtm/postgres,anon=r/postgres,authenticated=r/postgres}' then
    raise exception '44-02: la vista del catálogo cambió de opciones o de permisos';
  end if;
  if md5(
      coalesce((select string_agg(id || ':' || coalesce(publication_status, '-') || ':' || updated_at::text, '|' order by id) from public.products), '')
   || coalesce((select string_agg(id::text || ':' || status || ':' || version::text, '|' order by id) from public.product_proposals), ''))
     <> current_setting('mobau.p44b_datos') then
    raise exception '44-02: ha cambiado algún dato existente';
  end if;
end $$;

COMMIT;
