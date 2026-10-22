-- ============================================================
-- PROPUESTA NO EJECUTADA (45-03 · purga de la lámpara de prueba spectro-a7a2cfba) — no ejecutar sin aprobación explícita
-- ============================================================
-- Punto 45 · limpieza autorizada por la empresa: eliminar definitivamente
-- SOLO spectro-a7a2cfba («lampara de pie», prueba duplicada, legacy_retired).
--   * En legacy_retired ninguna función de ciclo de vida actúa (ni Mobau ni
--     distribuidor), así que se ejecuta como postgres con el MISMO borrado y
--     la MISMA auditoría que 41-07 (mobau_private.purge_product_rows +
--     log_lifecycle_event), sin cambiar funciones, permisos ni restricciones.
--   * Actor: actor_kind 'mobau', actor_id nulo (la columna lo admite; no se
--     inventa usuario) y el origen en meta (via sql_admin, autorización).
--   * Se borran el producto y su precio (product_prices). No tiene
--     propuestas, archivos, acabados, eventos, líneas de proyecto ni RFQ.
--   * spectro-02988ada NO se toca (tiene una línea de proyecto ajena).
-- Precondiciones: fila exacta (MD5), precio exacto (MD5), sin referencias.
-- Respaldo: la recuperación (.rollback.sql) reinserta la fila y el precio.
-- Si se aplica, se registra como migración NUEVA tras confirmar su COMMIT.
-- Ejecutar completo.
-- ============================================================

BEGIN;

DO $$
declare
  v_refs jsonb;
begin
  if current_user <> 'postgres' then
    raise exception '45-03: ejecutar como postgres';
  end if;
  if not exists (select 1 from supabase_migrations.schema_migrations where version = '20261026120000')
     or exists (select 1 from supabase_migrations.schema_migrations where version = '20261027120000') then
    raise exception '45-03: el registro de migraciones no es el esperado (45-02 registrada y 45-03 sin registrar)';
  end if;
  if (select md5(to_jsonb(p)::text) from public.products p where p.id = 'spectro-a7a2cfba') is distinct from '184760509b245183353d9150b03cd0fa'
     or (select mobau_private.product_lifecycle_state(p.publication_status, p.retired_at, p.trashed_at) from public.products p where p.id = 'spectro-a7a2cfba') is distinct from 'legacy_retired' then
    raise exception '45-03: spectro-a7a2cfba no es la fila verificada (contenido o estado distintos)';
  end if;
  if (select count(*) from public.product_prices where product_id = 'spectro-a7a2cfba') <> 1
     or (select md5(to_jsonb(pp)::text) from public.product_prices pp where pp.product_id = 'spectro-a7a2cfba') <> 'a53fac05564b595fe519b10ecee597a8' then
    raise exception '45-03: el precio no es el verificado';
  end if;
  if exists (select 1 from public.product_proposals where product_id = 'spectro-a7a2cfba' or created_product_id = 'spectro-a7a2cfba')
     or exists (select 1 from public.product_assets where product_id = 'spectro-a7a2cfba')
     or exists (select 1 from public.product_finishes where product_id = 'spectro-a7a2cfba')
     or exists (select 1 from mobau_private.product_lifecycle_events where product_id = 'spectro-a7a2cfba') then
    raise exception '45-03: el producto tiene propuestas, archivos, acabados o eventos';
  end if;
  v_refs := mobau_private.product_reference_counts('spectro-a7a2cfba');
  if pg_catalog.jsonb_array_length(v_refs -> 'unknown_reference_tables') > 0
     or (v_refs ->> 'project_lines_total')::bigint <> 0 or (v_refs ->> 'other_references')::bigint <> 0
     or (v_refs ->> 'rfqs')::bigint <> 0 then
    raise exception '45-03: el producto tiene referencias: %', v_refs;
  end if;
  perform set_config('mobau.p4503_otros', md5(
    coalesce((select string_agg(to_jsonb(p)::text, '|' order by p.id) from public.products p where p.id <> 'spectro-a7a2cfba'), '') || '#' ||
    coalesce((select string_agg(to_jsonb(pp)::text, '|' order by pp.id) from public.product_prices pp where pp.product_id <> 'spectro-a7a2cfba'), '') || '#' ||
    coalesce((select string_agg(to_jsonb(l)::text, '|' order by l.id) from public.project_products l), '') || '#' ||
    coalesce((select string_agg(to_jsonb(pr)::text, '|' order by pr.id) from public.product_proposals pr), '') || '#' ||
    coalesce((select string_agg(to_jsonb(a)::text, '|' order by a.id) from public.product_assets a), '') || '#' ||
    coalesce((select string_agg(to_jsonb(f)::text, '|' order by f.product_id, f.code) from public.product_finishes f), '')), true);
  perform set_config('mobau.p4503_eventos', (select count(*)::text from mobau_private.product_lifecycle_events), true);
end $$;

DO $$
declare
  v_res record;
begin
  perform 1 from public.products where id = 'spectro-a7a2cfba' for update;
  select * into v_res from mobau_private.purge_product_rows('spectro-a7a2cfba');
  if v_res.purge_counts is distinct from '{"products": 1, "product_prices": 1, "proposal_events": 0, "product_proposals": 0}'::jsonb then
    raise exception '45-03: recuentos de purga inesperados: %', v_res.purge_counts;
  end if;
  perform mobau_private.log_lifecycle_event('spectro-a7a2cfba', 'spectro', 'purge', 'legacy_retired', null, null, 'mobau',
            'Producto de prueba duplicado, eliminado a petición de la empresa (punto 45).',
            v_res.purge_counts, v_res.purge_sha256,
            pg_catalog.jsonb_build_object('name', 'lampara de pie', 'via', 'sql_admin', 'authorization', 'punto 45 · 2026-10-22'));
end $$;

DO $$
begin
  if exists (select 1 from public.products where id = 'spectro-a7a2cfba')
     or exists (select 1 from public.product_prices where product_id = 'spectro-a7a2cfba') then
    raise exception '45-03: el producto o su precio siguen existiendo';
  end if;
  if (select count(*) from mobau_private.product_lifecycle_events where product_id = 'spectro-a7a2cfba' and action = 'purge') <> 1
     or (select count(*) from mobau_private.product_lifecycle_events) <> current_setting('mobau.p4503_eventos')::bigint + 1 then
    raise exception '45-03: la auditoría no quedó como se esperaba';
  end if;
  if md5(
    coalesce((select string_agg(to_jsonb(p)::text, '|' order by p.id) from public.products p where p.id <> 'spectro-a7a2cfba'), '') || '#' ||
    coalesce((select string_agg(to_jsonb(pp)::text, '|' order by pp.id) from public.product_prices pp where pp.product_id <> 'spectro-a7a2cfba'), '') || '#' ||
    coalesce((select string_agg(to_jsonb(l)::text, '|' order by l.id) from public.project_products l), '') || '#' ||
    coalesce((select string_agg(to_jsonb(pr)::text, '|' order by pr.id) from public.product_proposals pr), '') || '#' ||
    coalesce((select string_agg(to_jsonb(a)::text, '|' order by a.id) from public.product_assets a), '') || '#' ||
    coalesce((select string_agg(to_jsonb(f)::text, '|' order by f.product_id, f.code) from public.product_finishes f), '')) <> current_setting('mobau.p4503_otros') then
    raise exception '45-03: ha cambiado algo fuera de spectro-a7a2cfba';
  end if;
end $$;

COMMIT;
