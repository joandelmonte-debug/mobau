-- ============================================================
-- PROPUESTA NO EJECUTADA (38-C) — no ejecutar sin aprobación explícita
-- ============================================================
-- 38-C · 03 · Acceso del distribuidor verificado a sus propuestas
-- ------------------------------------------------------------
-- Requiere 38-C 01 y 02. Abre las tablas SOLO al distribuidor verificado
-- y SOLO para sus propias propuestas:
--   product_proposals  SELECT (políticas) · INSERT y UPDATE de columnas
--                      concretas (permisos por columna + políticas)
--                      · sin DELETE (retirar = status 'withdrawn').
--   proposal_events    solo SELECT del historial de sus propuestas.
-- anon: ningún permiso. Mobau: ninguna política (punto 39); desde el
-- editor SQL (rol con BYPASSRLS) sigue pudiendo consultar.
--
-- Por qué permisos por columna y no una política "sin campos de Mobau":
-- una política RLS no puede usar OLD y, siendo permisiva, se sumaría con
-- OR a las demás. La protección de los campos de Mobau es doble:
--   1) sin permiso de escritura sobre rejection_reason, reviewed_at,
--      reviewed_by, product_snapshot, submitted_at, version, author_id,
--      distributor_id, product_id (en UPDATE) ni created_at/updated_at;
--   2) el trigger 20 (38-C 02) rechaza cualquier cambio en esos campos.
--
-- INSERT: el cliente envía product_id, proposed_changes, precio propuesto
-- e internal_note. status no se puede enviar (toma el valor por defecto
-- 'draft'); distributor_id y author_id los fija el trigger 10.
-- Ejecutar completo (BEGIN … COMMIT).
-- ============================================================

BEGIN;

-- ---------- prechecks ----------
DO $$
begin
  if to_regclass('public.product_proposals') is null or to_regclass('public.proposal_events') is null then
    raise exception '38-C 03: falta 38-C 01';
  end if;
  if (select count(*) from pg_trigger
       where not tgisinternal and tgrelid = 'public.product_proposals'::regclass
         and tgname like 'trg_product_proposals_%') <> 7 then
    raise exception '38-C 03: falta 38-C 02 (se esperan 7 triggers en product_proposals)';
  end if;
  if exists (select 1 from pg_policies where schemaname = 'public' and tablename in ('product_proposals', 'proposal_events')) then
    raise exception '38-C 03: las tablas de propuestas ya tienen políticas';
  end if;
  if has_table_privilege('authenticated', 'public.product_proposals', 'SELECT,INSERT,UPDATE,DELETE')
     or has_any_column_privilege('authenticated', 'public.product_proposals', 'SELECT,INSERT,UPDATE')
     or has_table_privilege('authenticated', 'public.proposal_events', 'SELECT,INSERT,UPDATE,DELETE') then
    raise exception '38-C 03: authenticated ya tiene permisos sobre las tablas de propuestas';
  end if;
  if (select count(*) from pg_policies where schemaname = 'public') <> 40 then
    raise exception '38-C 03: se esperaban 40 políticas en public antes de 03';
  end if;
end $$;

-- ---------- políticas: product_proposals ----------
create policy product_proposals_select_own
  on public.product_proposals
  for select
  to authenticated
  using (distributor_id = (select public.my_verified_distributor_id()));

create policy product_proposals_insert_own
  on public.product_proposals
  for insert
  to authenticated
  with check (
    distributor_id = (select public.my_verified_distributor_id())
    and status = 'draft'
  );

create policy product_proposals_update_own
  on public.product_proposals
  for update
  to authenticated
  using (distributor_id = (select public.my_verified_distributor_id()))
  with check (
    distributor_id = (select public.my_verified_distributor_id())
    and status in ('draft', 'submitted', 'changes_requested', 'withdrawn')
  );

-- ---------- políticas: proposal_events ----------
create policy proposal_events_select_own
  on public.proposal_events
  for select
  to authenticated
  using (
    proposal_id in (
      select pp.id from public.product_proposals pp
       where pp.distributor_id = (select public.my_verified_distributor_id())
    )
  );

-- ---------- permisos ----------
grant select on table public.product_proposals to authenticated;
grant insert (product_id, proposed_changes, proposed_price_status, proposed_price_amount, internal_note)
  on table public.product_proposals to authenticated;
grant update (proposed_changes, proposed_price_status, proposed_price_amount, internal_note, status)
  on table public.product_proposals to authenticated;

grant select on table public.proposal_events to authenticated;

-- anon sigue sin nada (01 ya lo revocó; se repite por claridad).
revoke all on table public.product_proposals from anon;
revoke all on table public.proposal_events from anon;

-- ---------- validación final ----------
DO $$
declare
  v_insert_cols text;
  v_update_cols text;
  v_seq text := pg_get_serial_sequence('public.proposal_events', 'id');
begin
  -- Políticas exactas
  if (select count(*) from pg_policies
       where schemaname = 'public' and tablename = 'product_proposals'
         and permissive = 'PERMISSIVE' and roles = '{authenticated}'
         and policyname in ('product_proposals_select_own', 'product_proposals_insert_own', 'product_proposals_update_own')) <> 3
     or (select count(*) from pg_policies where schemaname = 'public' and tablename = 'product_proposals') <> 3 then
    raise exception '38-C 03: product_proposals no tiene exactamente las 3 políticas esperadas';
  end if;
  if (select count(*) from pg_policies
       where schemaname = 'public' and tablename = 'proposal_events'
         and policyname = 'proposal_events_select_own' and cmd = 'SELECT' and roles = '{authenticated}') <> 1
     or (select count(*) from pg_policies where schemaname = 'public' and tablename = 'proposal_events') <> 1 then
    raise exception '38-C 03: proposal_events no tiene exactamente la política de lectura esperada';
  end if;
  if (select count(*) from pg_policies where schemaname = 'public') <> 44 then
    raise exception '38-C 03: se esperaban 44 políticas en public (40 + 4)';
  end if;

  -- anon: nada
  if has_table_privilege('anon', 'public.product_proposals', 'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER')
     or has_any_column_privilege('anon', 'public.product_proposals', 'SELECT,INSERT,UPDATE,REFERENCES')
     or has_table_privilege('anon', 'public.proposal_events', 'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER')
     or has_any_column_privilege('anon', 'public.proposal_events', 'SELECT,INSERT,UPDATE,REFERENCES') then
    raise exception '38-C 03: anon tiene algún permiso sobre las tablas de propuestas';
  end if;

  -- authenticated en product_proposals: lectura, escritura solo por columnas, sin borrar
  if not has_table_privilege('authenticated', 'public.product_proposals', 'SELECT') then
    raise exception '38-C 03: authenticated no puede leer product_proposals';
  end if;
  if has_table_privilege('authenticated', 'public.product_proposals', 'INSERT')
     or has_table_privilege('authenticated', 'public.product_proposals', 'UPDATE')
     or has_table_privilege('authenticated', 'public.product_proposals', 'DELETE,TRUNCATE,REFERENCES,TRIGGER') then
    raise exception '38-C 03: authenticated tiene permisos de tabla de más en product_proposals';
  end if;
  select string_agg(column_name, ',' order by column_name) into v_insert_cols
    from information_schema.column_privileges
   where table_schema = 'public' and table_name = 'product_proposals'
     and grantee = 'authenticated' and privilege_type = 'INSERT';
  select string_agg(column_name, ',' order by column_name) into v_update_cols
    from information_schema.column_privileges
   where table_schema = 'public' and table_name = 'product_proposals'
     and grantee = 'authenticated' and privilege_type = 'UPDATE';
  if v_insert_cols is distinct from 'internal_note,product_id,proposed_changes,proposed_price_amount,proposed_price_status' then
    raise exception '38-C 03: columnas de INSERT inesperadas: %', v_insert_cols;
  end if;
  if v_update_cols is distinct from 'internal_note,proposed_changes,proposed_price_amount,proposed_price_status,status' then
    raise exception '38-C 03: columnas de UPDATE inesperadas: %', v_update_cols;
  end if;

  -- authenticated en proposal_events: solo lectura
  if not has_table_privilege('authenticated', 'public.proposal_events', 'SELECT')
     or has_table_privilege('authenticated', 'public.proposal_events', 'INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER')
     or has_any_column_privilege('authenticated', 'public.proposal_events', 'INSERT,UPDATE') then
    raise exception '38-C 03: authenticated debe tener solo SELECT en proposal_events';
  end if;
  if has_sequence_privilege('authenticated', v_seq, 'USAGE,SELECT,UPDATE')
     or has_sequence_privilege('anon', v_seq, 'USAGE,SELECT,UPDATE') then
    raise exception '38-C 03: la secuencia de proposal_events no debe tener permisos de cliente';
  end if;

  raise notice '38-C 03 OK: 4 políticas (44 en public); escritura del distribuidor solo por columnas; anon sin acceso.';
end $$;

COMMIT;
