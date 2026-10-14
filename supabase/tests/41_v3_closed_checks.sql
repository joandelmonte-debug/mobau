-- ============================================================
-- PROPUESTA NO EJECUTADA (41 · V3 · grupo CL) — no ejecutar sin aprobación explícita
-- ============================================================
-- 41 · V3 · TODO INSTALADO Y CERRADO: 41-03a, 41-03, 41-04 y 41-05 con el
-- interruptor apagado y sin EXECUTE de cliente, en una transacción revertida.
-- Ejecutar después de 41-05. Rol postgres; JWT simulado como en 39.
--
-- Comprueba:
--   CL-ACL   ACL exacta {postgres=X/postgres} y EXECUTE efectivo nulo para
--            anon, authenticated, service_role (y sin PUBLIC) en las 9
--            funciones de entrada y los 8 auxiliares nuevos; sin USAGE de
--            mobau_private.
--   CL-CALL  cada función de entrada, llamada sin conceder nada, por anon,
--            distribuidor, Mobau con aal2 y service_role → 42501 (sin hint).
--   CL-OFF   cada acción con EXECUTE concedido DENTRO del caso y el
--            interruptor apagado → 55000 [feature_disabled] y NINGUNA
--            escritura antes del error (contadores de pg_stat_xact_all_tables
--            de las 6 tablas afectadas iguales antes y después: cuentan
--            también lo escrito en subtransacciones abortadas).
--   CL-REP   republish con el interruptor apagado, TODAS las rutas:
--            BLOQUEADAS (55000 [feature_disabled], sin escrituras): crear
--            (INSERT como authenticated, service_role y postgres), enviar
--            (UPDATE a submitted, también tras pedir cambios), editar, cambiar el
--            tipo y APROBAR (Mobau aal2).
--            PERMITIDAS (cierre, plan rev3 §3): retirar (withdrawn) desde draft
--            o submitted, y que Mobau la rechace o pida cambios; en todas, el
--            producto queda IDÉNTICO (fila completa) y sin eventos de ciclo de
--            vida: nunca se publica ni se restaura. Si service_role no tuviera el
--            privilegio de tabla, el resultado esperado es 42501 sin hint (sin
--            escrituras); el caso lo indica. La moderación sin sesión válida
--            (postgres, service_role) falla ANTES con 42501, también sin escrituras.
--   CL-GATE  la puerta: SECURITY DEFINER, propietario postgres, search_path
--            vacío, en mobau_private, ACL {postgres=X/postgres}; trigger
--            BEFORE ROW INSERT OR UPDATE en public.product_proposals, sin WHEN ni
--            columnas, habilitado; es el PRIMER BEFORE ROW en INSERT y en UPDATE
--            (lista exacta nombre:tipo:función); sin triggers internos BEFORE,
--            sin triggers de sentencia y sin reglas.
--   CTRL+    control positivo del mecanismo «sin escrituras»: antes de los
--            casos, un INSERT, UPDATE y DELETE deliberados y deshechos DEBEN
--            cambiar los contadores de pg_stat_xact_all_tables; si no, la suite
--            se detiene con MB998 (no se sustituye por la revisión estática).
--   CL-ORD   en el código, la comprobación del interruptor está antes de
--            cualquier INSERT/UPDATE/DELETE o auditoría (estática).
--   CL-AA    allowed_actions = {} para cualquier estado y actor.
--   CL-DAT   0 eventos, 0 republish, 0 productos con ciclo de vida, interruptor
--            en una fila y apagado, sin restos.
-- Formato de expect en 'exec': SQLSTATE (5) o SQLSTATE[hint] exactos.
-- ============================================================

BEGIN;

DO $$
declare
  v_sup uuid; v_sup_dist text; v_pro uuid; v_cat1 text; v_pub_a text;
  v_admin text; s_on text; s_off text; s_ret text; s_rep_on text; s_rep_sub text; s_rep_chg text; s_open_upd text; s_c0 text; s_upd text;
  s_fp0 text; q_same text;
  q_w text; q_nw text; v_sr_ins boolean; v_sr_upd boolean; v_sr_mod boolean;
  v_c0 text; v_c1 text; w_i0 bigint; w_u0 bigint; w_d0 bigint; w_i1 bigint; w_u1 bigint; w_d1 bigint;
  sig_entry constant text[] := array[
    'public.my_products_lifecycle()', 'public.my_product_lifecycle_events(text)',
    'public.distributor_retire_product(text, text, timestamp with time zone)',
    'public.distributor_trash_product(text, timestamp with time zone)',
    'public.distributor_restore_product(text, timestamp with time zone)',
    'public.mobau_product_lifecycle(text, text, text, timestamp with time zone)',
    'public.mobau_purge_product(text, text, text, boolean, timestamp with time zone)',
    'public.mobau_product_references(text)', 'public.mobau_product_lifecycle_view(text)'];
  sig_private constant text[] := array[
    'mobau_private.resolve_verified_distributor(uuid)', 'mobau_private.product_lifecycle_enabled()',
    'mobau_private.product_has_open_proposal(text)',
    'mobau_private.product_allowed_actions(text, boolean, timestamp with time zone, text)',
    'mobau_private.log_lifecycle_event(text, text, text, text, text, uuid, text, text, jsonb, text, jsonb)',
    'mobau_private.product_proposals_lifecycle_gate()', 'mobau_private.assert_mobau_admin()',
    'mobau_private.product_reference_counts(text)'];
  call_entry constant text[] := array[
    'select count(*) from public.my_products_lifecycle()',
    'select count(*) from public.my_product_lifecycle_events(null)',
    'select public.distributor_retire_product(''x'', ''Motivo'', now())',
    'select public.distributor_trash_product(''x'', now())',
    'select public.distributor_restore_product(''x'', now())',
    'select public.mobau_product_lifecycle(''x'', ''retire'', ''Motivo'', now())',
    'select public.mobau_purge_product(''x'', ''x'', ''Motivo'', true, now())',
    'select public.mobau_product_references(''x'')',
    'select public.mobau_product_lifecycle_view(''x'')'];
  fn_try constant text := 'do $t$ declare h text; begin perform %s; perform set_config(''mobau.test_result'', ''sin error'', true);'
                          || ' exception when others then get stacked diagnostics h = pg_exception_hint;'
                          || ' perform set_config(''mobau.test_result'', sqlstate || ''['' || coalesce(h, '''') || '']'', true); end $t$';
  fn_exec constant text := 'do $t$ declare h text; begin %s; perform set_config(''mobau.test_result'', ''sin error'', true);'
                          || ' exception when others then get stacked diagnostics h = pg_exception_hint;'
                          || ' perform set_config(''mobau.test_result'', sqlstate || ''['' || coalesce(h, '''') || '']'', true); end $t$';
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
  select c.id into v_cat1 from public.categories c order by c.id limit 1;
  select p.id into v_pub_a from public.products p
   where p.distributor_id = v_sup_dist and p.publication_status = 'published' order by p.id limit 1;
  if v_sup is null or v_pro is null or v_cat1 is null or v_pub_a is null then
    raise exception 'MOBAU_41_V3_CL: faltan datos de partida' using errcode = 'MB998';
  end if;
  if to_regprocedure('public.mobau_product_lifecycle(text, text, text, timestamp with time zone)') is null then
    raise exception 'MOBAU_41_V3_CL: falta 41-05' using errcode = 'MB998';
  end if;

  -- Auxiliares (como postgres, dentro de cada caso).
  v_admin := format('insert into public.mobau_admins (user_id, granted_note) values (%L, %L)', v_pro, 'Admin temporal de prueba 41 V3');
  s_on := 'update mobau_private.product_lifecycle_settings set enabled = true where id = 1';
  s_off := 'update mobau_private.product_lifecycle_settings set enabled = false where id = 1';
  s_ret := format('insert into public.products (id, name, distributor_id, category_id, publication_status, retired_at, retired_by, retired_reason)'
                  || ' values (%L, %L, %L, %L, %L, now(), %L, %L)', 'rls41v3-a-ret', 'A retirado 41 V3', v_sup_dist, v_cat1, 'archived', v_sup, 'Motivo de prueba 41 V3');
  -- republish creada con el interruptor ENCENDIDO (como postgres) y después apagado
  s_rep_on := format('insert into public.product_proposals (id, proposal_kind, product_id, distributor_id, status, proposed_changes)'
                     || ' values (%L, %L, %L, %L, %L, %L)', '00000000-0000-4000-8000-0000000413c1', 'republish', 'rls41v3-a-ret', v_sup_dist, 'draft', '{}');
  s_rep_sub := format('insert into public.product_proposals (id, proposal_kind, product_id, distributor_id, status, version, proposed_changes, submitted_at)'
                      || ' values (%L, %L, %L, %L, %L, 1, %L, now())', '00000000-0000-4000-8000-0000000413c2', 'republish', 'rls41v3-a-ret', v_sup_dist, 'submitted', '{}');
  s_rep_chg := format('insert into public.product_proposals (id, proposal_kind, product_id, distributor_id, status, version, proposed_changes, submitted_at)'
                      || ' values (%L, %L, %L, %L, %L, 1, %L, now())', '00000000-0000-4000-8000-0000000413c3', 'republish', 'rls41v3-a-ret', v_sup_dist, 'changes_requested', '{}');
  s_open_upd := format('insert into public.product_proposals (id, proposal_kind, product_id, distributor_id, status, proposed_changes) values (%L, %L, %L, %L, %L, %L)',
                       '00000000-0000-4000-8000-0000000413c4', 'update', 'rls41v3-a-ret', v_sup_dist, 'draft', '{"name": "Cambio 41 V3 CL"}');
  -- Producto intacto: la fila COMPLETA (incluidas las columnas de ciclo de vida) igual antes y después, y sin eventos de ciclo de vida.
  s_fp0 := 'select set_config(''mobau.fp0'', (select md5(to_jsonb(p)::text) from public.products p where p.id = ''rls41v3-a-ret''), true)';
  q_same := '(select md5(to_jsonb(p)::text) from public.products p where p.id = ''rls41v3-a-ret'') = current_setting(''mobau.fp0'')'
            || ' and (select publication_status from public.products where id = ''rls41v3-a-ret'') = ''archived'''
            || ' and not exists (select 1 from mobau_private.product_lifecycle_events)';
  s_upd := format('select set_config(%L, (select updated_at::text from public.products where id = %L), true)', 'mobau.upd', v_pub_a);
  -- Contadores de escritura de esta transacción (incluyen subtransacciones abortadas).
  q_w := '(select string_agg(s.relid::regclass::text || '':'' || s.n_tup_ins || '':'' || s.n_tup_upd || '':'' || s.n_tup_del, '','' order by s.relid::regclass::text)'
         || ' from pg_catalog.pg_stat_xact_all_tables s where s.relid in (''public.products''::regclass, ''public.product_prices''::regclass,'
         || ' ''public.product_proposals''::regclass, ''public.proposal_events''::regclass, ''mobau_private.product_lifecycle_events''::regclass,'
         || ' ''mobau_private.product_lifecycle_settings''::regclass))';
  s_c0 := 'select set_config(''mobau.c0'', ' || q_w || ', true)';
  q_nw := 'select count(*) where current_setting(''mobau.test_result'') = %L and ' || q_w || ' = current_setting(''mobau.c0'')';

  -- ---------- CTRL+ · control positivo de «sin escrituras» (pg_stat_xact) ----------
  -- Una escritura deliberada (INSERT, UPDATE y DELETE en products) dentro de una
  -- subtransacción que se deshace DEBE cambiar los contadores. Si no, el mecanismo
  -- no detectaría escrituras deshechas: la suite se DETIENE (MB998).
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
    raise exception 'MOBAU_41_V3_CL: CONTROL POSITIVO FALLIDO: pg_stat_xact no detecta una escritura deshecha (ins %->%, upd %->%, del %->%). Suite detenida.',
      w_i0, w_i1, w_u0, w_u1, w_d0, w_d1 using errcode = 'MB998';
  end if;
  -- Privilegios reales de service_role (fijan el resultado esperado de CL-REP-08/09/12).
  v_sr_ins := has_table_privilege('service_role', 'public.product_proposals', 'INSERT');
  v_sr_upd := has_table_privilege('service_role', 'public.product_proposals', 'UPDATE');
  v_sr_mod := has_function_privilege('service_role', 'public.moderate_product_proposal(uuid, text, text, integer)', 'EXECUTE');

  for t in
    select * from (
      -- ---------- CL-ACL: funciones de entrada y auxiliares ----------
      select format('CL-ACL %s: ACL {postgres=X/postgres}; sin EXECUTE de anon/authenticated/service_role ni PUBLIC', s.sig) as name,
             '-'::text as role, null::text as sub, null::text as aal, null::text[] as setup,
             array[format('select count(*) from pg_proc p where p.oid = to_regprocedure(%L) and p.proacl::text = %L'
                          || ' and not has_function_privilege(%L, p.oid, %L) and not has_function_privilege(%L, p.oid, %L)'
                          || ' and not has_function_privilege(%L, p.oid, %L) and not exists (select 1 from aclexplode(p.proacl) a where a.grantee = 0)',
                          s.sig, '{postgres=X/postgres}', 'anon', 'EXECUTE', 'authenticated', 'EXECUTE', 'service_role', 'EXECUTE')]::text[] as sql,
             'count'::text as kind, '1'::text as expect
        from unnest(sig_entry || sig_private) as s(sig)
      union all
      -- ---------- CL-CALL: sin conceder nada, nadie puede llamar ----------
      select format('CL-CALL %s como %s → 42501', substring(x.c from 'public\.(\w+)'), g.label),
             g.role, g.sub, g.aal, case when g.label = 'Mobau aal2' then array[v_admin] end, array[x.c], 'exec', '42501[]'
        from unnest(call_entry) as x(c)
        cross join (values ('anon', 'anon', null::text, null::text), ('distribuidor A', 'authenticated', v_sup::text, 'aal1'),
                           ('Mobau aal2', 'authenticated', v_pro::text, 'aal2'), ('service_role', 'service_role', null::text, null::text)) as g(label, role, sub, aal)
      union all
      select * from (values
      -- ---------- CTRL+ (también en el informe) ----------
      ('CTRL+ una escritura deliberada y deshecha cambia los contadores (el mecanismo detecta escrituras)', '-', null::text, null::text, array[s_c0]::text[],
         array[format(fn_exec, format('insert into public.products (id, name, distributor_id, category_id, publication_status) values (%L, %L, %L, %L, %L);'
                                      || ' delete from public.products where id = %L; raise exception %L',
                                      'rls41v3-ctl', 'Control positivo 41 V3', v_sup_dist, v_cat1, 'draft', 'rls41v3-ctl', 'control')),
               'select count(*) where ' || q_w || ' is distinct from current_setting(''mobau.c0'') and current_setting(''mobau.test_result'') = ''P0001[]'''
               || ' and not exists (select 1 from public.products where id = ''rls41v3-ctl'')']::text[], 'count', '1'),
      -- ---------- CL-GATE: forma de la puerta y orden real de disparo ----------
      ('CL-GATE-01 función: SECURITY DEFINER, propietario postgres, search_path vacío, en mobau_private, ACL {postgres=X/postgres}', '-', null, null, null::text[],
         array['select count(*) from pg_proc p where p.oid = ''mobau_private.product_proposals_lifecycle_gate()''::regprocedure and p.prosecdef'
               || ' and p.proowner = ''postgres''::regrole and p.proconfig @> array[''search_path=""''] and p.pronamespace = ''mobau_private''::regnamespace'
               || ' and p.proacl::text = ''{postgres=X/postgres}'' and p.prorettype = ''trigger''::regtype'
               || ' and not has_function_privilege(''anon'', p.oid, ''EXECUTE'') and not has_function_privilege(''authenticated'', p.oid, ''EXECUTE'')'
               || ' and not has_function_privilege(''service_role'', p.oid, ''EXECUTE'') and not exists (select 1 from aclexplode(p.proacl) a where a.grantee = 0)'], 'count', '1'),
      ('CL-GATE-02 trigger: en public.product_proposals, BEFORE ROW INSERT OR UPDATE (tgtype 23), sin WHEN, sin columnas, habilitado', '-', null, null, null::text[],
         array['select count(*) from pg_trigger t where t.tgname = ''trg_product_proposals_05_lifecycle_gate'' and t.tgrelid = ''public.product_proposals''::regclass'
               || ' and t.tgtype = 23 and t.tgqual is null and cardinality(t.tgattr::int2[]) = 0 and t.tgenabled = ''O'''
               || ' and t.tgfoid = ''mobau_private.product_proposals_lifecycle_gate()''::regprocedure'], 'count', '1'),
      ('CL-GATE-03 lista exacta y orden de disparo (nombre:tipo:función)', '-', null, null, null::text[],
         array['select string_agg(t.tgname || '':'' || t.tgtype || '':'' || n.nspname || ''.'' || f.proname, '','' order by t.tgname collate "C")'
               || ' from pg_trigger t join pg_proc f on f.oid = t.tgfoid join pg_namespace n on n.oid = f.pronamespace'
               || ' where t.tgrelid = ''public.product_proposals''::regclass and not t.tgisinternal'], 'text',
         'trg_product_proposals_05_lifecycle_gate:23:mobau_private.product_proposals_lifecycle_gate,trg_product_proposals_10_author:7:public.fix_proposal_author,'
         || 'trg_product_proposals_20_transition:19:public.transition_proposal_status,trg_product_proposals_30_validate:23:public.validate_proposal_changes,'
         || 'trg_product_proposals_40_snapshot:19:public.snapshot_product_on_submit,trg_product_proposals_50_updated_at:19:public.set_updated_at,'
         || 'trg_product_proposals_90_event_insert:5:public.log_proposal_event,trg_product_proposals_91_event_status:17:public.log_proposal_event'),
      ('CL-GATE-04 BEFORE ROW en INSERT, en orden: la puerta primero', '-', null, null, null::text[],
         array['select string_agg(t.tgname, '','' order by t.tgname collate "C") from pg_trigger t where t.tgrelid = ''public.product_proposals''::regclass'
               || ' and (t.tgtype & 3) = 3 and (t.tgtype & 4) = 4'], 'text',
         'trg_product_proposals_05_lifecycle_gate,trg_product_proposals_10_author,trg_product_proposals_30_validate'),
      ('CL-GATE-05 BEFORE ROW en UPDATE, en orden: la puerta primero', '-', null, null, null::text[],
         array['select string_agg(t.tgname, '','' order by t.tgname collate "C") from pg_trigger t where t.tgrelid = ''public.product_proposals''::regclass'
               || ' and (t.tgtype & 3) = 3 and (t.tgtype & 16) = 16'], 'text',
         'trg_product_proposals_05_lifecycle_gate,trg_product_proposals_20_transition,trg_product_proposals_30_validate,trg_product_proposals_40_snapshot,trg_product_proposals_50_updated_at'),
      ('CL-GATE-06 sin triggers internos BEFORE, sin triggers de sentencia y sin reglas en product_proposals', '-', null, null, null::text[],
         array['select (select count(*) from pg_trigger where tgrelid = ''public.product_proposals''::regclass and ((tgisinternal and (tgtype & 2) = 2) or (tgtype & 1) = 0))'
               || ' + (select count(*) from pg_rewrite where ev_class = ''public.product_proposals''::regclass)'], 'count', '0'),
      -- ---------- CL-OFF: con EXECUTE concedido en el caso y el interruptor apagado ----------
      ('CL-OFF-01 distributor_retire_product apagado → 55000[feature_disabled], sin escrituras', 'authenticated', v_sup::text, 'aal1',
         array['grant execute on function public.distributor_retire_product(text, text, timestamptz) to authenticated', s_upd, s_c0],
         array[format(fn_try, format('public.distributor_retire_product(%L, %L, current_setting(%L)::timestamptz)', v_pub_a, 'Motivo 41 V3', 'mobau.upd')),
               'reset role', format(q_nw, '55000[feature_disabled]')], 'count', '1'),
      ('CL-OFF-02 distributor_trash_product apagado → 55000[feature_disabled], sin escrituras', 'authenticated', v_sup::text, 'aal1',
         array['grant execute on function public.distributor_trash_product(text, timestamptz) to authenticated', s_ret,
               format('select set_config(%L, (select updated_at::text from public.products where id = %L), true)', 'mobau.upd', 'rls41v3-a-ret'), s_c0],
         array[format(fn_try, format('public.distributor_trash_product(%L, current_setting(%L)::timestamptz)', 'rls41v3-a-ret', 'mobau.upd')),
               'reset role', format(q_nw, '55000[feature_disabled]')], 'count', '1'),
      ('CL-OFF-03 distributor_restore_product apagado → 55000[feature_disabled], sin escrituras', 'authenticated', v_sup::text, 'aal1',
         array['grant execute on function public.distributor_restore_product(text, timestamptz) to authenticated', s_upd, s_c0],
         array[format(fn_try, format('public.distributor_restore_product(%L, current_setting(%L)::timestamptz)', v_pub_a, 'mobau.upd')),
               'reset role', format(q_nw, '55000[feature_disabled]')], 'count', '1'),
      ('CL-OFF-04 mobau_product_lifecycle apagado → 55000[feature_disabled], sin escrituras', 'authenticated', v_pro::text, 'aal2',
         array[v_admin, 'grant execute on function public.mobau_product_lifecycle(text, text, text, timestamptz) to authenticated', s_upd, s_c0],
         array[format(fn_try, format('public.mobau_product_lifecycle(%L, %L, %L, current_setting(%L)::timestamptz)', v_pub_a, 'retire', 'Motivo 41 V3', 'mobau.upd')),
               'reset role', format(q_nw, '55000[feature_disabled]')], 'count', '1'),
      ('CL-OFF-05 mobau_purge_product apagado → 55000[feature_disabled], sin escrituras', 'authenticated', v_pro::text, 'aal2',
         array[v_admin, 'grant execute on function public.mobau_purge_product(text, text, text, boolean, timestamptz) to authenticated', s_upd, s_c0],
         array[format(fn_try, format('public.mobau_purge_product(%L, %L, %L, true, current_setting(%L)::timestamptz)', v_pub_a, v_pub_a, 'Motivo 41 V3', 'mobau.upd')),
               'reset role', format(q_nw, '55000[feature_disabled]')], 'count', '1'),
      ('CL-OFF-06 mobau_product_references apagado → 55000[feature_disabled]', 'authenticated', v_pro::text, 'aal2',
         array[v_admin, 'grant execute on function public.mobau_product_references(text) to authenticated', s_c0],
         array[format(fn_try, format('public.mobau_product_references(%L)', v_pub_a)), 'reset role', format(q_nw, '55000[feature_disabled]')], 'count', '1'),
      ('CL-OFF-07 mobau_product_lifecycle_view apagado → 55000[feature_disabled]', 'authenticated', v_pro::text, 'aal2',
         array[v_admin, 'grant execute on function public.mobau_product_lifecycle_view(text) to authenticated', s_c0],
         array[format(fn_try, format('public.mobau_product_lifecycle_view(%L)', v_pub_a)), 'reset role', format(q_nw, '55000[feature_disabled]')], 'count', '1'),
      ('CL-OFF-08 interruptor antes que la sesión: postgres sin JWT → 55000[feature_disabled]', '-', null, null, null::text[],
         array[format('select public.distributor_retire_product(%L, %L, now())', v_pub_a, 'Motivo 41 V3')], 'exec', '55000[feature_disabled]'),
      ('CL-OFF-09 lecturas con EXECUTE concedido y apagado: allowed_actions vacío en todas las filas de A', 'authenticated', v_sup::text, 'aal1',
         array['grant execute on function public.my_products_lifecycle() to authenticated', s_ret],
         array['select count(*) from public.my_products_lifecycle() m where m.allowed_actions <> ''{}''::text[]'], 'count', '0'),
      -- ---------- CL-REP: republish bloqueada en todas las rutas ----------
      ('CL-REP-01 distribuidor A inserta republish (RLS de 38-C) → 55000[feature_disabled], sin escrituras', 'authenticated', v_sup::text, 'aal1',
         array[s_ret, s_c0],
         array[format(fn_exec, format('insert into public.product_proposals (proposal_kind, product_id, proposed_changes) values (%L, %L, %L)',
                                     'republish', 'rls41v3-a-ret', '{}')),
               'reset role', format(q_nw, '55000[feature_disabled]')], 'count', '1'),
      ('CL-REP-02 postgres inserta republish → 55000[feature_disabled], sin escrituras (la puerta no depende del rol)', '-', null, null, array[s_ret, s_c0],
         array[format(fn_exec, format('insert into public.product_proposals (proposal_kind, product_id, distributor_id, status, proposed_changes) values (%L, %L, %L, %L, %L)',
                                      'republish', 'rls41v3-a-ret', v_sup_dist, 'draft', '{}')),
               format(q_nw, '55000[feature_disabled]')], 'count', '1'),
      ('CL-REP-03 distribuidor A envía (UPDATE) una republish creada antes de apagar → 55000[feature_disabled], sin escrituras', 'authenticated', v_sup::text, 'aal1',
         array[s_ret, s_on, s_rep_on, s_off, s_c0],
         array[format(fn_exec, format('update public.product_proposals set status = %L where id = %L',
                                     'submitted', '00000000-0000-4000-8000-0000000413c1')),
               'reset role', format(q_nw, '55000[feature_disabled]')], 'count', '1'),
      ('CL-REP-04 PERMITIDO: A retira (withdrawn) su republish en borrador con el interruptor apagado; el producto queda idéntico', 'authenticated', v_sup::text, 'aal1',
         array[s_ret, s_on, s_rep_on, s_off, s_fp0],
         array[format('update public.product_proposals set status = %L where id = %L', 'withdrawn', '00000000-0000-4000-8000-0000000413c1'), 'reset role',
               'select count(*) where ' || q_same || format(' and (select status from public.product_proposals where id = %L) = %L', '00000000-0000-4000-8000-0000000413c1', 'withdrawn')],
         'count', '1'),
      ('CL-REP-04b PERMITIDO: A retira su republish ya enviada (submitted); el producto queda idéntico', 'authenticated', v_sup::text, 'aal1',
         array[s_ret, s_on, s_rep_sub, s_off, s_fp0],
         array[format('update public.product_proposals set status = %L where id = %L', 'withdrawn', '00000000-0000-4000-8000-0000000413c2'), 'reset role',
               'select count(*) where ' || q_same || format(' and (select status from public.product_proposals where id = %L) = %L', '00000000-0000-4000-8000-0000000413c2', 'withdrawn')],
         'count', '1'),
      ('CL-REP-05 Mobau aal2 aprueba una republish con el interruptor apagado → 55000[feature_disabled], sin escrituras', 'authenticated', v_pro::text, 'aal2',
         array[v_admin, s_ret, s_on, s_rep_sub, s_off, s_c0],
         array[format(fn_try, format('public.moderate_product_proposal(%L::uuid, %L, %L, 1)', '00000000-0000-4000-8000-0000000413c2', 'approve', 'Aprobada 41 V3')),
               'reset role', format(q_nw, '55000[feature_disabled]')], 'count', '1'),
      ('CL-REP-06 PERMITIDO: Mobau aal2 rechaza una republish con el interruptor apagado; el producto queda idéntico; evento de rechazo', 'authenticated', v_pro::text, 'aal2',
         array[v_admin, s_ret, s_on, s_rep_sub, s_off, s_fp0],
         array[format('select set_config(%L, public.moderate_product_proposal(%L::uuid, %L, %L, 1)::text, true)', 'mobau.test_result', '00000000-0000-4000-8000-0000000413c2', 'reject', 'Motivo 41 V3'),
               'reset role',
               'select count(*) where ' || q_same
               || format(' and current_setting(%L)::jsonb ->> %L = %L and (select status from public.product_proposals where id = %L) = %L'
                         || ' and exists (select 1 from public.proposal_events e where e.proposal_id = %L and e.to_status = %L and e.actor_kind = %L)',
                         'mobau.test_result', 'result', 'rejected', '00000000-0000-4000-8000-0000000413c2', 'rejected', '00000000-0000-4000-8000-0000000413c2', 'rejected', 'mobau')],
         'count', '1'),
      ('CL-REP-06b PERMITIDO: Mobau aal2 pide cambios en una republish con el interruptor apagado; el producto queda idéntico', 'authenticated', v_pro::text, 'aal2',
         array[v_admin, s_ret, s_on, s_rep_sub, s_off, s_fp0],
         array[format('select set_config(%L, public.moderate_product_proposal(%L::uuid, %L, %L, 1)::text, true)', 'mobau.test_result', '00000000-0000-4000-8000-0000000413c2', 'request_changes', 'Revisa 41 V3'),
               'reset role',
               'select count(*) where ' || q_same
               || format(' and current_setting(%L)::jsonb ->> %L = %L and (select status from public.product_proposals where id = %L) = %L',
                         'mobau.test_result', 'result', 'changes_requested', '00000000-0000-4000-8000-0000000413c2', 'changes_requested')],
         'count', '1'),
      ('CL-REP-06c BLOQUEADO: tras pedir cambios con el interruptor apagado, A no puede reenviar → 55000[feature_disabled], sin escrituras', 'authenticated', v_sup::text, 'aal1',
         array[s_ret, s_on, s_rep_chg, s_off, s_c0],
         array[format(fn_exec, format('update public.product_proposals set status = %L where id = %L', 'submitted', '00000000-0000-4000-8000-0000000413c3')),
               'reset role', format(q_nw, '55000[feature_disabled]')], 'count', '1'),
      ('CL-REP-06d PERMITIDO: A retira una republish con cambios solicitados; el producto queda idéntico', 'authenticated', v_sup::text, 'aal1',
         array[s_ret, s_on, s_rep_chg, s_off, s_fp0],
         array[format('update public.product_proposals set status = %L where id = %L', 'withdrawn', '00000000-0000-4000-8000-0000000413c3'), 'reset role',
               'select count(*) where ' || q_same],
         'count', '1'),
      ('CL-REP-06e BLOQUEADO: postgres cambia el tipo de una update a republish → 55000[feature_disabled], sin escrituras', '-', null, null,
         array[s_ret, s_open_upd, s_c0],
         array[format(fn_exec, format('update public.product_proposals set proposal_kind = %L, proposed_changes = %L where id = %L', 'republish', '{}', '00000000-0000-4000-8000-0000000413c4')),
               format(q_nw, '55000[feature_disabled]')], 'count', '1'),
      ('CL-REP-06f BLOQUEADO: postgres edita una republish en borrador sin cambiar el estado → 55000[feature_disabled], sin escrituras', '-', null, null,
         array[s_ret, s_on, s_rep_on, s_off, s_c0],
         array[format(fn_exec, format('update public.product_proposals set internal_note = %L where id = %L', 'Nota 41 V3', '00000000-0000-4000-8000-0000000413c1')),
               format(q_nw, '55000[feature_disabled]')], 'count', '1'),
      ('CL-REP-06g BLOQUEADO: postgres pasa una republish a rejected fuera de la decisión de Mobau → 55000[feature_disabled], sin escrituras', '-', null, null,
         array[s_ret, s_on, s_rep_sub, s_off, s_c0],
         array[format(fn_exec, format('update public.product_proposals set status = %L where id = %L', 'rejected', '00000000-0000-4000-8000-0000000413c2')),
               format(q_nw, '55000[feature_disabled]')], 'count', '1'),
      ('CL-REP-08 service_role inserta republish → 55000[feature_disabled] (42501 sin hint si no tiene INSERT), sin escrituras', 'service_role', null, null,
         array[s_ret, s_c0],
         array[format(fn_exec, format('insert into public.product_proposals (proposal_kind, product_id, distributor_id, status, proposed_changes) values (%L, %L, %L, %L, %L)',
                                      'republish', 'rls41v3-a-ret', v_sup_dist, 'draft', '{}')),
               'reset role', format(q_nw, case when v_sr_ins then '55000[feature_disabled]' else '42501[]' end)], 'count', '1'),
      ('CL-REP-09 service_role envía (UPDATE) una republish creada antes de apagar → 55000[feature_disabled] (42501 si no tiene UPDATE), sin escrituras', 'service_role', null, null,
         array[s_ret, s_on, s_rep_on, s_off, s_c0],
         array[format(fn_exec, format('update public.product_proposals set status = %L where id = %L', 'submitted', '00000000-0000-4000-8000-0000000413c1')),
               'reset role', format(q_nw, case when v_sr_upd then '55000[feature_disabled]' else '42501[]' end)], 'count', '1'),
      ('CL-REP-10 postgres envía (UPDATE) una republish creada antes de apagar → 55000[feature_disabled], sin escrituras', '-', null, null,
         array[s_ret, s_on, s_rep_on, s_off, s_c0],
         array[format(fn_exec, format('update public.product_proposals set status = %L where id = %L', 'submitted', '00000000-0000-4000-8000-0000000413c1')),
               format(q_nw, '55000[feature_disabled]')], 'count', '1'),
      ('CL-REP-11 moderación de una republish como postgres sin sesión → 42501[not_authenticated] antes de todo, sin escrituras', '-', null, null,
         array[s_ret, s_on, s_rep_sub, s_off, s_c0],
         array[format(fn_try, format('public.moderate_product_proposal(%L::uuid, %L, %L, 1)', '00000000-0000-4000-8000-0000000413c2', 'approve', null)),
               format(q_nw, '42501[not_authenticated]')], 'count', '1'),
      ('CL-REP-12 moderación de una republish como service_role → 42501 (sin sesión, o sin EXECUTE), sin escrituras', 'service_role', null, null,
         array[s_ret, s_on, s_rep_sub, s_off, s_c0],
         array[format(fn_try, format('public.moderate_product_proposal(%L::uuid, %L, %L, 1)', '00000000-0000-4000-8000-0000000413c2', 'approve', null)),
               'reset role', format(q_nw, case when v_sr_mod then '42501[not_authenticated]' else '42501[]' end)], 'count', '1'),
      ('CL-REP-07 las propuestas update siguen como hoy con el interruptor apagado (borrador de A)', 'authenticated', v_sup::text, 'aal1', null::text[],
         array[format('insert into public.product_proposals (proposal_kind, product_id, proposed_changes) values (%L, %L, %L)', 'update', v_pub_a, '{"name": "Cambio 41 V3 CL"}')], 'exec', 'ok'),
      -- ---------- CL-ORD: el interruptor va antes de cualquier escritura (estático) ----------
      ('CL-ORD acciones, puerta y moderación: feature_disabled aparece antes que cualquier INSERT/UPDATE/DELETE o auditoría', '-', null, null, null::text[],
         array['select count(*) from pg_proc p where p.oid in (''public.distributor_retire_product(text, text, timestamptz)''::regprocedure,'
               || ' ''public.distributor_trash_product(text, timestamptz)''::regprocedure, ''public.distributor_restore_product(text, timestamptz)''::regprocedure,'
               || ' ''public.mobau_product_lifecycle(text, text, text, timestamptz)''::regprocedure, ''public.mobau_purge_product(text, text, text, boolean, timestamptz)''::regprocedure,'
               || ' ''public.mobau_product_references(text)''::regprocedure, ''public.mobau_product_lifecycle_view(text)''::regprocedure,'
               || ' ''mobau_private.product_proposals_lifecycle_gate()''::regprocedure, ''public.moderate_product_proposal(uuid, text, text, integer)''::regprocedure)'
               || ' and strpos(p.prosrc, ''feature_disabled'') > 0'
               || ' and strpos(p.prosrc, ''feature_disabled'') < all (array(select x from unnest(array[strpos(lower(p.prosrc), ''insert into''),'
               || ' strpos(lower(p.prosrc), ''update public.''), strpos(lower(p.prosrc), ''delete from''), strpos(p.prosrc, ''log_lifecycle_event''),'
               || ' strpos(p.prosrc, ''mobau_moderation_context'')]) x where x > 0))'], 'count', '9'),
      -- ---------- CL-AA ----------
      ('CL-AA allowed_actions = {} para todos los estados y actores con el interruptor apagado', '-', null, null, null::text[],
         array['select count(*) from unnest(array[''published'', ''retired'', ''legacy_retired'', ''trashed'', ''draft'', ''in_review'', ''changes_requested'']) s,'
               || ' unnest(array[''distributor'', ''mobau'']) a, unnest(array[false, true]) o'
               || ' where mobau_private.product_allowed_actions(s, o, now() + interval ''1 day'', a) <> ''{}''::text[]'], 'count', '0'),
      ('CL-AA2 encendido dentro del caso, las acciones existen (la prueba anterior no es trivial)', '-', null, null, array[s_on],
         array['select count(*) where mobau_private.product_allowed_actions(''published'', false, null, ''distributor'') = array[''retire'']::text[]'], 'count', '1'),
      -- ---------- CL-DAT y superficie ----------
      ('CL-DAT interruptor: una fila, apagado, RLS, sin políticas ni permisos de cliente', '-', null, null, null::text[],
         array['select count(*) from mobau_private.product_lifecycle_settings s where s.id = 1 and not s.enabled'
               || ' and (select count(*) from mobau_private.product_lifecycle_settings) = 1'
               || ' and (select relrowsecurity from pg_class where oid = ''mobau_private.product_lifecycle_settings''::regclass)'
               || ' and not exists (select 1 from pg_policies where schemaname = ''mobau_private'')'
               || ' and not exists (select 1 from unnest(array[''anon'', ''authenticated'', ''service_role'']) g, unnest(array[''SELECT'', ''INSERT'', ''UPDATE'', ''DELETE'', ''TRUNCATE'']) p'
               || ' where has_table_privilege(g, ''mobau_private.product_lifecycle_settings'', p))'], 'count', '1'),
      ('CL-DAT 0 eventos de ciclo de vida, 0 republish, 0 productos con datos de ciclo de vida', '-', null, null, null::text[],
         array['select (select count(*) from mobau_private.product_lifecycle_events) + (select count(*) from public.product_proposals where proposal_kind = ''republish'')'
               || ' + (select count(*) from public.products where retired_at is not null or trashed_at is not null or retired_by is not null or trashed_by is not null)'], 'count', '0'),
      ('CL-DAT mobau_private sin USAGE para anon/authenticated/service_role ni PUBLIC', '-', null, null, null::text[],
         array['select count(*) from pg_namespace n where n.nspname = ''mobau_private'' and not has_schema_privilege(''anon'', n.oid, ''USAGE'')'
               || ' and not has_schema_privilege(''authenticated'', n.oid, ''USAGE'') and not has_schema_privilege(''service_role'', n.oid, ''USAGE'')'
               || ' and not exists (select 1 from aclexplode(n.nspacl) a where a.grantee <> ''postgres''::regrole)'], 'count', '1'),
      ('CL-DAT authenticated no lee el interruptor ni la auditoría (42501)', 'authenticated', v_sup::text, 'aal1', null::text[],
         array['select count(*) from mobau_private.product_lifecycle_settings'], 'exec', '42501'),
      ('CL-SURF ninguna función creada en V3 es ejecutable por anon o authenticated', '-', null, null, null::text[],
         array['select count(*) from pg_proc p where p.pronamespace in (''public''::regnamespace, ''mobau_private''::regnamespace)'
               || ' and p.proname in (''my_products_lifecycle'', ''my_product_lifecycle_events'', ''distributor_retire_product'', ''distributor_trash_product'','
               || ' ''distributor_restore_product'', ''mobau_product_lifecycle'', ''mobau_purge_product'', ''mobau_product_references'', ''mobau_product_lifecycle_view'','
               || ' ''resolve_verified_distributor'', ''product_lifecycle_enabled'', ''product_has_open_proposal'', ''product_allowed_actions'', ''log_lifecycle_event'','
               || ' ''product_proposals_lifecycle_gate'', ''assert_mobau_admin'', ''product_reference_counts'')'
               || ' and (has_function_privilege(''anon'', p.oid, ''EXECUTE'') or has_function_privilege(''authenticated'', p.oid, ''EXECUTE''))'], 'count', '0'),
      ('CL-TRIG product_proposals: 8 triggers y la puerta 05 es el primero BEFORE', '-', null, null, null::text[],
         array['select count(*) where (select count(*) from pg_trigger where tgrelid = ''public.product_proposals''::regclass and not tgisinternal) = 8'
               || ' and (select min(tgname) from pg_trigger where tgrelid = ''public.product_proposals''::regclass and not tgisinternal and (tgtype & 2) = 2)'
               || ' = ''trg_product_proposals_05_lifecycle_gate'''], 'count', '1'),
      ('CL-RES sin restos rls41v3 ni propuestas de prueba', '-', null, null, null::text[],
         array['select (select count(*) from public.products where id like ''rls41v3%'')'
               || ' + (select count(*) from public.product_proposals where id::text like ''00000000-0000-4000-8000-000000041%'')'], 'count', '0')
      ) as v(name, role, sub, aal, setup, sql, kind, expect)
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

  raise exception 'MOBAU_41_V3_CL total=% ok=% fallos=% :: %', n_total, n_ok, n_total - n_ok, r::text
    using errcode = 'MB999';
end $$;

ROLLBACK;
