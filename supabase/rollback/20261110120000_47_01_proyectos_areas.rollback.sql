-- ============================================================
-- RECUPERACIÓN DE 47-01 (proyectos por áreas) — NO EJECUTADA — no ejecutar sin aprobación explícita
-- ============================================================
-- Vuelve al estado anterior a 47-01. NO borra áreas ni asignaciones por su cuenta: si existe alguna área o alguna línea asignada,
-- SE DETIENE ANTES DE MODIFICAR NADA y explica el impedimento; entonces hace falta una decisión separada de conservación o
-- transformación de datos (por ejemplo, exportar las áreas, o pasar a «Sin área» las líneas y unir las equivalentes con criterio).
-- El respaldo no sustituye esta protección. Si no hay áreas ni asignaciones: elimina el trigger, las funciones y la tabla, quita
-- project_products.area_id, restaura el índice de identidad anterior y las dos funciones de 46-04 con sus definiciones exactas
-- (md5 de prosrc comprobados). Ejecutar completo, como postgres.
-- ============================================================

BEGIN;

DO $$
declare
  v_areas bigint;
  v_assigned bigint;
begin
  if current_user <> 'postgres' then raise exception '47-01 recuperación: ejecutar como postgres'; end if;
  select count(*) into v_areas from public.project_areas;
  select count(*) into v_assigned from public.project_products where area_id is not null;
  if v_areas > 0 or v_assigned > 0 then
    raise exception '47-01 recuperación DETENIDA sin cambios: hay % áreas y % líneas asignadas a un área. Volver al modelo anterior las perdería o las fusionaría. Decide aparte cómo conservar o transformar esos datos (exportarlos, o mover las líneas a Sin área y unir las equivalentes con criterio) y repite la recuperación cuando no queden áreas ni asignaciones.', v_areas, v_assigned;
  end if;
end $$;

drop trigger trg_project_products_05_areas_guard on public.project_products;
drop function public.project_products_areas_guard();
drop function public.project_lines_transfer(uuid[], uuid, text, jsonb);
drop function public.project_area_delete(uuid, jsonb);

create or replace function public.project_request_lines(p_project_id uuid)
 returns jsonb language sql stable set search_path to ''
as $function$
  select coalesce(pg_catalog.jsonb_agg(x.line order by x.ord1, x.ord2, x.ord3), '[]'::jsonb)
    from (
      select pp.order_position as ord1, pp.created_at as ord2, pp.id as ord3,
             pg_catalog.jsonb_build_object(
               'line_id', pp.id, 'product_id', pp.product_id, 'product_name', cp.name, 'brand', cp.brand,
               'reference_code', cp.reference_code, 'category_id', cp.category_id,
               'distributor_id', cp.distributor_id, 'distributor_name', d.name,
               'finish_code', pp.finish_code, 'finish_name', pf.name, 'finish_reference_code', pf.reference_code,
               'quantity', pp.quantity, 'unit', pp.unit, 'room_or_area', pp.room_or_area, 'notes', pp.notes,
               'configuration', pp.configuration, 'config_key', pp.config_key,
               'config_status', s.r ->> 'status', 'config_reasons', s.r -> 'reasons',
               'config_notices', s.r -> 'notices', 'config_summary', s.r ->> 'summary',
               'items', (select coalesce(pg_catalog.jsonb_agg(i.e || pg_catalog.jsonb_build_object(
                                  'total_quantity',
                                    case when (i.e ->> 'kind') = 'componente' and pg_catalog.jsonb_typeof(i.e -> 'factor') = 'number'
                                              and pp.quantity is not null
                                         then pg_catalog.trim_scale(pg_catalog.round(pp.quantity * (i.e ->> 'factor')::numeric, 3)) end,
                                  'quantity_status',
                                    case when (i.e ->> 'kind') = 'ajuste' then 'no_aplica'
                                         when pg_catalog.jsonb_typeof(i.e -> 'factor') = 'number' and pp.quantity is not null then 'calculada'
                                         else 'a_calcular' end)
                                order by i.n), '[]'::jsonb)
                           from pg_catalog.jsonb_array_elements(s.r -> 'items') with ordinality as i(e, n))
             ) as line
        from public.project_products pp
        left join public.catalog_products cp on cp.id = pp.product_id
        left join public.distributors d on d.id = cp.distributor_id
        left join public.product_finishes pf on pf.product_id = pp.product_id and pf.code = pp.finish_code
        cross join lateral (select public.line_configuration_resolve(pp.product_id, pp.configuration) as r) s
       where pp.project_id = p_project_id and pp.selected_for_rfq
    ) x
$function$;

create or replace function public.rfqs_lines_snapshot()
 returns trigger language plpgsql set search_path to ''
as $function$
declare
  v_lines jsonb;
  v_pending text;
begin
  if tg_op = 'UPDATE' then
    if new.lines_snapshot is distinct from old.lines_snapshot then
      raise exception 'La copia de lo solicitado en una RFQ no se puede modificar.'
        using errcode = '42501', hint = 'rfq_snapshot_immutable';
    end if;
    return new;
  end if;

  -- INSERT: lo que envíe el navegador en lines_snapshot se ignora.
  v_lines := public.project_request_lines(new.project_id);
  select pg_catalog.string_agg(coalesce(l ->> 'product_name', l ->> 'product_id'), ', ') into v_pending
    from pg_catalog.jsonb_array_elements(v_lines) as l
   where (l ->> 'config_status') = 'pendiente';
  if v_pending is not null then
    raise exception 'Completa la configuración antes de enviar la solicitud: %.', v_pending
      using errcode = '23514', hint = 'configuration_pending';
  end if;
  new.lines_snapshot := pg_catalog.jsonb_build_object(
    'version', 1, 'taken_at', pg_catalog.now(), 'project_id', new.project_id,
    'distributors', (select coalesce(pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
                                 'distributor_id', gd.did, 'distributor_name', gd.dname, 'lines', gd.lines)
                               order by gd.did), '[]'::jsonb)
                       from (select (t.l ->> 'distributor_id') as did, max(t.l ->> 'distributor_name') as dname,
                                    pg_catalog.jsonb_agg(t.l order by t.n) as lines
                               from pg_catalog.jsonb_array_elements(v_lines) with ordinality as t(l, n)
                              group by (t.l ->> 'distributor_id')) gd));
  return new;
end $function$;

alter table public.project_products drop constraint project_products_area_fk;
create unique index project_products_config_line_unique on public.project_products (project_id, product_id, coalesce(finish_code, ''), config_key);
drop index public.project_products_area_line_unique;
alter table public.project_products drop column area_id;
drop table public.project_areas;

DO $$
begin
  if exists (select 1 from pg_attribute where attrelid = 'public.project_products'::regclass and attname = 'area_id' and not attisdropped)
     or to_regclass('public.project_areas') is not null
     or not exists (select 1 from pg_indexes where schemaname = 'public' and indexname = 'project_products_config_line_unique')
     or to_regprocedure('public.project_lines_transfer(uuid[], uuid, text, jsonb)') is not null then
    raise exception '47-01 recuperación: el estado final no es el esperado';
  end if;
  if (select md5(prosrc) from pg_proc where oid = 'public.project_request_lines(uuid)'::regprocedure) <> 'eda482e41007f05fa96d77909cc6abee'
     or (select md5(prosrc) from pg_proc where oid = 'public.rfqs_lines_snapshot()'::regprocedure) <> 'a2a34a983f128532dce2a7bcdfbfb96a' then
    raise exception '47-01 recuperación: las funciones de 46-04 no quedaron idénticas';
  end if;
end $$;

COMMIT;
