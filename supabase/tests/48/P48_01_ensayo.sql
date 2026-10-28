-- ============================================================
-- PROPUESTA NO EJECUTADA — Ensayo de 48-01 (republicación: copia completa) · rollback deliberado · SOLO mobau-pruebas
-- ============================================================
-- Una sola transacción que termina SIEMPRE con una excepción (nada persiste). Estructura:
--   PARTE A  con las funciones ORIGINALES: crea productos z48-*, los retira y envía republicaciones (copias antiguas, sin las 3 columnas).
--   MIGRACIÓN 48-01 (sin BEGIN/COMMIT; el generador la pega en la marca @@MIGRACION@@).
--   PARTE B  con 48-01 aplicada: copias nuevas, cambios posteriores, null / '' / ausente, compatibilidad acotada, regresiones y,
--            al final, la RECUPERACIÓN (comprueba que las funciones vuelven a su md5 original).
-- Identidades de mobau-pruebas: proveedor verificado a7861ec2… (distribuidor-prueba) y admin fba6bf4d… con aal2 simulado.
-- ============================================================

-- ---------- PARTE A ----------
select set_config('statement_timeout', '60s', true), set_config('lock_timeout', '5s', true);

create temp table ens (k text primary key, v text);
create temp table res (n serial, name text, ok boolean, detail text);
create function pg_temp.chk(p_name text, p_ok boolean, p_detail text default null) returns void language sql as
  $f$ insert into pg_temp.res (name, ok, detail) values (p_name, coalesce(p_ok, false), p_detail) $f$;

create function pg_temp.as_user(p_uid uuid, p_aal text, p_sql text) returns text language plpgsql as $f$
declare n bigint; m text; h text;
begin
  perform set_config('request.jwt.claims', jsonb_build_object('sub', p_uid::text, 'role', 'authenticated', 'aal', p_aal)::text, true);
  perform set_config('role', 'authenticated', true);
  if auth.uid() is distinct from p_uid or current_user <> 'authenticated' then
    perform set_config('role', 'postgres', true);
    raise exception 'PARA: contexto distinto del esperado';
  end if;
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

-- Moderación como admin con aal2 simulado: devuelve el jsonb de la función (o el error).
create function pg_temp.mod(p_id uuid) returns jsonb language plpgsql as $f$
declare r jsonb; v int; m text; h text; adm uuid := 'fba6bf4d-6631-4b1b-ae41-f10128decc84';
begin
  select version into v from public.product_proposals where id = p_id;
  perform set_config('request.jwt.claims', jsonb_build_object('sub', adm::text, 'role', 'authenticated', 'aal', 'aal2')::text, true);
  perform set_config('role', 'authenticated', true);
  begin
    select public.moderate_product_proposal(p_id, 'approve', null, v) into r;
    perform set_config('role', 'postgres', true);
    return r;
  exception when others then
    get stacked diagnostics m = message_text, h = pg_exception_hint;
    perform set_config('role', 'postgres', true);
    return jsonb_build_object('error', sqlstate, 'message', m, 'hint', h);
  end;
end $f$;

-- Producto sintético publicado (opcionalmente con portada) -> retirado -> republicación enviada por el distribuidor. Devuelve la propuesta.
create function pg_temp.mk_republish(p_id text, p_ref text, p_light text default null, p_cover boolean default false, p_as_user boolean default false) returns uuid language plpgsql as $f$
declare dist uuid := (select id from auth.users where email = 'proveedor-verificado@example.test'); pid uuid; r text; a uuid;
begin
  -- Sin identidad simulada: con auth.uid() no nulo, products_before_insert reescribe id y distributor_id (así lo hace la app).
  perform set_config('request.jwt.claims', '', true);
  insert into public.products (id, name, distributor_id, category_id, publication_status, catalog_role, reference_code, light_source, description)
  values (p_id, 'Z48 ' || p_id, 'distribuidor-prueba', 'iluminacion', 'published', 'principal', p_ref, p_light, 'Ensayo 48');
  if p_cover then
    insert into public.product_assets (distributor_id, product_id, kind, bucket, path, original_name, format, status)
      values ('distribuidor-prueba', p_id, 'foto', 'productos-imagenes', 'distribuidor-prueba/z48/' || p_id || '-1.jpg', 'a.jpg', 'jpg', 'aprobado') returning id into a;
    update public.products set cover_asset_id = a where id = p_id;
  end if;
  update public.products set publication_status = 'archived', retired_at = now(), retired_by = dist, retired_reason = 'Ensayo 48' where id = p_id;
  if p_as_user then
    -- Ruta real del distribuidor (permisos por columna de authenticated incluidos). Solo se puede usar UNA vez por transacción
    -- (tras la primera, mi RLS de products en esta sesión de ensayo deja de ver los demás retirados; ver informe).
    r := pg_temp.as_user(dist, 'aal1', format($q$insert into public.product_proposals (proposal_kind, product_id) values ('republish', %L)$q$, p_id));
    if r not like 'OK%' then raise exception 'PARA: no se pudo crear el borrador de %: %', p_id, r; end if;
    select id into pid from public.product_proposals where product_id = p_id and status = 'draft';
    r := pg_temp.as_user(dist, 'aal1', format($q$update public.product_proposals set status = 'submitted' where id = %L$q$, pid));
    if r not like 'OK%' then raise exception 'PARA: no se pudo enviar %: %', p_id, r; end if;
  else
    -- Sin identidad (auth.uid() nulo) la guarda del ciclo de vida usa el distributor_id de la propia fila.
    perform set_config('request.jwt.claims', '', true);
    insert into public.product_proposals (proposal_kind, product_id, distributor_id) values ('republish', p_id, 'distribuidor-prueba') returning id into pid;
    update public.product_proposals set status = 'submitted' where id = pid;
  end if;
  return pid;
end $f$;

create function pg_temp.mk_update(p_id text, p_changes jsonb) returns uuid language plpgsql as $f$
declare pid uuid; dist uuid := (select id from auth.users where email = 'proveedor-verificado@example.test');
begin
  perform set_config('request.jwt.claims', '', true);
  insert into public.product_proposals (proposal_kind, product_id, distributor_id, proposed_changes) values ('update', p_id, 'distribuidor-prueba', p_changes) returning id into pid;
  update public.product_proposals set status = 'submitted' where id = pid;
  return pid;
end $f$;

-- Estado (producto + propuesta) y eventos, para comprobar que un intento fallido no deja cambios parciales.
-- Dentro de una transacción now() no avanza y trg_products_updated_at no cambiaría updated_at; en producción cada edición es otra
-- transacción. bump() reproduce eso: renueva updated_at con el reloj real desactivando solo trg_products_updated_at durante esa sentencia.
create function pg_temp.bump(p_prod text) returns void language plpgsql as $f$
begin
  set constraints all immediate;   -- ALTER TABLE exige que no haya eventos de disparador pendientes
  execute 'alter table public.products disable trigger trg_products_updated_at';
  update public.products set updated_at = clock_timestamp() where id = p_prod;
  set constraints all immediate;
  execute 'alter table public.products enable trigger trg_products_updated_at';
end $f$;

create function pg_temp.st(p_prod text, p_prop uuid) returns text language sql as
  $f$ select md5((select to_jsonb(x)::text from public.products x where id = p_prod) || (select to_jsonb(y)::text from public.product_proposals y where id = p_prop)) $f$;
create function pg_temp.nev(p_prop uuid) returns int language sql as
  $f$ select count(*)::int from public.proposal_events where proposal_id = p_prop $f$;
create function pg_temp.has(r jsonb, p_field text, p_reason text) returns boolean language sql as
  $f$ select exists (select 1 from jsonb_array_elements(coalesce(r -> 'conflicts', '[]'::jsonb)) c where c ->> 'field' = p_field and (p_reason is null or c ->> 'reason' = p_reason)) $f$;

DO $A$
begin
  if current_user <> 'postgres' then raise exception 'P48: ejecutar como postgres'; end if;
  if (select md5(prosrc) from pg_proc where oid = 'public.snapshot_product_on_submit()'::regprocedure) <> 'c0de5fdc0a49f8dd2ef80cb0e8959fef'
     or (select md5(prosrc) from pg_proc where oid = 'public.moderate_product_proposal(uuid,text,text,integer)'::regprocedure) <> '16b7b1650b34ca486859dec098f1a67f' then
    raise exception 'P48: las funciones de partida no son las originales (el ensayo exige 48-01 SIN aplicar)';
  end if;
  if (select count(*) from public.products where id like 'z48-%') <> 0 then raise exception 'P48: ya hay productos z48'; end if;
  if (select count(*) from public.product_proposals where status in ('draft', 'submitted', 'changes_requested')) <> 0 then
    raise exception 'P48: hay propuestas abiertas ajenas; el ensayo se detiene';
  end if;

  -- Copias antiguas (26 claves, sin marca): L1 sin cambios; L2 cambio real posterior (description); L3 cambia solo reference_code; L4 para la 4.ª columna.
  insert into ens values ('L1', pg_temp.mk_republish('z48-l1', 'Z48-L1')::text);
  insert into ens values ('L2', pg_temp.mk_republish('z48-l2', 'Z48-L2')::text);
  insert into ens values ('L3', pg_temp.mk_republish('z48-l3', 'Z48-L3')::text);
  insert into ens values ('L4', pg_temp.mk_republish('z48-l4', 'Z48-L4')::text);
  update public.products set description = 'Cambiada tras el envío' where id = 'z48-l2';
  update public.products set reference_code = 'Z48-L3-NUEVA' where id = 'z48-l3';
  perform pg_temp.bump('z48-l2'); perform pg_temp.bump('z48-l3');
  perform pg_temp.chk('A1 copia antigua: 26 claves, sin marca schema, sin las 3 columnas',
    (select (select count(*) from jsonb_object_keys(product_snapshot -> 'product')) = 26
            and (product_snapshot ->> 'schema') is null
            and not ((product_snapshot -> 'product') ?| array['catalog_role', 'cover_asset_id', 'reference_code'])
       from public.product_proposals where id = (select v::uuid from ens where k = 'L1')));
end
$A$;

-- ---------- MIGRACIÓN 48-01 ----------
-- @@MIGRACION@@

-- ---------- PARTE B ----------
DO $B$
declare
  r jsonb; p uuid; e1 int; e2 int; h1 text; h2 text; a2 uuid;
begin
  perform pg_temp.chk('B0 48-01 aplicada: ambas funciones distintas de las originales',
    (select md5(prosrc) from pg_proc where oid = 'public.snapshot_product_on_submit()'::regprocedure) <> 'c0de5fdc0a49f8dd2ef80cb0e8959fef'
    and (select md5(prosrc) from pg_proc where oid = 'public.moderate_product_proposal(uuid,text,text,integer)'::regprocedure) <> '16b7b1650b34ca486859dec098f1a67f');

  -- ===== N1 copia nueva, sin cambios: se permite =====
  p := pg_temp.mk_republish('z48-n1', 'Z48-N1', null, false, true);
  perform pg_temp.chk('N1a copia nueva: 29 claves, marca schema 2 y las 3 columnas (valor presente aunque sea null)',
    (select (select count(*) from jsonb_object_keys(product_snapshot -> 'product')) = 29 and (product_snapshot ->> 'schema') = '2'
            and ((product_snapshot -> 'product') ?& array['catalog_role', 'cover_asset_id', 'reference_code'])
       from public.product_proposals where id = p));
  r := pg_temp.mod(p);
  perform pg_temp.chk('N1b republicación con copia nueva y sin cambios posteriores: aprobada, producto publicado y sin retirada',
    (r ->> 'ok') = 'true' and (select publication_status = 'published' and retired_at is null from public.products where id = 'z48-n1')
    and (select status from public.product_proposals where id = p) = 'approved', r::text);

  -- ===== N2 cambio real posterior: se bloquea; el intento fallido no deja cambios parciales =====
  p := pg_temp.mk_republish('z48-n2', 'Z48-N2');
  update public.products set description = 'Cambiada tras el envío' where id = 'z48-n2';
  h1 := pg_temp.st('z48-n2', p); e1 := pg_temp.nev(p);
  r := pg_temp.mod(p);
  h2 := pg_temp.st('z48-n2', p); e2 := pg_temp.nev(p);
  perform pg_temp.chk('N2a cambio real posterior: conflicto en description (reason changed), sin ok', (r ->> 'code') = 'snapshot_conflict' and pg_temp.has(r, 'description', 'changed'), r::text);
  perform pg_temp.chk('N2b intento fallido: producto y propuesta idénticos; único cambio = 1 evento de auditoría snapshot_conflict; sigue retirado y enviada',
    h1 = h2 and e2 = e1 + 1 and (select payload ->> 'type' from public.proposal_events where proposal_id = p order by id desc limit 1) = 'snapshot_conflict'
    and (select publication_status from public.products where id = 'z48-n2') = 'archived' and (select status from public.product_proposals where id = p) = 'submitted',
    'eventos ' || e1 || '→' || e2);

  -- ===== N3 cambios en cada uno de los tres campos afectados (copia nueva): se detectan =====
  p := pg_temp.mk_republish('z48-n3r', 'Z48-N3R');
  update public.products set reference_code = 'Z48-N3R-CAMBIADA' where id = 'z48-n3r';
  perform pg_temp.bump('z48-n3r');
  r := pg_temp.mod(p);
  perform pg_temp.chk('N3a reference_code cambiado tras el envío: conflicto en reference_code (changed), solo él y updated_at', pg_temp.has(r, 'reference_code', 'changed') and pg_temp.has(r, 'updated_at', 'changed') and not pg_temp.has(r, 'catalog_role', null) and not pg_temp.has(r, 'cover_asset_id', null), r::text);

  p := pg_temp.mk_republish('z48-n3o', 'Z48-N3O');
  update public.products set catalog_role = 'ambos' where id = 'z48-n3o';
  r := pg_temp.mod(p);
  perform pg_temp.chk('N3b catalog_role cambiado tras el envío: conflicto en catalog_role (changed)', pg_temp.has(r, 'catalog_role', 'changed') and not pg_temp.has(r, 'reference_code', null), r::text);

  p := pg_temp.mk_republish('z48-n3c', 'Z48-N3C');
  insert into public.product_assets (distributor_id, product_id, kind, bucket, path, original_name, format, status)
    values ('distribuidor-prueba', 'z48-n3c', 'foto', 'productos-imagenes', 'distribuidor-prueba/z48/n3c-2.jpg', 'b.jpg', 'jpg', 'aprobado') returning id into a2;
  update public.products set cover_asset_id = a2 where id = 'z48-n3c';
  r := pg_temp.mod(p);
  perform pg_temp.chk('N3c cover_asset_id: de null a una portada tras el envío: conflicto (changed)', pg_temp.has(r, 'cover_asset_id', 'changed'), r::text);

  p := pg_temp.mk_republish('z48-n3d', 'Z48-N3D', null, true);
  insert into public.product_assets (distributor_id, product_id, kind, bucket, path, original_name, format, status)
    values ('distribuidor-prueba', 'z48-n3d', 'foto', 'productos-imagenes', 'distribuidor-prueba/z48/n3d-2.jpg', 'b.jpg', 'jpg', 'aprobado') returning id into a2;
  update public.products set cover_asset_id = a2 where id = 'z48-n3d';
  r := pg_temp.mod(p);
  perform pg_temp.chk('N3d cover_asset_id: de una portada a otra tras el envío: conflicto (changed)', pg_temp.has(r, 'cover_asset_id', 'changed'), r::text);

  p := pg_temp.mk_republish('z48-n3e', 'Z48-N3E', null, true);
  update public.products set cover_asset_id = null where id = 'z48-n3e';
  r := pg_temp.mod(p);
  perform pg_temp.chk('N3e cover_asset_id: de una portada a null tras el envío: conflicto (changed)', pg_temp.has(r, 'cover_asset_id', 'changed'), r::text);

  p := pg_temp.mk_republish('z48-n3f', 'Z48-N3F', null, true);
  r := pg_temp.mod(p);
  perform pg_temp.chk('N3f copia con portada y sin cambios: aprobada (la portada igual que al enviar no es conflicto)', (r ->> 'ok') = 'true', r::text);

  -- ===== N4 clave ausente, null y cadena vacía son distintos =====
  p := pg_temp.mk_republish('z48-n4a', 'Z48-N4A', null);
  update public.products set light_source = '' where id = 'z48-n4a';
  r := pg_temp.mod(p);
  perform pg_temp.chk('N4a copia con null y ahora cadena vacía: conflicto en light_source (changed)', pg_temp.has(r, 'light_source', 'changed'), r::text);
  p := pg_temp.mk_republish('z48-n4b', 'Z48-N4B', '');
  update public.products set light_source = null where id = 'z48-n4b';
  r := pg_temp.mod(p);
  perform pg_temp.chk('N4b copia con cadena vacía y ahora null: conflicto en light_source (changed)', pg_temp.has(r, 'light_source', 'changed'), r::text);
  p := pg_temp.mk_republish('z48-n4c', 'Z48-N4C', null);
  r := pg_temp.mod(p);
  perform pg_temp.chk('N4c null = null (clave presente en ambos lados): aprobada', (r ->> 'ok') = 'true', r::text);

  -- ===== L copias antiguas: compatibilidad explícita y acotada =====
  p := (select v::uuid from ens where k = 'L1');
  r := pg_temp.mod(p);
  perform pg_temp.chk('L1 copia antigua y fila SIN modificar desde el envío: aprobada (las 3 columnas no comparables se aceptan porque updated_at es idéntico)', (r ->> 'ok') = 'true', r::text);

  p := (select v::uuid from ens where k = 'L2');
  h1 := pg_temp.st('z48-l2', p); e1 := pg_temp.nev(p);
  r := pg_temp.mod(p);
  h2 := pg_temp.st('z48-l2', p); e2 := pg_temp.nev(p);
  perform pg_temp.chk('L2a copia antigua y cambio real (description): conflicto en description (changed) y las 3 columnas como legacy_not_comparable (la fila cambió)',
    (r ->> 'code') = 'snapshot_conflict' and pg_temp.has(r, 'description', 'changed') and pg_temp.has(r, 'catalog_role', 'legacy_not_comparable')
    and pg_temp.has(r, 'cover_asset_id', 'legacy_not_comparable') and pg_temp.has(r, 'reference_code', 'legacy_not_comparable'), r::text);
  perform pg_temp.chk('L2b intento fallido con copia antigua: sin cambios parciales (1 evento de auditoría)', h1 = h2 and e2 = e1 + 1, 'eventos ' || e1 || '→' || e2);

  p := (select v::uuid from ens where k = 'L3');
  r := pg_temp.mod(p);
  perform pg_temp.chk('L3 copia antigua y SOLO cambia reference_code: se bloquea (no se puede ver su valor, sí que la fila cambió)',
    (r ->> 'code') = 'snapshot_conflict' and pg_temp.has(r, 'reference_code', 'legacy_not_comparable') and pg_temp.has(r, 'updated_at', 'changed'), r::text);

  -- ===== R regresiones: los otros tipos de solicitud que usan estas funciones =====
  perform set_config('request.jwt.claims', '', true);
  insert into public.products (id, name, distributor_id, category_id, publication_status, catalog_role, reference_code, description)
    values ('z48-u1', 'Z48 u1', 'distribuidor-prueba', 'iluminacion', 'published', 'principal', 'Z48-U1', 'Original'),
           ('z48-u2', 'Z48 u2', 'distribuidor-prueba', 'iluminacion', 'published', 'principal', 'Z48-U2', 'Original'),
           ('z48-u3', 'Z48 u3', 'distribuidor-prueba', 'iluminacion', 'published', 'principal', 'Z48-U3', 'Original');
  -- update sin conflicto
  p := pg_temp.mk_update('z48-u1', '{"description": "Nueva descripción"}');
  perform pg_temp.chk('R0 update: propuesta enviada', (select status from public.product_proposals where id = p) = 'submitted');
  perform pg_temp.chk('R1a update: la copia nueva tiene 29 claves y marca schema 2', (select (select count(*) from jsonb_object_keys(product_snapshot -> 'product')) = 29 and (product_snapshot ->> 'schema') = '2' from public.product_proposals where id = p));
  r := pg_temp.mod(p);
  perform pg_temp.chk('R1b update sin cambios posteriores: aprobada y aplica el cambio', (r ->> 'ok') = 'true' and (select description from public.products where id = 'z48-u1') = 'Nueva descripción', r::text);
  p := pg_temp.mk_update('z48-u2', '{"description": "Otra"}');
  update public.products set description = 'Cambiada por otro' where id = 'z48-u2';
  r := pg_temp.mod(p);
  perform pg_temp.chk('R2 update con cambio posterior en el campo propuesto: sigue dando conflicto (como antes)', (r ->> 'code') = 'snapshot_conflict' and pg_temp.has(r, 'description', null), r::text);
  p := pg_temp.mk_update('z48-u3', '{"description": "Otra 3"}');
  update public.products set reference_code = 'Z48-U3-OTRA' where id = 'z48-u3';
  r := pg_temp.mod(p);
  perform pg_temp.chk('R3 update: cambio posterior en una columna no propuesta no bloquea (sin regresión)', (r ->> 'ok') = 'true', r::text);

  -- ===== D cuarta columna futura (desfase): se señala, no se ignora =====
  p := pg_temp.mk_republish('z48-d1', 'Z48-D1');               -- copia nueva (marca schema 2), creada ANTES de añadir la columna
  set constraints all immediate;   -- el disparador diferido de catalog_role impide el ALTER con eventos pendientes
  execute 'alter table public.products add column z48_futura text';
  r := pg_temp.mod(p);
  perform pg_temp.chk('D1 copia nueva y columna nueva en products sin añadir al trigger: conflicto snapshot_incomplete en esa columna (null actual, clave ausente), nunca en silencio',
    (r ->> 'code') = 'snapshot_conflict' and pg_temp.has(r, 'z48_futura', 'snapshot_incomplete'), r::text);
  p := (select v::uuid from ens where k = 'L4');
  r := pg_temp.mod(p);
  perform pg_temp.chk('D2 copia antigua sin modificar + columna nueva: las 3 conocidas se aceptan pero la columna nueva da snapshot_incomplete (la compatibilidad no se extiende a otras)',
    (r ->> 'code') = 'snapshot_conflict' and pg_temp.has(r, 'z48_futura', 'snapshot_incomplete') and not pg_temp.has(r, 'catalog_role', null) and not pg_temp.has(r, 'reference_code', null), r::text);
  set constraints all immediate;
  execute 'alter table public.products drop column z48_futura';

  -- ===== T guarda de cobertura: toda columna de products está en la copia o excluida expresamente =====
  perform pg_temp.chk('T1 guarda de cobertura: ninguna columna de products queda fuera de la copia (salvo las 7 de ciclo de vida)',
    (select count(*) = 0 from information_schema.columns c where c.table_schema = 'public' and c.table_name = 'products'
        and c.column_name not in ('retired_at', 'retired_by', 'retired_reason', 'trashed_at', 'trashed_by', 'trash_from', 'purge_after')
        and not ((select (product_snapshot -> 'product') ? c.column_name from public.product_proposals where id = (select id from public.product_proposals where product_id = 'z48-n1' limit 1))))
  , 'columnas de products fuera de la copia: ' || coalesce((select string_agg(c.column_name, ',') from information_schema.columns c where c.table_schema = 'public' and c.table_name = 'products'
        and c.column_name not in ('retired_at', 'retired_by', 'retired_reason', 'trashed_at', 'trashed_by', 'trash_from', 'purge_after')
        and not ((select (product_snapshot -> 'product') ? c.column_name from public.product_proposals where id = (select id from public.product_proposals where product_id = 'z48-n1' limit 1)))), '(ninguna)'));
end
$B$;

-- ---------- RECUPERACIÓN dentro de la misma transacción (prueba del script de recuperación) ----------
-- @@RECUPERACION@@

DO $C$
declare
  r text := ''; ok int := 0; ko int := 0; x record;
begin
  perform pg_temp.chk('Z1 recuperación: las dos funciones vuelven EXACTAMENTE a su md5 original',
    (select md5(prosrc) from pg_proc where oid = 'public.snapshot_product_on_submit()'::regprocedure) = 'c0de5fdc0a49f8dd2ef80cb0e8959fef'
    and (select md5(prosrc) from pg_proc where oid = 'public.moderate_product_proposal(uuid,text,text,integer)'::regprocedure) = '16b7b1650b34ca486859dec098f1a67f');
  for x in select * from pg_temp.res order by n loop
    r := r || E'\n[' || case when x.ok then 'OK' else 'FALLO' end || '] ' || x.name || case when x.ok then '' else ' · ' || coalesce(left(x.detail, 300), '') end;
    if x.ok then ok := ok + 1; else ko := ko + 1; end if;
  end loop;
  raise exception E'ENSAYO 48-01 · % OK, % FALLO (rollback deliberado)%', ok, ko, r;
end
$C$;
