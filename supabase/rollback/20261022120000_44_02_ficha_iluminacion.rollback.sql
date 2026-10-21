-- ============================================================
-- PROPUESTA NO EJECUTADA (44-02 · recuperación) — no ejecutar sin aprobación explícita
-- ============================================================
-- Deshace 44-02: devuelve las tres funciones a su texto anterior (MD5
-- comprobado), la vista a la de 44-01 y quita las tres columnas. Si alguna
-- tiene datos, antes los copia a mobau_private.r44b_products. Se detiene si
-- hay propuestas abiertas con los campos nuevos (hay que resolverlas antes).
-- Si se aplica, se registra como migración NUEVA tras confirmar su COMMIT.
-- ============================================================

BEGIN;

create function pg_temp.r44(t text, a text, b text) returns text language plpgsql as $$
begin
  if (length(t) - length(replace(t, a, ''))) <> length(a) then
    raise exception '44-02 R: el fragmento no aparece exactamente una vez: %', left(a, 80);
  end if;
  return replace(t, a, b);
end $$;

DO $$
begin
  if current_user <> 'postgres' then
    raise exception '44-02 R: ejecutar como postgres';
  end if;
  if not exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'products' and column_name = 'environment') then
    raise exception '44-02 R: 44-02 no está aplicada';
  end if;
  if exists (select 1 from public.product_proposals
              where status in ('draft', 'submitted', 'changes_requested')
                and proposed_changes ?| array['environment', 'light_source', 'electrical_connection']) then
    raise exception '44-02 R: hay propuestas abiertas con campos de 44-02' using errcode = 'MB443';
  end if;
  if exists (select 1 from public.products where environment is not null or light_source is not null or electrical_connection is not null) then
    create table mobau_private.r44b_products as
      select id, environment, light_source, electrical_connection from public.products
       where environment is not null or light_source is not null or electrical_connection is not null;
    revoke all on table mobau_private.r44b_products from public, anon, authenticated;
  end if;
end $$;

DO $$
declare
  d text;
begin
  d := pg_get_functiondef('public.validate_proposal_changes()'::regprocedure);
  d := pg_temp.r44(d, $a$'use_context', 'space',
                                   'environment', 'light_source', 'electrical_connection'];$a$, $a$'use_context', 'space'];$a$);
  d := pg_temp.r44(d, $a$"subcategory":100, "light_source":200, "electrical_connection":200}';$a$, $a$"subcategory":100}';$a$);
  d := pg_temp.r44(d, $a$array['name', 'description', 'category_id', 'availability', 'brand', 'measurements'];$a$,
                      $a$array['name', 'description', 'category_id', 'availability'];$a$);
  d := pg_temp.r44(d, $a$"availability": "disponibilidad", "brand": "marca", "measurements": "medidas"}';$a$,
                      $a$"availability": "disponibilidad"}';$a$);
  d := pg_temp.r44(d, $a$if k in ('name', 'category_id', 'availability', 'brand', 'measurements') and (s is null or$a$,
                      $a$if k in ('name', 'category_id', 'availability') and (s is null or$a$);
  d := pg_temp.r44(d, $a$    if k = 'environment' and s is not null and s not in ('interior', 'exterior', 'ambos') then
      raise exception 'Interior o exterior no válido: %.', s using errcode = '23514';
    end if;
$a$, '');
  execute d;

  d := pg_get_functiondef('public.moderate_product_proposal(uuid, text, text, integer)'::regprocedure);
  d := pg_temp.r44(d, $a$'use_context', 'space',
                                     'environment', 'light_source', 'electrical_connection'];$a$, $a$'use_context', 'space'];$a$);
  d := pg_temp.r44(d, $a$use_context, space, environment, light_source, electrical_connection, publication_status)$a$,
                      $a$use_context, space, publication_status)$a$);
  d := pg_temp.r44(d, $a$v_changes ->> 'space', v_changes ->> 'environment', v_changes ->> 'light_source',
              v_changes ->> 'electrical_connection', 'published');$a$, $a$v_changes ->> 'space', 'published');$a$);
  execute d;

  d := pg_get_functiondef('public.snapshot_product_on_submit()'::regprocedure);
  d := pg_temp.r44(d, $a$p.created_at, p.status, p.updated_at, p.publication_status,
                   p.environment, p.light_source, p.electrical_connection$a$,
                      $a$p.created_at, p.status, p.updated_at, p.publication_status$a$);
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
                   where f.product_id = p.id), '[]'::jsonb) as finish_options
   from public.products p
   left join public.product_assets cov on cov.id = p.cover_asset_id and cov.status = 'aprobado'
  where p.publication_status = 'published' and p.status = 'active';
revoke all on table public.catalog_products from public, anon, authenticated;
grant select on table public.catalog_products to anon, authenticated;
comment on view public.catalog_products is '44-01: catálogo público (publicado y activo): las 21 columnas de 41-02 más reference_code, cover_path, cover_card_path y finish_options. security_invoker: RLS y permisos de quien consulta. Solo SELECT para anon y authenticated.';

alter table public.products
  drop constraint products_44_02_fields,
  drop column environment,
  drop column light_source,
  drop column electrical_connection;

DO $$
begin
  if (select md5(prosrc) from pg_proc where oid = 'public.validate_proposal_changes()'::regprocedure) <> 'e5597c62fdd46f5db7c6ce40b82f06a6'
     or (select md5(prosrc) from pg_proc where oid = 'public.moderate_product_proposal(uuid, text, text, integer)'::regprocedure) <> 'aa4fac4c25f4634499532824782ee908'
     or (select md5(prosrc) from pg_proc where oid = 'public.snapshot_product_on_submit()'::regprocedure) <> '92d5158e8454b17263942346e5487d7c'
     or md5(pg_get_viewdef('public.catalog_products'::regclass)) <> '0cfa7549f16aba7e65d3ade0071c3ae9'
     or (select relacl::text from pg_class where oid = 'public.catalog_products'::regclass) <> '{postgres=arwdDxtm/postgres,anon=r/postgres,authenticated=r/postgres}' then
    raise exception '44-02 R: funciones o vista no volvieron a su estado';
  end if;
end $$;

COMMIT;
