-- ============================================================
-- PROPUESTA NO EJECUTADA — Ensayo de 48-02 (fecha de incorporación al catálogo) · rollback deliberado · SOLO mobau-pruebas
-- ============================================================
-- Requiere 48-01 y 48-02 YA aplicadas (estado final). Una sola transacción que termina SIEMPRE con una excepción (nada persiste).
-- Para distinguir fechas dentro de una transacción (now() no avanza) las filas de prueba se crean con una fecha antigua fija
-- (2020-01-01) desactivando el disparador solo en el ensayo; la renovación se reconoce porque deja de ser 2020.
-- ============================================================
select set_config('statement_timeout', '60s', true), set_config('lock_timeout', '5s', true);

create temp table res (n serial, name text, ok boolean, detail text);
create function pg_temp.chk(p_name text, p_ok boolean, p_detail text default null) returns void language sql as
  $f$ insert into pg_temp.res (name, ok, detail) values (p_name, coalesce(p_ok, false), p_detail) $f$;

create function pg_temp.as_user(p_uid uuid, p_aal text, p_sql text) returns text language plpgsql as $f$
declare n bigint; m text; h text;
begin
  perform set_config('request.jwt.claims', jsonb_build_object('sub', p_uid::text, 'role', 'authenticated', 'aal', p_aal)::text, true);
  perform set_config('role', 'authenticated', true);
  begin
    execute p_sql; get diagnostics n = row_count;
    perform set_config('role', 'postgres', true);
    return 'OK ' || n;
  exception when others then
    get stacked diagnostics m = message_text, h = pg_exception_hint;
    perform set_config('role', 'postgres', true);
    return 'ERROR ' || sqlstate || ' | ' || m || ' | hint=' || coalesce(h, '(ninguna)');
  end;
end $f$;

-- Moderación como admin (aal2 simulado): jsonb de la función o el error.
create function pg_temp.mod(p_id uuid, p_decision text default 'approve') returns jsonb language plpgsql as $f$
declare r jsonb; v int; m text; h text; adm uuid := 'fba6bf4d-6631-4b1b-ae41-f10128decc84';
begin
  select version into v from public.product_proposals where id = p_id;
  perform set_config('request.jwt.claims', jsonb_build_object('sub', adm::text, 'role', 'authenticated', 'aal', 'aal2')::text, true);
  perform set_config('role', 'authenticated', true);
  begin
    select public.moderate_product_proposal(p_id, p_decision, null, v) into r;
    perform set_config('role', 'postgres', true);
    return r;
  exception when others then
    get stacked diagnostics m = message_text, h = pg_exception_hint;
    perform set_config('role', 'postgres', true);
    return jsonb_build_object('error', sqlstate, 'message', m, 'hint', h);
  end;
end $f$;

create function pg_temp.old_date(p_id text) returns void language plpgsql as $f$
begin
  set constraints all immediate;
  execute 'alter table public.products disable trigger trg_products_catalog_entered_at';
  update public.products set catalog_entered_at = timestamptz '2020-01-01 00:00:00+00' where id = p_id;
  set constraints all immediate;
  execute 'alter table public.products enable trigger trg_products_catalog_entered_at';
end $f$;

-- Producto publicado con fecha antigua; opcionalmente retirado y con republicación enviada.
create function pg_temp.mk(p_id text, p_retire boolean default false, p_submit boolean default false) returns uuid language plpgsql as $f$
declare dist uuid := (select id from auth.users where email = 'proveedor-verificado@example.test'); pid uuid;
begin
  perform set_config('request.jwt.claims', '', true);
  insert into public.products (id, name, distributor_id, category_id, publication_status, catalog_role, reference_code, description)
    values (p_id, 'Z48S ' || p_id, 'distribuidor-prueba', 'iluminacion', 'published', 'principal', upper(p_id), 'Ensayo 48-02');
  perform pg_temp.old_date(p_id);
  if p_retire then
    update public.products set publication_status = 'archived', retired_at = now(), retired_by = dist, retired_reason = 'Ensayo 48-02' where id = p_id;
  end if;
  if p_submit then
    insert into public.product_proposals (proposal_kind, product_id, distributor_id) values ('republish', p_id, 'distribuidor-prueba') returning id into pid;
    update public.product_proposals set status = 'submitted' where id = pid;
  end if;
  return pid;
end $f$;

create function pg_temp.ed(p_id text) returns timestamptz language sql as $f$ select catalog_entered_at from public.products where id = p_id $f$;
create function pg_temp.has(r jsonb, p_field text, p_reason text) returns boolean language sql as
  $f$ select exists (select 1 from jsonb_array_elements(coalesce(r -> 'conflicts', '[]'::jsonb)) c where c ->> 'field' = p_field and (p_reason is null or c ->> 'reason' = p_reason)) $f$;

DO $B$
declare
  r jsonb; p uuid; t text; h1 text; h2 text; sub text; asset uuid;
  dist uuid := (select id from auth.users where email = 'proveedor-verificado@example.test');
  old_ts constant timestamptz := timestamptz '2020-01-01 00:00:00+00';
begin
  if (select md5(prosrc) from pg_proc where oid = 'public.moderate_product_proposal(uuid,text,text,integer)'::regprocedure) <> '44f72e48beb28f3f25108cc8688965b6'
     or (select md5(prosrc) from pg_proc where oid = 'public.snapshot_product_on_submit()'::regprocedure) <> '70c7ca25a047550c401a2e76ff1e2d52' then
    raise exception 'P48-02: el ensayo exige 48-01 y 48-02 aplicadas';
  end if;

  -- ===== E1 primera publicación =====
  -- E1a: producto nuevo publicado por la ruta de servicio (insert publicado) -> fecha = ahora; created_at igual (misma transacción)
  perform set_config('request.jwt.claims', '', true);
  insert into public.products (id, name, distributor_id, category_id, publication_status, description) values ('z48s-e1a', 'Z48S e1a', 'distribuidor-prueba', 'iluminacion', 'published', 'x');
  perform pg_temp.chk('E1a insert publicado: catalog_entered_at = now() y created_at intacto', (select catalog_entered_at = now() and created_at = now() from public.products where id = 'z48s-e1a'));
  -- E1b: borrador (DEFAULT draft) no tiene fecha; al publicarse por primera vez la recibe
  insert into public.products (id, name, distributor_id, category_id, description) values ('z48s-e1b', 'Z48S e1b', 'distribuidor-prueba', 'iluminacion', 'x');
  perform pg_temp.chk('E1b borrador: sin fecha de incorporación', (select publication_status = 'draft' and catalog_entered_at is null from public.products where id = 'z48s-e1b'));
  update public.products set description = 'borrador editado' where id = 'z48s-e1b';
  perform pg_temp.chk('E1c editar el borrador no le da fecha', pg_temp.ed('z48s-e1b') is null);
  update public.products set publication_status = 'published' where id = 'z48s-e1b';
  perform pg_temp.chk('E1d primera publicación de un borrador: fecha = ahora', pg_temp.ed('z48s-e1b') = now());
  -- E1e: aprobación real de una propuesta «create» (con foto de portada y referencia, como exige la app): el producto nace publicado con fecha
  perform set_config('request.jwt.claims', '', true);
  select subcategories[1] into sub from public.categories where id = 'iluminacion';
  insert into public.product_assets (distributor_id, kind, bucket, path, variants, original_name, format, status)
    values ('distribuidor-prueba', 'foto', 'productos-imagenes', 'distribuidor-prueba/z48s/e1e-1.jpg', jsonb_build_object('card', 'distribuidor-prueba/z48s/e1e-1-card.jpg'), 'a.jpg', 'jpg', 'pendiente') returning id into asset;
  insert into public.product_proposals (id, proposal_kind, distributor_id, status, version, proposed_changes, proposed_media, submitted_at)
    values ('00000000-0000-4000-8000-0000000048e1', 'create', 'distribuidor-prueba', 'submitted', 1,
            jsonb_build_object('name', 'Z48S creado por propuesta', 'brand', 'Marca 48', 'description', 'Descripción 48', 'category_id', 'iluminacion', 'subcategory', sub,
                               'availability', 'por-confirmar', 'lead_time', '2 semanas', 'measurements', '10 x 10 cm', 'materials', 'Aluminio', 'finishes', 'Negro',
                               'use_context', 'residencial', 'space', 'sala', 'environment', 'interior'),
            jsonb_build_object('reference_code', 'Z48S-NEW', 'cover_asset_id', asset, 'assets', jsonb_build_array(jsonb_build_object('id', asset))), now());
  r := pg_temp.mod('00000000-0000-4000-8000-0000000048e1');
  perform pg_temp.chk('E1e propuesta create aprobada: producto publicado con catalog_entered_at',
    (r ->> 'ok') = 'true' and (select publication_status = 'published' and catalog_entered_at = now() and created_at = now() from public.products where id = r ->> 'created_product_id'), r::text);

  -- ===== E2 republicación: renueva =====
  p := pg_temp.mk('z48s-e2', true, true);
  perform pg_temp.chk('E2a retirar no cambia la fecha (queda la antigua)', pg_temp.ed('z48s-e2') = old_ts);
  perform pg_temp.chk('E2b borrador y envío de la republicación no cambian la fecha', pg_temp.ed('z48s-e2') = old_ts and (select status from public.product_proposals where id = p) = 'submitted');
  r := pg_temp.mod(p);
  perform pg_temp.chk('E2c republicación aprobada: fecha renovada (ya no es la antigua) y = ahora', (r ->> 'ok') = 'true' and pg_temp.ed('z48s-e2') = now(), r::text);
  perform pg_temp.chk('E2d created_at intacto tras republicar', (select created_at = now() from public.products where id = 'z48s-e2'));  -- se creó en esta transacción

  -- ===== E3 aprobación repetida y reintento: no renuevan =====
  perform pg_temp.old_date('z48s-e2');
  h1 := (select md5(to_jsonb(x)::text) from public.products x where id = 'z48s-e2');
  r := pg_temp.mod(p);
  perform pg_temp.chk('E3a aprobar otra vez la solicitud ya aprobada: error 55000 y fecha/fila intactas',
    (r ->> 'error') = '55000' and pg_temp.ed('z48s-e2') = old_ts and h1 = (select md5(to_jsonb(x)::text) from public.products x where id = 'z48s-e2'), r::text);

  -- ===== E4 edición de un publicado aprobado: conserva =====
  p := null;
  perform pg_temp.mk('z48s-e4');
  insert into public.product_proposals (proposal_kind, product_id, distributor_id, proposed_changes) values ('update', 'z48s-e4', 'distribuidor-prueba', '{"description": "Editada"}') returning id into p;
  update public.product_proposals set status = 'submitted' where id = p;
  r := pg_temp.mod(p);
  perform pg_temp.chk('E4 update aprobado sobre un publicado: aplica el cambio y conserva la fecha',
    (r ->> 'ok') = 'true' and (select description from public.products where id = 'z48s-e4') = 'Editada' and pg_temp.ed('z48s-e4') = old_ts, r::text);

  -- ===== E5 intentos de cambiar la fecha =====
  perform pg_temp.mk('z48s-e5');
  update public.products set catalog_entered_at = now() where id = 'z48s-e5';
  perform pg_temp.chk('E5a UPDATE directo de la columna en un publicado: se ignora', pg_temp.ed('z48s-e5') = old_ts);
  update public.products set catalog_entered_at = null where id = 'z48s-e5';
  perform pg_temp.chk('E5b poner la fecha a null en un publicado: se ignora (el CHECK nunca salta)', pg_temp.ed('z48s-e5') = old_ts);
  t := pg_temp.as_user(dist, 'aal1', $q$update public.products set catalog_entered_at = now() where id = 'z48s-e5'$q$);
  perform pg_temp.chk('E5c un distribuidor no puede actualizar la columna (sin permiso)', t like 'ERROR 42501%', t);
  t := pg_temp.as_user(dist, 'aal1', $q$select catalog_entered_at from public.catalog_products limit 1$q$);
  perform pg_temp.chk('E5d la columna se lee desde catalog_products', t like 'OK%', t);

  -- ===== E6 intento fallido: no renueva ni deja cambios parciales =====
  p := pg_temp.mk('z48s-e6', true, true);
  update public.products set description = 'Cambiada tras el envío' where id = 'z48s-e6';
  h1 := (select md5(to_jsonb(x)::text) from public.products x where id = 'z48s-e6');
  r := pg_temp.mod(p);
  h2 := (select md5(to_jsonb(x)::text) from public.products x where id = 'z48s-e6');
  perform pg_temp.chk('E6 aprobación con conflicto: bloqueada, fecha y fila intactas, sigue retirado',
    (r ->> 'code') = 'snapshot_conflict' and h1 = h2 and pg_temp.ed('z48s-e6') = old_ts and (select publication_status from public.products where id = 'z48s-e6') = 'archived', r::text);
  r := pg_temp.mod(p, 'reject');
  perform pg_temp.chk('E6b rechazar (mensaje obligatorio) no renueva', (r ->> 'error') is not null and pg_temp.ed('z48s-e6') = old_ts, r::text);

  -- ===== C compatibilidad 48-01 + 48-02 en la comparación de la republicación =====
  -- C1 copia nueva (sin catalog_entered_at, 29 claves): se aprueba aunque la fila actual SÍ tiene catalog_entered_at
  p := pg_temp.mk('z48s-c1', true, true);
  perform pg_temp.chk('C1a la copia no incluye catalog_entered_at (excluida a propósito) y tiene 29 claves + marca',
    (select not ((product_snapshot -> 'product') ? 'catalog_entered_at') and (select count(*) from jsonb_object_keys(product_snapshot -> 'product')) = 29 and (product_snapshot ->> 'schema') = '2' from public.product_proposals where id = p));
  r := pg_temp.mod(p);
  perform pg_temp.chk('C1b republicación con copia nueva tras 48-02: aprobada y fecha renovada', (r ->> 'ok') = 'true' and pg_temp.ed('z48s-c1') = now(), r::text);
  -- C2 copia ANTIGUA (26 claves) fabricada como las pendientes anteriores a 48-01
  p := pg_temp.mk('z48s-c2', true, true);
  set constraints all immediate;
  execute 'alter table public.product_proposals disable trigger user';
  update public.product_proposals set product_snapshot = jsonb_set(product_snapshot - 'schema', '{product}', (product_snapshot -> 'product') - 'catalog_role' - 'cover_asset_id' - 'reference_code') where id = p;
  execute 'alter table public.product_proposals enable trigger user';
  perform pg_temp.chk('C2a copia antigua fabricada: 26 claves, sin marca', (select (select count(*) from jsonb_object_keys(product_snapshot -> 'product')) = 26 and (product_snapshot ->> 'schema') is null from public.product_proposals where id = p));
  r := pg_temp.mod(p);
  perform pg_temp.chk('C2b copia antigua sin cambios + 48-02: aprobada (la fecha no la bloquea) y fecha renovada', (r ->> 'ok') = 'true' and pg_temp.ed('z48s-c2') = now(), r::text);
  -- C3 copia antigua con cambio posterior: sigue bloqueada
  p := pg_temp.mk('z48s-c3', true, true);
  execute 'alter table public.product_proposals disable trigger user';
  update public.product_proposals set product_snapshot = jsonb_set(product_snapshot - 'schema', '{product}', (product_snapshot -> 'product') - 'catalog_role' - 'cover_asset_id' - 'reference_code') where id = p;
  execute 'alter table public.product_proposals enable trigger user';
  set constraints all immediate;
  execute 'alter table public.products disable trigger trg_products_updated_at';
  update public.products set reference_code = 'Z48S-C3-NUEVA', updated_at = clock_timestamp() where id = 'z48s-c3';
  set constraints all immediate;
  execute 'alter table public.products enable trigger trg_products_updated_at';
  r := pg_temp.mod(p);
  perform pg_temp.chk('C3 copia antigua + cambio de reference_code + 48-02: bloqueada (legacy_not_comparable), sin conflicto por catalog_entered_at',
    (r ->> 'code') = 'snapshot_conflict' and pg_temp.has(r, 'reference_code', 'legacy_not_comparable') and not pg_temp.has(r, 'catalog_entered_at', null), r::text);
  -- C4 columna futura sin añadir al trigger: se sigue señalando (la exclusión de catalog_entered_at no enmascara otras)
  p := pg_temp.mk('z48s-c4', true, true);
  set constraints all immediate;
  execute 'alter table public.products add column z48_futura text';
  r := pg_temp.mod(p);
  perform pg_temp.chk('C4 columna nueva ajena: snapshot_incomplete en ella y ninguno en catalog_entered_at',
    (r ->> 'code') = 'snapshot_conflict' and pg_temp.has(r, 'z48_futura', 'snapshot_incomplete') and not pg_temp.has(r, 'catalog_entered_at', null), r::text);
  set constraints all immediate;
  execute 'alter table public.products drop column z48_futura';
  -- C5 guarda de cobertura con las 8 columnas de ciclo de vida
  perform pg_temp.chk('C5 guarda de cobertura: toda columna de products está en la copia salvo las 8 de ciclo de vida',
    (select count(*) = 0 from information_schema.columns c where c.table_schema = 'public' and c.table_name = 'products'
        and c.column_name not in ('retired_at', 'retired_by', 'retired_reason', 'trashed_at', 'trashed_by', 'trash_from', 'purge_after', 'catalog_entered_at')
        and not ((select (product_snapshot -> 'product') ? c.column_name from public.product_proposals where id = (select id from public.product_proposals where product_id = 'z48s-c1' limit 1))))
    , 'fuera de la copia: ' || coalesce((select string_agg(c.column_name, ',') from information_schema.columns c where c.table_schema = 'public' and c.table_name = 'products'
        and c.column_name not in ('retired_at', 'retired_by', 'retired_reason', 'trashed_at', 'trashed_by', 'trash_from', 'purge_after', 'catalog_entered_at')
        and not ((select (product_snapshot -> 'product') ? c.column_name from public.product_proposals where id = (select id from public.product_proposals where product_id = 'z48s-c1' limit 1)))), '(ninguna)'));

  -- ===== I invariantes de los datos existentes =====
  perform pg_temp.chk('I1 productos existentes: catalog_entered_at = created_at (publicados y archivados)',
    (select count(*) = 0 from public.products where id not like 'z48s-%' and publication_status in ('published', 'archived') and catalog_entered_at is distinct from created_at));
  perform pg_temp.chk('I2 los borradores existentes no tienen fecha', (select count(*) = 0 from public.products where id not like 'z48s-%' and publication_status not in ('published', 'archived') and catalog_entered_at is not null));
  perform pg_temp.chk('I3 CHECK de publicado presente y válido', exists (select 1 from pg_constraint where conname = 'products_catalog_entered_published_check' and convalidated));
end
$B$;

DO $C$
declare
  r text := ''; ok int := 0; ko int := 0; x record;
begin
  for x in select * from pg_temp.res order by n loop
    r := r || E'\n[' || case when x.ok then 'OK' else 'FALLO' end || '] ' || x.name || case when x.ok then '' else ' · ' || coalesce(left(x.detail, 300), '') end;
    if x.ok then ok := ok + 1; else ko := ko + 1; end if;
  end loop;
  raise exception E'ENSAYO 48-02 · % OK, % FALLO (rollback deliberado)%', ok, ko, r;
end
$C$;
