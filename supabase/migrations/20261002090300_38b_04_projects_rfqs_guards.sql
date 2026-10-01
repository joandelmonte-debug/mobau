-- ============================================================
-- PROPUESTA NO EJECUTADA (38-B) — no ejecutar sin aprobación explícita
-- ============================================================
-- 38-B · 04 · Garantías de líneas de proyecto y solicitudes (RFQ)
-- ------------------------------------------------------------
-- TRANSACCIÓN ATÓMICA: todo el archivo va entre BEGIN y COMMIT y se
-- ejecuta completo, de una vez. No partirlo ni ejecutarlo por
-- fragmentos. Si cualquier comprobación o sentencia falla, se revierte
-- todo (políticas y permisos de project_products).
--
-- Requiere 38-B · 01 (publication_status) y 03 (is_supplier y las cinco
-- políticas restrictivas de distribuidor).
--
-- project_products:
--   * Una línea nueva solo puede apuntar a un producto publicado
--     (para cualquier rol; la clave foránea no respeta RLS y hoy
--     acepta cualquier product_id).
--   * Una línea existente no puede cambiar de producto ni de proyecto:
--     UPDATE se limita a quantity, unit, notes, room_or_area,
--     selected_for_rfq y order_position (lo único que actualiza el
--     frontend). Las líneas existentes con productos no publicados se
--     siguen pudiendo actualizar (p. ej. selected_for_rfq = false al
--     excluirlas de una solicitud) y borrar.
--
-- rfqs (INSERT, además de requester_user_id = auth.uid() y de
-- rfqs_supplier_no_insert de 38-B · 03):
--   * el proyecto pertenece al solicitante;
--   * el proyecto tiene al menos una línea incluida en la solicitud
--     (selected_for_rfq) con producto publicado;
--   * ninguna línea incluida apunta a un producto no publicado o no
--     visible. El frontend ya marca selected_for_rfq = false en las
--     líneas no disponibles antes de crear la solicitud.
--   * La RFQ se vincula al proyecto por rfqs.project_id (uuid NOT NULL,
--     FK a projects). Con project_id NULL la condición de proyecto propio
--     no se cumple y la inserción se rechaza.
--
-- rfq_distributors NO se toca: ya tiene RLS activa y ninguna política,
-- así que los clientes no tienen acceso. Sus políticas se diseñarán en
-- 38-C si se implementa el reparto de solicitudes.
--
-- Como en 03, propietario y grantor son solo auditoría (NOTICE): la
-- garantía es el permiso EFECTIVO comprobado tras el REVOKE/GRANT.
--
-- Rollback: supabase/rollback/20261002090300_38b_04_projects_rfqs_guards.rollback.sql
-- ============================================================

BEGIN;

-- ---------- validaciones previas ----------
do $$
declare
  v_pol record;
begin
  -- Auditoría (no aborta)
  raise notice '38-B 04 auditoría: current_user=%, propietario project_products=%, UPDATE de tabla de authenticated=%',
    current_user,
    (select pg_get_userbyid(relowner) from pg_class where oid = 'public.project_products'::regclass),
    has_table_privilege('authenticated', 'public.project_products', 'UPDATE');

  -- 38-B 01 aplicado
  if not exists (select 1 from information_schema.columns
                  where table_schema = 'public' and table_name = 'products' and column_name = 'publication_status') then
    raise exception '38-B 04: falta products.publication_status (aplicar antes 38-B 01)';
  end if;

  -- 38-B 03 aplicado: is_supplier() y sus cinco políticas restrictivas
  if not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                  where n.nspname = 'public' and p.proname = 'is_supplier') then
    raise exception '38-B 04: falta public.is_supplier() (aplicar antes 38-B 03)';
  end if;
  if (select count(*) from pg_policies
       where schemaname = 'public' and permissive = 'RESTRICTIVE'
         and policyname in ('projects_supplier_no_insert', 'projects_supplier_no_update',
                            'project_products_supplier_no_insert', 'project_products_supplier_no_update',
                            'rfqs_supplier_no_insert')) <> 5 then
    raise exception '38-B 04: faltan políticas restrictivas de 38-B 03';
  end if;

  -- Ninguna de las dos políticas objetivo existe
  if exists (select 1 from pg_policies
              where schemaname = 'public'
                and policyname in ('project_products_only_published_insert', 'rfqs_insert_guard')) then
    raise exception '38-B 04: alguna de las políticas objetivo ya existe';
  end if;

  -- RLS activa
  if exists (select 1 from pg_class
              where oid in ('public.project_products'::regclass, 'public.rfqs'::regclass, 'public.projects'::regclass)
                and not relrowsecurity) then
    raise exception '38-B 04: RLS no está activa en projects, project_products o rfqs';
  end if;

  -- Políticas permisivas que necesitan los profesionales
  for v_pol in
    select * from (values
      ('projects', 'proyectos_select', 'SELECT'),
      ('project_products', 'project_products_select', 'SELECT'),
      ('project_products', 'project_products_insert', 'INSERT'),
      ('project_products', 'project_products_update', 'UPDATE'),
      ('project_products', 'project_products_delete', 'DELETE'),
      ('rfqs', 'rfqs_select', 'SELECT'),
      ('rfqs', 'rfqs_insert', 'INSERT')
    ) as t(tablename, policyname, cmd)
  loop
    if not exists (select 1 from pg_policies
                    where schemaname = 'public' and tablename = v_pol.tablename
                      and policyname = v_pol.policyname and cmd = v_pol.cmd and permissive = 'PERMISSIVE') then
      raise exception '38-B 04: falta la política permisiva %.% (%)', v_pol.tablename, v_pol.policyname, v_pol.cmd;
    end if;
  end loop;
end $$;

-- Copia de las políticas actuales (para comprobar al final que ninguna cambió)
create temp table mobau_38b04_policies_before on commit drop as
  select tablename::text, policyname::text, cmd, permissive, roles::text as roles, qual, with_check
    from pg_policies
   where schemaname = 'public'
     and tablename in ('projects', 'project_products', 'rfqs', 'rfq_distributors');

-- ---------- líneas de proyecto: solo productos publicados ----------
create policy project_products_only_published_insert
  on public.project_products as restrictive
  for insert to authenticated
  with check (
    exists (
      select 1 from public.products p
      where p.id = project_products.product_id
        and p.publication_status = 'published'
    )
  );

-- UPDATE solo de columnas de la línea (nunca product_id ni project_id)
revoke update on public.project_products from authenticated;
grant update (quantity, unit, notes, room_or_area, selected_for_rfq, order_position)
  on public.project_products to authenticated;

-- Permiso efectivo de UPDATE de authenticated: exactamente esas seis columnas
do $$
declare
  v_allowed text[] := array['quantity', 'unit', 'notes', 'room_or_area', 'selected_for_rfq', 'order_position'];
  v_col text;
begin
  if has_table_privilege('authenticated', 'public.project_products', 'UPDATE') then
    raise exception '38-B 04: authenticated conserva UPDATE de tabla sobre project_products';
  end if;
  for v_col in select attname from pg_attribute
                where attrelid = 'public.project_products'::regclass and attnum > 0 and not attisdropped loop
    if has_column_privilege('authenticated', 'public.project_products', v_col, 'UPDATE') <> (v_col = any (v_allowed)) then
      raise exception '38-B 04: UPDATE efectivo de authenticated en project_products.% no es el esperado', v_col;
    end if;
  end loop;
end $$;

-- ---------- solicitudes: proyecto propio y solo líneas publicadas ----------
create policy rfqs_insert_guard
  on public.rfqs as restrictive
  for insert to authenticated
  with check (
    exists (
      select 1 from public.projects pr
      where pr.id = rfqs.project_id
        and pr.owner_user_id = (select auth.uid())
    )
    and exists (
      select 1
      from public.project_products pp
      join public.products p on p.id = pp.product_id
      where pp.project_id = rfqs.project_id
        and pp.selected_for_rfq
        and p.publication_status = 'published'
    )
    and not exists (
      select 1 from public.project_products pp
      where pp.project_id = rfqs.project_id
        and pp.selected_for_rfq
        and not exists (
          select 1 from public.products p
          where p.id = pp.product_id
            and p.publication_status = 'published'
        )
    )
  );

-- ---------- validaciones finales ----------
do $$
declare
  v_pol record;
  n_restrictive int;
  n_changed int;
begin
  -- Las dos políticas nuevas con la forma esperada (roles como conjunto)
  for v_pol in
    select * from (values
      ('project_products', 'project_products_only_published_insert', 'INSERT'),
      ('rfqs', 'rfqs_insert_guard', 'INSERT')
    ) as t(tablename, policyname, cmd)
  loop
    if not exists (select 1 from pg_policies
                    where schemaname = 'public' and tablename = v_pol.tablename
                      and policyname = v_pol.policyname and cmd = v_pol.cmd and permissive = 'RESTRICTIVE'
                      and roles @> array['authenticated']::name[]
                      and roles <@ array['authenticated']::name[]) then
      raise exception '38-B 04: % no existe con la forma esperada (RESTRICTIVE, %, authenticated)', v_pol.policyname, v_pol.cmd;
    end if;
  end loop;

  -- Restrictivas en las tablas de cliente: 5 de 03 + 2 de 04
  select count(*) into n_restrictive
    from pg_policies
   where schemaname = 'public' and permissive = 'RESTRICTIVE'
     and tablename in ('projects', 'project_products', 'rfqs', 'rfq_distributors');
  if n_restrictive <> 7 then
    raise exception '38-B 04: se esperaban exactamente 7 políticas restrictivas (5 de 03 + 2 de 04); hay %', n_restrictive;
  end if;

  -- rfq_distributors sigue sin ninguna política (no se toca en 38-B)
  if exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'rfq_distributors') then
    raise exception '38-B 04: rfq_distributors tiene políticas inesperadas';
  end if;

  -- Ninguna política previa (incluidas las de 03) se eliminó ni se modificó
  select count(*) into n_changed from (
    (select * from mobau_38b04_policies_before
     except
     select tablename::text, policyname::text, cmd, permissive, roles::text, qual, with_check
       from pg_policies
      where schemaname = 'public' and tablename in ('projects', 'project_products', 'rfqs', 'rfq_distributors'))
    union all
    (select tablename::text, policyname::text, cmd, permissive, roles::text, qual, with_check
       from pg_policies
      where schemaname = 'public' and tablename in ('projects', 'project_products', 'rfqs', 'rfq_distributors')
        and policyname not in ('project_products_only_published_insert', 'rfqs_insert_guard')
     except
     select * from mobau_38b04_policies_before)
  ) d;
  if n_changed <> 0 then
    raise exception '38-B 04: alguna política previa cambió (% diferencias)', n_changed;
  end if;

  -- authenticated conserva SELECT, INSERT y DELETE de tabla sobre project_products (sin regresión)
  if not (has_table_privilege('authenticated', 'public.project_products', 'SELECT')
          and has_table_privilege('authenticated', 'public.project_products', 'INSERT')
          and has_table_privilege('authenticated', 'public.project_products', 'DELETE')) then
    raise exception '38-B 04: authenticated perdió SELECT, INSERT o DELETE sobre project_products';
  end if;

  -- product_id y project_id nunca actualizables por authenticated
  if has_column_privilege('authenticated', 'public.project_products', 'product_id', 'UPDATE')
     or has_column_privilege('authenticated', 'public.project_products', 'project_id', 'UPDATE') then
    raise exception '38-B 04: authenticated puede actualizar product_id o project_id';
  end if;
end $$;

COMMIT;
