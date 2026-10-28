-- ============================================================
-- PROPUESTA NO EJECUTADA (47-01 · proyectos por áreas) — no ejecutar sin aprobación explícita
-- ============================================================
-- Punto 47 · áreas opcionales por proyecto, líneas independientes por área, operaciones atómicas de mover, copiar y eliminar áreas,
-- copia de RFQ con las áreas y protección de pestañas antiguas. Aditiva y compatible con la web actual mientras ningún proyecto tenga áreas.
--
--   1. public.project_areas (id, project_id, name, sort_order): nombre único por proyecto sin distinguir mayúsculas. Sin límite funcional de áreas.
--      RLS con el patrón de project_products: propietario; escritura solo con el proyecto activo; proveedor sin escritura; escritura solo con
--      my_professional_access(); lectura según el plan (D3). Sin permiso para modificar el proyecto tampoco se modifican sus áreas.
--   2. project_products.area_id (NULL = «Sin área») con clave foránea COMPUESTA (project_id, area_id): una línea solo puede apuntar a un
--      área de SU proyecto. NO ACTION: un área con líneas no se puede borrar directamente (solo con project_area_delete).
--   3. Identidad de línea: project_products_area_line_unique (proyecto, producto, acabado, configuración, área con coalesce al uuid nulo,
--      así «Sin área» también es único). Más débil que el índice actual: ninguna fila existente puede violarla. Se elimina el índice anterior.
--   4. Funciones atómicas SECURITY INVOKER (la RLS sigue aplicando): project_lines_transfer (mover/copiar) y project_area_delete.
--      Los conflictos se comprueban DE NUEVO al ejecutar, con bloqueo de filas; sin resolución explícita abortan sin cambiar nada.
--   5. Copia de RFQ: project_request_lines añade area_id/area_name/area_sort_order por línea y rfqs_lines_snapshot añade «areas»
--      (id, nombre y orden de las áreas usadas) y sube version a 2. Las RFQ ya enviadas NO se tocan (copia inmutable).
--   6. Pestañas antiguas: trigger project_products_areas_guard. Mientras un proyecto tenga áreas, las escrituras de clientes
--      autenticados sobre sus líneas deben llevar la cabecera x-mobau-areas: 1 (la envía la web nueva); sin ella se rechazan de forma
--      controlada (42501, pista client_outdated, «recarga la página») sin modificar ninguna línea. También bloquea reasignar líneas
--      de un proyecto archivado. No afecta a proyectos sin áreas, a SQL directo ni a funciones de servicio.
--   room_or_area (texto) NO se toca. En Production no contiene datos (0 líneas con valor), y la copia de RFQ lo sigue incluyendo.
-- Si se aplica, se registra como migración NUEVA tras confirmar su COMMIT. Recuperación: supabase/rollback/20261110120000_47_01_proyectos_areas.rollback.sql
-- (se detiene si ya existen áreas o líneas asignadas). Ejecutar completo.
-- ============================================================

BEGIN;

DO $$
declare
  v_reg int := 1;
begin
  if current_user <> 'postgres' then
    raise exception '47-01: ejecutar como postgres';
  end if;
  if to_regclass('supabase_migrations.schema_migrations') is not null then
    execute $q$select count(*) from supabase_migrations.schema_migrations where version = '20261101140000'$q$ into v_reg;
    if v_reg <> 1 then raise exception '47-01: 46-06 no está registrada'; end if;
    execute $q$select count(*) from supabase_migrations.schema_migrations where version = '20261110120000'$q$ into v_reg;
    if v_reg <> 0 then raise exception '47-01: ya está registrada'; end if;
  end if;
  if to_regclass('public.project_areas') is not null
     or exists (select 1 from pg_attribute where attrelid = 'public.project_products'::regclass and attname = 'area_id' and not attisdropped)
     or to_regprocedure('public.project_lines_transfer(uuid[], uuid, text, jsonb)') is not null
     or to_regprocedure('public.project_area_delete(uuid, jsonb)') is not null
     or to_regprocedure('public.project_products_areas_guard()') is not null then
    raise exception '47-01: el estado de partida no es el esperado (ya existe algún objeto)';
  end if;
  if (select indexdef from pg_indexes where schemaname = 'public' and indexname = 'project_products_config_line_unique')
     is distinct from 'CREATE UNIQUE INDEX project_products_config_line_unique ON public.project_products USING btree (project_id, product_id, COALESCE(finish_code, ''''::text), config_key)' then
    raise exception '47-01: el índice de identidad de línea no es el esperado';
  end if;
  if (select md5(prosrc) from pg_proc where oid = 'public.project_request_lines(uuid)'::regprocedure) <> 'eda482e41007f05fa96d77909cc6abee'
     or (select md5(prosrc) from pg_proc where oid = 'public.rfqs_lines_snapshot()'::regprocedure) <> 'a2a34a983f128532dce2a7bcdfbfb96a' then
    raise exception '47-01: las funciones de la copia de RFQ no son las de 46-04';
  end if;
  if to_regprocedure('public.set_updated_at()') is null or to_regprocedure('public.is_supplier()') is null
     or to_regprocedure('public.my_professional_access()') is null then
    raise exception '47-01: faltan funciones auxiliares';
  end if;
end $$;

-- ---------- 1. áreas ----------
create table public.project_areas (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.projects (id) on delete cascade,
  name text not null,
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint project_areas_name_valid check (name = btrim(name) and char_length(name) between 1 and 60),
  constraint project_areas_project_id_id_key unique (project_id, id)
);
create unique index project_areas_name_unique on public.project_areas (project_id, lower(name));
create index project_areas_order_idx on public.project_areas (project_id, sort_order, created_at, id);
comment on table public.project_areas is 'Punto 47: áreas opcionales de un proyecto (orden propio). Sin áreas, el proyecto es una lista sencilla.';
create trigger trg_project_areas_updated_at before update on public.project_areas
  for each row execute function public.set_updated_at();

-- ---------- 2. línea → área ----------
alter table public.project_products add column area_id uuid;
alter table public.project_products add constraint project_products_area_fk
  foreign key (project_id, area_id) references public.project_areas (project_id, id);
comment on column public.project_products.area_id is 'Punto 47: área de la línea (NULL = «Sin área»). Solo puede ser un área del mismo proyecto.';

-- ---------- 3. identidad de línea con área ----------
create unique index project_products_area_line_unique
  on public.project_products (project_id, product_id, coalesce(finish_code, ''), config_key, coalesce(area_id, '00000000-0000-0000-0000-000000000000'::uuid));
drop index public.project_products_config_line_unique;

-- ---------- 4. permisos y políticas de las áreas ----------
alter table public.project_areas enable row level security;
revoke all on public.project_areas from public, anon, authenticated;
grant select, insert, delete on public.project_areas to authenticated;
grant update (name, sort_order) on public.project_areas to authenticated;
grant update (area_id) on public.project_products to authenticated;

create policy project_areas_select on public.project_areas for select to authenticated
  using (exists (select 1 from public.projects p where p.id = project_areas.project_id and p.owner_user_id = (select auth.uid())));
create policy project_areas_insert on public.project_areas for insert to authenticated
  with check (exists (select 1 from public.projects p where p.id = project_areas.project_id and p.owner_user_id = (select auth.uid()) and p.status = 'active'));
create policy project_areas_update on public.project_areas for update to authenticated
  using (exists (select 1 from public.projects p where p.id = project_areas.project_id and p.owner_user_id = (select auth.uid()) and p.status = 'active'))
  with check (exists (select 1 from public.projects p where p.id = project_areas.project_id and p.owner_user_id = (select auth.uid()) and p.status = 'active'));
create policy project_areas_delete on public.project_areas for delete to authenticated
  using (exists (select 1 from public.projects p where p.id = project_areas.project_id and p.owner_user_id = (select auth.uid()) and p.status = 'active'));
create policy project_areas_supplier_no_insert on public.project_areas as restrictive for insert to authenticated
  with check (not (select public.is_supplier()));
create policy project_areas_supplier_no_update on public.project_areas as restrictive for update to authenticated
  using (not (select public.is_supplier())) with check (not (select public.is_supplier()));
create policy project_areas_supplier_no_delete on public.project_areas as restrictive for delete to authenticated
  using (not (select public.is_supplier()));
create policy project_areas_plan_select on public.project_areas as restrictive for select to authenticated
  using ((select public.my_professional_access())
         or not coalesce((select (pr.role = any (array['individual'::text, 'studio_member'::text])) from public.profiles pr where pr.id = (select auth.uid())), true));
create policy project_areas_plan_insert on public.project_areas as restrictive for insert to authenticated
  with check ((select public.my_professional_access()));
create policy project_areas_plan_update on public.project_areas as restrictive for update to authenticated
  using ((select public.my_professional_access())) with check ((select public.my_professional_access()));
create policy project_areas_plan_delete on public.project_areas as restrictive for delete to authenticated
  using ((select public.my_professional_access()));

-- ---------- 5. protección de pestañas antiguas y de proyectos archivados ----------
create function public.project_products_areas_guard() returns trigger
  language plpgsql set search_path = '' as $$
declare
  v_project uuid;
  v_hdr text;
  v_status text;
begin
  if current_user <> 'authenticated' then
    if tg_op = 'DELETE' then return old; end if;
    return new;
  end if;
  v_project := case when tg_op = 'DELETE' then old.project_id else new.project_id end;
  if exists (select 1 from public.project_areas a where a.project_id = v_project) then
    begin
      v_hdr := (pg_catalog.current_setting('request.headers', true))::jsonb ->> 'x-mobau-areas';
    exception when others then
      v_hdr := null;
    end;
    if v_hdr is distinct from '1' then
      raise exception 'Esta página está desactualizada y no puede modificar un proyecto organizado por áreas. Recárgala para continuar.'
        using errcode = '42501', hint = 'client_outdated';
    end if;
  end if;
  if tg_op = 'UPDATE' and new.area_id is distinct from old.area_id then
    select p.status into v_status from public.projects p where p.id = new.project_id;
    if v_status is distinct from 'active' then
      raise exception 'Las líneas de un proyecto archivado no se pueden reorganizar.'
        using errcode = '42501', hint = 'project_not_active';
    end if;
  end if;
  if tg_op = 'DELETE' then return old; end if;
  return new;
end $$;
revoke all on function public.project_products_areas_guard() from public, anon, authenticated;
create trigger trg_project_products_05_areas_guard before insert or update or delete on public.project_products
  for each row execute function public.project_products_areas_guard();

-- ---------- 6. mover y copiar líneas (atómico, con conflictos explícitos) ----------
-- p_resolutions: { "<line_id>": { "action": "sum" | "skip", "note": "existing" | "incoming" | "both" } }
-- «note» solo es obligatorio si ambas líneas tienen nota y son distintas. Nada se funde sin resolución.
create function public.project_lines_transfer(p_line_ids uuid[], p_area_id uuid, p_kind text, p_resolutions jsonb default '{}'::jsonb)
  returns jsonb language plpgsql set search_path = '' as $$
declare
  v_project uuid;
  v_projects int;
  v_n int;
  v_status text;
  v_conf jsonb := '[]'::jsonb;
  l public.project_products;
  t public.project_products;
  r jsonb;
  v_note text;
  v_mode text;
  v_moved int := 0;
  v_copied int := 0;
  v_summed int := 0;
  v_skipped int := 0;
begin
  if p_kind is null or p_kind not in ('move', 'copy') then
    raise exception 'Tipo de operación no válido.' using errcode = '22023';
  end if;
  if p_line_ids is null or pg_catalog.cardinality(p_line_ids) = 0 then
    return pg_catalog.jsonb_build_object('moved', 0, 'copied', 0, 'summed', 0, 'skipped', 0);
  end if;
  select pg_catalog.count(distinct pp.project_id), pg_catalog.min(pp.project_id::text)::uuid, pg_catalog.count(*)
    into v_projects, v_project, v_n
    from public.project_products pp where pp.id = any (p_line_ids);
  if v_project is null or v_projects <> 1 or v_n <> (select pg_catalog.count(distinct x) from pg_catalog.unnest(p_line_ids) as x) then
    raise exception 'Alguna línea no existe o no pertenece a un único proyecto.' using errcode = '23514', hint = 'line_invalid';
  end if;
  select p.status into v_status from public.projects p where p.id = v_project;
  if v_status is distinct from 'active' then
    raise exception 'Solo se pueden reorganizar las líneas de un proyecto activo.' using errcode = '42501', hint = 'project_not_active';
  end if;
  if p_area_id is not null then
    perform 1 from public.project_areas a where a.id = p_area_id and a.project_id = v_project for share;
    if not found then
      raise exception 'El área no existe o no pertenece a este proyecto.' using errcode = '23514', hint = 'area_invalid';
    end if;
  end if;
  perform 1 from public.project_products pp where pp.id = any (p_line_ids) order by pp.id for update;

  -- Pasada 1: conflictos con lo que haya AHORA en el destino (bloqueado).
  for l in select * from public.project_products pp where pp.id = any (p_line_ids) order by pp.order_position, pp.created_at, pp.id loop
    if p_kind = 'move' and l.area_id is not distinct from p_area_id then continue; end if;
    select * into t from public.project_products x
     where x.project_id = v_project and x.id <> l.id and x.product_id = l.product_id
       and coalesce(x.finish_code, '') = coalesce(l.finish_code, '') and x.config_key = l.config_key
       and x.area_id is not distinct from p_area_id
     for update;
    if found then
      r := p_resolutions -> l.id::text;
      if r is null or (r ->> 'action') not in ('sum', 'skip')
         or ((r ->> 'action') = 'sum' and nullif(pg_catalog.btrim(l.notes), '') is not null and nullif(pg_catalog.btrim(t.notes), '') is not null
             and pg_catalog.btrim(l.notes) <> pg_catalog.btrim(t.notes) and not coalesce((r ->> 'note') = any (array['existing', 'incoming', 'both']), false)) then
        v_conf := v_conf || pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object('line_id', l.id, 'twin_id', t.id));
      end if;
    end if;
  end loop;
  if pg_catalog.jsonb_array_length(v_conf) > 0 then
    raise exception 'Hay líneas equivalentes en el destino: resuélvelas antes de continuar.'
      using errcode = '23514', hint = 'transfer_conflict', detail = v_conf::text;
  end if;

  -- Pasada 2: aplicar.
  for l in select * from public.project_products pp where pp.id = any (p_line_ids) order by pp.order_position, pp.created_at, pp.id loop
    if p_kind = 'move' and l.area_id is not distinct from p_area_id then v_skipped := v_skipped + 1; continue; end if;
    select * into t from public.project_products x
     where x.project_id = v_project and x.id <> l.id and x.product_id = l.product_id
       and coalesce(x.finish_code, '') = coalesce(l.finish_code, '') and x.config_key = l.config_key
       and x.area_id is not distinct from p_area_id
     for update;
    if found then
      r := p_resolutions -> l.id::text;
      if (r ->> 'action') = 'skip' then v_skipped := v_skipped + 1; continue; end if;
      v_mode := r ->> 'note';
      if nullif(pg_catalog.btrim(l.notes), '') is not null and nullif(pg_catalog.btrim(t.notes), '') is not null
         and pg_catalog.btrim(l.notes) <> pg_catalog.btrim(t.notes) then
        v_note := case v_mode when 'incoming' then l.notes when 'both' then t.notes || E'\n\n' || l.notes else t.notes end;
      else
        v_note := coalesce(nullif(pg_catalog.btrim(t.notes), ''), nullif(pg_catalog.btrim(l.notes), ''));
      end if;
      update public.project_products set quantity = pg_catalog.round(coalesce(t.quantity, 0) + coalesce(l.quantity, 0), 2), notes = v_note where id = t.id;
      if p_kind = 'move' then delete from public.project_products where id = l.id; end if;
      v_summed := v_summed + 1;
    elsif p_kind = 'move' then
      update public.project_products set area_id = p_area_id where id = l.id;
      v_moved := v_moved + 1;
    else
      insert into public.project_products (project_id, product_id, room_or_area, notes, quantity, selected_for_rfq, order_position, unit, finish_code, configuration, area_id)
      values (l.project_id, l.product_id, l.room_or_area, l.notes, l.quantity, l.selected_for_rfq,
              (select coalesce(pg_catalog.max(x.order_position), 0) + 1 from public.project_products x where x.project_id = v_project),
              l.unit, l.finish_code, l.configuration, p_area_id);
      v_copied := v_copied + 1;
    end if;
  end loop;
  return pg_catalog.jsonb_build_object('moved', v_moved, 'copied', v_copied, 'summed', v_summed, 'skipped', v_skipped);
end $$;
comment on function public.project_lines_transfer(uuid[], uuid, text, jsonb) is
  'Punto 47: mueve o copia líneas a un área (NULL = Sin área) de forma atómica; los conflictos se resuelven explícitamente y se re-comprueban al ejecutar.';

-- ---------- 7. eliminar un área (atómico): sus líneas pasan a «Sin área» ----------
-- p_resolutions: { "<line_id>": { "action": "sum", "note": ... } | { "action": "move", "area_id": "<uuid>" } }
create function public.project_area_delete(p_area_id uuid, p_resolutions jsonb default '{}'::jsonb)
  returns jsonb language plpgsql set search_path = '' as $$
declare
  v_project uuid;
  v_status text;
  v_conf jsonb := '[]'::jsonb;
  l public.project_products;
  t public.project_products;
  r jsonb;
  v_target uuid;
  v_note text;
  v_mode text;
  v_unassigned int := 0;
  v_summed int := 0;
  v_moved int := 0;
begin
  select a.project_id into v_project from public.project_areas a where a.id = p_area_id;
  if not found then
    raise exception 'El área no existe.' using errcode = '23514', hint = 'area_invalid';
  end if;
  select p.status into v_status from public.projects p where p.id = v_project;
  if v_status is distinct from 'active' then
    raise exception 'Solo se pueden modificar las áreas de un proyecto activo.' using errcode = '42501', hint = 'project_not_active';
  end if;
  perform 1 from public.project_areas a where a.id = p_area_id for update;
  perform 1 from public.project_products pp where pp.area_id = p_area_id order by pp.id for update;

  for l in select * from public.project_products pp where pp.area_id = p_area_id order by pp.order_position, pp.created_at, pp.id loop
    select * into t from public.project_products x
     where x.project_id = v_project and x.id <> l.id and x.product_id = l.product_id
       and coalesce(x.finish_code, '') = coalesce(l.finish_code, '') and x.config_key = l.config_key and x.area_id is null
     for update;
    if found then
      r := p_resolutions -> l.id::text;
      if r is null or (r ->> 'action') not in ('sum', 'move') then
        v_conf := v_conf || pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object('line_id', l.id, 'twin_id', t.id));
      elsif (r ->> 'action') = 'sum' then
        if nullif(pg_catalog.btrim(l.notes), '') is not null and nullif(pg_catalog.btrim(t.notes), '') is not null
           and pg_catalog.btrim(l.notes) <> pg_catalog.btrim(t.notes) and not coalesce((r ->> 'note') = any (array['existing', 'incoming', 'both']), false) then
          v_conf := v_conf || pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object('line_id', l.id, 'twin_id', t.id));
        end if;
      else
        begin v_target := (r ->> 'area_id')::uuid; exception when others then v_target := null; end;
        if v_target is null or v_target = p_area_id
           or not exists (select 1 from public.project_areas a where a.id = v_target and a.project_id = v_project)
           or exists (select 1 from public.project_products x where x.project_id = v_project and x.id <> l.id and x.product_id = l.product_id
                       and coalesce(x.finish_code, '') = coalesce(l.finish_code, '') and x.config_key = l.config_key and x.area_id = v_target) then
          v_conf := v_conf || pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object('line_id', l.id, 'twin_id', t.id));
        end if;
      end if;
    end if;
  end loop;
  if pg_catalog.jsonb_array_length(v_conf) > 0 then
    raise exception 'Hay líneas equivalentes en «Sin área»: resuélvelas antes de eliminar el área.'
      using errcode = '23514', hint = 'area_conflict', detail = v_conf::text;
  end if;

  for l in select * from public.project_products pp where pp.area_id = p_area_id order by pp.order_position, pp.created_at, pp.id loop
    select * into t from public.project_products x
     where x.project_id = v_project and x.id <> l.id and x.product_id = l.product_id
       and coalesce(x.finish_code, '') = coalesce(l.finish_code, '') and x.config_key = l.config_key and x.area_id is null
     for update;
    if found then
      r := p_resolutions -> l.id::text;
      if (r ->> 'action') = 'move' then
        update public.project_products set area_id = (r ->> 'area_id')::uuid where id = l.id;
        v_moved := v_moved + 1;
      else
        v_mode := r ->> 'note';
        if nullif(pg_catalog.btrim(l.notes), '') is not null and nullif(pg_catalog.btrim(t.notes), '') is not null
           and pg_catalog.btrim(l.notes) <> pg_catalog.btrim(t.notes) then
          v_note := case v_mode when 'incoming' then l.notes when 'both' then t.notes || E'\n\n' || l.notes else t.notes end;
        else
          v_note := coalesce(nullif(pg_catalog.btrim(t.notes), ''), nullif(pg_catalog.btrim(l.notes), ''));
        end if;
        update public.project_products set quantity = pg_catalog.round(coalesce(t.quantity, 0) + coalesce(l.quantity, 0), 2), notes = v_note where id = t.id;
        delete from public.project_products where id = l.id;
        v_summed := v_summed + 1;
      end if;
    else
      update public.project_products set area_id = null where id = l.id;
      v_unassigned := v_unassigned + 1;
    end if;
  end loop;
  delete from public.project_areas where id = p_area_id;
  return pg_catalog.jsonb_build_object('unassigned', v_unassigned, 'summed', v_summed, 'moved', v_moved);
end $$;
comment on function public.project_area_delete(uuid, jsonb) is
  'Punto 47: elimina un área y pasa sus líneas a Sin área de forma atómica; los conflictos se resuelven antes y se re-comprueban al ejecutar.';
revoke all on function public.project_lines_transfer(uuid[], uuid, text, jsonb) from public, anon;
revoke all on function public.project_area_delete(uuid, jsonb) from public, anon;
grant execute on function public.project_lines_transfer(uuid[], uuid, text, jsonb) to authenticated;
grant execute on function public.project_area_delete(uuid, jsonb) to authenticated;

-- ---------- 8. copia de RFQ con las áreas (solo añade claves) ----------
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
               'area_id', pp.area_id, 'area_name', pa.name, 'area_sort_order', pa.sort_order,
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
        left join public.project_areas pa on pa.id = pp.area_id
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
    'version', 2, 'taken_at', pg_catalog.now(), 'project_id', new.project_id,
    'areas', (select coalesce(pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
                                 'id', a.id, 'name', a.name, 'sort_order', a.sort_order)
                               order by a.sort_order, a.created_at, a.id), '[]'::jsonb)
                from public.project_areas a
               where a.project_id = new.project_id
                 and exists (select 1 from pg_catalog.jsonb_array_elements(v_lines) as l where (l ->> 'area_id') = a.id::text)),
    'distributors', (select coalesce(pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
                                 'distributor_id', gd.did, 'distributor_name', gd.dname, 'lines', gd.lines)
                               order by gd.did), '[]'::jsonb)
                       from (select (t.l ->> 'distributor_id') as did, max(t.l ->> 'distributor_name') as dname,
                                    pg_catalog.jsonb_agg(t.l order by t.n) as lines
                               from pg_catalog.jsonb_array_elements(v_lines) with ordinality as t(l, n)
                              group by (t.l ->> 'distributor_id')) gd));
  return new;
end $function$;

-- ---------- 9. validación final ----------
DO $$
begin
  if to_regclass('public.project_areas') is null
     or not (select relrowsecurity from pg_class where oid = 'public.project_areas'::regclass)
     or (select count(*) from pg_policies where schemaname = 'public' and tablename = 'project_areas') <> 11
     or not exists (select 1 from pg_indexes where schemaname = 'public' and indexname = 'project_products_area_line_unique')
     or exists (select 1 from pg_indexes where schemaname = 'public' and indexname = 'project_products_config_line_unique')
     or not exists (select 1 from pg_trigger where tgrelid = 'public.project_products'::regclass and tgname = 'trg_project_products_05_areas_guard' and not tgisinternal)
     or to_regprocedure('public.project_lines_transfer(uuid[], uuid, text, jsonb)') is null
     or to_regprocedure('public.project_area_delete(uuid, jsonb)') is null then
    raise exception '47-01: el estado final no es el esperado';
  end if;
  if (select md5(prosrc) from pg_proc where oid = 'public.project_request_lines(uuid)'::regprocedure) = 'eda482e41007f05fa96d77909cc6abee'
     or (select md5(prosrc) from pg_proc where oid = 'public.rfqs_lines_snapshot()'::regprocedure) = 'a2a34a983f128532dce2a7bcdfbfb96a' then
    raise exception '47-01: las funciones de la copia de RFQ no se actualizaron';
  end if;
  if has_function_privilege('anon', 'public.project_lines_transfer(uuid[], uuid, text, jsonb)', 'EXECUTE')
     or has_function_privilege('anon', 'public.project_area_delete(uuid, jsonb)', 'EXECUTE')
     or has_table_privilege('anon', 'public.project_areas', 'SELECT')
     or not has_function_privilege('authenticated', 'public.project_request_lines(uuid)', 'EXECUTE') then
    raise exception '47-01: permisos inesperados';
  end if;
  if (select count(*) from public.project_products where area_id is not null) <> 0 then
    raise exception '47-01: no debe haber líneas con área al terminar';
  end if;
end $$;

COMMIT;
