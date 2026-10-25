-- ============================================================
-- PROPUESTA NO EJECUTADA (46-01 · componentes y accesorios: base) — no ejecutar sin aprobación explícita
-- ============================================================
-- Punto 46 · bloque 1 (solo base de datos). Mobau organiza elecciones
-- declaradas por el distribuidor; no certifica compatibilidad técnica.
--   * products.catalog_role: principal (por defecto, todos los existentes),
--     componente o ambos. Clasificación transversal, no categoría.
--   * product_component_groups: grupos de elección de un producto
--     (necesario/opcional, una/varias, dependencia declarada de otra opción).
--   * product_component_options: opciones de un grupo, de tipo
--     «componente» (otro producto del mismo distribuidor, acabado opcional,
--     suministro y cantidad POR UNIDAD del padre) o «ajuste» (valor del
--     propio artículo, sin producto). El suministro es de la relación: no se
--     hereda de padres a descendientes.
--   * Niveles: principal → componente → subcomponente (máximo 2 relaciones
--     de componente encadenadas). Más profundidad o un ciclo se RECHAZA.
--   * Comprobaciones diferidas al final de la transacción (se pueden crear
--     grupos y opciones en cualquier orden dentro de una misma transacción).
--   * Lectura pública solo de lo publicado (vistas catalog_component_groups
--     y catalog_component_options). Un grupo activo de un producto visible se
--     muestra aunque no le quede ninguna opción disponible
--     (available_options = 0), sin exponer las opciones no publicadas.
--   * Sin escritura directa para anon ni authenticated: las escrituras
--     llegarán con las funciones de propuestas (bloque 2). Claves estables
--     (code) y estado activo/retirado: se retira, no se borra.
--   * catalog_products: se añade catalog_role al final, conservando
--     definición, opciones (security_invoker, security_barrier) y permisos.
-- Si se aplica, se registra como migración NUEVA tras confirmar su COMMIT.
-- Ejecutar completo.
-- ============================================================

BEGIN;

DO $$
begin
  if current_user <> 'postgres' then
    raise exception '46-01: ejecutar como postgres';
  end if;
  if not exists (select 1 from supabase_migrations.schema_migrations where version = '20261029120000')
     or exists (select 1 from supabase_migrations.schema_migrations where version = '20261030120000') then
    raise exception '46-01: el registro de migraciones no es el esperado (45.1-01 registrada y 46-01 sin registrar)';
  end if;
  if exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'products' and column_name = 'catalog_role')
     or to_regclass('public.product_component_groups') is not null or to_regclass('public.product_component_options') is not null
     or to_regclass('public.catalog_component_groups') is not null or to_regclass('public.catalog_component_options') is not null then
    raise exception '46-01: algún objeto ya existe';
  end if;
  if (select coalesce(array_to_string(reloptions, ','), '') || '|' || coalesce(relacl::text, '') from pg_class where oid = 'public.catalog_products'::regclass)
     <> 'security_invoker=true,security_barrier=true|{postgres=arwdDxtm/postgres,anon=r/postgres,authenticated=r/postgres}'
     or (select count(*) from information_schema.columns where table_schema = 'public' and table_name = 'catalog_products') <> 29 then
    raise exception '46-01: catalog_products no es la vista esperada (29 columnas, opciones y permisos)';
  end if;
  perform set_config('mobau.p4601_catalogo', md5(coalesce((select string_agg(to_jsonb(c)::text, '|' order by c.id) from public.catalog_products c), '')), true);
  perform set_config('mobau.p4601_productos', md5(coalesce((select string_agg(to_jsonb(p)::text, '|' order by p.id) from public.products p), '')), true);
end $$;

-- 1. Rol en el catálogo
alter table public.products add column catalog_role text not null default 'principal'
  constraint products_catalog_role_check check (catalog_role in ('principal', 'componente', 'ambos'));
comment on column public.products.catalog_role is
  'Punto 46: principal (catálogo principal), componente (solo como componente o accesorio) o ambos. Transversal a las categorías.';
grant select (catalog_role) on public.products to anon, authenticated;

-- 2. Grupos y opciones
create table public.product_component_groups (
  id                   uuid primary key default gen_random_uuid(),
  product_id           text not null references public.products (id) on delete cascade,
  code                 text not null,
  label                text not null,
  requirement          text not null,
  choice               text not null,
  depends_on_option_id uuid,
  status               text not null default 'activo',
  sort_order           integer not null default 0,
  created_at           timestamptz not null default now(),
  updated_at           timestamptz not null default now(),
  constraint product_component_groups_code_unique unique (product_id, code),
  constraint product_component_groups_text check (code = btrim(code) and char_length(code) between 1 and 40
                                                  and label = btrim(label) and char_length(label) between 1 and 80),
  constraint product_component_groups_requirement check (requirement in ('necesario', 'opcional')),
  constraint product_component_groups_choice check (choice in ('una', 'varias')),
  constraint product_component_groups_status check (status in ('activo', 'retirado'))
);
comment on table public.product_component_groups is
  'Punto 46: grupos de elección de un producto (declarados por el distribuidor; Mobau no certifica compatibilidad).';

create table public.product_component_options (
  id                    uuid primary key default gen_random_uuid(),
  group_id              uuid not null references public.product_component_groups (id) on delete cascade,
  code                  text not null,
  kind                  text not null,
  component_product_id  text references public.products (id) on delete restrict,
  component_finish_code text,
  setting_label         text,
  supply                text,
  quantity              numeric(10,3),
  quantity_mode         text,
  attributes            jsonb not null default '[]'::jsonb,
  status                text not null default 'activo',
  sort_order            integer not null default 0,
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now(),
  constraint product_component_options_code_unique unique (group_id, code),
  constraint product_component_options_code check (code = btrim(code) and char_length(code) between 1 and 40),
  constraint product_component_options_kind check (kind in ('componente', 'ajuste')),
  constraint product_component_options_supply check (supply is null or supply in ('incluido', 'aparte')),
  constraint product_component_options_quantity check (quantity is null or quantity > 0),
  constraint product_component_options_quantity_mode check (quantity_mode is null or quantity_mode in ('fija', 'a_calcular')),
  constraint product_component_options_status check (status in ('activo', 'retirado')),
  constraint product_component_options_texts check (
    (setting_label is null or (setting_label = btrim(setting_label) and char_length(setting_label) between 1 and 80))
    and (component_finish_code is null or (component_finish_code = btrim(component_finish_code) and char_length(component_finish_code) between 1 and 20))),
  constraint product_component_options_attributes check (jsonb_typeof(attributes) = 'array' and jsonb_array_length(attributes) <= 8),
  -- componente: producto, suministro y cantidad (fija o a calcular); ajuste: solo su etiqueta.
  constraint product_component_options_shape check (
    (kind = 'componente' and component_product_id is not null and setting_label is null and supply is not null
       and ((quantity_mode = 'fija' and quantity is not null) or (quantity_mode = 'a_calcular' and quantity is null)))
    or (kind = 'ajuste' and component_product_id is null and component_finish_code is null and setting_label is not null
       and supply is null and quantity is null and quantity_mode is null))
);
comment on table public.product_component_options is
  'Punto 46: opciones de un grupo. componente: otro producto del mismo distribuidor (cantidad por unidad del padre; suministro propio de esta relación). ajuste: valor del propio artículo.';
comment on column public.product_component_options.quantity is
  'Cantidad por cada unidad del producto padre. Nula si quantity_mode = a_calcular (la calcula el distribuidor).';

alter table public.product_component_groups add constraint product_component_groups_depends_fk
  foreign key (depends_on_option_id) references public.product_component_options (id);

create index product_component_groups_product_idx on public.product_component_groups (product_id);
create index product_component_groups_depends_idx on public.product_component_groups (depends_on_option_id) where depends_on_option_id is not null;
create index product_component_options_group_idx on public.product_component_options (group_id);
create index product_component_options_component_idx on public.product_component_options (component_product_id) where component_product_id is not null;

create trigger trg_product_component_groups_updated_at before update on public.product_component_groups
  for each row execute function public.set_updated_at();
create trigger trg_product_component_options_updated_at before update on public.product_component_options
  for each row execute function public.set_updated_at();

-- 3. Integridad estructural (estado final de la transacción)
create function mobau_private.component_structure_violations() returns text
  language plpgsql stable security definer set search_path = '' as $$
declare
  v text;
begin
  -- 3a. Opciones de componente activas: mismo distribuidor, clasificado como componente, no el propio producto.
  select string_agg(x.msg, '; ') into v from (
    select pg_catalog.format('opción %s del grupo %s: %s', o.code, g.code,
             case when c.id = g.product_id then 'el componente no puede ser el propio producto'
                  when c.distributor_id <> p.distributor_id then 'el componente es de otro distribuidor'
                  when c.catalog_role not in ('componente', 'ambos') then 'el artículo no está clasificado como componente' end) as msg
      from public.product_component_options o
      join public.product_component_groups g on g.id = o.group_id
      join public.products p on p.id = g.product_id
      join public.products c on c.id = o.component_product_id
     where o.kind = 'componente' and o.status = 'activo' and g.status = 'activo'
       and (c.id = g.product_id or c.distributor_id <> p.distributor_id or c.catalog_role not in ('componente', 'ambos'))) x;
  if v is not null then return v; end if;

  -- 3b. Características informativas: lista de {label, value} de texto.
  select string_agg(pg_catalog.format('opción %s: características no válidas', o.code), '; ') into v
    from public.product_component_options o
   where exists (select 1 from pg_catalog.jsonb_array_elements(o.attributes) e
                  where case when pg_catalog.jsonb_typeof(e) <> 'object' then true
                             else (select count(*) from pg_catalog.jsonb_object_keys(e)) <> 2
                                  or pg_catalog.jsonb_typeof(e -> 'label') is distinct from 'string'
                                  or pg_catalog.jsonb_typeof(e -> 'value') is distinct from 'string'
                                  or pg_catalog.char_length(pg_catalog.btrim(e ->> 'label')) not between 1 and 60
                                  or pg_catalog.char_length(pg_catalog.btrim(e ->> 'value')) not between 1 and 120 end);
  if v is not null then return v; end if;

  -- 3c. Dependencias: de una opción activa de OTRO grupo del MISMO producto.
  select string_agg(pg_catalog.format('grupo %s: depende de una opción no válida', g.code), '; ') into v
    from public.product_component_groups g
    join public.product_component_options o on o.id = g.depends_on_option_id
    join public.product_component_groups og on og.id = o.group_id
   where g.status = 'activo'
     and (og.product_id <> g.product_id or og.id = g.id or o.status <> 'activo' or og.status <> 'activo');
  if v is not null then return v; end if;

  -- 3d. Sin ciclos entre dependencias de grupos.
  with recursive dep as (
    select g.id as grp, og.id as needs
      from public.product_component_groups g
      join public.product_component_options o on o.id = g.depends_on_option_id
      join public.product_component_groups og on og.id = o.group_id
     where g.status = 'activo'
  ), walk as (
    select d.grp as root, d.needs as node, array[d.grp, d.needs] as path, d.needs = d.grp as cyc from dep d
    union all
    select w.root, d.needs, w.path || d.needs, d.needs = any (w.path)
      from walk w join dep d on d.grp = w.node
     where not w.cyc and pg_catalog.cardinality(w.path) < 50
  )
  select string_agg(distinct pg_catalog.format('grupo %s: dependencia circular', g.code), '; ') into v
    from walk w join public.product_component_groups g on g.id = w.root where w.cyc;
  if v is not null then return v; end if;

  -- 3e. Grupo necesario activo con al menos una opción activa.
  select string_agg(pg_catalog.format('grupo necesario %s sin opciones activas', g.code), '; ') into v
    from public.product_component_groups g
   where g.status = 'activo' and g.requirement = 'necesario'
     and not exists (select 1 from public.product_component_options o where o.group_id = g.id and o.status = 'activo');
  if v is not null then return v; end if;

  -- 3f. Niveles: como máximo principal → componente → subcomponente
  --     (2 relaciones encadenadas) y sin ciclos. Se rechaza; nunca se trunca.
  with recursive e as (
    select distinct g.product_id as src, o.component_product_id as dst
      from public.product_component_groups g
      join public.product_component_options o on o.group_id = g.id
     where g.status = 'activo' and o.status = 'activo' and o.kind = 'componente'
  ), walk as (
    select e.src as root, e.dst as node, 1 as depth, array[e.src, e.dst] as path, e.src = e.dst as cyc from e
    union all
    select w.root, e.dst, w.depth + 1, w.path || e.dst, e.dst = any (w.path)
      from walk w join e on e.src = w.node
     where not w.cyc and w.depth < 3
  )
  select string_agg(distinct case when w.cyc then pg_catalog.format('ciclo de componentes desde %s', w.root)
                                   else pg_catalog.format('más de tres niveles desde %s', w.root) end, '; ') into v
    from walk w where w.cyc or w.depth >= 3;
  return v;
end $$;

create function mobau_private.component_structure_check() returns trigger
  language plpgsql security definer set search_path = '' as $$
declare
  v text;
begin
  -- El acabado elegido se comprueba al escribir la opción (después puede
  -- retirarse del componente: eso se informa al mostrar, no bloquea).
  if tg_table_name = 'product_component_options' and tg_op <> 'DELETE'
     and new.kind = 'componente' and new.status = 'activo' and new.component_finish_code is not null
     and not exists (select 1 from public.product_finishes f
                      where f.product_id = new.component_product_id and f.code = new.component_finish_code) then
    raise exception 'Componentes: el acabado % no existe en el artículo %.', new.component_finish_code, new.component_product_id
      using errcode = '23514';
  end if;
  v := mobau_private.component_structure_violations();
  if v is not null then
    raise exception 'Componentes: %.', v using errcode = '23514';
  end if;
  return null;
end $$;
revoke all on function mobau_private.component_structure_violations() from public, anon, authenticated;
revoke all on function mobau_private.component_structure_check() from public, anon, authenticated;

create constraint trigger trg_product_component_groups_check
  after insert or update or delete on public.product_component_groups
  deferrable initially deferred for each row execute function mobau_private.component_structure_check();
create constraint trigger trg_product_component_options_check
  after insert or update or delete on public.product_component_options
  deferrable initially deferred for each row execute function mobau_private.component_structure_check();
create constraint trigger trg_products_component_role_check
  after update of catalog_role, distributor_id on public.products
  deferrable initially deferred for each row execute function mobau_private.component_structure_check();

-- 4. RLS y permisos: solo lectura; sin escritura directa.
alter table public.product_component_groups enable row level security;
alter table public.product_component_options enable row level security;

create policy product_component_groups_select_public on public.product_component_groups
  for select to anon, authenticated
  using (status = 'activo' and (select public.catalog_product_visible(product_id)));
create policy product_component_groups_select_own on public.product_component_groups
  for select to authenticated
  using (exists (select 1 from public.products p
                  where p.id = product_component_groups.product_id
                    and p.distributor_id = (select public.my_verified_distributor_id())));
create policy product_component_groups_select_mobau on public.product_component_groups
  for select to authenticated using ((select public.is_mobau_admin()));

create policy product_component_options_select_public on public.product_component_options
  for select to anon, authenticated
  using (status = 'activo'
         and exists (select 1 from public.product_component_groups g
                      where g.id = product_component_options.group_id and g.status = 'activo'
                        and (select public.catalog_product_visible(g.product_id)))
         and (kind = 'ajuste' or (select public.catalog_product_visible(component_product_id))));
create policy product_component_options_select_own on public.product_component_options
  for select to authenticated
  using (exists (select 1 from public.product_component_groups g join public.products p on p.id = g.product_id
                  where g.id = product_component_options.group_id
                    and p.distributor_id = (select public.my_verified_distributor_id())));
create policy product_component_options_select_mobau on public.product_component_options
  for select to authenticated using ((select public.is_mobau_admin()));

revoke all on table public.product_component_groups, public.product_component_options from public, anon, authenticated;
grant select on table public.product_component_groups, public.product_component_options to anon, authenticated;

-- 5. Lectura pública
create view public.catalog_component_groups with (security_invoker = true, security_barrier = true) as
  select g.id, g.product_id, g.code, g.label, g.requirement, g.choice, g.depends_on_option_id, g.sort_order,
         (select count(*) from public.product_component_options o
           where o.group_id = g.id and o.status = 'activo'
             and (o.kind = 'ajuste' or public.catalog_product_visible(o.component_product_id)))::integer as available_options
    from public.product_component_groups g
   where g.status = 'activo' and public.catalog_product_visible(g.product_id);
comment on view public.catalog_component_groups is
  'Punto 46: grupos activos de productos publicados. available_options = 0 indica un requisito sin opciones disponibles.';

create view public.catalog_component_options with (security_invoker = true, security_barrier = true) as
  select o.id, o.group_id, g.product_id, o.code, o.kind, o.component_product_id, o.component_finish_code, o.setting_label,
         o.supply, o.quantity, o.quantity_mode, o.attributes, o.sort_order
    from public.product_component_options o
    join public.product_component_groups g on g.id = o.group_id
   where o.status = 'activo' and g.status = 'activo' and public.catalog_product_visible(g.product_id)
     and (o.kind = 'ajuste' or public.catalog_product_visible(o.component_product_id));

revoke all on table public.catalog_component_groups, public.catalog_component_options from public, anon, authenticated;
grant select on table public.catalog_component_groups, public.catalog_component_options to anon, authenticated;

-- 6. catalog_products + catalog_role (misma definición; columna añadida al final)
create or replace view public.catalog_products with (security_invoker = true, security_barrier = true) as
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
    p.color_temperature,
    p.catalog_role
   FROM (products p
     LEFT JOIN product_assets cov ON (((cov.id = p.cover_asset_id) AND (cov.status = 'aprobado'::text))))
  WHERE ((p.publication_status = 'published'::text) AND (p.status = 'active'::text));

-- 7. Comprobaciones finales
DO $$
begin
  if (select coalesce(array_to_string(reloptions, ','), '') || '|' || coalesce(relacl::text, '') from pg_class where oid = 'public.catalog_products'::regclass)
     <> 'security_invoker=true,security_barrier=true|{postgres=arwdDxtm/postgres,anon=r/postgres,authenticated=r/postgres}'
     or (select count(*) from information_schema.columns where table_schema = 'public' and table_name = 'catalog_products') <> 30
     or md5(coalesce((select string_agg((to_jsonb(c) - 'catalog_role')::text, '|' order by c.id) from public.catalog_products c), ''))
        <> current_setting('mobau.p4601_catalogo') then
    raise exception '46-01: catalog_products cambió más allá de la columna nueva';
  end if;
  if md5(coalesce((select string_agg((to_jsonb(p) - 'catalog_role')::text, '|' order by p.id) from public.products p), ''))
       <> current_setting('mobau.p4601_productos')
     or exists (select 1 from public.products where catalog_role <> 'principal') then
    raise exception '46-01: los productos cambiaron o no quedaron como principal';
  end if;
  if not has_column_privilege('anon', 'public.products', 'catalog_role', 'SELECT')
     or not has_column_privilege('authenticated', 'public.products', 'catalog_role', 'SELECT')
     or has_column_privilege('authenticated', 'public.products', 'catalog_role', 'UPDATE') then
    raise exception '46-01: permisos de catalog_role no esperados';
  end if;
  if not (select relrowsecurity from pg_class where oid = 'public.product_component_groups'::regclass)
     or not (select relrowsecurity from pg_class where oid = 'public.product_component_options'::regclass)
     or (select count(*) from pg_policies where schemaname = 'public' and tablename in ('product_component_groups', 'product_component_options')) <> 6 then
    raise exception '46-01: RLS no quedó como se esperaba';
  end if;
  if exists (select 1 from (values ('public.product_component_groups'), ('public.product_component_options'),
                                   ('public.catalog_component_groups'), ('public.catalog_component_options')) t(rel),
                           (values ('anon'), ('authenticated')) r(role),
                           (values ('INSERT'), ('UPDATE'), ('DELETE'), ('TRUNCATE'), ('REFERENCES'), ('TRIGGER')) pr(priv)
              where has_table_privilege(r.role, t.rel, pr.priv))
     or not has_table_privilege('anon', 'public.catalog_component_groups', 'SELECT')
     or not has_table_privilege('anon', 'public.catalog_component_options', 'SELECT') then
    raise exception '46-01: permisos de tablas o vistas no esperados';
  end if;
  if (select count(*) from pg_class where oid in ('public.catalog_component_groups'::regclass, 'public.catalog_component_options'::regclass)
        and reloptions @> array['security_invoker=true', 'security_barrier=true']) <> 2 then
    raise exception '46-01: opciones de las vistas nuevas no esperadas';
  end if;
  if (select count(*) from pg_trigger where not tgisinternal and tgdeferrable and tgname in
        ('trg_product_component_groups_check', 'trg_product_component_options_check', 'trg_products_component_role_check')) <> 3 then
    raise exception '46-01: faltan las comprobaciones diferidas';
  end if;
end $$;

COMMIT;
