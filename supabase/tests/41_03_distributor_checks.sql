-- ============================================================
-- PROPUESTA NO EJECUTADA (41-03 · distribuidor) — no ejecutar sin aprobación explícita
-- ============================================================
-- 41 · 03 · Lecturas y acciones del distribuidor, en una transacción
-- revertida. Ejecutar después de 41-05 (V3 completa). Rol postgres; JWT
-- simulado como en 39.
--
-- En cada caso, DENTRO de su subtransacción (se deshace con MB001):
--   · se enciende el interruptor y se concede EXECUTE de las 5 funciones del
--     distribuidor a authenticated (fuera del caso todo sigue apagado y
--     cerrado: lo comprueba la suite CL y el último caso de esta);
--   · se crean los auxiliares rls41v3-* (productos de A en 9 estados, 2 de B,
--     precios y eventos de auditoría) y el vínculo temporal de B como
--     supplier verificado de 'rls41v3-dist-b'.
-- Grupos: ISO (aislamiento rev5), NA (identidad rev7), T (T1, T6, T7 y sus
-- bloqueos), R (papelera y restauración idénticas), VER (sello del
-- catálogo), N (N1, N2, N8, N10–N12), NW (sin escrituras antes del error).
-- CTRL+: antes de los casos, un INSERT/UPDATE/DELETE deliberado y deshecho DEBE
-- cambiar los contadores de pg_stat_xact; si no, la suite se detiene (MB998).
-- Formato de expect en 'exec': SQLSTATE (5) o SQLSTATE[hint] exactos.
-- ============================================================

BEGIN;

DO $$
declare
  v_sup uuid; v_sup_dist text; v_pro uuid; v_pro2 uuid; v_pro3 uuid; v_cat1 text;
  n_a_real bigint;
  s_on text; g_dist text[]; s_b text[]; s_b_nosup text[]; s_b_pend text[]; s_aux text[]; s_open text; s_open_ret text;
  base text[]; s_c0 text; q_w text; q_nw text; s_ver0 text;
  dp_cols constant text := 'insert into public.distributor_profiles (user_id, nombre_comercial, razon_social, rnc, direccion_fiscal, telefono, email_contacto, nombre_contacto, cargo_contacto, verification_status, verified_at, distributor_id)'
                           || ' values (%L, %L, %L, %L, %L, %L, %L, %L, %L, %L, %s, %L)';
  -- updated_at una hora antes: así cualquier UPDATE del caso (trigger = now()) cambia la versión.
  ins_p constant text := 'insert into public.products (id, name, distributor_id, category_id, publication_status, retired_at, retired_by, retired_reason, trashed_at, trashed_by, trash_from, purge_after, updated_at)'
                         || ' values (%L, %L, %L, %L, %L, %s, %L, %L, %s, %L, %L, %s, now() - interval ''1 hour'')';
  ins_e constant text := 'insert into mobau_private.product_lifecycle_events (product_id, distributor_id, action, from_state, to_state, actor_id, actor_kind, reason, purge_counts, purge_sha256, meta)'
                         || ' values (%L, %L, %L, %L, %L, %L, %L, %L, %L, %L, %L)';
  s_upd constant text := 'select set_config(''mobau.upd'', (select updated_at::text from public.products where id = %L), true)';
  upd constant text := 'current_setting(''mobau.upd'')::timestamptz';
  save constant text := 'select set_config(''mobau.test_result'', (%s)::text, true)';
  fn_try constant text := 'do $t$ declare h text; begin perform %s; perform set_config(''mobau.test_result'', ''sin error'', true);'
                          || ' exception when others then get stacked diagnostics h = pg_exception_hint;'
                          || ' perform set_config(''mobau.test_result'', sqlstate || ''['' || coalesce(h, '''') || '']'', true); end $t$';
  fp_ret constant text := '(select md5((to_jsonb(p) - ''updated_at'')::text) || ''/'' || coalesce(md5(to_jsonb(pp)::text), ''-'')'
                          || ' from public.products p left join public.product_prices pp on pp.product_id = p.id where p.id = %L)';
  fn_exec constant text := 'do $t$ declare h text; begin %s; perform set_config(''mobau.test_result'', ''sin error'', true);'
                          || ' exception when others then get stacked diagnostics h = pg_exception_hint;'
                          || ' perform set_config(''mobau.test_result'', sqlstate || ''['' || coalesce(h, '''') || '']'', true); end $t$';
  v_c0 text; v_c1 text; w_i0 bigint; w_u0 bigint; w_d0 bigint; w_i1 bigint; w_u1 bigint; w_d1 bigint;
  r jsonb := '[]'::jsonb; t record; i int;
  v_got text; v_n bigint; v_ok boolean; v_stmt text; v_hint text;
  n_total int := 0; n_ok int := 0;
begin
  select dp.user_id, dp.distributor_id into v_sup, v_sup_dist
    from public.distributor_profiles dp join public.profiles p on p.id = dp.user_id
   where p.role = 'supplier' and dp.verification_status = 'verified' and dp.distributor_id is not null
   order by dp.created_at limit 1;
  select p.id into v_pro from public.profiles p
   where p.role = 'individual' and not exists (select 1 from public.mobau_admins a where a.user_id = p.id)
     and not exists (select 1 from public.distributor_profiles dp where dp.user_id = p.id)
   order by p.created_at limit 1;
  select p.id into v_pro2 from public.profiles p
   where p.role = 'individual' and p.id <> v_pro and not exists (select 1 from public.mobau_admins a where a.user_id = p.id)
     and not exists (select 1 from public.distributor_profiles dp where dp.user_id = p.id)
   order by p.created_at limit 1;
  select p.id into v_pro3 from public.profiles p
   where p.role = 'individual' and p.id not in (v_pro, v_pro2) and not exists (select 1 from public.mobau_admins a where a.user_id = p.id)
     and not exists (select 1 from public.distributor_profiles dp where dp.user_id = p.id)
   order by p.created_at limit 1;
  select c.id into v_cat1 from public.categories c order by c.id limit 1;
  select count(*) into n_a_real from public.products where distributor_id = v_sup_dist;
  if v_sup is null or v_pro is null or v_pro2 is null or v_pro3 is null or v_cat1 is null then
    raise exception 'MOBAU_41_03: faltan datos de partida' using errcode = 'MB998';
  end if;
  if to_regprocedure('public.distributor_retire_product(text, text, timestamp with time zone)') is null then
    raise exception 'MOBAU_41_03: falta 41-03' using errcode = 'MB998';
  end if;
  if exists (select 1 from public.products where id like 'rls41v3%') then
    raise exception 'MOBAU_41_03: ya existen auxiliares rls41v3' using errcode = 'MB998';
  end if;

  -- ---------- auxiliares (como postgres, dentro de cada caso) ----------
  s_on := 'update mobau_private.product_lifecycle_settings set enabled = true where id = 1';
  g_dist := array[
    'grant execute on function public.my_products_lifecycle() to authenticated',
    'grant execute on function public.my_product_lifecycle_events(text) to authenticated',
    'grant execute on function public.distributor_retire_product(text, text, timestamptz) to authenticated',
    'grant execute on function public.distributor_trash_product(text, timestamptz) to authenticated',
    'grant execute on function public.distributor_restore_product(text, timestamptz) to authenticated'];
  s_b_nosup := array[
    format('insert into public.distributors (id, name) values (%L, %L)', 'rls41v3-dist-b', 'Distribuidor B (prueba 41 V3)'),
    format(dp_cols, v_pro2, 'Prueba 41 V3 B', 'Prueba 41 V3 B SRL', '999999943', 'Calle de prueba 41', '0000000043',
           'prueba41v3@example.invalid', 'Contacto prueba 41', 'Prueba', 'verified', 'now()', 'rls41v3-dist-b')];
  s_b := s_b_nosup || format('update public.profiles set role = %L where id = %L', 'supplier', v_pro2);
  s_b_pend := array[s_b_nosup[1],
    format(dp_cols, v_pro2, 'Prueba 41 V3 B', 'Prueba 41 V3 B SRL', '999999943', 'Calle de prueba 41', '0000000043',
           'prueba41v3@example.invalid', 'Contacto prueba 41', 'Prueba', 'pending_verification', 'null', 'rls41v3-dist-b'),
    format('update public.profiles set role = %L where id = %L', 'supplier', v_pro2)];
  s_aux := array[
    -- A: 9 estados
    format(ins_p, 'rls41v3-a-pub', 'A publicado 41 V3', v_sup_dist, v_cat1, 'published', 'null', null, null, 'null', null, null, 'null'),
    format(ins_p, 'rls41v3-a-draft', 'A borrador 41 V3', v_sup_dist, v_cat1, 'draft', 'null', null, null, 'null', null, null, 'null'),
    format(ins_p, 'rls41v3-a-rev', 'A en revisión 41 V3', v_sup_dist, v_cat1, 'in_review', 'null', null, null, 'null', null, null, 'null'),
    format(ins_p, 'rls41v3-a-chg', 'A con cambios 41 V3', v_sup_dist, v_cat1, 'changes_requested', 'null', null, null, 'null', null, null, 'null'),
    format(ins_p, 'rls41v3-a-leg', 'A heredado 41 V3', v_sup_dist, v_cat1, 'archived', 'null', null, null, 'null', null, null, 'null'),
    format(ins_p, 'rls41v3-a-ret', 'A retirado 41 V3', v_sup_dist, v_cat1, 'archived', 'now() - interval ''2 days''', v_pro, 'Motivo de Mobau 41 V3', 'null', null, null, 'null'),
    format(ins_p, 'rls41v3-a-trr', 'A papelera (retirado) 41 V3', v_sup_dist, v_cat1, 'archived', 'now() - interval ''3 days''', v_sup, 'Motivo de A 41 V3',
           'now() - interval ''1 day''', v_sup, 'retired', 'now() - interval ''1 day'' + interval ''30 days'''),
    format(ins_p, 'rls41v3-a-trd', 'A papelera (borrador) 41 V3', v_sup_dist, v_cat1, 'draft', 'null', null, null,
           'now() - interval ''1 day''', v_sup, 'draft', 'now() - interval ''1 day'' + interval ''30 days'''),
    format(ins_p, 'rls41v3-a-trx', 'A papelera vencida 41 V3', v_sup_dist, v_cat1, 'draft', 'null', null, null,
           'now() - interval ''31 days''', v_sup, 'draft', 'now() - interval ''31 days'' + interval ''30 days'''),
    -- B: 2 productos
    format(ins_p, 'rls41v3-b-pub', 'B publicado 41 V3', 'rls41v3-dist-b', v_cat1, 'published', 'null', null, null, 'null', null, null, 'null'),
    format(ins_p, 'rls41v3-b-ret', 'B retirado 41 V3', 'rls41v3-dist-b', v_cat1, 'archived', 'now()', v_pro2, 'Motivo de B 41 V3', 'null', null, null, 'null'),
    -- precios
    format('insert into public.product_prices (product_id, price_status, price_amount, currency, includes_itbis) values (%L, %L, 50, %L, true)', 'rls41v3-a-pub', 'published', 'USD'),
    format('insert into public.product_prices (product_id, price_status, price_amount, currency, includes_itbis) values (%L, %L, 60, %L, true)', 'rls41v3-a-ret', 'published', 'USD'),
    -- auditoría: A (retirada de Mobau, papelera de A); B (retirada de B y una purga)
    format(ins_e, 'rls41v3-a-ret', v_sup_dist, 'retire', 'published', 'retired', v_pro, 'mobau', 'Motivo de Mobau 41 V3', null, null, null),
    format(ins_e, 'rls41v3-a-trr', v_sup_dist, 'trash', 'retired', 'trashed', v_sup, 'distributor', null, null, null, null),
    format(ins_e, 'rls41v3-b-ret', 'rls41v3-dist-b', 'retire', 'published', 'retired', v_pro2, 'distributor', 'Motivo de B 41 V3', null, null, null),
    format(ins_e, 'rls41v3-b-gone', 'rls41v3-dist-b', 'purge', 'trashed', null, v_pro, 'mobau', 'Purga de prueba 41 V3',
           '{"products": 1, "product_prices": 0, "product_proposals": 0, "proposal_events": 0}', repeat('a', 64), '{"category_id": "x"}')];
  base := s_b || s_aux || s_on || g_dist;
  s_open := format('insert into public.product_proposals (proposal_kind, product_id, distributor_id, status, proposed_changes) values (%L, %L, %L, %L, %L)',
                   'update', 'rls41v3-a-pub', v_sup_dist, 'draft', '{"name": "Propuesta abierta 41 V3"}');
  s_open_ret := format('insert into public.product_proposals (proposal_kind, product_id, distributor_id, status, proposed_changes) values (%L, %L, %L, %L, %L)',
                       'update', 'rls41v3-a-ret', v_sup_dist, 'draft', '{"name": "Propuesta abierta 41 V3"}');
  q_w := '(select string_agg(s.relid::regclass::text || '':'' || s.n_tup_ins || '':'' || s.n_tup_upd || '':'' || s.n_tup_del, '','' order by s.relid::regclass::text)'
         || ' from pg_catalog.pg_stat_xact_all_tables s where s.relid in (''public.products''::regclass, ''public.product_prices''::regclass,'
         || ' ''public.product_proposals''::regclass, ''public.proposal_events''::regclass, ''mobau_private.product_lifecycle_events''::regclass,'
         || ' ''mobau_private.product_lifecycle_settings''::regclass))';
  s_c0 := 'select set_config(''mobau.c0'', ' || q_w || ', true)';
  q_nw := 'select count(*) where current_setting(''mobau.test_result'') = %L and ' || q_w || ' = current_setting(''mobau.c0'')';
  s_ver0 := 'select set_config(''mobau.ver0'', public.catalog_version(), true)';

  -- ---------- CTRL+ · control positivo de «sin escrituras» (pg_stat_xact) ----------
  -- Una escritura deliberada (INSERT, UPDATE y DELETE en products) dentro de una
  -- subtransacción que se deshace DEBE cambiar los contadores. Si no, la suite se
  -- DETIENE (MB998): no se sustituye por la revisión estática.
  select s.n_tup_ins, s.n_tup_upd, s.n_tup_del into w_i0, w_u0, w_d0
    from pg_catalog.pg_stat_xact_all_tables s where s.relid = 'public.products'::regclass;
  execute 'select ' || q_w into v_c0;
  begin
    insert into public.products (id, name, distributor_id, category_id, publication_status)
    values ('rls41v3-ctl', 'Control positivo 41 V3', v_sup_dist, v_cat1, 'draft');
    update public.products set name = 'Control positivo 41 V3 (2)' where id = 'rls41v3-ctl';
    delete from public.products where id = 'rls41v3-ctl';
    raise exception using errcode = 'MB002';
  exception when sqlstate 'MB002' then null;
  end;
  select s.n_tup_ins, s.n_tup_upd, s.n_tup_del into w_i1, w_u1, w_d1
    from pg_catalog.pg_stat_xact_all_tables s where s.relid = 'public.products'::regclass;
  execute 'select ' || q_w into v_c1;
  if not (w_i1 > coalesce(w_i0, 0) and w_u1 > coalesce(w_u0, 0) and w_d1 > coalesce(w_d0, 0)) or v_c1 is not distinct from v_c0 then
    raise exception '%: CONTROL POSITIVO FALLIDO: pg_stat_xact no detecta una escritura deshecha (ins %->%, upd %->%, del %->%). Suite detenida.',
      'MOBAU_41_03', w_i0, w_i1, w_u0, w_u1, w_d0, w_d1 using errcode = 'MB998';
  end if;

  for t in
    select * from (values
      -- ---------- CTRL+ (también en el informe) ----------
      ('CTRL+ una escritura deliberada y deshecha cambia los contadores (el mecanismo detecta escrituras)', '-', null::text, null::text, array[s_c0]::text[],
         array[format(fn_exec, format('insert into public.products (id, name, distributor_id, category_id, publication_status) values (%L, %L, %L, %L, %L);'
                                      || ' delete from public.products where id = %L; raise exception %L',
                                      'rls41v3-ctl', 'Control positivo 41 V3', v_sup_dist, v_cat1, 'draft', 'rls41v3-ctl', 'control')),
               'select count(*) where ' || q_w || ' is distinct from current_setting(''mobau.c0'') and current_setting(''mobau.test_result'') = ''P0001[]'''
               || ' and not exists (select 1 from public.products where id = ''rls41v3-ctl'')']::text[], 'count', '1'),
      -- ========== ISO · aislamiento (rev5) ==========
      ('I01 A: my_products_lifecycle() = todos sus productos (reales + 9 auxiliares) y nada más', 'authenticated', v_sup::text, 'aal1', base,
         array['select count(*) from public.my_products_lifecycle()']::text[], 'count', (n_a_real + 9)::text),
      ('I02 A no ve ningún producto de B', 'authenticated', v_sup::text, 'aal1', base,
         array['select count(*) from public.my_products_lifecycle() m where m.id like ''rls41v3-b-%'''], 'count', '0'),
      ('I03 B ve exactamente sus 2 productos', 'authenticated', v_pro2::text, 'aal1', base,
         array['select count(*) where (select count(*) from public.my_products_lifecycle()) = 2'
               || ' and (select count(*) from public.my_products_lifecycle() m where m.id in (''rls41v3-b-pub'', ''rls41v3-b-ret'')) = 2'
               || ' and not exists (select 1 from public.my_products_lifecycle() m where m.id not in (''rls41v3-b-pub'', ''rls41v3-b-ret''))'], 'count', '1'),
      ('I04 A: my_product_lifecycle_events(null) = solo sus 2 eventos', 'authenticated', v_sup::text, 'aal1', base,
         array['select count(*) where (select count(*) from public.my_product_lifecycle_events(null)) = 2'
               || ' and (select count(*) from public.my_product_lifecycle_events(null) e'
               || '      where (e.product_id, e.action) in ((''rls41v3-a-ret'', ''retire''), (''rls41v3-a-trr'', ''trash''))) = 2'
               || ' and not exists (select 1 from public.my_product_lifecycle_events(null) e where e.product_id not in (''rls41v3-a-ret'', ''rls41v3-a-trr''))'], 'count', '1'),
      ('I05 A pide eventos de un producto de B → 0 filas, sin error', 'authenticated', v_sup::text, 'aal1', base,
         array['select count(*) from public.my_product_lifecycle_events(''rls41v3-b-ret'')'], 'count', '0'),
      ('I06 A pide eventos de un id inexistente → 0 filas, sin error (igual que I05)', 'authenticated', v_sup::text, 'aal1', base,
         array['select count(*) from public.my_product_lifecycle_events(''rls41v3-no-existe'')'], 'count', '0'),
      ('I07 columnas fijas: my_products_lifecycle sin uuids; eventos sin actor_id ni purga', '-', null, null, null::text[],
         array['select count(*) where array_to_string((select proargnames from pg_proc where oid = ''public.my_products_lifecycle()''::regprocedure), '','')'
               || ' = ''id,name,publication_status,lifecycle_state,allowed_actions,has_open_proposal,retired_at,retired_reason,retired_by_kind,trashed_at,purge_after,updated_at'''
               || ' and array_to_string((select proargnames from pg_proc where oid = ''public.my_product_lifecycle_events(text)''::regprocedure), '','')'
               || ' = ''p_product_id,product_id,action,from_state,to_state,actor_kind,reason,created_at'''], 'count', '1'),
      ('I08 B ve su purga sin estados, motivo, recuentos ni huella', 'authenticated', v_pro2::text, 'aal1', base,
         array['select count(*) from public.my_product_lifecycle_events(null) e where e.action = ''purge'' and e.from_state is null and e.to_state is null and e.reason is null'], 'count', '1'),
      ('I09 A ve la retirada de Mobau como «mobau», sin uuid (eventos y retired_by_kind)', 'authenticated', v_sup::text, 'aal1', base,
         array['select count(*) where (select count(*) from public.my_product_lifecycle_events(''rls41v3-a-ret'') e where e.actor_kind = ''mobau'') = 1'
               || ' and (select m.retired_by_kind from public.my_products_lifecycle() m where m.id = ''rls41v3-a-ret'') = ''mobau'''], 'count', '1'),
      ('I10 profesional sin empresa: 0 filas en las dos lecturas', 'authenticated', v_pro3::text, 'aal1', base,
         array['select (select count(*) from public.my_products_lifecycle()) + (select count(*) from public.my_product_lifecycle_events(null))'], 'count', '0'),
      ('I11 B verificado SIN role supplier (B3): 0 filas', 'authenticated', v_pro2::text, 'aal1', s_b_nosup || s_aux || s_on || g_dist,
         array['select (select count(*) from public.my_products_lifecycle()) + (select count(*) from public.my_product_lifecycle_events(null))'], 'count', '0'),
      ('I12 B supplier con empresa pendiente: 0 filas', 'authenticated', v_pro2::text, 'aal1', s_b_pend || s_aux || s_on || g_dist,
         array['select (select count(*) from public.my_products_lifecycle()) + (select count(*) from public.my_product_lifecycle_events(null))'], 'count', '0'),
      ('I13 NA-01 authenticated sin JWT → 42501[not_authenticated]', 'authenticated', null, null, base,
         array['select count(*) from public.my_products_lifecycle()'], 'exec', '42501[not_authenticated]'),
      ('I14 NA-02 JWT authenticated sin sub → 42501[not_authenticated] (también eventos)', 'authenticated', 'nosub', 'aal1', base,
         array['select count(*) from public.my_product_lifecycle_events(''rls41v3-a-ret'')'], 'exec', '42501[not_authenticated]'),
      ('I15 parámetro vacío → 22023[invalid_parameter]', 'authenticated', v_sup::text, 'aal1', base,
         array['select count(*) from public.my_product_lifecycle_events('''')'], 'exec', '22023[invalid_parameter]'),
      ('I16 parámetro de 201 caracteres → 22023[invalid_parameter] (igual para ajeno e inexistente)', 'authenticated', v_sup::text, 'aal1', base,
         array['select count(*) from public.my_product_lifecycle_events(repeat(''x'', 201))'], 'exec', '22023[invalid_parameter]'),
      ('I17 A no lee la auditoría directamente (sin USAGE de mobau_private)', 'authenticated', v_sup::text, 'aal1', base,
         array['select count(*) from mobau_private.product_lifecycle_events'], 'exec', '42501'),
      ('I18 estado lógico de los 9 estados de A (origen único)', 'authenticated', v_sup::text, 'aal1', base,
         array['select string_agg(substr(m.id, 9) || ''='' || m.lifecycle_state, '';'' order by m.id) from public.my_products_lifecycle() m where m.id like ''rls41v3-a-%'''],
         'text', 'a-chg=changes_requested;a-draft=draft;a-leg=legacy_retired;a-pub=published;a-ret=retired;a-rev=in_review;a-trd=trashed;a-trr=trashed;a-trx=trashed'),
      ('I19 acciones permitidas por estado con el interruptor encendido', 'authenticated', v_sup::text, 'aal1', base,
         array['select string_agg(substr(m.id, 9) || ''='' || m.allowed_actions::text, '';'' order by m.id) from public.my_products_lifecycle() m where m.id like ''rls41v3-a-%'''],
         'text', 'a-chg={};a-draft={trash};a-leg={};a-pub={retire};a-ret={request_republish,trash};a-rev={};a-trd={restore};a-trr={restore};a-trx={}'),
      ('I20 propuesta abierta: has_open_proposal y sin acciones', 'authenticated', v_sup::text, 'aal1', base || s_open,
         array['select count(*) from public.my_products_lifecycle() m where m.id = ''rls41v3-a-pub'' and m.has_open_proposal and m.allowed_actions = ''{}''::text[]'], 'count', '1'),
      -- ========== T1 · retirar ==========
      ('T01 A retira su publicado: archived/archived, retired_* de A, evento retire de distributor', 'authenticated', v_sup::text, 'aal1', base || format(s_upd, 'rls41v3-a-pub'),
         array[format(save, format('public.distributor_retire_product(%L, %L, %s)', 'rls41v3-a-pub', 'Motivo 41 V3', upd)), 'reset role',
               format('select count(*) from public.products p where p.id = %L and p.publication_status = %L and p.status = %L and p.retired_by = %L'
                      || ' and p.retired_reason = %L and p.retired_at is not null and p.trashed_at is null and p.updated_at > current_setting(%L)::timestamptz'
                      || ' and (current_setting(%L)::jsonb ->> %L)::boolean and current_setting(%L)::jsonb ->> %L = %L'
                      || ' and exists (select 1 from mobau_private.product_lifecycle_events e where e.product_id = p.id and e.action = %L'
                      || '             and e.from_state = %L and e.to_state = %L and e.actor_kind = %L and e.actor_id = %L and e.reason = %L)',
                      'rls41v3-a-pub', 'archived', 'archived', v_sup, 'Motivo 41 V3', 'mobau.upd', 'mobau.test_result', 'ok', 'mobau.test_result', 'lifecycle_state', 'retired',
                      'retire', 'published', 'retired', 'distributor', v_sup, 'Motivo 41 V3')], 'count', '1'),
      ('T02 VER: tras retirar, anon ya no lo ve en catalog_products y catalog_version() cambia', 'authenticated', v_sup::text, 'aal1', base || format(s_upd, 'rls41v3-a-pub') || s_ver0,
         array[format('select public.distributor_retire_product(%L, %L, %s)', 'rls41v3-a-pub', 'Motivo 41 V3', upd), 'reset role', 'set local role anon',
               'select count(*) where not exists (select 1 from public.catalog_products where id = ''rls41v3-a-pub'') and public.catalog_version() <> current_setting(''mobau.ver0'')'], 'count', '1'),
      ('T03 retirar con propuesta abierta → 55000[open_proposal], sin escrituras (D3, N10)', 'authenticated', v_sup::text, 'aal1', base || s_open || format(s_upd, 'rls41v3-a-pub') || s_c0,
         array[format(fn_try, format('public.distributor_retire_product(%L, %L, %s)', 'rls41v3-a-pub', 'Motivo 41 V3', upd)), 'reset role', format(q_nw, '55000[open_proposal]')], 'count', '1'),
      ('T04 retirar un borrador → 55000[invalid_state]', 'authenticated', v_sup::text, 'aal1', base || format(s_upd, 'rls41v3-a-draft'),
         array[format('select public.distributor_retire_product(%L, %L, %s)', 'rls41v3-a-draft', 'Motivo 41 V3', upd)], 'exec', '55000[invalid_state]'),
      ('T05 retirar un heredado → 55000[legacy_pending_review] (N9)', 'authenticated', v_sup::text, 'aal1', base || format(s_upd, 'rls41v3-a-leg'),
         array[format('select public.distributor_retire_product(%L, %L, %s)', 'rls41v3-a-leg', 'Motivo 41 V3', upd)], 'exec', '55000[legacy_pending_review]'),
      ('T06 retirar un retirado → 55000[invalid_state]', 'authenticated', v_sup::text, 'aal1', base || format(s_upd, 'rls41v3-a-ret'),
         array[format('select public.distributor_retire_product(%L, %L, %s)', 'rls41v3-a-ret', 'Motivo 41 V3', upd)], 'exec', '55000[invalid_state]'),
      ('T07 retirar uno de la papelera → 55000[invalid_state]', 'authenticated', v_sup::text, 'aal1', base || format(s_upd, 'rls41v3-a-trr'),
         array[format('select public.distributor_retire_product(%L, %L, %s)', 'rls41v3-a-trr', 'Motivo 41 V3', upd)], 'exec', '55000[invalid_state]'),
      ('T08 versión distinta (real − 1 s) → 40001[version_conflict], sin escrituras', 'authenticated', v_sup::text, 'aal1', base || format(s_upd, 'rls41v3-a-pub') || s_c0,
         array[format(fn_try, format('public.distributor_retire_product(%L, %L, %s - interval ''1 second'')', 'rls41v3-a-pub', 'Motivo 41 V3', upd)), 'reset role', format(q_nw, '40001[version_conflict]')], 'count', '1'),
      ('T09 motivo vacío → 22023[invalid_reason]', 'authenticated', v_sup::text, 'aal1', base || format(s_upd, 'rls41v3-a-pub'),
         array[format('select public.distributor_retire_product(%L, %L, %s)', 'rls41v3-a-pub', '   ', upd)], 'exec', '22023[invalid_reason]'),
      ('T10 motivo de 501 caracteres → 22023[invalid_reason]', 'authenticated', v_sup::text, 'aal1', base || format(s_upd, 'rls41v3-a-pub'),
         array[format('select public.distributor_retire_product(%L, repeat(%L, 501), %s)', 'rls41v3-a-pub', 'x', upd)], 'exec', '22023[invalid_reason]'),
      ('T11 sin versión → 22023[missing_version]', 'authenticated', v_sup::text, 'aal1', base,
         array[format('select public.distributor_retire_product(%L, %L, null)', 'rls41v3-a-pub', 'Motivo 41 V3')], 'exec', '22023[missing_version]'),
      ('T12 producto de B → P0002[product_not_found]', 'authenticated', v_sup::text, 'aal1', base,
         array[format('select public.distributor_retire_product(%L, %L, now())', 'rls41v3-b-pub', 'Motivo 41 V3')], 'exec', 'P0002[product_not_found]'),
      ('T13 producto inexistente → P0002[product_not_found] (igual que T12)', 'authenticated', v_sup::text, 'aal1', base,
         array[format('select public.distributor_retire_product(%L, %L, now())', 'rls41v3-no-existe', 'Motivo 41 V3')], 'exec', 'P0002[product_not_found]'),
      ('T14 B verificado SIN supplier → 42501[not_verified_distributor] (B3)', 'authenticated', v_pro2::text, 'aal1', s_b_nosup || s_aux || s_on || g_dist,
         array[format('select public.distributor_retire_product(%L, %L, now())', 'rls41v3-b-pub', 'Motivo 41 V3')], 'exec', '42501[not_verified_distributor]'),
      ('T15 profesional → 42501[not_verified_distributor]', 'authenticated', v_pro3::text, 'aal1', base,
         array[format('select public.distributor_retire_product(%L, %L, now())', 'rls41v3-a-pub', 'Motivo 41 V3')], 'exec', '42501[not_verified_distributor]'),
      ('T16 sin sub → 42501[not_authenticated]', 'authenticated', 'nosub', 'aal1', base,
         array[format('select public.distributor_retire_product(%L, %L, now())', 'rls41v3-a-pub', 'Motivo 41 V3')], 'exec', '42501[not_authenticated]'),
      ('T17 B retira su publicado; A no ve el evento (aislamiento de escrituras)', 'authenticated', v_pro2::text, 'aal1', base || format(s_upd, 'rls41v3-b-pub'),
         array[format('select public.distributor_retire_product(%L, %L, %s)', 'rls41v3-b-pub', 'Motivo B 41 V3', upd), 'reset role',
               format('select count(*) from mobau_private.product_lifecycle_events e where e.product_id = %L and e.distributor_id = %L and e.actor_id = %L and e.action = %L',
                      'rls41v3-b-pub', 'rls41v3-dist-b', v_pro2, 'retire')], 'count', '1'),
      -- ========== T6 · papelera ==========
      ('T20 A mueve a la papelera su retirado: trash_from retired, purge_after = trashed_at + 30 días, retired_* intactos', 'authenticated', v_sup::text, 'aal1', base || format(s_upd, 'rls41v3-a-ret'),
         array[format('select public.distributor_trash_product(%L, %s)', 'rls41v3-a-ret', upd), 'reset role',
               format('select count(*) from public.products p where p.id = %L and p.trash_from = %L and p.purge_after = p.trashed_at + interval ''30 days'''
                      || ' and p.trashed_by = %L and p.publication_status = %L and p.retired_reason = %L and p.retired_by = %L'
                      || ' and exists (select 1 from mobau_private.product_lifecycle_events e where e.product_id = p.id and e.action = %L and e.from_state = %L and e.to_state = %L and e.actor_kind = %L)',
                      'rls41v3-a-ret', 'retired', v_sup, 'archived', 'Motivo de Mobau 41 V3', v_pro, 'trash', 'retired', 'trashed', 'distributor')], 'count', '1'),
      ('T21 A mueve a la papelera su borrador: trash_from draft', 'authenticated', v_sup::text, 'aal1', base || format(s_upd, 'rls41v3-a-draft'),
         array[format('select public.distributor_trash_product(%L, %s)', 'rls41v3-a-draft', upd), 'reset role',
               format('select count(*) from public.products where id = %L and trash_from = %L and publication_status = %L', 'rls41v3-a-draft', 'draft', 'draft')], 'count', '1'),
      ('T22 publicado → papelera directamente → 55000[invalid_state] (N11)', 'authenticated', v_sup::text, 'aal1', base || format(s_upd, 'rls41v3-a-pub'),
         array[format('select public.distributor_trash_product(%L, %s)', 'rls41v3-a-pub', upd)], 'exec', '55000[invalid_state]'),
      ('T23 en revisión → 55000[in_review]', 'authenticated', v_sup::text, 'aal1', base || format(s_upd, 'rls41v3-a-rev'),
         array[format('select public.distributor_trash_product(%L, %s)', 'rls41v3-a-rev', upd)], 'exec', '55000[in_review]'),
      ('T24 cambios solicitados → 55000[in_review]', 'authenticated', v_sup::text, 'aal1', base || format(s_upd, 'rls41v3-a-chg'),
         array[format('select public.distributor_trash_product(%L, %s)', 'rls41v3-a-chg', upd)], 'exec', '55000[in_review]'),
      ('T25 heredado → 55000[legacy_pending_review]', 'authenticated', v_sup::text, 'aal1', base || format(s_upd, 'rls41v3-a-leg'),
         array[format('select public.distributor_trash_product(%L, %s)', 'rls41v3-a-leg', upd)], 'exec', '55000[legacy_pending_review]'),
      ('T26 ya en la papelera → 55000[invalid_state]', 'authenticated', v_sup::text, 'aal1', base || format(s_upd, 'rls41v3-a-trr'),
         array[format('select public.distributor_trash_product(%L, %s)', 'rls41v3-a-trr', upd)], 'exec', '55000[invalid_state]'),
      ('T27 retirado con propuesta abierta → 55000[open_proposal]', 'authenticated', v_sup::text, 'aal1', base || s_open_ret || format(s_upd, 'rls41v3-a-ret'),
         array[format('select public.distributor_trash_product(%L, %s)', 'rls41v3-a-ret', upd)], 'exec', '55000[open_proposal]'),
      -- ========== T7 · restaurar ==========
      ('T30 restaurar desde retirado: vuelve a retirado con sus retired_* originales; nunca publica (N8)', 'authenticated', v_sup::text, 'aal1',
         base || format(s_upd, 'rls41v3-a-trr')
              || format('select set_config(%L, (select retired_at::text || %L || retired_by::text || %L || retired_reason from public.products where id = %L), true)', 'mobau.ret0', '|', '|', 'rls41v3-a-trr'),
         array[format(save, format('public.distributor_restore_product(%L, %s)', 'rls41v3-a-trr', upd)), 'reset role',
               format('select count(*) from public.products p where p.id = %L and p.publication_status = %L and p.trashed_at is null and p.trashed_by is null'
                      || ' and p.trash_from is null and p.purge_after is null'
                      || ' and p.retired_at::text || %L || p.retired_by::text || %L || p.retired_reason = current_setting(%L)'
                      || ' and current_setting(%L)::jsonb ->> %L = %L'
                      || ' and exists (select 1 from mobau_private.product_lifecycle_events e where e.product_id = p.id and e.action = %L and e.from_state = %L and e.to_state = %L)',
                      'rls41v3-a-trr', 'archived', '|', '|', 'mobau.ret0', 'mobau.test_result', 'lifecycle_state', 'retired', 'restore', 'trashed', 'retired')], 'count', '1'),
      ('T31 restaurar desde borrador → borrador', 'authenticated', v_sup::text, 'aal1', base || format(s_upd, 'rls41v3-a-trd'),
         array[format('select public.distributor_restore_product(%L, %s)', 'rls41v3-a-trd', upd), 'reset role',
               format('select count(*) from public.products where id = %L and publication_status = %L and trashed_at is null', 'rls41v3-a-trd', 'draft')], 'count', '1'),
      ('T32 fuera de plazo → 55000[restore_window_expired], sin escrituras (N12)', 'authenticated', v_sup::text, 'aal1', base || format(s_upd, 'rls41v3-a-trx') || s_c0,
         array[format(fn_try, format('public.distributor_restore_product(%L, %s)', 'rls41v3-a-trx', upd)), 'reset role', format(q_nw, '55000[restore_window_expired]')], 'count', '1'),
      ('T33 restaurar algo que no está en la papelera → 55000[invalid_state]', 'authenticated', v_sup::text, 'aal1', base || format(s_upd, 'rls41v3-a-ret'),
         array[format('select public.distributor_restore_product(%L, %s)', 'rls41v3-a-ret', upd)], 'exec', '55000[invalid_state]'),
      -- ========== R · papelera y restauración idénticas (producto y precio) ==========
      ('R01 retirado con precio → papelera → restaurar: producto (sin updated_at) y precio idénticos, sigue archived', 'authenticated', v_sup::text, 'aal1',
         base || format(s_upd, 'rls41v3-a-ret') || format('select set_config(%L, %s, true)', 'mobau.fp0', format(fp_ret, 'rls41v3-a-ret')),
         array[format('select set_config(%L, (public.distributor_trash_product(%L, %s) ->> %L), true)', 'mobau.u2', 'rls41v3-a-ret', upd, 'updated_at'),
               format('select public.distributor_restore_product(%L, current_setting(%L)::timestamptz)', 'rls41v3-a-ret', 'mobau.u2'), 'reset role',
               format('select count(*) where %s = current_setting(%L) and (select publication_status from public.products where id = %L) = %L',
                      format(fp_ret, 'rls41v3-a-ret'), 'mobau.fp0', 'rls41v3-a-ret', 'archived')], 'count', '1'),
      -- ========== N · el distribuidor nunca publica ni escribe directamente ==========
      ('N01 retirar → papelera → restaurar nunca deja published (N1)', 'authenticated', v_sup::text, 'aal1', base || format(s_upd, 'rls41v3-a-pub'),
         array[format('select set_config(%L, (public.distributor_retire_product(%L, %L, %s) ->> %L), true)', 'mobau.u2', 'rls41v3-a-pub', 'Motivo 41 V3', upd, 'updated_at'),
               format('select set_config(%L, (public.distributor_trash_product(%L, current_setting(%L)::timestamptz) ->> %L), true)', 'mobau.u3', 'rls41v3-a-pub', 'mobau.u2', 'updated_at'),
               format('select public.distributor_restore_product(%L, current_setting(%L)::timestamptz)', 'rls41v3-a-pub', 'mobau.u3'), 'reset role',
               format('select count(*) from public.products where id = %L and publication_status = %L and retired_at is not null', 'rls41v3-a-pub', 'archived')], 'count', '1'),
      ('N02 A no puede escribir retired_at directamente (42501)', 'authenticated', v_sup::text, 'aal1', base,
         array['update public.products set retired_at = now() where id = ''rls41v3-a-pub'''], 'exec', '42501'),
      ('N03 A no puede publicar su retirado directamente (42501)', 'authenticated', v_sup::text, 'aal1', base,
         array['update public.products set publication_status = ''published'' where id = ''rls41v3-a-ret'''], 'exec', '42501'),
      -- ========== estado tras la suite ==========
      ('Z01 fuera de los casos: interruptor apagado, sin EXECUTE de cliente y sin restos', '-', null, null, null::text[],
         array['select count(*) where not mobau_private.product_lifecycle_enabled()'
               || ' and not has_function_privilege(''authenticated'', ''public.distributor_retire_product(text, text, timestamptz)'', ''EXECUTE'')'
               || ' and not has_function_privilege(''authenticated'', ''public.my_products_lifecycle()'', ''EXECUTE'')'
               || ' and not exists (select 1 from public.products where id like ''rls41v3%'')'
               || ' and not exists (select 1 from mobau_private.product_lifecycle_events)'
               || ' and (select role from public.profiles where id = ''' || v_pro2 || ''') = ''individual'''], 'count', '1')
    ) as c(name, role, sub, aal, setup, sql, kind, expect)
  loop
    v_got := null;
    begin
      if t.setup is not null then
        foreach v_stmt in array t.setup loop execute v_stmt; end loop;
      end if;
      if t.role <> '-' then execute format('set local role %I', t.role); end if;
      perform set_config('request.jwt.claim.sub', case when t.sub is null or t.sub = 'nosub' then '' else t.sub end, true);
      perform set_config('request.jwt.claim.role', '', true);
      perform set_config('request.jwt.claims',
        case when t.sub is null then ''
             when t.sub = 'nosub' then json_build_object('role', 'authenticated', 'aud', 'authenticated', 'aal', 'aal1')::text
             else json_build_object('sub', t.sub, 'role', t.role, 'aal', t.aal)::text end, true);
      for i in 1 .. array_length(t.sql, 1) loop
        if i < array_length(t.sql, 1) then
          execute t.sql[i];
        elsif t.kind = 'count' then
          execute t.sql[i] into v_n; v_got := v_n::text;
        elsif t.kind = 'text' then
          execute t.sql[i] into v_got;
        else
          execute t.sql[i]; get diagnostics v_n = row_count; v_got := 'ok rows=' || v_n;
        end if;
      end loop;
      raise exception using errcode = 'MB001';
    exception
      when sqlstate 'MB001' then null;
      when others then
        get stacked diagnostics v_hint = pg_exception_hint;
        v_got := sqlstate || ' [' || coalesce(v_hint, '') || '] ' || left(sqlerrm, 160);
    end;
    v_ok := case
      when t.kind = 'exec' and t.expect ~ '^[0-9A-Z]{5}\[' then left(v_got, length(t.expect) + 1) = substr(t.expect, 1, 5) || ' ' || substr(t.expect, 6)
      when t.kind = 'exec' and t.expect ~ '^[0-9A-Z]{5}$' then left(v_got, 6) = t.expect || ' '
      when t.expect = 'ok' then v_got like 'ok rows=%' and v_got <> 'ok rows=0'
      else v_got = t.expect
    end;
    n_total := n_total + 1;
    if v_ok then n_ok := n_ok + 1; end if;
    r := r || jsonb_build_object('prueba', t.name, 'esperado', t.expect, 'obtenido', v_got, 'ok', coalesce(v_ok, false));
  end loop;

  raise exception 'MOBAU_41_03_DISTRIBUIDOR total=% ok=% fallos=% :: %', n_total, n_ok, n_total - n_ok, r::text
    using errcode = 'MB999';
end $$;

ROLLBACK;
