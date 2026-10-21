-- ============================================================
-- PROPUESTA NO EJECUTADA (44-05 · recuperación) — no ejecutar sin aprobación explícita
-- ============================================================
-- Deshace 44-05: devuelve las dos funciones de archivos a su texto anterior
-- (MD5 comprobado) y quita la columna finish_code con su clave ajena. Si hay
-- fotos con acabado, antes las copia a mobau_private.r44e_assets. Se detiene
-- si hay propuestas abiertas con «finish» en sus archivos.
-- Si se aplica, se registra como migración NUEVA tras confirmar su COMMIT.
-- ============================================================

BEGIN;

create function pg_temp.r44(t text, a text, b text) returns text language plpgsql as $$
begin
  if (length(t) - length(replace(t, a, ''))) <> length(a) then
    raise exception '44-05 R: el fragmento no aparece exactamente una vez: %', left(a, 80);
  end if;
  return replace(t, a, b);
end $$;

DO $$
begin
  if current_user <> 'postgres' then
    raise exception '44-05 R: ejecutar como postgres';
  end if;
  if not exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'product_assets' and column_name = 'finish_code') then
    raise exception '44-05 R: 44-05 no está aplicada';
  end if;
  if exists (select 1 from public.product_proposals p, pg_catalog.jsonb_array_elements(coalesce(p.proposed_media -> 'assets', '[]'::jsonb)) e
              where p.status in ('draft', 'submitted', 'changes_requested') and e ? 'finish') then
    raise exception '44-05 R: hay propuestas abiertas con acabados asignados a fotos' using errcode = 'MB445';
  end if;
  if exists (select 1 from public.product_assets where finish_code is not null) then
    create table mobau_private.r44e_assets as
      select id, product_id, finish_code from public.product_assets where finish_code is not null;
    revoke all on table mobau_private.r44e_assets from public, anon, authenticated;
  end if;
end $$;

DO $$
declare
  d text;
begin
  d := pg_get_functiondef('public.validate_proposal_media()'::regprocedure);
  d := pg_temp.r44(d, $a$where x not in ('id', 'label', 'finish'))$a$, $a$where x not in ('id', 'label'))$a$);
  d := pg_temp.r44(d, $a$  -- Acabado de cada foto (44-05): uno de los acabados de la propuesta, solo en fotos.
  for v_item in select e from pg_catalog.jsonb_array_elements(v_assets) e loop
    if v_item ? 'finish' and pg_catalog.jsonb_typeof(v_item -> 'finish') <> 'null' then
      if pg_catalog.jsonb_typeof(v_item -> 'finish') <> 'string'
         or not exists (select 1 from pg_catalog.jsonb_array_elements(v_finishes) f where f ->> 'code' = v_item ->> 'finish')
         or not exists (select 1 from public.product_assets a where a.id = (v_item ->> 'id')::uuid and a.kind = 'foto') then
        raise exception 'El acabado asignado a una foto no es válido: elige uno de los acabados del producto o «Sin asignar».' using errcode = '23514';
      end if;
    end if;
  end loop;

$a$, '');
  execute d;

  d := pg_get_functiondef('public.apply_proposal_media()'::regprocedure);
  d := pg_temp.r44(d, $a$  -- Acabado de cada foto (44-05), una vez guardados los acabados: el de la
  -- propuesta o ninguno (la lista es completa).
  update public.product_assets a
     set finish_code = nullif(t.e ->> 'finish', '')
    from pg_catalog.jsonb_array_elements(coalesce(m -> 'assets', '[]'::jsonb)) as t(e)
   where a.id = (t.e ->> 'id')::uuid and a.product_id = v_product and a.kind = 'foto';

$a$, '');
  execute d;
end $$;

drop index public.product_assets_finish_idx;
alter table public.product_assets
  drop constraint product_assets_finish_fk,
  drop constraint product_assets_finish_only_photos,
  drop column finish_code;

DO $$
begin
  if (select md5(prosrc) from pg_proc where oid = 'public.validate_proposal_media()'::regprocedure) <> '0ca7b91787c2bfcd506c320648769358'
     or (select md5(prosrc) from pg_proc where oid = 'public.apply_proposal_media()'::regprocedure) <> 'a30169702ad6197a97d37ca3c54ca8ee' then
    raise exception '44-05 R: las funciones no volvieron a su estado';
  end if;
end $$;

COMMIT;
