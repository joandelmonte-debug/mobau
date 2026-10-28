-- ============================================================
-- RECUPERACIÓN de 48-02 (fecha de incorporación al catálogo) — no ejecutar sin aprobación explícita
-- ============================================================
-- Deshace 48-02 en este orden: disparador y función, vista sin la columna, columna (y su CHECK y permiso) y la exclusión añadida a
-- moderate_product_proposal (vuelve al md5 que dejó 48-01). La vista se recrea con opciones y permisos originales.
-- Consecuencia: las fechas de incorporación renovadas desde la aplicación de 48-02 se pierden; el orden vuelve a depender de created_at.
-- Después de ejecutar y confirmar el COMMIT, eliminar la fila 20261111130000 de supabase_migrations.schema_migrations (si se había registrado).
-- ============================================================

BEGIN;

create function pg_temp.unpatch_fn(p_fn regprocedure, p_md5_expected text, p_old text[], p_new text[]) returns boolean
  language plpgsql as $f$
declare
  v_def text := pg_get_functiondef(p_fn);
  v_n int;
  i int;
begin
  for i in 1 .. array_length(p_old, 1) loop
    v_n := (length(v_def) - length(replace(v_def, p_old[i], ''))) / length(p_old[i]);
    if v_n <> 1 then
      raise exception '48-02 recuperación: el trozo % de % aparece % veces (debe ser 1): la función no es la de 48-02', i, p_fn, v_n;
    end if;
    v_def := replace(v_def, p_old[i], p_new[i]);
  end loop;
  execute v_def;
  if (select md5(prosrc) from pg_proc where oid = p_fn) <> p_md5_expected then
    raise exception '48-02 recuperación: % no quedó con el md5 de 48-01', p_fn;
  end if;
  return true;
end $f$;

DO $$
begin
  if current_user <> 'postgres' then raise exception '48-02 recuperación: ejecutar como postgres'; end if;
  if not exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'products' and column_name = 'catalog_entered_at') then
    raise exception '48-02 recuperación: catalog_entered_at no existe (¿ya recuperada?)';
  end if;
end $$;

drop trigger trg_products_catalog_entered_at on public.products;
drop function mobau_private.products_catalog_entered_at();

DO $$
declare
  v_def text := pg_get_viewdef('public.catalog_products'::regclass, true);
  v_new constant text := E'    p.catalog_role,\n    p.catalog_entered_at\n   FROM products p';
  v_n int := (length(v_def) - length(replace(v_def, v_new, ''))) / length(v_new);
begin
  if v_n <> 1 then raise exception '48-02 recuperación: la definición de catalog_products no es la de 48-02 (% coincidencias)', v_n; end if;
  v_def := replace(v_def, v_new, E'    p.catalog_role\n   FROM products p');
  drop view public.catalog_products;
  execute 'create view public.catalog_products with (security_invoker = true, security_barrier = true) as ' || v_def;
  -- Una vista nueva recibe por defecto todos los permisos para anon, authenticated y service_role: se dejan solo los originales.
  revoke all on table public.catalog_products from public, anon, authenticated, service_role;
  grant select on table public.catalog_products to anon, authenticated;
end $$;

alter table public.products drop constraint products_catalog_entered_published_check;
alter table public.products drop column catalog_entered_at;

select pg_temp.unpatch_fn('public.moderate_product_proposal(uuid,text,text,integer)'::regprocedure, '34b24ec9396e5c143d5d639a1bad8d10',
  array[
    $r$array['retired_at', 'retired_by', 'retired_reason', 'trashed_at', 'trashed_by', 'trash_from', 'purge_after', 'catalog_entered_at'];$r$
  ],
  array[
    $r$array['retired_at', 'retired_by', 'retired_reason', 'trashed_at', 'trashed_by', 'trash_from', 'purge_after'];$r$
  ]);

DO $$
begin
  if exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'products' and column_name = 'catalog_entered_at')
     or (select coalesce(array_to_string(reloptions, ','), '') || '|' || relacl::text from pg_class where oid = 'public.catalog_products'::regclass)
        <> 'security_invoker=true,security_barrier=true|{postgres=arwdDxtm/postgres,anon=r/postgres,authenticated=r/postgres}'
     or (select count(*) from information_schema.columns where table_schema = 'public' and table_name = 'catalog_products') <> 30
     or (select tgenabled from pg_trigger where tgrelid = 'public.products'::regclass and tgname = 'trg_products_updated_at') <> 'O' then
    raise exception '48-02 recuperación: el estado final no es el esperado';
  end if;
end $$;

COMMIT;
