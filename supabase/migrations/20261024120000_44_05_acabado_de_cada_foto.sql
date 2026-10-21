-- ============================================================
-- PROPUESTA NO EJECUTADA (44-05 · acabado de cada foto) — no ejecutar sin aprobación explícita
-- ============================================================
-- Punto 44 · cada foto de la galería puede asociarse a un acabado (o quedar
-- sin asignar, como imagen de referencia). Un acabado puede tener varias
-- fotos; una foto, como mucho un acabado.
--   * Propuesta: en proposed_media.assets cada foto puede llevar «finish»
--     (código de uno de los acabados de la misma propuesta) o no llevarlo.
--     El manifiesto es completo: al aprobar se reescriben a la vez acabados y
--     asociaciones, así que cambiar el código de un acabado o quitarlo nunca
--     deja una foto apuntando a un acabado que ya no existe.
--   * product_assets.finish_code: el acabado aprobado de cada foto. Clave
--     ajena compuesta a product_finishes (product_id, code): ON UPDATE
--     CASCADE y ON DELETE SET NULL (finish_code) (la foto queda sin asignar,
--     nunca se reasigna). Solo fotos.
--   * validate_proposal_media (trigger 35): admite «finish», que debe ser
--     uno de los códigos de la propuesta y solo en fotos. No exige recorte.
--   * apply_proposal_media (trigger 60): al aprobar, tras guardar los
--     acabados, fija el acabado de cada foto de la lista (o lo deja vacío).
-- La web no puede escribir finish_code (sin permiso de columna); solo lo
-- escribe la aprobación. No toca datos existentes (todas las fotos quedan
-- sin asignar), la portada ni el orden. Ejecutar completo.
-- ============================================================

BEGIN;

create function pg_temp.r44(t text, a text, b text) returns text language plpgsql as $$
begin
  if (length(t) - length(replace(t, a, ''))) <> length(a) then
    raise exception '44-05: el fragmento no aparece exactamente una vez: %', left(a, 80);
  end if;
  return replace(t, a, b);
end $$;

DO $$
begin
  if current_user <> 'postgres' then
    raise exception '44-05: ejecutar como postgres';
  end if;
  if not exists (select 1 from supabase_migrations.schema_migrations where version = '20261023120100')
     or exists (select 1 from supabase_migrations.schema_migrations where version = '20261024120000') then
    raise exception '44-05: el registro de migraciones no es el esperado (44-04 registrada y 44-05 sin registrar)';
  end if;
  if exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'product_assets' and column_name = 'finish_code') then
    raise exception '44-05: ya existe la columna finish_code';
  end if;
  if (select md5(prosrc) from pg_proc where oid = 'public.validate_proposal_media()'::regprocedure) <> '0ca7b91787c2bfcd506c320648769358'
     or (select md5(prosrc) from pg_proc where oid = 'public.apply_proposal_media()'::regprocedure) <> 'a30169702ad6197a97d37ca3c54ca8ee' then
    raise exception '44-05: las funciones de archivos no son las esperadas';
  end if;
  perform set_config('mobau.p44e_datos', md5(
      coalesce((select string_agg(id::text || ':' || coalesce(product_id, '-') || ':' || status || ':' || sort_order || ':' || coalesce(label, '-'), '|' order by id) from public.product_assets), '')
   || coalesce((select string_agg(id || ':' || coalesce(publication_status, '-') || ':' || updated_at::text || ':' || coalesce(cover_asset_id::text, '-'), '|' order by id) from public.products), '')
   || coalesce((select string_agg(product_id || ':' || code || ':' || name || ':' || is_default, '|' order by product_id, code) from public.product_finishes), '')), true);
end $$;

-- ---------- 1. Columna y clave ajena ----------
alter table public.product_assets
  add column finish_code text,
  add constraint product_assets_finish_only_photos check (finish_code is null or kind = 'foto'),
  add constraint product_assets_finish_fk foreign key (product_id, finish_code)
    references public.product_finishes (product_id, code)
    on update cascade on delete set null (finish_code);
create index product_assets_finish_idx on public.product_assets (product_id, finish_code) where finish_code is not null;

-- ---------- 2. Funciones: sustituciones exactas ----------
DO $$
declare
  d text;
begin
  d := pg_get_functiondef('public.validate_proposal_media()'::regprocedure);
  d := pg_temp.r44(d, $a$where x not in ('id', 'label'))$a$,
                      $a$where x not in ('id', 'label', 'finish'))$a$);
  d := pg_temp.r44(d, $a$  -- Al enviar
  if v_entering then$a$,
                      $a$  -- Acabado de cada foto (44-05): uno de los acabados de la propuesta, solo en fotos.
  for v_item in select e from pg_catalog.jsonb_array_elements(v_assets) e loop
    if v_item ? 'finish' and pg_catalog.jsonb_typeof(v_item -> 'finish') <> 'null' then
      if pg_catalog.jsonb_typeof(v_item -> 'finish') <> 'string'
         or not exists (select 1 from pg_catalog.jsonb_array_elements(v_finishes) f where f ->> 'code' = v_item ->> 'finish')
         or not exists (select 1 from public.product_assets a where a.id = (v_item ->> 'id')::uuid and a.kind = 'foto') then
        raise exception 'El acabado asignado a una foto no es válido: elige uno de los acabados del producto o «Sin asignar».' using errcode = '23514';
      end if;
    end if;
  end loop;

  -- Al enviar
  if v_entering then$a$);
  execute d;

  d := pg_get_functiondef('public.apply_proposal_media()'::regprocedure);
  d := pg_temp.r44(d, $a$  select pg_catalog.left(pg_catalog.string_agg(t.f ->> 'name', ', ' order by t.o), 200) into v_names$a$,
                      $a$  -- Acabado de cada foto (44-05), una vez guardados los acabados: el de la
  -- propuesta o ninguno (la lista es completa).
  update public.product_assets a
     set finish_code = nullif(t.e ->> 'finish', '')
    from pg_catalog.jsonb_array_elements(coalesce(m -> 'assets', '[]'::jsonb)) as t(e)
   where a.id = (t.e ->> 'id')::uuid and a.product_id = v_product and a.kind = 'foto';

  select pg_catalog.left(pg_catalog.string_agg(t.f ->> 'name', ', ' order by t.o), 200) into v_names$a$);
  execute d;
end $$;

-- ---------- 3. Comprobación final ----------
DO $$
begin
  if strpos((select prosrc from pg_proc where oid = 'public.validate_proposal_media()'::regprocedure), $a$('id', 'label', 'finish')$a$) = 0
     or strpos((select prosrc from pg_proc where oid = 'public.validate_proposal_media()'::regprocedure), 'El acabado asignado a una foto no es válido') = 0
     or strpos((select prosrc from pg_proc where oid = 'public.apply_proposal_media()'::regprocedure), 'set finish_code = nullif') = 0 then
    raise exception '44-05: las funciones no quedaron como se esperaba';
  end if;
  if not (select prosecdef from pg_proc where oid = 'public.apply_proposal_media()'::regprocedure)
     or has_function_privilege('authenticated', 'public.apply_proposal_media()', 'EXECUTE')
     or has_column_privilege('authenticated', 'public.product_assets', 'finish_code', 'INSERT')
     or has_column_privilege('authenticated', 'public.product_assets', 'finish_code', 'UPDATE')
     or not has_column_privilege('anon', 'public.product_assets', 'finish_code', 'SELECT') then
    raise exception '44-05: permisos no esperados';
  end if;
  if (select pg_get_constraintdef(oid) from pg_constraint where conname = 'product_assets_finish_fk')
     not like '%ON UPDATE CASCADE ON DELETE SET NULL (finish_code)%' then
    raise exception '44-05: la clave ajena no quedó como se esperaba';
  end if;
  if exists (select 1 from public.product_assets where finish_code is not null)
     or md5(
      coalesce((select string_agg(id::text || ':' || coalesce(product_id, '-') || ':' || status || ':' || sort_order || ':' || coalesce(label, '-'), '|' order by id) from public.product_assets), '')
   || coalesce((select string_agg(id || ':' || coalesce(publication_status, '-') || ':' || updated_at::text || ':' || coalesce(cover_asset_id::text, '-'), '|' order by id) from public.products), '')
   || coalesce((select string_agg(product_id || ':' || code || ':' || name || ':' || is_default, '|' order by product_id, code) from public.product_finishes), ''))
     <> current_setting('mobau.p44e_datos') then
    raise exception '44-05: ha cambiado algún dato existente';
  end if;
end $$;

COMMIT;
