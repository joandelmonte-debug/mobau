-- ============================================================
-- PROPUESTA NO EJECUTADA (39) — no ejecutar sin aprobación explícita
-- ============================================================
-- 39 · Pruebas de moderación de propuestas, en una transacción revertida
-- ------------------------------------------------------------
-- Ejecutar SOLO después de aplicar 39-01 a 39-04. Editor SQL de Supabase
-- (rol postgres). Mismo patrón que 38b/38c_rls_checks.sql.
--
-- PRUEBAS UNITARIAS DE BASE DE DATOS CON JWT SIMULADO. Comprueban la
-- lógica SQL (autorización, triggers, conflictos, atomicidad) fijando a
-- mano las claims del JWT. NO validan el MFA real: no prueban que Supabase
-- emita aal2 tras el challenge/verify de TOTP. Esa prueba es aparte (plan
-- de prueba MFA real en 39-IMPLEMENTACION-REVISION.md).
--
-- Identidades (sin crear cuentas ni roles):
--   * Distribuidor A: el distribuidor verificado real.
--   * Admin temporal: el profesional real, dado de alta en mobau_admins
--     SOLO dentro de la subtransacción del caso (se deshace con el caso).
--     Nunca queda un admin permanente.
--   * Admin + distribuidor (casos F, S y C): el propio distribuidor A dado
--     de alta como admin temporal, para probar que no puede autodecidir.
--
-- Admins reales: mobau_admins puede tener filas reales. Precondición: ni el
-- profesional ni el distribuidor A tienen fila en mobau_admins (activa o
-- revocada), porque estas pruebas los dan de alta como admins temporales.
-- Antes de los casos se toma una línea base completa de mobau_admins
-- (recuento y MD5 de todas las filas y columnas, sin filtrar ninguna) y R02
-- exige que al final sea idéntica.
-- Eventos: también se toma el número de eventos ya registrados por el
-- distribuidor A y por el profesional (puede haber eventos reales). S06–S08
-- y E01–E04 exigen que los intentos bloqueados no añadan ninguno.
--
-- Casos C: algunas filas de contexto se preparan como postgres (solo
-- posible con el rol propietario) para demostrar que el contexto está
-- ligado a la transacción, la propuesta y el admin; nunca se crean como
-- cliente. 'reset role' vuelve a postgres para comprobar que el contexto
-- y los eventos quedan vacíos.
--   * Distribuidor B: auxiliar sin usuario ni verificación ('rls39-dist-b').
--   * anon.
--   El segundo factor se simula con la claim "aal" del JWT de la prueba
--   (aal1 / aal2), igual que la leería auth.jwt() en una sesión real.
--
-- Casos A (atomicidad): dentro de la subtransacción del caso se añade una
-- restricción NOT VALID que rechaza el importe 777.77 en product_prices,
-- para forzar un fallo DESPUÉS de crear el producto y la subcategoría. Se
-- deshace con el caso; mientras dura (milisegundos) bloquea product_prices.
--
-- Datos auxiliares (solo dentro de cada caso): producto 'rls39-a' de A con
-- su precio, producto 'rls39-b' de B y propuestas con ids fijos de prueba,
-- insertadas como postgres ya en 'submitted' y con el snapshot que crearía
-- el trigger 40. El resultado de la función se guarda en el ajuste local
-- mobau.test_result para comprobarlo en la sentencia siguiente.
--
-- NADA queda guardado: BEGIN … ROLLBACK, cada caso en su subtransacción
-- (MB001) y error final MB999 con los resultados. Sin IDs reales, correos
-- ni secretos en el archivo.
-- Después: repetir 38c_rls_checks.sql (74) y 38b_rls_checks.sql (50).
-- 40-01: con 40-01 aplicada, aprobar un create publica el producto
-- (M17 y D01 lo exigen). Las pruebas propias de 40-01 están en
-- 40_01_publish_checks.sql.
-- ============================================================

BEGIN;

DO $$
declare
  v_sup uuid; v_sup_dist text; v_pro uuid;
  v_cat1 text; v_sub1 text;
  u1 constant text := '00000000-0000-4000-8000-000000039a01';  -- update de A (nombre)
  u2 constant text := '00000000-0000-4000-8000-000000039a02';  -- update de A (solo precio)
  c1 constant text := '00000000-0000-4000-8000-000000039a03';  -- create de A (completo)
  c2 constant text := '00000000-0000-4000-8000-000000039a04';  -- create de A (subcategoría nueva)
  w1 constant text := '00000000-0000-4000-8000-000000039a05';  -- retirada de A
  c3 constant text := '00000000-0000-4000-8000-000000039a06';  -- create de A (subcategoría nueva + precio que fallará)
  u3 constant text := '00000000-0000-4000-8000-000000039a07';  -- update de A (nombre + precio que fallará)
  x1 constant text := '00000000-0000-4000-8000-000000039a08';  -- precio inválido (no debe poder guardarse)
  u4 constant text := '00000000-0000-4000-8000-000000039a09';  -- update de A: quote_required con importe
  u5 constant text := '00000000-0000-4000-8000-000000039a0a';  -- update de A: pending_confirmation sin importe
  u6 constant text := '00000000-0000-4000-8000-000000039a0b';  -- update de A: unavailable con importe
  b1 constant text := '00000000-0000-4000-8000-000000039b01';  -- update de B
  v_admin text; v_admin_a text; v_admin_revoked text; v_prod text; v_price text; v_dist_b text; v_prod_b text;
  v_u1 text; v_u2 text; v_u3 text; v_c1 text; v_c2_new text; v_c2_par text; v_c3 text; v_w1 text; v_b1 text;
  v_price_later text; v_fail_price text; v_fake_flag text; v_fake_event text;
  v_u4 text; v_u5 text; v_u6 text; f_u_price text;
  v_ctx_other_tx text; v_ctx_other_prop text; v_ctx_other_admin text; v_ctx_exact text; v_ctx_a text;
  r jsonb := '[]'::jsonb;
  t record;
  i int;
  v_got text; v_n bigint; v_ok boolean; v_stmt text;
  n_total int := 0; n_ok int := 0;
  -- Líneas base (como postgres, antes de los casos)
  v_adm_n bigint; v_adm_md5 text; v_ev_sup bigint; v_ev_pro bigint;
  -- Llamadas a la función
  fn_call constant text := 'select public.moderate_product_proposal(%L::uuid, %L, %L, %s)';
  fn_save constant text := 'select set_config(''mobau.test_result'', public.moderate_product_proposal(%L::uuid, %L, %L, %s)::text, true)';
  res constant text := 'current_setting(''mobau.test_result'')::jsonb';
  -- Llamada que captura el error dentro de un bloque: el bloque deshace
  -- todo lo que hizo la función y deja el SQLSTATE en mobau.test_result.
  fn_try constant text := 'do $t$ begin perform public.moderate_product_proposal(%L::uuid, %L, %L, %s);'
                          || ' perform set_config(''mobau.test_result'', ''sin error'', true);'
                          || ' exception when others then perform set_config(''mobau.test_result'', sqlstate, true); end $t$';
begin
  -- ---------- datos de partida (lectura como postgres) ----------
  select dp.user_id, dp.distributor_id into v_sup, v_sup_dist
    from public.distributor_profiles dp join public.profiles p on p.id = dp.user_id
   where p.role = 'supplier' and dp.verification_status = 'verified' and dp.distributor_id is not null
   order by dp.created_at limit 1;
  select p.id into v_pro from public.profiles p where p.role = 'individual' order by p.created_at limit 1;
  select c.id, c.subcategories[1] into v_cat1, v_sub1
    from public.categories c where cardinality(c.subcategories) >= 1 order by c.id limit 1;
  if v_sup is null or v_pro is null or v_cat1 is null then
    raise exception 'MOBAU_39: faltan datos de partida' using errcode = 'MB998';
  end if;
  if exists (select 1 from public.mobau_admins a where a.user_id in (v_pro, v_sup)) then
    raise exception 'MOBAU_39: el profesional o el distribuidor de prueba ya tiene fila en mobau_admins; estas pruebas los dan de alta como admins temporales' using errcode = 'MB998';
  end if;

  -- ---------- líneas base (lectura como postgres, antes de los casos) ----------
  -- mobau_admins completa: todas las filas y columnas, sin filtrar ninguna.
  select count(*), md5(coalesce(string_agg(to_jsonb(a)::text, '|' order by a.user_id), ''))
    into v_adm_n, v_adm_md5 from public.mobau_admins a;
  -- Eventos ya registrados por cada identidad de prueba.
  select count(*) into v_ev_sup from public.proposal_events e where e.actor_id = v_sup;
  select count(*) into v_ev_pro from public.proposal_events e where e.actor_id = v_pro;

  -- ---------- SQL auxiliar (como postgres, dentro de cada caso) ----------
  v_admin := format('insert into public.mobau_admins (user_id, granted_note) values (%L, %L)', v_pro, 'Admin temporal de prueba 39');
  v_admin_a := format('insert into public.mobau_admins (user_id, granted_note) values (%L, %L)', v_sup, 'Admin+distribuidor temporal de prueba 39');
  v_admin_revoked := format('insert into public.mobau_admins (user_id, granted_note, revoked_at) values (%L, %L, now())', v_pro, 'Admin temporal revocado 39');
  v_prod := format('insert into public.products (id, name, distributor_id, category_id, subcategory, brand, availability, publication_status) values (%L, %L, %L, %L, %L, %L, %L, %L)',
                   'rls39-a', 'Producto A39', v_sup_dist, v_cat1, v_sub1, 'Marca A39', 'en-stock', 'published');
  v_price := format('insert into public.product_prices (product_id, price_status, price_amount, currency, includes_itbis, price_source) values (%L, %L, 100, %L, true, %L)',
                    'rls39-a', 'published', 'USD', 'demo');
  v_dist_b := format('insert into public.distributors (id, name) values (%L, %L)', 'rls39-dist-b', 'Distribuidor B (prueba 39)');
  v_prod_b := format('insert into public.products (id, name, distributor_id, category_id, publication_status) values (%L, %L, %L, %L, %L)',
                     'rls39-b', 'Producto B39', 'rls39-dist-b', v_cat1, 'published');
  -- Propuesta update en revisión, con el snapshot que guardaría el trigger 40.
  v_u1 := format('insert into public.product_proposals (id, proposal_kind, product_id, distributor_id, status, version, proposed_changes, product_snapshot, submitted_at)'
                 || ' select %L, %L, p.id, p.distributor_id, %L, 1, %L::jsonb,'
                 || ' jsonb_build_object(%L, to_jsonb(p), %L, (select to_jsonb(pp) from public.product_prices pp where pp.product_id = p.id), %L, now()), now()'
                 || ' from public.products p where p.id = %L',
                 u1, 'update', 'submitted', '{"name": "Nombre aprobado 39"}', 'product', 'price', 'taken_at', 'rls39-a');
  v_u2 := format('insert into public.product_proposals (id, proposal_kind, product_id, distributor_id, status, version, proposed_changes, proposed_price_status, proposed_price_amount, product_snapshot, submitted_at)'
                 || ' select %L, %L, p.id, p.distributor_id, %L, 1, %L::jsonb, %L, 120,'
                 || ' jsonb_build_object(%L, to_jsonb(p), %L, (select to_jsonb(pp) from public.product_prices pp where pp.product_id = p.id), %L, now()), now()'
                 || ' from public.products p where p.id = %L',
                 u2, 'update', 'submitted', '{}', 'published', 'product', 'price', 'taken_at', 'rls39-a');
  v_c1 := format('insert into public.product_proposals (id, proposal_kind, distributor_id, status, version, proposed_changes, proposed_price_status, submitted_at) values (%L, %L, %L, %L, 1, %L::jsonb, %L, now())',
                 c1, 'create', v_sup_dist, 'submitted',
                 jsonb_build_object('name', 'Producto nuevo 39', 'description', 'Descripción de prueba 39', 'category_id', v_cat1,
                                    'subcategory', v_sub1, 'availability', 'bajo-pedido', 'brand', 'Marca nueva 39')::text,
                 'quote_required');
  v_c2_new := format('insert into public.product_proposals (id, proposal_kind, distributor_id, status, version, proposed_changes, proposed_new_subcategory, submitted_at) values (%L, %L, %L, %L, 1, %L::jsonb, %L, now())',
                     c2, 'create', v_sup_dist, 'submitted',
                     jsonb_build_object('name', 'Producto con subcategoría nueva 39', 'description', 'Descripción de prueba 39',
                                        'category_id', v_cat1, 'availability', 'por-confirmar')::text,
                     'Subcategoría nueva 39');
  v_c2_par := format('insert into public.product_proposals (id, proposal_kind, distributor_id, status, version, proposed_changes, proposed_new_subcategory, submitted_at) values (%L, %L, %L, %L, 1, %L::jsonb, %L, now())',
                     c2, 'create', v_sup_dist, 'submitted',
                     jsonb_build_object('name', 'Producto con subcategoría paralela 39', 'description', 'Descripción de prueba 39',
                                        'category_id', v_cat1, 'availability', 'por-confirmar')::text,
                     'Subcategoría paralela 39');
  v_u3 := format('insert into public.product_proposals (id, proposal_kind, product_id, distributor_id, status, version, proposed_changes, proposed_price_status, proposed_price_amount, product_snapshot, submitted_at)'
                 || ' select %L, %L, p.id, p.distributor_id, %L, 1, %L::jsonb, %L, 777.77,'
                 || ' jsonb_build_object(%L, to_jsonb(p), %L, (select to_jsonb(pp) from public.product_prices pp where pp.product_id = p.id), %L, now()), now()'
                 || ' from public.products p where p.id = %L',
                 u3, 'update', 'submitted', '{"name": "Nombre atómico 39"}', 'published', 'product', 'price', 'taken_at', 'rls39-a');
  v_c3 := format('insert into public.product_proposals (id, proposal_kind, distributor_id, status, version, proposed_changes, proposed_new_subcategory, proposed_price_status, proposed_price_amount, submitted_at) values (%L, %L, %L, %L, 1, %L::jsonb, %L, %L, 777.77, now())',
                 c3, 'create', v_sup_dist, 'submitted',
                 jsonb_build_object('name', 'Producto atómico 39', 'description', 'Descripción de prueba 39',
                                    'category_id', v_cat1, 'availability', 'por-confirmar')::text,
                 'Subcategoría atómica 39', 'published');
  v_price_later := format('update public.product_prices set price_amount = 150 where product_id = %L', 'rls39-a');
  v_fail_price := 'alter table public.product_prices add constraint rls39_fallo_simulado check (price_amount is distinct from 777.77) not valid';
  v_fake_flag := format('select set_config(%L, %L, true)', 'mobau.moderation_proposal', u1);
  v_fake_event := format('select set_config(%L, %L, true)', 'mobau.moderation_event', '{"decision": "approve", "falsa": true}');
  -- Propuesta update de A solo con precio (estado e importe dados).
  f_u_price := 'insert into public.product_proposals (id, proposal_kind, product_id, distributor_id, status, version, proposed_changes, proposed_price_status, proposed_price_amount, product_snapshot, submitted_at)'
               || ' select %L, %L, p.id, p.distributor_id, %L, 1, %L::jsonb, %L, %L::numeric,'
               || ' jsonb_build_object(%L, to_jsonb(p), %L, (select to_jsonb(pp) from public.product_prices pp where pp.product_id = p.id), %L, now()), now()'
               || ' from public.products p where p.id = %L';
  v_u4 := format(f_u_price, u4, 'update', 'submitted', '{}', 'quote_required', 80, 'product', 'price', 'taken_at', 'rls39-a');
  v_u5 := format(f_u_price, u5, 'update', 'submitted', '{}', 'pending_confirmation', null, 'product', 'price', 'taken_at', 'rls39-a');
  v_u6 := format(f_u_price, u6, 'update', 'submitted', '{}', 'unavailable', 30, 'product', 'price', 'taken_at', 'rls39-a');
  -- Filas de contexto preparadas como postgres (solo en pruebas C), para
  -- demostrar que el contexto está ligado a txid, propuesta y admin.
  v_ctx_other_tx    := format('insert into public.mobau_moderation_context (txid, proposal_id, admin_id) values (1, %L, %L)', u1, v_pro);
  v_ctx_other_prop  := format('insert into public.mobau_moderation_context (txid, proposal_id, admin_id) values (txid_current(), %L, %L)', u2, v_pro);
  v_ctx_other_admin := format('insert into public.mobau_moderation_context (txid, proposal_id, admin_id) values (txid_current(), %L, %L)', u1, v_sup);
  v_ctx_exact       := format('insert into public.mobau_moderation_context (txid, proposal_id, admin_id) values (txid_current(), %L, %L)', u1, v_pro);
  v_ctx_a           := format('insert into public.mobau_moderation_context (txid, proposal_id, admin_id) values (txid_current(), %L, %L)', u1, v_sup);
  v_w1 := format('insert into public.product_proposals (id, proposal_kind, product_id, distributor_id, status, version, proposed_changes) values (%L, %L, %L, %L, %L, 1, %L::jsonb)',
                 w1, 'update', 'rls39-a', v_sup_dist, 'withdrawn', '{"brand": "Marca retirada 39"}');
  v_b1 := format('insert into public.product_proposals (id, proposal_kind, product_id, distributor_id, status, version, proposed_changes, product_snapshot, submitted_at)'
                 || ' select %L, %L, p.id, p.distributor_id, %L, 1, %L::jsonb, jsonb_build_object(%L, to_jsonb(p), %L, null, %L, now()), now()'
                 || ' from public.products p where p.id = %L',
                 b1, 'update', 'submitted', '{"name": "Nombre de B 39"}', 'product', 'price', 'taken_at', 'rls39-b');

  -- kind: 'count' (última sentencia devuelve un número) | 'exec' (se mide row_count de la última)
  -- expect: número | 'ok' | 'rows=0' | SQLSTATE (5 caracteres) | 'SQLSTATE:texto' (código y texto en el mensaje)
  -- role '-' = postgres. aal: claim de segundo factor de la sesión de prueba.
  for t in
    select * from (values
      -- ---------- Autorización ----------
      ('M01 distribuidor no puede moderar',                    'authenticated', v_sup::text, 'aal2', array[v_admin, v_prod, v_price, v_u1]::text[],
         array[format(fn_call, u1, 'approve', null, 1)]::text[], 'exec', '42501'),
      ('M02 anon no puede moderar',                            'anon', null, null, array[v_prod, v_price, v_u1],
         array[format(fn_call, u1, 'approve', null, 1)], 'exec', '42501'),
      ('M03 autenticado no admin no puede moderar',            'authenticated', v_pro::text, 'aal2', array[v_prod, v_price, v_u1],
         array[format(fn_call, u1, 'approve', null, 1)], 'exec', '42501:No tienes permiso'),
      ('M04 admin sin aal2: rechazado con aviso de MFA',       'authenticated', v_pro::text, 'aal1', array[v_admin, v_prod, v_price, v_u1],
         array[format(fn_call, u1, 'approve', null, 1)], 'exec', '42501:segundo factor'),
      ('M05 admin sin aal2 no ve la bandeja',                  'authenticated', v_pro::text, 'aal1', array[v_admin, v_prod, v_price, v_u1],
         array[format('select count(*) from public.product_proposals where id = %L', u1)], 'count', '0'),
      ('M06 admin con aal2 ve propuestas en revisión de A y B', 'authenticated', v_pro::text, 'aal2', array[v_admin, v_prod, v_price, v_u1, v_dist_b, v_prod_b, v_b1],
         array[format('select count(*) from public.product_proposals where id in (%L, %L) and status = %L', u1, b1, 'submitted')], 'count', '2'),
      ('M07 admin revocado no puede moderar',                  'authenticated', v_pro::text, 'aal2', array[v_admin_revoked, v_prod, v_price, v_u1],
         array[format(fn_call, u1, 'approve', null, 1)], 'exec', '42501'),
      -- ---------- Mobau no edita la ficha ----------
      ('M08 admin no puede modificar la propuesta directamente', 'authenticated', v_pro::text, 'aal2', array[v_admin, v_prod, v_price, v_u1],
         array[format('update public.product_proposals set proposed_changes = %L, status = %L where id = %L', '{"name": "Cambio de Mobau"}', 'approved', u1),
               format('select count(*) from public.product_proposals where id = %L and status = %L and proposed_changes ->> %L = %L', u1, 'submitted', 'name', 'Nombre aprobado 39')], 'count', '1'),
      ('M09 la función no acepta campos de producto',          'authenticated', v_pro::text, 'aal2', array[v_admin, v_prod, v_price, v_u1],
         array[format('select public.moderate_product_proposal(p_proposal_id => %L::uuid, p_decision => %L, p_message => null, p_expected_version => 1, p_name => %L)', u1, 'approve', 'Nombre de Mobau')], 'exec', '42883'),
      ('M10 admin no puede escribir productos directamente',   'authenticated', v_pro::text, 'aal2', array[v_admin],
         array[format('insert into public.products (id, name, distributor_id, category_id) values (%L, %L, %L, %L)', 'rls39-x', 'X', v_sup_dist, v_cat1)], 'exec', '42501'),
      -- ---------- Validaciones y estado ----------
      ('M11 decisión inválida',                                'authenticated', v_pro::text, 'aal2', array[v_admin, v_prod, v_price, v_u1],
         array[format(fn_call, u1, 'publish', null, 1)], 'exec', '22023'),
      ('M12 propuesta inexistente',                            'authenticated', v_pro::text, 'aal2', array[v_admin],
         array[format(fn_call, '00000000-0000-4000-8000-000000039fff', 'approve', null, 1)], 'exec', 'P0002'),
      ('M13 propuesta ya cerrada (retirada)',                  'authenticated', v_pro::text, 'aal2', array[v_admin, v_prod, v_price, v_w1],
         array[format(fn_call, w1, 'approve', null, 1)], 'exec', '55000'),
      ('M14 segunda decisión sobre la misma propuesta',        'authenticated', v_pro::text, 'aal2', array[v_admin, v_prod, v_price, v_u1],
         array[format(fn_call, u1, 'approve', null, 1), format(fn_call, u1, 'reject', 'Otra decisión', 1)], 'exec', '55000'),
      ('M15 versión distinta: nada se aplica y queda auditado (submitted → submitted)', 'authenticated', v_pro::text, 'aal2', array[v_admin, v_prod, v_price, v_u1],
         array[format(fn_save, u1, 'approve', null, 2),
               format('select count(*) from public.product_proposals pr where pr.id = %L and pr.status = %L and pr.reviewed_by is null and %s ->> %L = %L'
                      || ' and not (%s ->> %L)::boolean'
                      || ' and (select name from public.products where id = %L) = %L'
                      || ' and (select count(*) from public.proposal_events e where e.proposal_id = pr.id and e.actor_id = %L) = 1'
                      || ' and exists (select 1 from public.proposal_events e where e.proposal_id = pr.id and e.actor_id = %L and e.actor_kind = %L'
                      || ' and e.from_status = %L and e.to_status = %L and e.version = 1 and e.note is null'
                      || ' and e.payload = jsonb_build_object(%L, %L, %L, %L, %L, 2, %L, 1))',
                      u1, 'submitted', res, 'code', 'version_conflict', res, 'ok', 'rls39-a', 'Producto A39', v_pro, v_pro, 'mobau',
                      'submitted', 'submitted', 'type', 'version_conflict', 'decision', 'approve', 'expected_version', 'current_version')], 'count', '1'),
      ('M16 empresa sin verificar: no se puede aprobar',       'authenticated', v_pro::text, 'aal2', array[v_admin, v_dist_b, v_prod_b, v_b1],
         array[format(fn_call, b1, 'approve', null, 1)], 'exec', '55000:verificada'),
      -- ---------- Aprobar ----------
      ('M17 aprobar create: producto publicado y enlazado',    'authenticated', v_pro::text, 'aal2', array[v_admin, v_c1],
         array[format(fn_save, c1, 'approve', null, 1),
               format('select count(*) from public.products p where p.id = %s ->> %L and p.name = %L and p.brand = %L and p.distributor_id = %L'
                      || ' and p.category_id = %L and p.subcategory = %L and p.availability = %L and p.publication_status = %L and p.status = %L'
                      || ' and exists (select 1 from public.product_proposals pr where pr.id = %L and pr.status = %L and pr.created_product_id = p.id and pr.reviewed_by = %L)'
                      || ' and exists (select 1 from public.product_prices pp where pp.product_id = p.id and pp.price_status = %L and pp.price_amount is null'
                      || ' and pp.currency = %L and pp.includes_itbis and pp.price_source = %L)'
                      || ' and exists (select 1 from public.proposal_events e where e.proposal_id = %L and e.to_status = %L and e.actor_kind = %L and e.payload ->> %L = p.id)',
                      res, 'created_product_id', 'Producto nuevo 39', 'Marca nueva 39', v_sup_dist, v_cat1, v_sub1, 'bajo-pedido', 'published', 'active',
                      c1, 'approved', v_pro, 'quote_required', 'USD', 'distributor', c1, 'approved', 'mobau', 'created_product_id')], 'count', '1'),
      ('M18 aprobar update: solo cambian los campos propuestos', 'authenticated', v_pro::text, 'aal2', array[v_admin, v_prod, v_price, v_u1],
         array[format(fn_save, u1, 'approve', null, 1),
               format('select count(*) from public.products p, public.product_proposals pr where p.id = %L and pr.id = %L and p.name = %L'
                      || ' and (to_jsonb(p) - %L - %L) = (pr.product_snapshot -> %L) - %L - %L and pr.status = %L',
                      'rls39-a', u1, 'Nombre aprobado 39', 'name', 'updated_at', 'product', 'name', 'updated_at', 'approved')], 'count', '1'),
      ('M19 aprobar precio: solo cambia el precio',            'authenticated', v_pro::text, 'aal2', array[v_admin, v_prod, v_price, v_u2],
         array[format(fn_save, u2, 'approve', null, 1),
               format('select count(*) from public.products p, public.product_proposals pr, public.product_prices pp'
                      || ' where p.id = %L and pr.id = %L and pp.product_id = p.id and to_jsonb(p) = pr.product_snapshot -> %L'
                      || ' and pp.price_status = %L and pp.price_amount = 120 and pp.price_source = %L and pr.status = %L'
                      || ' and pp.currency = %L and pp.includes_itbis and pp.price_reference is null'
                      || ' and pp.id::text = pr.product_snapshot -> %L ->> %L and pp.created_at = (pr.product_snapshot -> %L ->> %L)::timestamptz',
                      'rls39-a', u2, 'product', 'published', 'distributor', 'approved', 'USD', 'price', 'id', 'price', 'created_at')], 'count', '1'),
      -- ---------- Conflicto con el snapshot ----------
      ('M20 campo propuesto cambiado tras el envío: bloquea',  'authenticated', v_pro::text, 'aal2',
         array[v_admin, v_prod, v_price, v_u1, format('update public.products set name = %L where id = %L', 'Nombre cambiado después', 'rls39-a')],
         array[format(fn_save, u1, 'approve', null, 1),
               format('select count(*) from public.product_proposals pr where pr.id = %L and pr.status = %L and pr.reviewed_by is null and %s ->> %L = %L'
                      || ' and %s -> %L -> 0 ->> %L = %L and (select name from public.products where id = %L) = %L'
                      || ' and (select count(*) from public.proposal_events e where e.proposal_id = pr.id and e.actor_id = %L) = 1'
                      || ' and exists (select 1 from public.proposal_events e where e.proposal_id = pr.id and e.actor_id = %L and e.actor_kind = %L'
                      || ' and e.from_status = %L and e.to_status = %L and e.note is null and e.payload ->> %L = %L and e.payload ->> %L = %L'
                      || ' and jsonb_array_length(e.payload -> %L) = 1 and e.payload -> %L -> 0 ->> %L = %L'
                      || ' and (select array_agg(k order by k) from jsonb_object_keys(e.payload) as k) = array[%L, %L, %L])',
                      u1, 'submitted', res, 'code', 'snapshot_conflict', res, 'conflicts', 'field', 'name', 'rls39-a', 'Nombre cambiado después',
                      v_pro, v_pro, 'mobau', 'submitted', 'submitted', 'type', 'snapshot_conflict', 'decision', 'approve',
                      'conflicts', 'conflicts', 'field', 'name', 'conflicts', 'decision', 'type')], 'count', '1'),
      ('M21 campo no propuesto cambiado tras el envío: se aprueba', 'authenticated', v_pro::text, 'aal2',
         array[v_admin, v_prod, v_price, v_u1, format('update public.products set brand = %L where id = %L', 'Marca cambiada después', 'rls39-a')],
         array[format(fn_save, u1, 'approve', null, 1),
               format('select count(*) from public.products p where p.id = %L and p.name = %L and p.brand = %L and (%s ->> %L)::boolean',
                      'rls39-a', 'Nombre aprobado 39', 'Marca cambiada después', res, 'ok')], 'count', '1'),
      -- ---------- Subcategoría nueva ----------
      ('M22 subcategoría nueva: se añade a la categoría',      'authenticated', v_pro::text, 'aal2', array[v_admin, v_c2_new],
         array[format(fn_save, c2, 'approve', null, 1),
               format('select count(*) from public.categories c, public.products p where c.id = %L and %L = any (c.subcategories)'
                      || ' and p.id = %s ->> %L and p.subcategory = %L and %s -> %L ->> %L = %L',
                      v_cat1, 'Subcategoría nueva 39', res, 'created_product_id', 'Subcategoría nueva 39', res, 'subcategory', 'result', 'added')], 'count', '1'),
      ('M23 subcategoría ya existente: no se duplica',         'authenticated', v_pro::text, 'aal2',
         array[v_admin, v_c2_par, format('update public.categories set subcategories = array_append(subcategories, %L) where id = %L', 'SUBCATEGORÍA PARALELA 39', v_cat1)],
         array[format(fn_save, c2, 'approve', null, 1),
               format('select count(*) from public.categories c, public.products p where c.id = %L'
                      || ' and (select count(*) from unnest(c.subcategories) s where lower(s) = lower(%L)) = 1'
                      || ' and p.id = %s ->> %L and p.subcategory = %L and %s -> %L ->> %L = %L',
                      v_cat1, 'Subcategoría paralela 39', res, 'created_product_id', 'SUBCATEGORÍA PARALELA 39', res, 'subcategory', 'result', 'existing')], 'count', '1'),
      -- ---------- Rechazar y solicitar cambios ----------
      ('M24 rechazar con motivo',                              'authenticated', v_pro::text, 'aal2', array[v_admin, v_prod, v_price, v_u1],
         array[format(fn_call, u1, 'reject', 'No encaja en el catálogo: propón otra categoría.', 1),
               format('select count(*) from public.product_proposals pr where pr.id = %L and pr.status = %L and pr.rejection_reason = %L and pr.reviewed_by = %L'
                      || ' and exists (select 1 from public.proposal_events e where e.proposal_id = pr.id and e.to_status = %L and e.actor_kind = %L and e.note = pr.rejection_reason)'
                      || ' and (select name from public.products where id = %L) = %L',
                      u1, 'rejected', 'No encaja en el catálogo: propón otra categoría.', v_pro, 'rejected', 'mobau', 'rls39-a', 'Producto A39')], 'count', '1'),
      ('M25 rechazar sin motivo',                              'authenticated', v_pro::text, 'aal2', array[v_admin, v_prod, v_price, v_u1],
         array[format(fn_call, u1, 'reject', '   ', 1)], 'exec', '22023'),
      ('M26 solicitar cambios con motivo',                     'authenticated', v_pro::text, 'aal2', array[v_admin, v_prod, v_price, v_u1],
         array[format(fn_call, u1, 'request_changes', 'Añade medidas y ficha técnica.', 1),
               format('select count(*) from public.product_proposals where id = %L and status = %L and rejection_reason = %L',
                      u1, 'changes_requested', 'Añade medidas y ficha técnica.')], 'count', '1'),
      ('M27 solicitar cambios sin motivo',                     'authenticated', v_pro::text, 'aal2', array[v_admin, v_prod, v_price, v_u1],
         array[format(fn_call, u1, 'request_changes', null, 1)], 'exec', '22023'),
      ('M28 rechazar es posible aunque la empresa no esté verificada', 'authenticated', v_pro::text, 'aal2', array[v_admin, v_dist_b, v_prod_b, v_b1],
         array[format(fn_call, b1, 'reject', 'Empresa pendiente de verificación.', 1),
               format('select count(*) from public.product_proposals where id = %L and status = %L', b1, 'rejected')], 'count', '1'),
      -- ---------- Marca de moderación falsa (set_config) ----------
      ('F01 fijar la marca sin ser admin no activa nada',      'authenticated', v_sup::text, 'aal2', array[v_prod, v_price, v_u1],
         array[v_fake_flag, v_fake_event,
               format('select count(*) where public.mobau_moderating(%L::uuid) or public.mobau_moderation_proposal_id() is not null', u1)], 'count', '0'),
      ('F02 marca falsa: distribuidor no puede decidir su propuesta', 'authenticated', v_sup::text, 'aal2', array[v_prod, v_price, v_u1],
         array[v_fake_flag, v_fake_event,
               format('update public.product_proposals set status = %L where id = %L', 'changes_requested', u1)], 'exec', '42501:Transición no permitida'),
      ('F03 marca falsa: admin que es distribuidor no puede autodecidir', 'authenticated', v_sup::text, 'aal2', array[v_admin_a, v_prod, v_price, v_u1],
         array[v_fake_flag, v_fake_event,
               format('update public.product_proposals set status = %L where id = %L', 'changes_requested', u1)], 'exec', '42501:Transición no permitida'),
      ('F04 marca falsa: admin que es distribuidor no puede aprobar por UPDATE', 'authenticated', v_sup::text, 'aal2', array[v_admin_a, v_prod, v_price, v_u1],
         array[v_fake_flag, format('update public.product_proposals set status = %L where id = %L', 'approved', u1)], 'exec', '42501'),
      ('F05 marca falsa: distribuidor no puede insertar productos', 'authenticated', v_sup::text, 'aal2', array[v_prod],
         array[v_fake_flag, format('insert into public.products (id, name, distributor_id, category_id, publication_status) values (%L, %L, %L, %L, %L)',
                                   'rls39-falso', 'Falso', v_sup_dist, v_cat1, 'published')], 'exec', '42501'),
      ('F06 marca falsa: admin que es distribuidor no puede insertar productos', 'authenticated', v_sup::text, 'aal2', array[v_admin_a, v_prod],
         array[v_fake_flag, format('insert into public.products (id, name, distributor_id, category_id, publication_status) values (%L, %L, %L, %L, %L)',
                                   'rls39-falso', 'Falso', v_sup_dist, v_cat1, 'published')], 'exec', '42501'),
      ('F07 marca falsa: ejecutar la función sin ser admin',   'authenticated', v_sup::text, 'aal2', array[v_prod, v_price, v_u1],
         array[v_fake_flag, v_fake_event, format(fn_call, u1, 'approve', null, 1)], 'exec', '42501:No tienes permiso'),
      ('F08 el contexto privado no se puede escribir desde el cliente', 'authenticated', v_sup::text, 'aal2', array[v_admin_a, v_prod, v_price, v_u1],
         array[format('insert into public.mobau_moderation_context (txid, proposal_id, admin_id) values (txid_current(), %L, %L)', u1, v_sup)], 'exec', '42501'),
      ('F09 evento falso ignorado en una decisión real',       'authenticated', v_pro::text, 'aal2', array[v_admin, v_prod, v_price, v_u1],
         array[v_fake_flag, v_fake_event, format(fn_call, u1, 'reject', 'Motivo real 39.', 1),
               format('select count(*) from public.proposal_events e where e.proposal_id = %L and e.to_status = %L and e.actor_kind = %L'
                      || ' and e.payload ->> %L = %L and not (e.payload ? %L)', u1, 'rejected', 'mobau', 'decision', 'reject', 'falsa')], 'count', '1'),
      ('F10 marca falsa: la retirada del admin-distribuidor queda como distribuidor', 'authenticated', v_sup::text, 'aal2', array[v_admin_a, v_prod, v_price, v_u1],
         array[v_fake_flag, v_fake_event, format('update public.product_proposals set status = %L where id = %L', 'withdrawn', u1),
               format('select count(*) from public.proposal_events e where e.proposal_id = %L and e.to_status = %L and e.actor_kind = %L', u1, 'withdrawn', 'distributor')], 'count', '1'),
      ('F11 admin con marca falsa no puede editar la propuesta', 'authenticated', v_pro::text, 'aal2', array[v_admin, v_prod, v_price, v_u1],
         array[v_fake_flag, format('update public.product_proposals set proposed_changes = %L, status = %L where id = %L', '{"name": "Cambio de Mobau"}', 'approved', u1),
               format('select count(*) from public.product_proposals where id = %L and status = %L and proposed_changes ->> %L = %L', u1, 'submitted', 'name', 'Nombre aprobado 39')], 'count', '1'),
      -- ---------- Precio ----------
      ('P01 propuesta de nombre y precio cambiado después: se aprueba sin tocar el precio', 'authenticated', v_pro::text, 'aal2', array[v_admin, v_prod, v_price, v_u1, v_price_later],
         array[format(fn_save, u1, 'approve', null, 1),
               format('select count(*) from public.products p join public.product_prices pp on pp.product_id = p.id where p.id = %L and p.name = %L'
                      || ' and pp.price_amount = 150 and pp.price_source = %L and (%s ->> %L)::boolean and not (%s ->> %L)::boolean',
                      'rls39-a', 'Nombre aprobado 39', 'demo', res, 'ok', res, 'price_applied')], 'count', '1'),
      ('P02 propuesta de precio y precio cambiado después: conflicto', 'authenticated', v_pro::text, 'aal2', array[v_admin, v_prod, v_price, v_u2, v_price_later],
         array[format(fn_save, u2, 'approve', null, 1),
               format('select count(*) from public.product_proposals pr, public.product_prices pp where pr.id = %L and pp.product_id = %L'
                      || ' and pr.status = %L and pr.reviewed_by is null and %s ->> %L = %L and %s -> %L -> 0 ->> %L = %L and pp.price_amount = 150 and pp.price_source = %L'
                      || ' and (select count(*) from public.proposal_events e where e.proposal_id = pr.id and e.actor_id = %L) = 1'
                      || ' and exists (select 1 from public.proposal_events e where e.proposal_id = pr.id and e.actor_id = %L and e.actor_kind = %L'
                      || ' and e.from_status = %L and e.to_status = %L and e.note is null and e.payload ->> %L = %L and e.payload ->> %L = %L'
                      || ' and jsonb_array_length(e.payload -> %L) = 1 and e.payload -> %L -> 0 ->> %L = %L'
                      || ' and (select array_agg(k order by k) from jsonb_object_keys(e.payload) as k) = array[%L, %L, %L])',
                      u2, 'rls39-a', 'submitted', res, 'code', 'snapshot_conflict', res, 'conflicts', 'field', 'price', 'demo',
                      v_pro, v_pro, 'mobau', 'submitted', 'submitted', 'type', 'snapshot_conflict', 'decision', 'approve',
                      'conflicts', 'conflicts', 'field', 'price', 'conflicts', 'decision', 'type')], 'count', '1'),
      ('P03 propuesta sin precio: la fila de precio queda idéntica', 'authenticated', v_pro::text, 'aal2', array[v_admin, v_prod, v_price, v_u1],
         array[format(fn_save, u1, 'approve', null, 1),
               format('select count(*) from public.product_prices pp, public.product_proposals pr where pp.product_id = %L and pr.id = %L'
                      || ' and pr.status = %L and to_jsonb(pp) = pr.product_snapshot -> %L', 'rls39-a', u1, 'approved', 'price')], 'count', '1'),
      ('P04 precio publicado sin importe: no puede guardarse', '-', null, null, array[v_prod, v_price],
         array[format('insert into public.product_proposals (id, proposal_kind, product_id, distributor_id, status, version, proposed_changes, proposed_price_status, proposed_price_amount)'
                      || ' values (%L, %L, %L, %L, %L, 1, %L::jsonb, %L, null)', x1, 'update', 'rls39-a', v_sup_dist, 'draft', '{}', 'published')], 'exec', '23514'),
      ('P05 precio negativo: no puede guardarse',              '-', null, null, array[v_prod, v_price],
         array[format('insert into public.product_proposals (id, proposal_kind, product_id, distributor_id, status, version, proposed_changes, proposed_price_status, proposed_price_amount)'
                      || ' values (%L, %L, %L, %L, %L, 1, %L::jsonb, %L, -5)', x1, 'update', 'rls39-a', v_sup_dist, 'draft', '{}', 'published')], 'exec', '23514'),
      ('P06 importe sin tipo de precio: no puede guardarse',   '-', null, null, array[v_prod, v_price],
         array[format('insert into public.product_proposals (id, proposal_kind, product_id, distributor_id, status, version, proposed_changes, proposed_price_status, proposed_price_amount)'
                      || ' values (%L, %L, %L, %L, %L, 1, %L::jsonb, null, 50)', x1, 'update', 'rls39-a', v_sup_dist, 'draft', '{}')], 'exec', '23514'),
      -- ---------- Atomicidad ----------
      ('A01 fallo al guardar el precio de un create: nada queda aplicado', 'authenticated', v_pro::text, 'aal2', array[v_admin, v_c3, v_fail_price],
         array[format(fn_try, c3, 'approve', null, 1),
               format('select count(*) where current_setting(%L) = %L'
                      || ' and not exists (select 1 from public.products where name = %L)'
                      || ' and not exists (select 1 from public.categories c where c.id = %L and %L = any (c.subcategories))'
                      || ' and exists (select 1 from public.product_proposals where id = %L and status = %L and created_product_id is null and reviewed_by is null)'
                      || ' and not exists (select 1 from public.proposal_events where proposal_id = %L and to_status = %L)'
                      || ' and public.mobau_moderation_proposal_id() is null',
                      'mobau.test_result', '23514', 'Producto atómico 39', v_cat1, 'Subcategoría atómica 39', c3, 'submitted', c3, 'approved')], 'count', '1'),
      ('A02 fallo al guardar el precio de un update: el nombre no cambia', 'authenticated', v_pro::text, 'aal2', array[v_admin, v_prod, v_price, v_u3, v_fail_price],
         array[format(fn_try, u3, 'approve', null, 1),
               format('select count(*) from public.products p, public.product_prices pp, public.product_proposals pr'
                      || ' where p.id = %L and pp.product_id = p.id and pr.id = %L and current_setting(%L) = %L'
                      || ' and to_jsonb(p) = pr.product_snapshot -> %L and to_jsonb(pp) = pr.product_snapshot -> %L and pr.status = %L',
                      'rls39-a', u3, 'mobau.test_result', '23514', 'product', 'price', 'submitted')], 'count', '1'),
      -- ---------- Producto nuevo: publicado (40-01) ----------
      ('D01 producto nuevo: publication_status = published exacto y visible para anon', 'authenticated', v_pro::text, 'aal2', array[v_admin, v_c1],
         array[format(fn_save, c1, 'approve', null, 1),
               format('select set_config(%L, (select publication_status from public.products where id = %s ->> %L), true)', 'mobau.test_pub', res, 'created_product_id'),
               'set local role anon',
               'select set_config(''request.jwt.claims'', '''', true), set_config(''request.jwt.claim.sub'', '''', true)',
               format('select count(*) where current_setting(%L) = %L and exists (select 1 from public.products where id = %s ->> %L)',
                      'mobau.test_pub', 'published', res, 'created_product_id')], 'count', '1'),
      -- ---------- Autoaprobación (admin que pertenece a la empresa) ----------
      ('S01 admin de la propia empresa no puede aprobar',      'authenticated', v_sup::text, 'aal2', array[v_admin_a, v_prod, v_price, v_u1],
         array[format(fn_call, u1, 'approve', null, 1)], 'exec', '42501:propia empresa'),
      ('S02 admin de la propia empresa no puede solicitar cambios', 'authenticated', v_sup::text, 'aal2', array[v_admin_a, v_prod, v_price, v_u1],
         array[format(fn_call, u1, 'request_changes', 'Cambios 39.', 1)], 'exec', '42501:propia empresa'),
      ('S03 admin de la propia empresa no puede rechazar',     'authenticated', v_sup::text, 'aal2', array[v_admin_a, v_prod, v_price, v_u1],
         array[format(fn_call, u1, 'reject', 'Rechazo 39.', 1)], 'exec', '42501:propia empresa'),
      ('S04 admin sin relación con la empresa sí puede aprobar', 'authenticated', v_pro::text, 'aal2', array[v_admin, v_admin_a, v_prod, v_price, v_u1],
         array[format(fn_save, u1, 'approve', null, 1),
               format('select count(*) from public.product_proposals where id = %L and status = %L and reviewed_by = %L', u1, 'approved', v_pro)], 'count', '1'),
      ('S05 admin-distribuidor sí puede moderar otra empresa', 'authenticated', v_sup::text, 'aal2', array[v_admin_a, v_dist_b, v_prod_b, v_b1],
         array[format(fn_call, b1, 'reject', 'Rechazo 39 de otra empresa.', 1),
               format('select count(*) from public.product_proposals where id = %L and status = %L and reviewed_by = %L', b1, 'rejected', v_sup)], 'count', '1'),
      ('S06 intento bloqueado: ni producto, ni subcategoría, ni evento, ni contexto', 'authenticated', v_sup::text, 'aal2', array[v_admin_a, v_c2_new],
         array[format(fn_try, c2, 'approve', null, 1), 'reset role',
               format('select count(*) where current_setting(%L) = %L'
                      || ' and not exists (select 1 from public.products where name = %L)'
                      || ' and not exists (select 1 from public.categories c where c.id = %L and %L = any (c.subcategories))'
                      || ' and exists (select 1 from public.product_proposals where id = %L and status = %L and reviewed_by is null and created_product_id is null)'
                      || ' and (select count(*) from public.proposal_events where actor_id = %L) = %s'
                      || ' and not exists (select 1 from public.mobau_moderation_context)',
                      'mobau.test_result', '42501', 'Producto con subcategoría nueva 39', v_cat1, 'Subcategoría nueva 39', c2, 'submitted', v_sup, v_ev_sup)], 'count', '1'),
      ('S07 intento bloqueado con versión distinta: tampoco deja evento de conflicto', 'authenticated', v_sup::text, 'aal2', array[v_admin_a, v_prod, v_price, v_u1],
         array[format(fn_try, u1, 'approve', null, 2), 'reset role',
               format('select count(*) where current_setting(%L) = %L and (select count(*) from public.proposal_events where actor_id = %L) = %s',
                      'mobau.test_result', '42501', v_sup, v_ev_sup)], 'count', '1'),
      ('S08 versión antigua: admin de la empresa bloqueado sin evento; admin externo recibe el conflicto', 'authenticated', v_sup::text, 'aal2',
         array[v_admin, v_admin_a, v_prod, v_price, v_u1],
         array[format(fn_try, u1, 'approve', null, 2),
               'select set_config(''mobau.test_self'', current_setting(''mobau.test_result''), true)',
               format('select set_config(%L, %L, true), set_config(%L, %L, true)', 'request.jwt.claim.sub', v_pro,
                      'request.jwt.claims', json_build_object('sub', v_pro, 'role', 'authenticated', 'aal', 'aal2')::text),
               format(fn_save, u1, 'approve', null, 2), 'reset role',
               format('select count(*) where current_setting(%L) = %L and %s ->> %L = %L'
                      || ' and (select count(*) from public.proposal_events where actor_id = %L) = %s'
                      || ' and (select count(*) from public.proposal_events e where e.proposal_id = %L and e.actor_id = %L) = 1'
                      || ' and exists (select 1 from public.proposal_events e where e.proposal_id = %L and e.actor_id = %L'
                      || ' and e.from_status = %L and e.to_status = %L and e.note is null'
                      || ' and e.payload = jsonb_build_object(%L, %L, %L, %L, %L, 2, %L, 1))'
                      || ' and exists (select 1 from public.product_proposals where id = %L and status = %L and reviewed_by is null)',
                      'mobau.test_self', '42501', res, 'code', 'version_conflict', v_sup, v_ev_sup, u1, v_pro, u1, v_pro, 'submitted', 'submitted',
                      'type', 'version_conflict', 'decision', 'approve', 'expected_version', 'current_version', u1, 'submitted')], 'count', '1'),
      -- ---------- Intentos sin evento de moderación ----------
      ('E01 no admin: error y ningún evento',                  'authenticated', v_pro::text, 'aal2', array[v_prod, v_price, v_u1],
         array[format(fn_try, u1, 'approve', null, 1), 'reset role',
               format('select count(*) where current_setting(%L) = %L and (select count(*) from public.proposal_events where actor_id = %L) = %s'
                      || ' and exists (select 1 from public.product_proposals where id = %L and status = %L)',
                      'mobau.test_result', '42501', v_pro, v_ev_pro, u1, 'submitted')], 'count', '1'),
      ('E02 admin sin MFA: error y ningún evento',             'authenticated', v_pro::text, 'aal1', array[v_admin, v_prod, v_price, v_u1],
         array[format(fn_try, u1, 'reject', 'Motivo 39.', 1), 'reset role',
               format('select count(*) where current_setting(%L) = %L and (select count(*) from public.proposal_events where actor_id = %L) = %s'
                      || ' and exists (select 1 from public.product_proposals where id = %L and status = %L)',
                      'mobau.test_result', '42501', v_pro, v_ev_pro, u1, 'submitted')], 'count', '1'),
      ('E03 propuesta inexistente: error y ningún evento',     'authenticated', v_pro::text, 'aal2', array[v_admin],
         array[format(fn_try, '00000000-0000-4000-8000-000000039fff', 'approve', null, 1), 'reset role',
               format('select count(*) where current_setting(%L) = %L and (select count(*) from public.proposal_events where actor_id = %L) = %s'
                      || ' and not exists (select 1 from public.proposal_events where proposal_id = %L)',
                      'mobau.test_result', 'P0002', v_pro, v_ev_pro, '00000000-0000-4000-8000-000000039fff')], 'count', '1'),
      ('E04 propuesta cerrada: error y ningún evento',         'authenticated', v_pro::text, 'aal2', array[v_admin, v_prod, v_price, v_w1],
         array[format(fn_try, w1, 'approve', null, 1), 'reset role',
               format('select count(*) where current_setting(%L) = %L and (select count(*) from public.proposal_events where actor_id = %L) = %s',
                      'mobau.test_result', '55000', v_pro, v_ev_pro)], 'count', '1'),
      -- ---------- Precios no publicados (comportamiento de 38-C) ----------
      ('P07 quote_required con importe: se guarda tal cual, sin publicar', 'authenticated', v_pro::text, 'aal2', array[v_admin, v_prod, v_price, v_u4],
         array[format(fn_save, u4, 'approve', null, 1),
               format('select count(*) from public.product_prices pp join public.products p on p.id = pp.product_id where p.id = %L'
                      || ' and pp.price_status = %L and pp.price_amount = 80 and pp.currency = %L and pp.includes_itbis and pp.price_source = %L'
                      || ' and p.publication_status = %L', 'rls39-a', 'quote_required', 'USD', 'distributor', 'published')], 'count', '1'),
      ('P08 pending_confirmation sin importe: se guarda con importe null', 'authenticated', v_pro::text, 'aal2', array[v_admin, v_prod, v_price, v_u5],
         array[format(fn_save, u5, 'approve', null, 1),
               format('select count(*) from public.product_prices pp where pp.product_id = %L and pp.price_status = %L and pp.price_amount is null'
                      || ' and pp.currency = %L and pp.includes_itbis', 'rls39-a', 'pending_confirmation', 'USD')], 'count', '1'),
      ('P09 unavailable con importe: se guarda tal cual',      'authenticated', v_pro::text, 'aal2', array[v_admin, v_prod, v_price, v_u6],
         array[format(fn_save, u6, 'approve', null, 1),
               format('select count(*) from public.product_prices pp where pp.product_id = %L and pp.price_status = %L and pp.price_amount = 30',
                      'rls39-a', 'unavailable')], 'count', '1'),
      -- ---------- Contexto privado ----------
      ('C01 admin-distribuidor no puede insertar contexto',    'authenticated', v_sup::text, 'aal2', array[v_admin_a, v_prod, v_price, v_u1],
         array[format('insert into public.mobau_moderation_context (txid, proposal_id, admin_id) values (txid_current(), %L, %L)', u1, v_sup)], 'exec', '42501'),
      ('C02 admin no puede modificar una fila de contexto',    'authenticated', v_sup::text, 'aal2', array[v_admin_a, v_prod, v_price, v_u1, v_ctx_a],
         array[format('update public.mobau_moderation_context set proposal_id = %L', u2)], 'exec', '42501'),
      ('C03 admin no puede borrar una fila de contexto',       'authenticated', v_sup::text, 'aal2', array[v_admin_a, v_prod, v_price, v_u1, v_ctx_a],
         array['delete from public.mobau_moderation_context'], 'exec', '42501'),
      ('C04 admin no puede fijar contexto para otra propuesta', 'authenticated', v_pro::text, 'aal2', array[v_admin, v_prod, v_price, v_u1],
         array[format('insert into public.mobau_moderation_context (txid, proposal_id, admin_id) values (txid_current(), %L, %L)', u2, v_pro)], 'exec', '42501'),
      ('C05 admin no puede fijar contexto con otro admin_id',  'authenticated', v_pro::text, 'aal2', array[v_admin, v_prod, v_price, v_u1],
         array[format('insert into public.mobau_moderation_context (txid, proposal_id, admin_id) values (txid_current(), %L, %L)', u1, v_sup)], 'exec', '42501'),
      ('C06 admin no puede leer la tabla de contexto',         'authenticated', v_pro::text, 'aal2', array[v_admin, v_ctx_other_tx],
         array['select count(*) from public.mobau_moderation_context'], 'exec', '42501'),
      ('C07 fila de otra transacción: no se reutiliza ni se revela', 'authenticated', v_pro::text, 'aal2', array[v_admin, v_prod, v_price, v_u1, v_ctx_other_tx],
         array[format('select count(*) where public.mobau_moderation_proposal_id() is not null or public.mobau_moderating(%L::uuid)', u1)], 'count', '0'),
      ('C08 contexto de otra propuesta: no vale para esta',    'authenticated', v_pro::text, 'aal2', array[v_admin, v_prod, v_price, v_u1, v_ctx_other_prop],
         array[format('select count(*) where public.mobau_moderating(%L::uuid)', u1)], 'count', '0'),
      ('C09 contexto de otro admin: no vale para este',        'authenticated', v_pro::text, 'aal2', array[v_admin, v_prod, v_price, v_u1, v_ctx_other_admin],
         array[format('select count(*) where public.mobau_moderating(%L::uuid) or public.mobau_moderation_proposal_id() is not null', u1)], 'count', '0'),
      ('C10 contexto exacto pero sesión sin aal2: no vale',    'authenticated', v_pro::text, 'aal1', array[v_admin, v_prod, v_price, v_u1, v_ctx_exact],
         array[format('select count(*) where public.mobau_moderating(%L::uuid)', u1)], 'count', '0'),
      ('C11 contexto vacío tras aprobar',                      'authenticated', v_pro::text, 'aal2', array[v_admin, v_c1],
         array[format(fn_save, c1, 'approve', null, 1), 'reset role',
               format('select case when %s ->> %L = %L then (select count(*) from public.mobau_moderation_context) else -1 end', res, 'result', 'approved')], 'count', '0'),
      ('C12 contexto vacío tras rechazar',                     'authenticated', v_pro::text, 'aal2', array[v_admin, v_prod, v_price, v_u1],
         array[format(fn_save, u1, 'reject', 'Motivo 39.', 1), 'reset role',
               format('select case when %s ->> %L = %L then (select count(*) from public.mobau_moderation_context) else -1 end', res, 'result', 'rejected')], 'count', '0'),
      ('C13 contexto vacío tras un fallo revertido',           'authenticated', v_pro::text, 'aal2', array[v_admin, v_c3, v_fail_price],
         array[format(fn_try, c3, 'approve', null, 1), 'reset role',
               format('select case when current_setting(%L) = %L then (select count(*) from public.mobau_moderation_context) else -1 end', 'mobau.test_result', '23514')], 'count', '0'),
      ('C14 contexto vacío tras un conflicto de versión',      'authenticated', v_pro::text, 'aal2', array[v_admin, v_prod, v_price, v_u1],
         array[format(fn_save, u1, 'approve', null, 2), 'reset role',
               format('select case when %s ->> %L = %L then (select count(*) from public.mobau_moderation_context) else -1 end', res, 'code', 'version_conflict')], 'count', '0'),
      -- ---------- Estado global ----------
      ('R01 políticas en public = 48 (47 de 39 − 1 + 2 de 39-06)', '-', null, null, null::text[],
         array['select count(*) from pg_policies where schemaname = ''public'''], 'count', '48'),
      ('R02 mobau_admins idéntica a la línea base (ningún admin de prueba queda)', '-', null, null, null::text[],
         array[format('select count(*) from (select count(*) as n, md5(coalesce(string_agg(to_jsonb(a)::text, %L order by a.user_id), %L)) as fp'
                      || ' from public.mobau_admins a) x where x.n = %s and x.fp = %L', '|', '', v_adm_n, v_adm_md5)], 'count', '1'),
      ('R03 contexto de moderación vacío',                     '-', null, null, null::text[],
         array['select count(*) from public.mobau_moderation_context'], 'count', '0')
    ) as c(name, role, sub, aal, setup, sql, kind, expect)
  loop
    v_got := null;
    begin
      if t.setup is not null then
        foreach v_stmt in array t.setup loop
          execute v_stmt;
        end loop;
      end if;
      if t.role <> '-' then
        execute format('set local role %I', t.role);
      end if;
      perform set_config('request.jwt.claim.sub', coalesce(t.sub, ''), true);
      perform set_config('request.jwt.claims',
        case when t.sub is null then '' else json_build_object('sub', t.sub, 'role', t.role, 'aal', t.aal)::text end, true);
      for i in 1 .. array_length(t.sql, 1) loop
        if i < array_length(t.sql, 1) then
          execute t.sql[i];
        elsif t.kind = 'count' then
          execute t.sql[i] into v_n;
          v_got := v_n::text;
        else
          execute t.sql[i];
          get diagnostics v_n = row_count;
          v_got := 'ok rows=' || v_n;
        end if;
      end loop;
      raise exception using errcode = 'MB001'; -- deshace el caso: datos auxiliares, admin temporal y rol
    exception
      when sqlstate 'MB001' then null;
      when others then v_got := sqlstate || ' ' || left(sqlerrm, 160);
    end;

    -- Errores esperados (solo en casos 'exec'): 'SQLSTATE' o 'SQLSTATE:texto'.
    v_ok := case
      when t.kind = 'exec' and t.expect ~ '^[0-9A-Z]{5}:' then
        v_got like split_part(t.expect, ':', 1) || '%' and v_got ilike '%' || split_part(t.expect, ':', 2) || '%'
      when t.kind = 'exec' and t.expect ~ '^[0-9A-Z]{5}$' then v_got like t.expect || '%'
      when t.expect = 'ok' then v_got like 'ok rows=%' and v_got <> 'ok rows=0'
      when t.expect = 'rows=0' then v_got = 'ok rows=0'
      else v_got = t.expect
    end;
    n_total := n_total + 1;
    if v_ok then n_ok := n_ok + 1; end if;
    r := r || jsonb_build_object('prueba', t.name, 'esperado', t.expect, 'obtenido', v_got, 'ok', v_ok);
  end loop;

  raise exception 'MOBAU_39_MODERACION total=% ok=% fallos=% :: %', n_total, n_ok, n_total - n_ok, r::text
    using errcode = 'MB999';
end $$;

ROLLBACK;
