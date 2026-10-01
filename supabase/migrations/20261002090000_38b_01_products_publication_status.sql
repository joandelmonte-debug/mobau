-- ============================================================
-- PROPUESTA NO EJECUTADA (38-B) — no ejecutar sin aprobación explícita
-- ============================================================
-- 38-B · 01 · Estado de publicación de productos
-- ------------------------------------------------------------
-- TRANSACCIÓN ATÓMICA: todo el archivo va entre BEGIN y COMMIT y se
-- ejecuta completo, de una vez. No partirlo ni ejecutarlo por
-- fragmentos. Si cualquier sentencia falla (incluida la validación
-- DO), se revierte todo: columna, restricción, relleno, índice,
-- función, trigger y el estado de trg_products_updated_at. Si falla,
-- NO se continúa con 02, 03 ni 04.
--
-- Añade products.publication_status (draft, in_review,
-- changes_requested, published, archived) SIN eliminar
-- products.status, que pasa a ser un espejo derivado:
--   published            -> status 'active'
--   cualquier otro valor -> status 'archived'
-- Así el frontend actual (que filtra status = 'active') sigue
-- funcionando sin cambios.
--
-- Relleno explícito y único de datos existentes:
--   status 'active'   -> publication_status 'published'
--   status 'archived' -> publication_status 'archived'
-- Solo define visibilidad inicial; no afirma que los productos
-- estén completos. No toca ninguna otra columna: el trigger
-- trg_products_updated_at se pausa durante el relleno para no
-- alterar updated_at.
--
-- Trigger de espejo (trg_products_sync_legacy_status):
--   * solo se dispara en INSERT y en UPDATE OF publication_status;
--     las actualizaciones de nombre, descripción, imágenes o datos
--     técnicos no reescriben status;
--   * en un INSERT sin publication_status, el valor por defecto
--     'draft' genera status = 'archived' (oculto hasta publicarse);
--   * la moderación manual modifica SIEMPRE publication_status, nunca
--     status. Tras 38-B ningún rol de cliente puede editar status.
--     Un cambio directo de status (solo posible desde Supabase) no
--     dispara el trigger: la coherencia
--       publication_status = 'published'  <->  status = 'active'
--     se comprueba en moderacion/38b_moderacion_manual.sql.
--
-- Rollback: supabase/rollback/20261002090000_38b_01_products_publication_status.rollback.sql
-- ============================================================

BEGIN;

alter table public.products
  add column publication_status text not null default 'draft';

alter table public.products
  add constraint products_publication_status_check
  check (publication_status in ('draft', 'in_review', 'changes_requested', 'published', 'archived'));

comment on column public.products.publication_status is
  'Estado de publicación (38-B). Fuente de verdad de la visibilidad. Solo se modera desde Supabase; ningún rol de cliente puede escribirlo.';

-- Relleno explícito (sin modificar updated_at)
alter table public.products disable trigger trg_products_updated_at;
update public.products set publication_status = 'published' where status = 'active';
update public.products set publication_status = 'archived'  where status = 'archived';
alter table public.products enable trigger trg_products_updated_at;

-- Validación dentro de la misma transacción: si algo no cuadra, se aborta todo
do $$
declare
  n_total int; n_active int; n_archived int;
  n_published int; n_pub_archived int; n_other int;
begin
  select count(*),
         count(*) filter (where status = 'active'),
         count(*) filter (where status = 'archived'),
         count(*) filter (where publication_status = 'published'),
         count(*) filter (where publication_status = 'archived'),
         count(*) filter (where publication_status not in ('published', 'archived'))
    into n_total, n_active, n_archived, n_published, n_pub_archived, n_other
    from public.products;
  if n_other <> 0 or n_published <> n_active or n_pub_archived <> n_archived
     or n_published + n_pub_archived <> n_total then
    raise exception '38-B relleno incompleto: total=% active=% archived=% published=% pub_archived=% otros=%',
      n_total, n_active, n_archived, n_published, n_pub_archived, n_other;
  end if;
end $$;

create index products_publication_status_idx on public.products (publication_status);

-- Espejo de status: se calcula a partir de publication_status
create function public.products_sync_legacy_status()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.status := case when new.publication_status = 'published' then 'active' else 'archived' end;
  return new;
end;
$$;

comment on function public.products_sync_legacy_status() is
  '38-B: mantiene products.status como espejo de publication_status (published -> active, resto -> archived). Solo en INSERT y UPDATE OF publication_status.';

-- Función de trigger: ningún rol de cliente necesita ejecutarla directamente
revoke all on function public.products_sync_legacy_status() from public, anon, authenticated;

create trigger trg_products_sync_legacy_status
  before insert or update of publication_status on public.products
  for each row execute function public.products_sync_legacy_status();

COMMIT;
