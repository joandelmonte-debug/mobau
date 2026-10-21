-- ============================================================
-- PROPUESTA NO EJECUTADA (44-03 · recuperación) — no ejecutar sin aprobación explícita
-- ============================================================
-- Deshace 44-03: devuelve las tres funciones a su texto anterior (MD5
-- comprobado), la vista a la de 44-02 y quita la columna. Si tiene datos,
-- antes los copia a mobau_private.r44c_products. Se detiene si hay
-- propuestas abiertas con color_temperature (hay que resolverlas antes).
-- Si se aplica, se registra como migración NUEVA tras confirmar su COMMIT.
-- ============================================================

BEGIN;

create function pg_temp.r44(t text, a text, b text) returns text language plpgsql as $$
begin
  if (length(t) - length(replace(t, a, ''))) <> length(a) then
    raise exception '44-03 R: el fragmento no aparece exactamente una vez: %', left(a, 80);
  end if;
  return replace(t, a, b);
end $$;

DO $$
begin
  if current_user <> 'postgres' then
    raise exception '44-03 R: ejecutar como postgres';
  end if;
  if not exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'products' and column_name = 'color_temperature') then
    raise exception '44-03 R: 44-03 no está aplicada';
  end if;
  if exists (select 1 from public.product_proposals
              where status in ('draft', 'submitted', 'changes_requested') and proposed_changes ? 'color_temperature') then
    raise exception '44-03 R: hay propuestas abiertas con color_temperature' using errcode = 'MB444';
  end if;
  if exists (select 1 from public.products where color_temperature is not null) then
    create table mobau_private.r44c_products as
      select id, color_temperature from public.products where color_temperature is not null;
    revoke all on table mobau_private.r44c_products from public, anon, authenticated;
  end if;
end $$;

DO $$
declare
  d text;
begin
  d := pg_get_functiondef('public.validate_proposal_changes()'::regprocedure);
  d := pg_temp.r44(d, $a$'environment', 'light_source', 'electrical_connection', 'color_temperature'];$a$,
                      $a$'environment', 'light_source', 'electrical_connection'];$a$);
  d := pg_temp.r44(d, $a$"electrical_connection":200, "color_temperature":60}';$a$, $a$"electrical_connection":200}';$a$);
  d := pg_temp.r44(d, $a$    if k = 'color_temperature' and s is not null and not (
         (s ~ '^[0-9]{4,5}(,[0-9]{4,5}){0,9}$'
          and not exists (select 1 from pg_catalog.unnest(pg_catalog.string_to_array(s, ',')) t(v) where t.v::int not between 1000 and 20000)
          and (select pg_catalog.count(distinct t.v) = pg_catalog.count(*) from pg_catalog.unnest(pg_catalog.string_to_array(s, ',')) t(v)))
      or (s ~ '^[0-9]{4,5}-[0-9]{4,5}$'
          and pg_catalog.split_part(s, '-', 1)::int between 1000 and 20000
          and pg_catalog.split_part(s, '-', 2)::int between 1000 and 20000
          and pg_catalog.split_part(s, '-', 1)::int < pg_catalog.split_part(s, '-', 2)::int)) then
      raise exception 'Temperatura de color no válida: indica opciones fijas (por ejemplo 2700,3000) o un intervalo regulable de menor a mayor (por ejemplo 2700-6500), entre 1000 y 20000 K.' using errcode = '23514';
    end if;
$a$, '');
  execute d;

  d := pg_get_functiondef('public.moderate_product_proposal(uuid, text, text, integer)'::regprocedure);
  d := pg_temp.r44(d, $a$'environment', 'light_source', 'electrical_connection', 'color_temperature'];$a$,
                      $a$'environment', 'light_source', 'electrical_connection'];$a$);
  d := pg_temp.r44(d, $a$light_source, electrical_connection, color_temperature, publication_status)$a$,
                      $a$light_source, electrical_connection, publication_status)$a$);
  d := pg_temp.r44(d, $a$v_changes ->> 'electrical_connection', v_changes ->> 'color_temperature', 'published');$a$,
                      $a$v_changes ->> 'electrical_connection', 'published');$a$);
  execute d;

  d := pg_get_functiondef('public.snapshot_product_on_submit()'::regprocedure);
  d := pg_temp.r44(d, $a$p.environment, p.light_source, p.electrical_connection, p.color_temperature$a$,
                      $a$p.environment, p.light_source, p.electrical_connection$a$);
  execute d;
end $$;

drop view public.catalog_products;
create view public.catalog_products with (security_invoker = true, security_barrier = true) as
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
revoke all on table public.catalog_products from public, anon, authenticated;
grant select on table public.catalog_products to anon, authenticated;
comment on view public.catalog_products is '44-02: catálogo público (publicado y activo): las 21 columnas de 41-02, las 4 de 44-01 (reference_code, cover_path, cover_card_path, finish_options) y environment, light_source y electrical_connection. security_invoker: RLS y permisos de quien consulta. Solo SELECT para anon y authenticated.';

alter table public.products
  drop constraint products_44_03_color_temperature,
  drop column color_temperature;

DO $$
begin
  if (select md5(prosrc) from pg_proc where oid = 'public.validate_proposal_changes()'::regprocedure) <> '51efef497141b8af85de4c98ea244028'
     or (select md5(prosrc) from pg_proc where oid = 'public.moderate_product_proposal(uuid, text, text, integer)'::regprocedure) <> 'f4d433d65a34755ed75c707f6783e9b7'
     or (select md5(prosrc) from pg_proc where oid = 'public.snapshot_product_on_submit()'::regprocedure) <> '24a8bef78493e7f00332b050dc8fd819'
     or md5(pg_get_viewdef('public.catalog_products'::regclass)) <> '730aac79eb3a86fcac728b8020b16234'
     or (select relacl::text from pg_class where oid = 'public.catalog_products'::regclass) <> '{postgres=arwdDxtm/postgres,anon=r/postgres,authenticated=r/postgres}' then
    raise exception '44-03 R: funciones o vista no volvieron a su estado';
  end if;
end $$;

COMMIT;
