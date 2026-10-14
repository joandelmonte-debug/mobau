-- ============================================================
-- PROPUESTA NO EJECUTADA (41-05 · Mobau) — no ejecutar sin aprobación explícita
-- ============================================================
-- 41 · 05 · Acciones, purga, referencias y vista de Mobau con el interruptor
-- ENCENDIDO y EXECUTE concedido DENTRO de cada caso (fuera, todo apagado y
-- cerrado), en una transacción revertida. Ejecutar después de 41-05.
-- Rol postgres; JWT simulado como en 39.
--
-- Identidades: Mobau (1.er perfil individual con fila temporal en
-- mobau_admins; aal2 salvo donde se indique), A (distribuidor verificado
-- real; en A08 también admin temporal, para la autoaprobación).
-- Grupos: AAL2 y permisos (N3, N4), parámetros (N5), autoaprobación, T2,
-- T6, T8, T9/T10, bloqueos de purga (N13, sin escrituras ni cambios en
-- proyectos, líneas, RFQ y propuestas), auditoría A, referencias y vista.
-- CTRL+: antes de los casos, un INSERT/UPDATE/DELETE deliberado y deshecho DEBE
-- cambiar los contadores de pg_stat_xact; si no, la suite se detiene (MB998).
-- Formato de expect en 'exec': SQLSTATE (5) o SQLSTATE[hint] exactos.
-- ============================================================

BEGIN;

DO $$
declare
  v_sup uuid; v_sup_dist text; v_pro uuid; v_cat1 text; v_proj uuid;
  s_on text; v_admin text; v_admin_rev text; v_admin_sup text; g_mobau text[]; s_aux text[]; base text[];
  s_closed text[]; s_line text; s_open_trr text; s_open_ret text; s_c0 text; q_w text; q_nw text; q_cli text; s_cli0 text;
  ins_p constant text := 'insert into public.products (id, name, distributor_id, category_id, publication_status, retired_at, retired_by, retired_reason, trashed_at, trashed_by, trash_from, purge_after, updated_at)'
                         || ' values (%L, %L, %L, %L, %L, %s, %L, %L, %s, %L, %L, %s, now() - interval ''1 hour'')';
  s_upd constant text := 'select set_config(''mobau.upd'', (select updated_at::text from public.products where id = %L), true)';
  upd constant text := 'current_setting(''mobau.upd'')::timestamptz';
  save constant text := 'select set_config(''mobau.test_result'', (%s)::text, true)';
  res constant text := 'current_setting(''mobau.test_result'')::jsonb';
  fn_try constant text := 'do $t$ declare h text; begin perform %s; perform set_config(''mobau.test_result'', ''sin error'', true);'
                          || ' exception when others then get stacked diagnostics h = pg_exception_hint;'
                          || ' perform set_config(''mobau.test_result'', sqlstate || ''['' || coalesce(h, '''') || '']'', true); end $t$';
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
  select c.id into v_cat1 from public.categories c order by c.id limit 1;
  select pr.id into v_proj from public.projects pr where pr.status = 'active' order by pr.created_at limit 1;
  if v_sup is null or v_pro is null or v_cat1 is null or v_proj is null then
    raise exception 'MOBAU_41_05: faltan datos de partida (distribuidor, admin temporal, categoría o proyecto activo)' using errcode = 'MB998';
  end if;
  if to_regprocedure('public.mobau_purge_product(text, text, text, boolean, timestamp with time zone)') is null then
    raise exception 'MOBAU_41_05: falta 41-05' using errcode = 'MB998';
  end if;

  s_on := 'update mobau_private.product_lifecycle_settings set enabled = true where id = 1';
  v_admin := format('insert into public.mobau_admins (user_id, granted_note) values (%L, %L)', v_pro, 'Admin temporal de prueba 41 V3');
  v_admin_rev := format('insert into public.mobau_admins (user_id, granted_note, revoked_at) values (%L, %L, now())', v_pro, 'Admin revocado de prueba 41 V3');
  v_admin_sup := format('insert into public.mobau_admins (user_id, granted_note) values (%L, %L)', v_sup, 'Admin temporal (autoaprobación) 41 V3');
  g_mobau := array[
    'grant execute on function public.mobau_product_lifecycle(text, text, text, timestamptz) to authenticated',
    'grant execute on function public.mobau_purge_product(text, text, text, boolean, timestamptz) to authenticated',
    'grant execute on function public.mobau_product_references(text) to authenticated',
    'grant execute on function public.mobau_product_lifecycle_view(text) to authenticated',
    'grant execute on function public.my_product_lifecycle_events(text) to authenticated'];
  s_aux := array[
    format(ins_p, 'rls41v3-a-pub', 'A publicado 41 V3', v_sup_dist, v_cat1, 'published', 'null', null, null, 'null', null, null, 'null'),
    format(ins_p, 'rls41v3-a-draft', 'A borrador 41 V3', v_sup_dist, v_cat1, 'draft', 'null', null, null, 'null', null, null, 'null'),
    format(ins_p, 'rls41v3-a-rev', 'A en revisión 41 V3', v_sup_dist, v_cat1, 'in_review', 'null', null, null, 'null', null, null, 'null'),
    format(ins_p, 'rls41v3-a-leg', 'A heredado 41 V3', v_sup_dist, v_cat1, 'archived', 'null', null, null, 'null', null, null, 'null'),
    format(ins_p, 'rls41v3-a-ret', 'A retirado 41 V3', v_sup_dist, v_cat1, 'archived', 'now() - interval ''2 days''', v_sup, 'Motivo de A 41 V3', 'null', null, null, 'null'),
    format(ins_p, 'rls41v3-a-trr', 'A papelera 41 V3', v_sup_dist, v_cat1, 'archived', 'now() - interval ''3 days''', v_sup, 'Motivo de A 41 V3',
           'now() - interval ''1 day''', v_sup, 'retired', 'now() - interval ''1 day'' + interval ''30 days'''),
    format(ins_p, 'rls41v3-a-trx', 'A papelera vencida 41 V3', v_sup_dist, v_cat1, 'draft', 'null', null, null,
           'now() - interval ''31 days''', v_sup, 'draft', 'now() - interval ''31 days'' + interval ''30 days'''),
    format('insert into public.product_prices (product_id, price_status, price_amount, currency, includes_itbis) values (%L, %L, 70, %L, true)', 'rls41v3-a-trr', 'published', 'USD')];
  base := s_aux || s_on || v_admin || g_mobau;
  -- Propuesta CERRADA de a-trr (borrador → retirada): 1 propuesta y 2 eventos que la purga debe borrar.
  s_closed := array[
    format('insert into public.product_proposals (id, proposal_kind, product_id, distributor_id, status, proposed_changes) values (%L, %L, %L, %L, %L, %L)',
           '00000000-0000-4000-8000-0000000415c1', 'update', 'rls41v3-a-trr', v_sup_dist, 'draft', '{"name": "Cerrada 41 V3"}'),
    format('update public.product_proposals set status = %L where id = %L', 'withdrawn', '00000000-0000-4000-8000-0000000415c1')];
  s_line := format('insert into public.project_products (project_id, product_id) values (%L, %L)', v_proj, 'rls41v3-a-trr');
  s_open_trr := format('insert into public.product_proposals (proposal_kind, product_id, distributor_id, status, proposed_changes) values (%L, %L, %L, %L, %L)',
                       'update', 'rls41v3-a-trr', v_sup_dist, 'draft', '{"name": "Abierta 41 V3"}');
  s_open_ret := format('insert into public.product_proposals (proposal_kind, product_id, distributor_id, status, proposed_changes) values (%L, %L, %L, %L, %L)',
                       'update', 'rls41v3-a-ret', v_sup_dist, 'draft', '{"name": "Abierta 41 V3"}');
  q_w := '(select string_agg(s.relid::regclass::text || '':'' || s.n_tup_ins || '':'' || s.n_tup_upd || '':'' || s.n_tup_del, '','' order by s.relid::regclass::text)'
         || ' from pg_catalog.pg_stat_xact_all_tables s where s.relid in (''public.products''::regclass, ''public.product_prices''::regclass,'
         || ' ''public.product_proposals''::regclass, ''public.proposal_events''::regclass, ''mobau_private.product_lifecycle_events''::regclass,'
         || ' ''public.projects''::regclass, ''public.project_products''::regclass, ''public.rfqs''::regclass))';
  s_c0 := 'select set_config(''mobau.c0'', ' || q_w || ', true)';
  q_nw := 'select count(*) where current_setting(''mobau.test_result'') = %L and ' || q_w || ' = current_setting(''mobau.c0'')';
  -- Datos de clientes y propuestas (N13): md5 de proyectos, líneas, RFQ y propuestas.
  q_cli := '(select md5(coalesce((select string_agg(x::text, ''|'' order by x::text) from public.projects x), '''')'
           || ' || coalesce((select string_agg(x::text, ''|'' order by x::text) from public.project_products x), '''')'
           || ' || coalesce((select string_agg(x::text, ''|'' order by x::text) from public.rfqs x), '''')'
           || ' || coalesce((select string_agg(x::text, ''|'' order by x::text) from public.product_proposals x), '''')))';
  s_cli0 := 'select set_config(''mobau.cli0'', ' || q_cli || ', true)';

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
      'MOBAU_41_05', w_i0, w_i1, w_u0, w_u1, w_d0, w_d1 using errcode = 'MB998';
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
      -- ========== AAL2, permisos y parámetros ==========
      ('M01 Mobau sin aal2 → 42501[aal2_required] (N4)', 'authenticated', v_pro::text, 'aal1', base || format(s_upd, 'rls41v3-a-pub'),
         array[format('select public.mobau_product_lifecycle(%L, %L, %L, %s)', 'rls41v3-a-pub', 'retire', 'Motivo 41 V3', upd)]::text[], 'exec', '42501[aal2_required]'),
      ('M02 distribuidor A (no admin) → 42501[not_admin] (N3)', 'authenticated', v_sup::text, 'aal1', base || format(s_upd, 'rls41v3-a-pub'),
         array[format('select public.mobau_product_lifecycle(%L, %L, %L, %s)', 'rls41v3-a-pub', 'retire', 'Motivo 41 V3', upd)], 'exec', '42501[not_admin]'),
      ('M03 admin revocado → 42501[not_admin]', 'authenticated', v_pro::text, 'aal2', s_aux || s_on || v_admin_rev || g_mobau,
         array[format('select public.mobau_product_lifecycle(%L, %L, %L, now())', 'rls41v3-a-pub', 'retire', 'Motivo 41 V3')], 'exec', '42501[not_admin]'),
      ('M04 sin sub → 42501[not_authenticated]', 'authenticated', 'nosub', 'aal1', base,
         array[format('select public.mobau_product_lifecycle(%L, %L, %L, now())', 'rls41v3-a-pub', 'retire', 'Motivo 41 V3')], 'exec', '42501[not_authenticated]'),
      ('M05 acción republish por la función de ciclo de vida → 22023[invalid_action] (N5)', 'authenticated', v_pro::text, 'aal2', base,
         array[format('select public.mobau_product_lifecycle(%L, %L, %L, now())', 'rls41v3-a-ret', 'republish', 'Motivo 41 V3')], 'exec', '22023[invalid_action]'),
      ('M06 acción purge por la función de ciclo de vida → 22023[invalid_action]', 'authenticated', v_pro::text, 'aal2', base,
         array[format('select public.mobau_product_lifecycle(%L, %L, %L, now())', 'rls41v3-a-trr', 'purge', 'Motivo 41 V3')], 'exec', '22023[invalid_action]'),
      ('M07 retirar sin motivo → 22023[invalid_reason]', 'authenticated', v_pro::text, 'aal2', base || format(s_upd, 'rls41v3-a-pub'),
         array[format('select public.mobau_product_lifecycle(%L, %L, null, %s)', 'rls41v3-a-pub', 'retire', upd)], 'exec', '22023[invalid_reason]'),
      ('M08 autoaprobación: admin de la propia empresa → 42501[self_moderation_forbidden]', 'authenticated', v_sup::text, 'aal2', base || v_admin_sup || format(s_upd, 'rls41v3-a-pub'),
         array[format('select public.mobau_product_lifecycle(%L, %L, %L, %s)', 'rls41v3-a-pub', 'retire', 'Motivo 41 V3', upd)], 'exec', '42501[self_moderation_forbidden]'),
      ('M09 versión distinta → 40001[version_conflict], sin escrituras', 'authenticated', v_pro::text, 'aal2', base || s_c0,
         array[format(fn_try, format('public.mobau_product_lifecycle(%L, %L, %L, now() - interval ''2 hours'')', 'rls41v3-a-pub', 'retire', 'Motivo 41 V3')),
               'reset role', format(q_nw, '40001[version_conflict]')], 'count', '1'),
      ('M10 producto inexistente → P0002[product_not_found]', 'authenticated', v_pro::text, 'aal2', base,
         array[format('select public.mobau_product_lifecycle(%L, %L, %L, now())', 'rls41v3-no-existe', 'retire', 'Motivo 41 V3')], 'exec', 'P0002[product_not_found]'),
      -- ========== T2 · retirar (Mobau) ==========
      ('M20 Mobau retira: archived, retired_by = admin, motivo visible para A, evento mobau', 'authenticated', v_pro::text, 'aal2', base || format(s_upd, 'rls41v3-a-pub'),
         array[format('select public.mobau_product_lifecycle(%L, %L, %L, %s)', 'rls41v3-a-pub', 'retire', 'Motivo de Mobau 41 V3', upd), 'reset role',
               format('select count(*) from public.products p where p.id = %L and p.publication_status = %L and p.retired_by = %L and p.retired_reason = %L'
                      || ' and exists (select 1 from mobau_private.product_lifecycle_events e where e.product_id = p.id and e.action = %L and e.actor_kind = %L'
                      || '             and e.actor_id = %L and e.from_state = %L and e.to_state = %L)',
                      'rls41v3-a-pub', 'archived', v_pro, 'Motivo de Mobau 41 V3', 'retire', 'mobau', v_pro, 'published', 'retired')], 'count', '1'),
      ('M21 retirar un heredado → 55000[legacy_pending_review]', 'authenticated', v_pro::text, 'aal2', base || format(s_upd, 'rls41v3-a-leg'),
         array[format('select public.mobau_product_lifecycle(%L, %L, %L, %s)', 'rls41v3-a-leg', 'retire', 'Motivo 41 V3', upd)], 'exec', '55000[legacy_pending_review]'),
      ('M22 retirar un borrador → 55000[invalid_state]', 'authenticated', v_pro::text, 'aal2', base || format(s_upd, 'rls41v3-a-draft'),
         array[format('select public.mobau_product_lifecycle(%L, %L, %L, %s)', 'rls41v3-a-draft', 'retire', 'Motivo 41 V3', upd)], 'exec', '55000[invalid_state]'),
      -- ========== T6 · papelera (Mobau) ==========
      ('M30 Mobau mueve a la papelera un retirado: trashed_by = admin, trash_from retired', 'authenticated', v_pro::text, 'aal2', base || format(s_upd, 'rls41v3-a-ret'),
         array[format('select public.mobau_product_lifecycle(%L, %L, null, %s)', 'rls41v3-a-ret', 'trash', upd), 'reset role',
               format('select count(*) from public.products where id = %L and trashed_by = %L and trash_from = %L and purge_after = trashed_at + interval ''30 days''',
                      'rls41v3-a-ret', v_pro, 'retired')], 'count', '1'),
      ('M31 Mobau mueve a la papelera un borrador', 'authenticated', v_pro::text, 'aal2', base || format(s_upd, 'rls41v3-a-draft'),
         array[format('select public.mobau_product_lifecycle(%L, %L, null, %s)', 'rls41v3-a-draft', 'trash', upd), 'reset role',
               format('select count(*) from public.products where id = %L and trash_from = %L', 'rls41v3-a-draft', 'draft')], 'count', '1'),
      ('M32 publicado → papelera → 55000[invalid_state]', 'authenticated', v_pro::text, 'aal2', base || format(s_upd, 'rls41v3-a-pub'),
         array[format('select public.mobau_product_lifecycle(%L, %L, null, %s)', 'rls41v3-a-pub', 'trash', upd)], 'exec', '55000[invalid_state]'),
      ('M33 en revisión → 55000[in_review]', 'authenticated', v_pro::text, 'aal2', base || format(s_upd, 'rls41v3-a-rev'),
         array[format('select public.mobau_product_lifecycle(%L, %L, null, %s)', 'rls41v3-a-rev', 'trash', upd)], 'exec', '55000[in_review]'),
      ('M34 retirado con propuesta abierta → 55000[open_proposal]', 'authenticated', v_pro::text, 'aal2', base || s_open_ret || format(s_upd, 'rls41v3-a-ret'),
         array[format('select public.mobau_product_lifecycle(%L, %L, null, %s)', 'rls41v3-a-ret', 'trash', upd)], 'exec', '55000[open_proposal]'),
      -- ========== T8 · restaurar (Mobau, sin plazo) ==========
      ('M40 Mobau restaura una papelera vencida (sin plazo para Mobau) → borrador', 'authenticated', v_pro::text, 'aal2', base || format(s_upd, 'rls41v3-a-trx'),
         array[format('select public.mobau_product_lifecycle(%L, %L, null, %s)', 'rls41v3-a-trx', 'restore', upd), 'reset role',
               format('select count(*) from public.products where id = %L and trashed_at is null and publication_status = %L', 'rls41v3-a-trx', 'draft')], 'count', '1'),
      ('M41 Mobau restaura desde retirado → retirado (nunca publica)', 'authenticated', v_pro::text, 'aal2', base || format(s_upd, 'rls41v3-a-trr'),
         array[format('select public.mobau_product_lifecycle(%L, %L, null, %s)', 'rls41v3-a-trr', 'restore', upd), 'reset role',
               format('select count(*) from public.products where id = %L and trashed_at is null and publication_status = %L and retired_at is not null', 'rls41v3-a-trr', 'archived')], 'count', '1'),
      ('M42 retirar → papelera → restaurar por Mobau nunca deja published', 'authenticated', v_pro::text, 'aal2', base || format(s_upd, 'rls41v3-a-pub'),
         array[format('select set_config(%L, (public.mobau_product_lifecycle(%L, %L, %L, %s) ->> %L), true)', 'mobau.u2', 'rls41v3-a-pub', 'retire', 'Motivo 41 V3', upd, 'updated_at'),
               format('select set_config(%L, (public.mobau_product_lifecycle(%L, %L, null, current_setting(%L)::timestamptz) ->> %L), true)', 'mobau.u3', 'rls41v3-a-pub', 'trash', 'mobau.u2', 'updated_at'),
               format('select public.mobau_product_lifecycle(%L, %L, null, current_setting(%L)::timestamptz)', 'rls41v3-a-pub', 'restore', 'mobau.u3'), 'reset role',
               format('select count(*) from public.products where id = %L and publication_status = %L', 'rls41v3-a-pub', 'archived')], 'count', '1'),
      -- ========== T9 / T10 · purga ==========
      ('M50 purga normal antes de plazo → 55000[purge_not_due], sin escrituras', 'authenticated', v_pro::text, 'aal2', base || format(s_upd, 'rls41v3-a-trr') || s_c0,
         array[format(fn_try, format('public.mobau_purge_product(%L, %L, %L, false, %s)', 'rls41v3-a-trr', 'rls41v3-a-trr', 'Motivo 41 V3', upd)),
               'reset role', format(q_nw, '55000[purge_not_due]')], 'count', '1'),
      ('M51 id de confirmación distinto → 22023[confirm_mismatch]', 'authenticated', v_pro::text, 'aal2', base || format(s_upd, 'rls41v3-a-trr'),
         array[format('select public.mobau_purge_product(%L, %L, %L, true, %s)', 'rls41v3-a-trr', 'rls41v3-a-tr', 'Motivo 41 V3', upd)], 'exec', '22023[confirm_mismatch]'),
      ('M52 purga sin motivo → 22023[invalid_reason]', 'authenticated', v_pro::text, 'aal2', base || format(s_upd, 'rls41v3-a-trr'),
         array[format('select public.mobau_purge_product(%L, %L, null, true, %s)', 'rls41v3-a-trr', 'rls41v3-a-trr', upd)], 'exec', '22023[invalid_reason]'),
      ('M53 tipo de purga sin indicar → 22023[invalid_parameter]', 'authenticated', v_pro::text, 'aal2', base || format(s_upd, 'rls41v3-a-trr'),
         array[format('select public.mobau_purge_product(%L, %L, %L, null, %s)', 'rls41v3-a-trr', 'rls41v3-a-trr', 'Motivo 41 V3', upd)], 'exec', '22023[invalid_parameter]'),
      ('M54 purgar algo que no está en la papelera → 55000[invalid_state]', 'authenticated', v_pro::text, 'aal2', base || format(s_upd, 'rls41v3-a-ret'),
         array[format('select public.mobau_purge_product(%L, %L, %L, true, %s)', 'rls41v3-a-ret', 'rls41v3-a-ret', 'Motivo 41 V3', upd)], 'exec', '55000[invalid_state]'),
      ('M55 con propuesta abierta → 55000[open_proposal]', 'authenticated', v_pro::text, 'aal2', base || s_open_trr || format(s_upd, 'rls41v3-a-trr'),
         array[format('select public.mobau_purge_product(%L, %L, %L, true, %s)', 'rls41v3-a-trr', 'rls41v3-a-trr', 'Motivo 41 V3', upd)], 'exec', '55000[open_proposal]'),
      ('M56 con una línea en un proyecto → 55000[purge_blocked_references]; proyectos, líneas, RFQ y propuestas intactos; sin escrituras (N13)', 'authenticated', v_pro::text, 'aal2',
         base || s_line || format(s_upd, 'rls41v3-a-trr') || s_cli0 || s_c0,
         array[format(fn_try, format('public.mobau_purge_product(%L, %L, %L, true, %s)', 'rls41v3-a-trr', 'rls41v3-a-trr', 'Motivo 41 V3', upd)),
               'reset role', format(q_nw, '55000[purge_blocked_references]') || ' and ' || q_cli || ' = current_setting(''mobau.cli0'')'], 'count', '1'),
      ('M57 purga anticipada correcta: borra eventos, propuesta cerrada, precio y producto; auditoría A sin contenido', 'authenticated', v_pro::text, 'aal2',
         base || s_closed || format(s_upd, 'rls41v3-a-trr'),
         array[format(save, format('public.mobau_purge_product(%L, %L, %L, true, %s)', 'rls41v3-a-trr', 'rls41v3-a-trr', 'Purga anticipada 41 V3', upd)), 'reset role',
               format('select count(*) where (%s ->> %L)::boolean'
                      || ' and %s -> %L = %L::jsonb'
                      || ' and not exists (select 1 from public.products where id = %L)'
                      || ' and not exists (select 1 from public.product_prices where product_id = %L)'
                      || ' and not exists (select 1 from public.product_proposals where id = %L)'
                      || ' and not exists (select 1 from public.proposal_events where proposal_id = %L)'
                      || ' and exists (select 1 from mobau_private.product_lifecycle_events e where e.product_id = %L and e.action = %L and e.actor_kind = %L'
                      || '             and e.actor_id = %L and e.from_state = %L and e.to_state is null and e.reason = %L and e.purge_counts = %L::jsonb'
                      || '             and e.purge_sha256 ~ %L and (e.meta ->> %L)::boolean and not (e.meta ? %L) and e.meta ? %L)',
                      res, 'ok', res, 'purged_counts', '{"products": 1, "product_prices": 1, "proposal_events": 2, "product_proposals": 1}',
                      'rls41v3-a-trr', 'rls41v3-a-trr', '00000000-0000-4000-8000-0000000415c1', '00000000-0000-4000-8000-0000000415c1',
                      'rls41v3-a-trr', 'purge', 'mobau', v_pro, 'trashed', 'Purga anticipada 41 V3',
                      '{"products": 1, "product_prices": 1, "proposal_events": 2, "product_proposals": 1}', '^[0-9a-f]{64}$', 'early', 'name', 'category_id')], 'count', '1'),
      ('M58 purga normal de una papelera vencida', 'authenticated', v_pro::text, 'aal2', base || format(s_upd, 'rls41v3-a-trx'),
         array[format('select public.mobau_purge_product(%L, %L, %L, false, %s)', 'rls41v3-a-trx', 'rls41v3-a-trx', 'Purga normal 41 V3', upd), 'reset role',
               format('select count(*) where not exists (select 1 from public.products where id = %L)'
                      || ' and exists (select 1 from mobau_private.product_lifecycle_events e where e.product_id = %L and e.action = %L and not (e.meta ->> %L)::boolean)',
                      'rls41v3-a-trx', 'rls41v3-a-trx', 'purge', 'early')], 'count', '1'),
      ('M59 A ve la purga de su producto sin estados, motivo, recuentos ni huella', 'authenticated', v_pro::text, 'aal2', base || format(s_upd, 'rls41v3-a-trx'),
         array[format('select public.mobau_purge_product(%L, %L, %L, false, %s)', 'rls41v3-a-trx', 'rls41v3-a-trx', 'Purga normal 41 V3', upd),
               format('select set_config(%L, %L, true), set_config(%L, %L, true)', 'request.jwt.claims',
                      json_build_object('sub', v_sup, 'role', 'authenticated', 'aal', 'aal1')::text, 'request.jwt.claim.sub', v_sup),
               format('select count(*) from public.my_product_lifecycle_events(%L) e where e.action = %L and e.from_state is null and e.to_state is null and e.reason is null',
                      'rls41v3-a-trx', 'purge')], 'count', '1'),
      -- ========== referencias y vista ==========
      ('M60 referencias: recuentos con una línea de proyecto; sin ids ni datos de clientes', 'authenticated', v_pro::text, 'aal2', base || s_line,
         array[format(save, format('public.mobau_product_references(%L)', 'rls41v3-a-trr')), 'reset role',
               format('select count(*) where (%s ->> %L)::int = 1 and (%s ->> %L)::int = 1 and (%s ->> %L)::int = 0'
                      || ' and (select count(*) from jsonb_object_keys(%s)) = 9',
                      res, 'project_lines_total', res, 'project_lines_active', res, 'other_references', res)], 'count', '1'),
      ('M61 referencias de un id inexistente → P0002[product_not_found]', 'authenticated', v_pro::text, 'aal2', base,
         array[format('select public.mobau_product_references(%L)', 'rls41v3-no-existe')], 'exec', 'P0002[product_not_found]'),
      ('M62 referencias como distribuidor → 42501[not_admin]', 'authenticated', v_sup::text, 'aal1', base,
         array[format('select public.mobau_product_references(%L)', 'rls41v3-a-trr')], 'exec', '42501[not_admin]'),
      ('M63 vista: papelera con línea → acciones restore y purge; bloqueos purge_not_due y purge_blocked_references; actores con uuid', 'authenticated', v_pro::text, 'aal2', base || s_line,
         array[format(save, format('public.mobau_product_lifecycle_view(%L)', 'rls41v3-a-trr')), 'reset role',
               format('select count(*) where %s ->> %L = %L and %s -> %L = %L::jsonb and %s -> %L @> %L::jsonb and %s ->> %L = %L',
                      res, 'lifecycle_state', 'trashed', res, 'allowed_actions', '["restore", "purge"]', res, 'blocks', '["purge_not_due", "purge_blocked_references"]',
                      res, 'trashed_by', v_sup)], 'count', '1'),
      ('M64 vista como Mobau sin aal2 → 42501[aal2_required]', 'authenticated', v_pro::text, 'aal1', base,
         array[format('select public.mobau_product_lifecycle_view(%L)', 'rls41v3-a-trr')], 'exec', '42501[aal2_required]'),
      -- ========== estado tras la suite ==========
      ('Z01 fuera de los casos: apagado, sin EXECUTE de cliente, sin eventos ni restos', '-', null, null, null::text[],
         array['select count(*) where not mobau_private.product_lifecycle_enabled()'
               || ' and not has_function_privilege(''authenticated'', ''public.mobau_purge_product(text, text, text, boolean, timestamptz)'', ''EXECUTE'')'
               || ' and not exists (select 1 from mobau_private.product_lifecycle_events)'
               || ' and not exists (select 1 from public.products where id like ''rls41v3%'')'
               || ' and not exists (select 1 from public.project_products where product_id like ''rls41v3%'')'], 'count', '1')
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

  raise exception 'MOBAU_41_05_MOBAU total=% ok=% fallos=% :: %', n_total, n_ok, n_total - n_ok, r::text
    using errcode = 'MB999';
end $$;

ROLLBACK;
