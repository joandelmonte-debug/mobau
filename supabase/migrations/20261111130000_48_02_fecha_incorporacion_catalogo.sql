-- ============================================================
-- PROPUESTA NO EJECUTADA (48-02 · fecha de incorporación al catálogo) — no ejecutar sin aprobación explícita
-- ============================================================
-- Requisito: un producto republicado tras una retirada debe aparecer AL FINAL de «Orden del catálogo» y como reciente en «Más
-- recientes»; editar un producto ya publicado no cambia su posición; created_at no se toca.
--
-- Qué se añade:
--   1. products.catalog_entered_at timestamptz: momento de la PUBLICACIÓN EFECTIVA (no de la creación de la fila: products.publication_status
--      tiene DEFAULT 'draft' y authenticated no puede insertar/actualizar products; las filas nacen publicadas al aprobar una propuesta
--      «create» o por una carga de servicio, y un borrador puede publicarse más tarde).
--   2. Disparador BEFORE INSERT OR UPDATE (mobau_private.products_catalog_entered_at), única vía que la escribe:
--        · INSERT publicado: coalesce(valor dado, now()); INSERT no publicado: se conserva lo dado (null).
--        · UPDATE que PASA a 'published' desde otro estado (primera publicación o reincorporación tras retirada): now().
--        · cualquier otro UPDATE (editar un publicado aprobado, retirar, papelera, etc.): conserva el valor anterior,
--          aunque la sentencia intente cambiarlo.
--      Reaprobar una solicitud ya aprobada no vuelve a pasar por aquí: moderate_product_proposal exige status = 'submitted'.
--      Corregir una fecha a mano exige desactivar el disparador (decisión consciente de quien opera).
--   3. Relleno de los productos existentes: catalog_entered_at = created_at para published y archived (orden actual sin cambios). Se hace
--      SIN renovar updated_at (se desactiva solo trg_products_updated_at durante el relleno): la compatibilidad con copias antiguas de
--      48-01 y las solicitudes pendientes dependen de updated_at. Se comprueba al final que ningún updated_at cambió.
--   4. CHECK: un producto publicado siempre tiene fecha de incorporación.
--   5. catalog_products añade catalog_entered_at AL FINAL (definición, opciones y permisos conservados) y GRANT SELECT de la columna a
--      anon/authenticated (la vista es security_invoker).
--   6. moderate_product_proposal(), rama republish: catalog_entered_at se EXCLUYE de la comparación igual que las 7 columnas de ciclo de
--      vida (retired_*, trashed_*, trash_from, purge_after). Motivo: no entra en la copia del envío (la escribe la propia publicación; no puede
--      cambiar legítimamente mientras el producto está retirado) y comparar una columna que las copias anteriores no tienen reproduciría el
--      desfase corregido en 48-01. Las solicitudes enviadas antes de 48-02 (copias de 26 o 29 claves) se aprueban igual después.
-- No cambia: created_at, la copia del envío (snapshot_product_on_submit), la rama update/create, permisos de escritura.
-- Requiere 48-01 aplicada (la sustitución parte del md5 de moderate_product_proposal que deja 48-01).
-- Recuperación: supabase/rollback/20261111130000_48_02_fecha_incorporacion_catalogo.rollback.sql (la columna se elimina: las fechas
-- renovadas desde entonces se pierden y el orden vuelve a depender de created_at).
-- Si se aplica, se registra como migración NUEVA tras confirmar su COMMIT.
-- ============================================================

BEGIN;

create function pg_temp.patch_fn(p_fn regprocedure, p_md5_before text, p_old text[], p_new text[]) returns text
  language plpgsql as $f$
declare
  v_def text := pg_get_functiondef(p_fn);
  v_n int;
  i int;
begin
  if (select md5(prosrc) from pg_proc where oid = p_fn) is distinct from p_md5_before then
    raise exception '48-02: % no tiene el md5 esperado', p_fn;
  end if;
  for i in 1 .. array_length(p_old, 1) loop
    v_n := (length(v_def) - length(replace(v_def, p_old[i], ''))) / length(p_old[i]);
    if v_n <> 1 then
      raise exception '48-02: el trozo % de % aparece % veces (debe ser 1)', i, p_fn, v_n;
    end if;
    v_def := replace(v_def, p_old[i], p_new[i]);
  end loop;
  execute v_def;
  return (select md5(prosrc) from pg_proc where oid = p_fn);
end $f$;

DO $$
declare
  v_reg int;
begin
  if current_user <> 'postgres' then raise exception '48-02: ejecutar como postgres'; end if;
  if to_regclass('supabase_migrations.schema_migrations') is not null then
    execute $q$select count(*) from supabase_migrations.schema_migrations where version = '20261111120000'$q$ into v_reg;
    if v_reg <> 1 then raise exception '48-02: 48-01 no está registrada'; end if;
    execute $q$select count(*) from supabase_migrations.schema_migrations where version = '20261111130000'$q$ into v_reg;
    if v_reg <> 0 then raise exception '48-02: ya está registrada'; end if;
  end if;
  if (select md5(prosrc) from pg_proc where oid = 'public.moderate_product_proposal(uuid,text,text,integer)'::regprocedure) <> '34b24ec9396e5c143d5d639a1bad8d10'
     or (select md5(prosrc) from pg_proc where oid = 'public.snapshot_product_on_submit()'::regprocedure) <> '70c7ca25a047550c401a2e76ff1e2d52' then
    raise exception '48-02: las funciones no son las que deja 48-01';
  end if;
  if exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'products' and column_name = 'catalog_entered_at') then
    raise exception '48-02: catalog_entered_at ya existe';
  end if;
  if (select coalesce(array_to_string(reloptions, ','), '') || '|' || relacl::text from pg_class where oid = 'public.catalog_products'::regclass)
     <> 'security_invoker=true,security_barrier=true|{postgres=arwdDxtm/postgres,anon=r/postgres,authenticated=r/postgres}' then
    raise exception '48-02: catalog_products no tiene las opciones o permisos esperados';
  end if;
  -- Huella para comprobar al final que el relleno no renovó ningún updated_at.
  perform set_config('mobau.p4802_upd', md5(coalesce((select string_agg(id || '|' || updated_at::text, ',' order by id) from public.products), '')), true);
  perform set_config('mobau.p4802_n', (select count(*) from public.products)::text, true);
end $$;

-- 1. Columna y relleno (sin renovar updated_at).
alter table public.products add column catalog_entered_at timestamptz;
comment on column public.products.catalog_entered_at is
  '48-02: momento de la publicación efectiva en el catálogo (primera publicación o última reincorporación tras una retirada). Solo la escribe el disparador trg_products_catalog_entered_at; orden del catálogo y «Más recientes». created_at no cambia.';

alter table public.products disable trigger trg_products_updated_at;
update public.products set catalog_entered_at = created_at where publication_status in ('published', 'archived');
alter table public.products enable trigger trg_products_updated_at;

alter table public.products add constraint products_catalog_entered_published_check
  check (publication_status <> 'published' or catalog_entered_at is not null);

-- 2. Disparador.
create function mobau_private.products_catalog_entered_at() returns trigger
  language plpgsql
  set search_path to ''
as $f$
begin
  if tg_op = 'INSERT' then
    if new.publication_status = 'published' then
      new.catalog_entered_at := coalesce(new.catalog_entered_at, pg_catalog.now());
    end if;
    return new;
  end if;
  if new.publication_status = 'published' and old.publication_status is distinct from 'published' then
    new.catalog_entered_at := pg_catalog.now();           -- primera publicación o reincorporación
  else
    new.catalog_entered_at := old.catalog_entered_at;     -- cualquier otro cambio la conserva
  end if;
  return new;
end $f$;
revoke all on function mobau_private.products_catalog_entered_at() from public, anon, authenticated;

create trigger trg_products_catalog_entered_at
  before insert or update on public.products
  for each row execute function mobau_private.products_catalog_entered_at();

-- 3. Lectura pública de la columna y vista (columna añadida al final).
grant select (catalog_entered_at) on table public.products to anon, authenticated;

DO $$
declare
  v_def text := pg_get_viewdef('public.catalog_products'::regclass, true);
  v_old constant text := E'    p.catalog_role\n   FROM products p';
  v_n int := (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old);
begin
  if v_n <> 1 then raise exception '48-02: la definición de catalog_products no es la esperada (% coincidencias)', v_n; end if;
  execute 'create or replace view public.catalog_products with (security_invoker = true, security_barrier = true) as '
          || replace(v_def, v_old, E'    p.catalog_role,\n    p.catalog_entered_at\n   FROM products p');
end $$;

-- 4. Comparación de la republicación: la fecha es un dato de ciclo de vida, no del producto.
select pg_temp.patch_fn('public.moderate_product_proposal(uuid,text,text,integer)'::regprocedure, '34b24ec9396e5c143d5d639a1bad8d10',
  array[
    $r$array['retired_at', 'retired_by', 'retired_reason', 'trashed_at', 'trashed_by', 'trash_from', 'purge_after'];$r$
  ],
  array[
    $r$array['retired_at', 'retired_by', 'retired_reason', 'trashed_at', 'trashed_by', 'trash_from', 'purge_after', 'catalog_entered_at'];$r$
  ]);

DO $$
begin
  if (select md5(prosrc) from pg_proc where oid = 'public.moderate_product_proposal(uuid,text,text,integer)'::regprocedure) = '34b24ec9396e5c143d5d639a1bad8d10'
     or (select prosrc from pg_proc where oid = 'public.moderate_product_proposal(uuid,text,text,integer)'::regprocedure) not like '%''purge_after'', ''catalog_entered_at''%'
     or (select md5(prosrc) from pg_proc where oid = 'public.snapshot_product_on_submit()'::regprocedure) <> '70c7ca25a047550c401a2e76ff1e2d52' then
    raise exception '48-02: las funciones no quedaron como se esperaba';
  end if;
  if (select prosecdef from pg_proc where oid = 'public.moderate_product_proposal(uuid,text,text,integer)'::regprocedure) is not true
     or has_function_privilege('anon', 'public.moderate_product_proposal(uuid,text,text,integer)', 'EXECUTE')
     or not has_function_privilege('authenticated', 'public.moderate_product_proposal(uuid,text,text,integer)', 'EXECUTE') then
    raise exception '48-02: atributos o permisos de moderate_product_proposal distintos de los esperados';
  end if;
  -- Datos: ningún updated_at cambió, mismo número de productos, orden idéntico y ninguna fecha distinta de created_at.
  if md5(coalesce((select string_agg(id || '|' || updated_at::text, ',' order by id) from public.products), '')) <> current_setting('mobau.p4802_upd')
     or (select count(*) from public.products)::text <> current_setting('mobau.p4802_n') then
    raise exception '48-02: el relleno alteró updated_at o el número de productos';
  end if;
  if exists (select 1 from public.products where publication_status in ('published', 'archived') and catalog_entered_at is distinct from created_at)
     or exists (select 1 from public.products where publication_status not in ('published', 'archived') and catalog_entered_at is not null) then
    raise exception '48-02: relleno distinto del esperado';
  end if;
  -- Vista, columnas y permisos.
  if (select coalesce(array_to_string(reloptions, ','), '') || '|' || relacl::text from pg_class where oid = 'public.catalog_products'::regclass)
     <> 'security_invoker=true,security_barrier=true|{postgres=arwdDxtm/postgres,anon=r/postgres,authenticated=r/postgres}'
     or (select column_name from information_schema.columns where table_schema = 'public' and table_name = 'catalog_products' order by ordinal_position desc limit 1) <> 'catalog_entered_at'
     or (select count(*) from information_schema.columns where table_schema = 'public' and table_name = 'catalog_products') <> 31 then
    raise exception '48-02: catalog_products no quedó como se esperaba';
  end if;
  if not has_column_privilege('anon', 'public.products', 'catalog_entered_at', 'SELECT')
     or not has_column_privilege('authenticated', 'public.products', 'catalog_entered_at', 'SELECT')
     or has_column_privilege('authenticated', 'public.products', 'catalog_entered_at', 'UPDATE')
     or has_column_privilege('authenticated', 'public.products', 'catalog_entered_at', 'INSERT')
     or has_function_privilege('authenticated', 'mobau_private.products_catalog_entered_at()', 'EXECUTE') then
    raise exception '48-02: permisos de catalog_entered_at no esperados';
  end if;
  if (select tgenabled from pg_trigger where tgrelid = 'public.products'::regclass and tgname = 'trg_products_updated_at') <> 'O'
     or (select tgenabled from pg_trigger where tgrelid = 'public.products'::regclass and tgname = 'trg_products_catalog_entered_at') <> 'O' then
    raise exception '48-02: disparadores de products no activos';
  end if;
end $$;

COMMIT;
