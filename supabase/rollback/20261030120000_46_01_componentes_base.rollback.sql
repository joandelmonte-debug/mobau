-- ============================================================
-- PROPUESTA NO EJECUTADA (recuperación de 46-01) — no ejecutar sin aprobación explícita
-- ============================================================
-- Deshace 46-01 SOLO si no hay nada que perder:
--   * se detiene si hay grupos u opciones, si algún producto no es
--     «principal» o si otros objetos dependen de lo creado;
--   * sin DROP ... CASCADE: cada objeto se elimina de forma explícita;
--   * catalog_products vuelve a su definición, opciones y permisos de antes
--     (29 columnas), con las mismas filas.
-- Si se aplica, se registra como migración NUEVA tras confirmar su COMMIT.
-- Ejecutar completo.
-- ============================================================

BEGIN;

DO $$
begin
  if current_user <> 'postgres' then
    raise exception 'recuperación 46-01: ejecutar como postgres';
  end if;
  if to_regclass('public.product_component_groups') is null or to_regclass('public.product_component_options') is null
     or to_regclass('public.catalog_component_groups') is null or to_regclass('public.catalog_component_options') is null
     or not exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'products' and column_name = 'catalog_role') then
    raise exception 'recuperación 46-01: falta algún objeto de 46-01; no se toca nada';
  end if;
  if exists (select 1 from public.product_component_groups) or exists (select 1 from public.product_component_options) then
    raise exception 'recuperación 46-01: hay grupos u opciones de componentes que se perderían; no se toca nada';
  end if;
  if exists (select 1 from public.products where catalog_role <> 'principal') then
    raise exception 'recuperación 46-01: hay productos clasificados como componente o ambos; no se toca nada';
  end if;
  -- Dependencias ajenas: vistas o reglas que usen lo creado, salvo las propias de 46-01.
  if exists (select 1 from pg_depend d join pg_rewrite r on r.oid = d.objid
              where d.refobjid in ('public.product_component_groups'::regclass, 'public.product_component_options'::regclass,
                                   'public.catalog_component_groups'::regclass, 'public.catalog_component_options'::regclass)
                and r.ev_class not in ('public.catalog_component_groups'::regclass, 'public.catalog_component_options'::regclass))
     or exists (select 1 from pg_depend d join pg_rewrite r on r.oid = d.objid
                 where d.refobjid = 'public.catalog_products'::regclass and r.ev_class <> 'public.catalog_products'::regclass)
     or exists (select 1 from pg_depend d join pg_rewrite r on r.oid = d.objid
                 join pg_attribute a on a.attrelid = d.refobjid and a.attnum = d.refobjsubid
                 where d.refobjid = 'public.products'::regclass and a.attname = 'catalog_role'
                   and r.ev_class <> 'public.catalog_products'::regclass)
     or exists (select 1 from pg_constraint c
                 where c.confrelid in ('public.product_component_groups'::regclass, 'public.product_component_options'::regclass)
                   and c.conrelid not in ('public.product_component_groups'::regclass, 'public.product_component_options'::regclass)) then
    raise exception 'recuperación 46-01: otros objetos dependen de 46-01; no se toca nada';
  end if;
  perform set_config('mobau.r4601_catalogo', md5(coalesce((select string_agg((to_jsonb(c) - 'catalog_role')::text, '|' order by c.id) from public.catalog_products c), '')), true);
  perform set_config('mobau.r4601_productos', md5(coalesce((select string_agg((to_jsonb(p) - 'catalog_role')::text, '|' order by p.id) from public.products p), '')), true);
end $$;

drop view public.catalog_component_options;
drop view public.catalog_component_groups;
drop trigger trg_products_component_role_check on public.products;
alter table public.product_component_groups drop constraint product_component_groups_depends_fk;
drop table public.product_component_options;
drop table public.product_component_groups;
drop function mobau_private.component_structure_check();
drop function mobau_private.component_structure_violations();

drop view public.catalog_products;
create view public.catalog_products with (security_invoker = true, security_barrier = true) as
 SELECT p.id,
    p.name,
    p.brand,
    p.distributor_id,
    p.category_id,
    p.subcategory,
    p.use_context,
    p.space,
    p.availability,
    p.description,
    p.measurements,
    p.materials,
    p.finishes,
    p.lead_time,
    p.icon,
    p.image_url,
    p.technical_sheet_url,
    p.cad_bim_3d_url,
    p.status,
    p.created_at,
    p.updated_at,
    p.reference_code,
    cov.path AS cover_path,
    (cov.variants ->> 'card'::text) AS cover_card_path,
    COALESCE(( SELECT jsonb_agg(jsonb_build_object('code', f.code, 'name', f.name, 'reference_code', f.reference_code, 'is_default', f.is_default, 'image_path', fa.path, 'image_card_path', (fa.variants ->> 'card'::text)) ORDER BY f.sort_order, f.code) AS jsonb_agg
           FROM (product_finishes f
             LEFT JOIN product_assets fa ON (((fa.id = f.image_asset_id) AND (fa.status = 'aprobado'::text))))
          WHERE (f.product_id = p.id)), '[]'::jsonb) AS finish_options,
    p.environment,
    p.light_source,
    p.electrical_connection,
    p.color_temperature
   FROM (products p
     LEFT JOIN product_assets cov ON (((cov.id = p.cover_asset_id) AND (cov.status = 'aprobado'::text))))
  WHERE ((p.publication_status = 'published'::text) AND (p.status = 'active'::text));
revoke all on table public.catalog_products from public, anon, authenticated, service_role;
grant select on table public.catalog_products to anon, authenticated;

alter table public.products drop column catalog_role;

DO $$
begin
  if (select coalesce(array_to_string(reloptions, ','), '') || '|' || coalesce(relacl::text, '') from pg_class where oid = 'public.catalog_products'::regclass)
     <> 'security_invoker=true,security_barrier=true|{postgres=arwdDxtm/postgres,anon=r/postgres,authenticated=r/postgres}'
     or (select count(*) from information_schema.columns where table_schema = 'public' and table_name = 'catalog_products') <> 29
     or md5(coalesce((select string_agg(to_jsonb(c)::text, '|' order by c.id) from public.catalog_products c), '')) <> current_setting('mobau.r4601_catalogo') then
    raise exception 'recuperación 46-01: catalog_products no quedó como antes';
  end if;
  if md5(coalesce((select string_agg(to_jsonb(p)::text, '|' order by p.id) from public.products p), '')) <> current_setting('mobau.r4601_productos')
     or to_regclass('public.product_component_groups') is not null or to_regclass('public.product_component_options') is not null then
    raise exception 'recuperación 46-01: el estado final no es el esperado';
  end if;
end $$;

COMMIT;
