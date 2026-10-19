-- ============================================================
-- PROPUESTA NO EJECUTADA (41-07 · suite) — no ejecutar sin aprobación explícita
-- ============================================================
-- 41-07 · SUITE ACOTADA a lo que cambia, en una transacción revertida.
-- Requiere 41-07 aplicada (de verdad o dentro del ensayo E7). Rol postgres;
-- JWT simulado como en 39/41. Cada caso es una subtransacción que se deshace
-- (MB001) y crea dentro sus auxiliares rls41v7-* (productos de A, empresa B,
-- eventos de auditoría, admin temporal con aal2). Al final, MB999 con el
-- resultado y ROLLBACK.
-- Efectos no transaccionales: avanzan proposal_events_id_seq y
-- product_lifecycle_events_id_seq, y los contadores de pg_stat. Nada más.
-- Formato de expect en 'exec': SQLSTATE (5) o SQLSTATE[hint] exactos.
-- ============================================================

BEGIN;

DO $E7S$
declare
  v_sup uuid; v_sup_dist text; v_adm uuid; v_cat1 text; v_sub1 text; v_proj uuid; n_ev0 bigint;
  s_aux text[]; base text[]; as_admin text; as_sup text; stop_sw text; stop_all text[];
  ins_p constant text := 'insert into public.products (id, name, distributor_id, category_id, subcategory, publication_status, retired_at, retired_by, retired_reason, trashed_at, trashed_by, trash_from, purge_after, updated_at)'
                         || ' values (%L, %L, %L, %L, %L, %L, %s, %L, %L, %s, %L, %L, %s, now() - interval ''1 hour'')';
  ins_e constant text := 'insert into mobau_private.product_lifecycle_events (product_id, distributor_id, action, from_state, to_state, actor_id, actor_kind, reason, created_at)'
                         || ' values (%L, %L, %L, %L, %L, %L, %L, %L, now() - interval %L)';
  rep_ins constant text := 'insert into public.product_proposals (proposal_kind, product_id, proposed_changes) values (''republish'', %L, ''{}'')';
  rep_id constant text := '(select pr.id from public.product_proposals pr where pr.product_id = %L and pr.proposal_kind = ''republish'')';
  rep_submit constant text := 'update public.product_proposals set status = ''submitted'' where product_id = %L and proposal_kind = ''republish''';
  open_upd constant text := 'insert into public.product_proposals (proposal_kind, product_id, distributor_id, status, proposed_changes) values (''update'', %L, %L, ''draft'', ''{"name": "Abierta 41-07"}'')';
  s_line text;
  s_upd constant text := 'select set_config(''mobau.upd'', (select updated_at::text from public.products where id = %L), true)';
  upd constant text := 'current_setting(''mobau.upd'')::timestamptz';
  save constant text := 'select set_config(''mobau.test_result'', (%s)::text, true)';
  res constant text := 'current_setting(''mobau.test_result'')::jsonb';
  fn_try constant text := 'do $t$ declare h text; begin perform %s; perform set_config(''mobau.test_result'', ''sin error'', true);'
                          || ' exception when others then get stacked diagnostics h = pg_exception_hint;'
                          || ' perform set_config(''mobau.test_result'', sqlstate || ''['' || coalesce(h, '''') || '']'', true); end $t$';
  keep constant text := 'select set_config(%L, current_setting(''mobau.test_result''), true)';
  f10 constant text := '''public.my_products_lifecycle()''::regprocedure, ''public.my_product_lifecycle_events(text)''::regprocedure,'
                       || ' ''public.distributor_trash_product(text, timestamptz)''::regprocedure, ''public.distributor_restore_product(text, timestamptz)''::regprocedure,'
                       || ' ''public.distributor_purge_product(text, text, timestamptz)''::regprocedure, ''public.mobau_product_lifecycle(text, text, text, timestamptz)''::regprocedure,'
                       || ' ''public.mobau_purge_product(text, text, text, boolean, timestamptz)''::regprocedure, ''public.mobau_product_references(text)''::regprocedure,'
                       || ' ''public.mobau_product_lifecycle_view(text)''::regprocedure, ''public.mobau_lifecycle_history(text)''::regprocedure';
  acl_10 constant text := '(select count(*) from pg_proc p where p.oid in (' || f10 || ') and p.proacl::text = %L)';
  acl_11 constant text := '(select count(*) from pg_proc p where p.oid in (' || f10 || ', ''public.distributor_retire_product(text, text, timestamptz)''::regprocedure) and p.proacl::text = %L)';
  ev_of constant text := '(select string_agg(e.action || '':'' || e.actor_kind, '','' order by e.id) from mobau_private.product_lifecycle_events e where e.product_id = %L)';
  r jsonb := '[]'::jsonb; t record; i int;
  v_got text; v_n bigint; v_ok boolean; v_stmt text; v_hint text;
  n_total int := 0; n_ok int := 0;
begin
  select dp.user_id, dp.distributor_id into v_sup, v_sup_dist
    from public.distributor_profiles dp join public.profiles p on p.id = dp.user_id
   where p.role = 'supplier' and dp.verification_status = 'verified' and dp.distributor_id is not null
   order by dp.created_at limit 1;
  select p.id into v_adm from public.profiles p
   where p.role = 'individual' and not exists (select 1 from public.mobau_admins a where a.user_id = p.id)
     and not exists (select 1 from public.distributor_profiles dp where dp.user_id = p.id)
   order by p.created_at limit 1;
  select c.id, c.subcategories[1] into v_cat1, v_sub1 from public.categories c where cardinality(c.subcategories) >= 1 order by c.id limit 1;
  select pr.id into v_proj from public.projects pr where pr.status = 'active' order by pr.created_at limit 1;
  select count(*) into n_ev0 from mobau_private.product_lifecycle_events;
  if v_sup is null or v_adm is null or v_cat1 is null or v_proj is null then
    raise exception 'MOBAU_41_07_SUITE: faltan datos de partida' using errcode = 'MB998';
  end if;
  if not mobau_private.product_lifecycle_enabled()
     or to_regprocedure('public.distributor_purge_product(text, text, timestamptz)') is null
     or to_regprocedure('public.mobau_lifecycle_history(text)') is null then
    raise exception 'MOBAU_41_07_SUITE: 41-07 no está aplicada o el interruptor está apagado' using errcode = 'MB998';
  end if;
  if exists (select 1 from public.products where id like 'rls41v7%') or exists (select 1 from public.distributors where id like 'rls41v7%')
     or exists (select 1 from public.mobau_admins where granted_note like '%41-07%') then
    raise exception 'MOBAU_41_07_SUITE: ya existen auxiliares rls41v7' using errcode = 'MB998';
  end if;

  -- ---------- auxiliares (como postgres, dentro de cada caso) ----------
  s_aux := array[
    format('insert into public.distributors (id, name) values (%L, %L)', 'rls41v7-dist-b', 'Distribuidor B (ensayo 41-07)'),
    format(ins_p, 'rls41v7-a-pub', 'A publicado 41-07', v_sup_dist, v_cat1, v_sub1, 'published', 'null', null, null, 'null', null, null, 'null'),
    format(ins_p, 'rls41v7-a-draft', 'A borrador 41-07', v_sup_dist, v_cat1, v_sub1, 'draft', 'null', null, null, 'null', null, null, 'null'),
    -- retirado por Mobau (intervención vigente)
    format(ins_p, 'rls41v7-a-mret', 'A retirado por Mobau 41-07', v_sup_dist, v_cat1, v_sub1, 'archived', 'now() - interval ''2 days''', v_adm, 'Motivo Mobau 41-07', 'null', null, null, 'null'),
    format(ins_e, 'rls41v7-a-mret', v_sup_dist, 'retire', 'published', 'retired', v_adm, 'mobau', 'Motivo Mobau 41-07', '2 days'),
    -- retirado voluntariamente por A (papelera nueva, sin purge_after)
    format(ins_p, 'rls41v7-a-trd', 'A papelera voluntaria 41-07', v_sup_dist, v_cat1, v_sub1, 'archived', 'now() - interval ''3 days''', v_sup, 'Retirado por la empresa',
           'now() - interval ''1 day''', v_sup, 'retired', 'null'),
    format(ins_e, 'rls41v7-a-trd', v_sup_dist, 'retire', 'published', 'retired', v_sup, 'distributor', 'Retirado por la empresa', '3 days'),
    format(ins_e, 'rls41v7-a-trd', v_sup_dist, 'trash', 'retired', 'trashed', v_sup, 'distributor', null, '1 day'),
    format('insert into public.product_prices (product_id, price_status, price_amount, currency, includes_itbis) values (%L, %L, 80, %L, true)', 'rls41v7-a-trd', 'published', 'USD'),
    -- intervenido por Mobau: retirado y movido a la papelera por Mobau
    format(ins_p, 'rls41v7-a-trm', 'A papelera Mobau 41-07', v_sup_dist, v_cat1, v_sub1, 'archived', 'now() - interval ''3 days''', v_adm, 'Motivo Mobau 41-07',
           'now() - interval ''1 day''', v_adm, 'retired', 'null'),
    format(ins_e, 'rls41v7-a-trm', v_sup_dist, 'retire', 'published', 'retired', v_adm, 'mobau', 'Motivo Mobau 41-07', '3 days'),
    format(ins_e, 'rls41v7-a-trm', v_sup_dist, 'trash', 'retired', 'trashed', v_adm, 'mobau', 'Papelera Mobau 41-07', '1 day'),
    -- borrador en la papelera desde hace 40 días con el plazo antiguo (V3) ya vencido
    format(ins_p, 'rls41v7-a-old', 'A papelera antigua 41-07', v_sup_dist, v_cat1, v_sub1, 'draft', 'null', null, null,
           'now() - interval ''40 days''', v_sup, 'draft', 'now() - interval ''40 days'' + interval ''30 days'''),
    format(ins_e, 'rls41v7-a-old', v_sup_dist, 'trash', 'draft', 'trashed', v_sup, 'distributor', null, '40 days'),
    -- empresa B
    format(ins_p, 'rls41v7-b-pub', 'B publicado 41-07', 'rls41v7-dist-b', v_cat1, v_sub1, 'published', 'null', null, null, 'null', null, null, 'null'),
    format(ins_p, 'rls41v7-b-trd', 'B papelera 41-07', 'rls41v7-dist-b', v_cat1, v_sub1, 'archived', 'now() - interval ''3 days''', v_adm, 'Motivo B 41-07',
           'now() - interval ''1 day''', v_adm, 'retired', 'null')];
  base := s_aux || format('insert into public.mobau_admins (user_id, granted_note) values (%L, %L)', v_adm, 'Admin temporal ensayo 41-07');
  s_line := format('insert into public.project_products (project_id, product_id) values (%L, %L)', v_proj, 'rls41v7-a-trd');
  as_admin := format('select set_config(%L, %L, true), set_config(%L, %L, true)', 'request.jwt.claims',
                     json_build_object('sub', v_adm, 'role', 'authenticated', 'aal', 'aal2')::text, 'request.jwt.claim.sub', v_adm);
  as_sup := format('select set_config(%L, %L, true), set_config(%L, %L, true)', 'request.jwt.claims',
                   json_build_object('sub', v_sup, 'role', 'authenticated', 'aal', 'aal1')::text, 'request.jwt.claim.sub', v_sup);
  -- parada: mismas sentencias que 41_07_parada.sql (sin BEGIN/COMMIT ni lock_timeout)
  stop_sw := 'update mobau_private.product_lifecycle_settings set enabled = false, changed_at = now(), changed_by = null, note = ''41-07 parada: interruptor apagado y EXECUTE revocado'' where id = 1';
  stop_all := array[stop_sw,
    'revoke all on function public.my_products_lifecycle() from public, anon, authenticated, service_role',
    'revoke all on function public.my_product_lifecycle_events(text) from public, anon, authenticated, service_role',
    'revoke all on function public.distributor_retire_product(text, text, timestamptz) from public, anon, authenticated, service_role',
    'revoke all on function public.distributor_trash_product(text, timestamptz) from public, anon, authenticated, service_role',
    'revoke all on function public.distributor_restore_product(text, timestamptz) from public, anon, authenticated, service_role',
    'revoke all on function public.mobau_product_lifecycle(text, text, text, timestamptz) from public, anon, authenticated, service_role',
    'revoke all on function public.mobau_purge_product(text, text, text, boolean, timestamptz) from public, anon, authenticated, service_role',
    'revoke all on function public.mobau_product_references(text) from public, anon, authenticated, service_role',
    'revoke all on function public.mobau_product_lifecycle_view(text) from public, anon, authenticated, service_role',
    'revoke all on function public.distributor_purge_product(text, text, timestamptz) from public, anon, authenticated, service_role',
    'revoke all on function public.mobau_lifecycle_history(text) from public, anon, authenticated, service_role'];

  for t in
    select * from (values
      -- ========== P · permisos ==========
      ('P01 estado real: interruptor encendido; 10 funciones con EXECUTE solo de authenticated; distributor_retire_product sin EXECUTE', '-', null::text, null::text, null::text[],
         array['select count(*) where mobau_private.product_lifecycle_enabled()'
               || ' and ' || format(acl_10, '{postgres=X/postgres,authenticated=X/postgres}') || ' = 10'
               || ' and (select proacl::text from pg_proc where oid = ''public.distributor_retire_product(text, text, timestamptz)''::regprocedure) = ''{postgres=X/postgres}''']::text[], 'count', '1'),
      ('P02 A llama a distributor_retire_product → 42501 (sin EXECUTE)', 'authenticated', v_sup::text, 'aal1', base,
         array[format('select public.distributor_retire_product(%L, %L, now())', 'rls41v7-a-pub', 'Motivo 41-07')], 'exec', '42501'),
      -- ========== D · distribuidor ==========
      ('D01 A lee su ciclo de vida: estado, acciones, destino al restaurar e intervención de Mobau', 'authenticated', v_sup::text, 'aal1', base,
         array['select string_agg(substr(m.id, 9) || ''='' || m.lifecycle_state || '':'' || m.allowed_actions::text || '':'' || coalesce(m.restore_to, ''-'') || '':'' || m.mobau_hold::text, '';'' order by m.id)'
               || ' from public.my_products_lifecycle() m where m.id like ''rls41v7-%'''],
         'text', 'a-draft=draft:{trash}:-:false;a-mret=retired:{request_republish,trash}:-:true;a-old=trashed:{restore,purge}:draft:false;'
                 || 'a-pub=published:{trash}:-:false;a-trd=trashed:{restore,purge}:published:false;a-trm=trashed:{purge}:-:true'),
      ('D02 Retirar un publicado: una llamada → papelera (archived, retired_* y trashed_* de A, sin purge_after), fuera del catálogo, eventos retire+trash de A', 'authenticated', v_sup::text, 'aal1',
         base || format(s_upd, 'rls41v7-a-pub'),
         array[format(save, format('public.distributor_trash_product(%L, %s)', 'rls41v7-a-pub', upd)), 'reset role',
               format('select count(*) from public.products p where p.id = %L and p.publication_status = %L and p.retired_by = %L and p.retired_reason = %L'
                      || ' and p.trashed_by = %L and p.trash_from = %L and p.purge_after is null and %s ->> %L = %L'
                      || ' and not exists (select 1 from public.catalog_products c where c.id = p.id) and %s = %L',
                      'rls41v7-a-pub', 'archived', v_sup, 'Retirado por la empresa', v_sup, 'retired', res, 'lifecycle_state', 'trashed',
                      format(ev_of, 'rls41v7-a-pub'), 'retire:distributor,trash:distributor')], 'count', '1'),
      ('D03 Retirar un borrador → papelera (trash_from draft), un solo evento trash', 'authenticated', v_sup::text, 'aal1', base || format(s_upd, 'rls41v7-a-draft'),
         array[format('select public.distributor_trash_product(%L, %s)', 'rls41v7-a-draft', upd), 'reset role',
               format('select count(*) from public.products p where p.id = %L and p.publication_status = %L and p.retired_at is null and p.trash_from = %L and p.purge_after is null and %s = %L',
                      'rls41v7-a-draft', 'draft', 'draft', format(ev_of, 'rls41v7-a-draft'), 'trash:distributor')], 'count', '1'),
      ('D04 Restaurar lo retirado voluntariamente → publicado y de nuevo en el catálogo; retired_* y trashed_* a null', 'authenticated', v_sup::text, 'aal1', base || format(s_upd, 'rls41v7-a-trd'),
         array[format(save, format('public.distributor_restore_product(%L, %s)', 'rls41v7-a-trd', upd)), 'reset role',
               format('select count(*) from public.products p where p.id = %L and p.publication_status = %L and p.retired_at is null and p.retired_by is null'
                      || ' and p.retired_reason is null and p.trashed_at is null and p.purge_after is null and %s ->> %L = %L'
                      || ' and exists (select 1 from public.catalog_products c where c.id = p.id)'
                      || ' and exists (select 1 from mobau_private.product_lifecycle_events e where e.product_id = p.id and e.action = %L and e.to_state = %L and e.actor_kind = %L)',
                      'rls41v7-a-trd', 'published', res, 'lifecycle_state', 'published', 'restore', 'published', 'distributor')], 'count', '1'),
      ('D05 Intervención vigente: A retira lo que Mobau retiró y lo restaura → vuelve RETIRADO POR MOBAU (motivo intacto), nunca publicado', 'authenticated', v_sup::text, 'aal1',
         base || format(s_upd, 'rls41v7-a-mret'),
         array[format('select set_config(%L, (public.distributor_trash_product(%L, %s) ->> %L), true)', 'mobau.u2', 'rls41v7-a-mret', upd, 'updated_at'),
               format(save, format('public.distributor_restore_product(%L, current_setting(%L)::timestamptz)', 'rls41v7-a-mret', 'mobau.u2')), 'reset role',
               format('select count(*) from public.products p where p.id = %L and p.publication_status = %L and p.retired_by = %L and p.retired_reason = %L'
                      || ' and p.trashed_at is null and %s ->> %L = %L and not exists (select 1 from public.catalog_products c where c.id = p.id)',
                      'rls41v7-a-mret', 'archived', v_adm, 'Motivo Mobau 41-07', res, 'lifecycle_state', 'retired')], 'count', '1'),
      ('D06 Restaurar lo que movió Mobau → 55000[mobau_intervention] porque la última papelera del ciclo es de Mobau (trashed_by_kind mobau, intervención vigente, solo {purge}); el producto no cambia', 'authenticated', v_sup::text, 'aal1',
         base || format(s_upd, 'rls41v7-a-trm'),
         array[format(fn_try, format('public.distributor_restore_product(%L, %s)', 'rls41v7-a-trm', upd)),
               format('select set_config(%L, (select m.trashed_by_kind || '':'' || m.mobau_hold::text || '':'' || m.allowed_actions::text from public.my_products_lifecycle() m where m.id = %L), true)',
                      'mobau.d6', 'rls41v7-a-trm'), 'reset role',
               format('select current_setting(%L) || ''|'' || current_setting(%L) || ''|'' || (select count(*) from public.products where id = %L and trashed_at is not null and updated_at = current_setting(%L)::timestamptz)',
                      'mobau.test_result', 'mobau.d6', 'rls41v7-a-trm', 'mobau.upd')],
         'text', '55000[mobau_intervention]|mobau:true:{purge}|1'),
      ('D07 Sin caducidad: restaurar un borrador con 40 días en la papelera (plazo antiguo vencido) → borrador', 'authenticated', v_sup::text, 'aal1', base || format(s_upd, 'rls41v7-a-old'),
         array[format('select public.distributor_restore_product(%L, %s)', 'rls41v7-a-old', upd), 'reset role',
               format('select count(*) from public.products p where p.id = %L and p.publication_status = %L and p.trashed_at is null and p.purge_after is null',
                      'rls41v7-a-old', 'draft')], 'count', '1'),
      ('D08 A elimina definitivamente lo que movió Mobau: producto borrado; auditoría purge de A con meta solo {name}', 'authenticated', v_sup::text, 'aal1', base || format(s_upd, 'rls41v7-a-trm'),
         array[format('select public.distributor_purge_product(%L, %L, %s)', 'rls41v7-a-trm', 'rls41v7-a-trm', upd), 'reset role',
               format('select count(*) where not exists (select 1 from public.products where id = %L)'
                      || ' and exists (select 1 from mobau_private.product_lifecycle_events e where e.product_id = %L and e.action = %L and e.actor_kind = %L'
                      || ' and e.actor_id = %L and e.meta = %L::jsonb and (e.purge_counts ->> %L)::int = 1 and length(e.purge_sha256) = 64)',
                      'rls41v7-a-trm', 'rls41v7-a-trm', 'purge', 'distributor', v_sup, '{"name": "A papelera Mobau 41-07"}', 'products')], 'count', '1'),
      ('D09 Eliminar con una línea de proyecto → 55000[purge_blocked_references]; el producto sigue', 'authenticated', v_sup::text, 'aal1',
         base || s_line || format(s_upd, 'rls41v7-a-trd'),
         array[format(fn_try, format('public.distributor_purge_product(%L, %L, %s)', 'rls41v7-a-trd', 'rls41v7-a-trd', upd)), 'reset role',
               format('select count(*) where current_setting(%L) = %L and exists (select 1 from public.products where id = %L)',
                      'mobau.test_result', '55000[purge_blocked_references]', 'rls41v7-a-trd')], 'count', '1'),
      ('D10 Eliminar con una propuesta abierta → 55000[open_proposal]', 'authenticated', v_sup::text, 'aal1',
         base || format(open_upd, 'rls41v7-a-trd', v_sup_dist) || format(s_upd, 'rls41v7-a-trd'),
         array[format('select public.distributor_purge_product(%L, %L, %s)', 'rls41v7-a-trd', 'rls41v7-a-trd', upd)], 'exec', '55000[open_proposal]'),
      ('D11 Retirar con una propuesta abierta → 55000[open_proposal] (no se cancela sola)', 'authenticated', v_sup::text, 'aal1',
         base || format(open_upd, 'rls41v7-a-pub', v_sup_dist) || format(s_upd, 'rls41v7-a-pub'),
         array[format(fn_try, format('public.distributor_trash_product(%L, %s)', 'rls41v7-a-pub', upd)), 'reset role',
               format('select count(*) where current_setting(%L) = %L and exists (select 1 from public.product_proposals where product_id = %L and status = %L)',
                      'mobau.test_result', '55000[open_proposal]', 'rls41v7-a-pub', 'draft')], 'count', '1'),
      ('D12 Productos de otra empresa: retirar, restaurar y eliminar → P0002[product_not_found] ×3; B intacto', 'authenticated', v_sup::text, 'aal1', base,
         array[format(fn_try, format('public.distributor_trash_product(%L, now())', 'rls41v7-b-pub')), format(keep, 'mobau.r1'),
               format(fn_try, format('public.distributor_restore_product(%L, now())', 'rls41v7-b-trd')), format(keep, 'mobau.r2'),
               format(fn_try, format('public.distributor_purge_product(%L, %L, now())', 'rls41v7-b-trd', 'rls41v7-b-trd')), 'reset role',
               format('select current_setting(%L) || ''|'' || current_setting(%L) || ''|'' || current_setting(%L)'
                      || ' || ''|'' || (select count(*) from public.products where id in (%L, %L) and updated_at < now() - interval ''30 minutes'')',
                      'mobau.r1', 'mobau.r2', 'mobau.test_result', 'rls41v7-b-pub', 'rls41v7-b-trd')],
         'text', 'P0002[product_not_found]|P0002[product_not_found]|P0002[product_not_found]|2'),
      ('D13 Eliminar con un identificador de confirmación distinto → 22023[confirm_mismatch]', 'authenticated', v_sup::text, 'aal1', base,
         array[format('select public.distributor_purge_product(%L, %L, now())', 'rls41v7-a-trd', 'rls41v7-a-pub')], 'exec', '22023[confirm_mismatch]'),
      ('D14 Eliminar un producto fuera de la papelera → 55000[invalid_state]', 'authenticated', v_sup::text, 'aal1', base || format(s_upd, 'rls41v7-a-pub'),
         array[format('select public.distributor_purge_product(%L, %L, %s)', 'rls41v7-a-pub', 'rls41v7-a-pub', upd)], 'exec', '55000[invalid_state]'),
      ('D15 La republicación aprobada levanta la intervención: después A retira y restaura → publicado', 'authenticated', v_sup::text, 'aal1', base,
         array[format(rep_ins, 'rls41v7-a-mret'), format(rep_submit, 'rls41v7-a-mret'), as_admin,
               format('select public.moderate_product_proposal(%s, %L, %L, %s)', format(rep_id, 'rls41v7-a-mret'), 'approve', 'Aprobada (ensayo 41-07)', '1'),
               as_sup,
               format('select set_config(%L, (select m.updated_at::text from public.my_products_lifecycle() m where m.id = %L), true)', 'mobau.u3', 'rls41v7-a-mret'),
               format('select set_config(%L, (public.distributor_trash_product(%L, current_setting(%L)::timestamptz) ->> %L), true)', 'mobau.u4', 'rls41v7-a-mret', 'mobau.u3', 'updated_at'),
               format(save, format('public.distributor_restore_product(%L, current_setting(%L)::timestamptz)', 'rls41v7-a-mret', 'mobau.u4')),
               format('select %s ->> %L', res, 'lifecycle_state')], 'text', 'published'),
      ('D16 Identificador reutilizado: el ciclo anterior (otra empresa, retirada de Mobau y eliminación) no cuenta para el actual ni mezcla nombres', 'authenticated', v_sup::text, 'aal1',
         base || array[
           format(ins_e, 'rls41v7-a-reu', 'rls41v7-dist-b', 'retire', 'published', 'retired', v_adm, 'mobau', 'Motivo antiguo 41-07', '10 days'),
           format('insert into mobau_private.product_lifecycle_events (product_id, distributor_id, action, from_state, to_state, actor_id, actor_kind, reason, meta, created_at)'
                  || ' values (%L, %L, %L, %L, null, %L, %L, %L, %L::jsonb, now() - interval %L)',
                  'rls41v7-a-reu', 'rls41v7-dist-b', 'purge', 'retired', v_adm, 'mobau', 'Eliminación antigua 41-07', '{"name": "Antiguo 41-07"}', '9 days'),
           format(ins_p, 'rls41v7-a-reu', 'A reutilizado 41-07', v_sup_dist, v_cat1, v_sub1, 'archived', 'now() - interval ''3 days''', v_sup, 'Retirado por la empresa',
                  'now() - interval ''1 day''', v_sup, 'retired', 'null'),
           format(ins_e, 'rls41v7-a-reu', v_sup_dist, 'retire', 'published', 'retired', v_sup, 'distributor', 'Retirado por la empresa', '3 days'),
           format(ins_e, 'rls41v7-a-reu', v_sup_dist, 'trash', 'retired', 'trashed', v_sup, 'distributor', null, '1 day')],
         array[format('select set_config(%L, (select m.mobau_hold::text || '':'' || m.restore_to || '':'' || m.trashed_by_kind || '':'' || m.allowed_actions::text from public.my_products_lifecycle() m where m.id = %L), true)',
                      'mobau.c1', 'rls41v7-a-reu'),
               format('select set_config(%L, (select count(*)::text || '':'' || string_agg(distinct coalesce(e.product_name, ''-''), '','') from public.my_product_lifecycle_events(%L) e), true)',
                      'mobau.c2', 'rls41v7-a-reu'),
               as_admin,
               format('select current_setting(%L) || ''|'' || current_setting(%L) || ''|'' || (select string_agg(h.action || '':'' || coalesce(h.product_name, ''-''), '','' order by h.created_at)'
                      || ' from public.mobau_lifecycle_history(%L) h)', 'mobau.c1', 'mobau.c2', 'rls41v7-a-reu')],
         'text', 'false:published:distributor:{restore,purge}|2:A reutilizado 41-07|retire:Antiguo 41-07,purge:Antiguo 41-07,retire:A reutilizado 41-07,trash:A reutilizado 41-07'),
      -- ========== M · Mobau ==========
      ('M01 Mobau mueve a la papelera sin motivo → 22023[invalid_reason]', 'authenticated', v_adm::text, 'aal2', base,
         array[format('select public.mobau_product_lifecycle(%L, %L, null, now())', 'rls41v7-a-mret', 'trash')], 'exec', '22023[invalid_reason]'),
      ('M02 Mobau retira con motivo; A ve «retirado por Mobau», el motivo y la intervención vigente', 'authenticated', v_adm::text, 'aal2', base || format(s_upd, 'rls41v7-a-pub'),
         array[format('select public.mobau_product_lifecycle(%L, %L, %L, %s)', 'rls41v7-a-pub', 'retire', 'Motivo intervención 41-07', upd), as_sup,
               format('select (select m.retired_by_kind || '':'' || m.retired_reason || '':'' || m.mobau_hold::text from public.my_products_lifecycle() m where m.id = %L)'
                      || ' || ''|'' || (select e.actor_kind || '':'' || e.reason from public.my_product_lifecycle_events(%L) e where e.action = %L limit 1)',
                      'rls41v7-a-pub', 'rls41v7-a-pub', 'retire')],
         'text', 'mobau:Motivo intervención 41-07:true|mobau:Motivo intervención 41-07'),
      ('M03 Mobau mueve a la papelera con motivo: sin purge_after; A no puede restaurarlo (acciones {purge})', 'authenticated', v_adm::text, 'aal2', base || format(s_upd, 'rls41v7-a-mret'),
         array[format('select public.mobau_product_lifecycle(%L, %L, %L, %s)', 'rls41v7-a-mret', 'trash', 'Papelera Mobau 41-07', upd), as_sup,
               format('select set_config(%L, (select m.lifecycle_state || '':'' || m.allowed_actions::text || '':'' || m.trashed_by_kind from public.my_products_lifecycle() m where m.id = %L), true)',
                      'mobau.m3', 'rls41v7-a-mret'), 'reset role',
               format('select current_setting(%L) || '':'' || (select (purge_after is null)::text from public.products where id = %L)', 'mobau.m3', 'rls41v7-a-mret')],
         'text', 'trashed:{purge}:mobau:true'),
      ('M04 Mobau elimina directamente un PUBLICADO (p_early = false, como la interfaz anterior); A ve nombre, actor y motivo; meta solo {name}', 'authenticated', v_adm::text, 'aal2',
         base || format(s_upd, 'rls41v7-a-pub'),
         array[format('select public.mobau_purge_product(%L, %L, %L, false, %s)', 'rls41v7-a-pub', 'rls41v7-a-pub', 'Motivo eliminación 41-07', upd), as_sup,
               format('select set_config(%L, (select e.product_name || '':'' || e.actor_kind || '':'' || e.reason from public.my_product_lifecycle_events(%L) e where e.action = %L), true)',
                      'mobau.e', 'rls41v7-a-pub', 'purge'), 'reset role',
               format('select current_setting(%L) || ''|'' || (select e.from_state || '':'' || e.meta::text from mobau_private.product_lifecycle_events e where e.product_id = %L and e.action = %L)',
                      'mobau.e', 'rls41v7-a-pub', 'purge')],
         'text', 'A publicado 41-07:mobau:Motivo eliminación 41-07|published:{"name": "A publicado 41-07"}'),
      ('M05 Mobau elimina con una línea de proyecto → 55000[purge_blocked_references]', 'authenticated', v_adm::text, 'aal2', base || s_line || format(s_upd, 'rls41v7-a-trd'),
         array[format('select public.mobau_purge_product(%L, %L, %L, true, %s)', 'rls41v7-a-trd', 'rls41v7-a-trd', 'Motivo 41-07', upd)], 'exec', '55000[purge_blocked_references]'),
      ('M06 Historial de Mobau de un producto ya eliminado (con id) y en la lista de eliminaciones (sin id)', 'authenticated', v_adm::text, 'aal2', base || format(s_upd, 'rls41v7-a-trm'),
         array[format('select public.mobau_purge_product(%L, %L, %L, false, %s)', 'rls41v7-a-trm', 'rls41v7-a-trm', 'Eliminación Mobau 41-07', upd),
               format('select (select string_agg(h.action || '':'' || h.actor_kind || '':'' || h.product_exists::text || '':'' || coalesce(h.product_name, ''-''), '','' order by h.created_at, h.action)'
                      || ' from public.mobau_lifecycle_history(%L) h) || ''|'' || (select count(*) from public.mobau_lifecycle_history(null) h where h.product_id = %L and h.reason = %L)',
                      'rls41v7-a-trm', 'rls41v7-a-trm', 'Eliminación Mobau 41-07')],
         'text', 'retire:mobau:false:A papelera Mobau 41-07,trash:mobau:false:A papelera Mobau 41-07,purge:mobau:false:A papelera Mobau 41-07|1'),
      ('M07 Un distribuidor no puede leer el historial de Mobau → 42501[not_admin]', 'authenticated', v_sup::text, 'aal1', base,
         array['select count(*) from public.mobau_lifecycle_history(null)'], 'exec', '42501[not_admin]'),
      ('M08 Vista de Mobau del retirado por Mobau: intervención vigente y acciones', 'authenticated', v_adm::text, 'aal2', base,
         array[format('select (v ->> %L) || '':'' || (v -> %L)::text || '':'' || (v ->> %L) from public.mobau_product_lifecycle_view(%L) v',
                      'lifecycle_state', 'allowed_actions', 'mobau_hold', 'rls41v7-a-mret')], 'text', 'retired:["trash", "purge"]:true'),
      -- ========== K · interruptor, parada y restricciones ==========
      ('K01 interruptor apagado (en el caso): A elimina → 55000[feature_disabled]', 'authenticated', v_sup::text, 'aal1', base || stop_sw,
         array[format('select public.distributor_purge_product(%L, %L, now())', 'rls41v7-a-trd', 'rls41v7-a-trd')], 'exec', '55000[feature_disabled]'),
      ('K02 interruptor apagado (en el caso): historial de Mobau → 55000[feature_disabled]', 'authenticated', v_adm::text, 'aal2', base || stop_sw,
         array['select count(*) from public.mobau_lifecycle_history(null)'], 'exec', '55000[feature_disabled]'),
      ('K03 parada de 41-07 (en el caso): interruptor apagado y las 11 funciones de entrada con ACL {postgres=X/postgres}', '-', null, null, base || stop_all,
         array['select count(*) where not mobau_private.product_lifecycle_enabled() and ' || format(acl_11, '{postgres=X/postgres}') || ' = 11'], 'count', '1'),
      ('K04 restricciones: un producto publicado nunca puede estar en la papelera → 23514', '-', null, null, base,
         array[format('update public.products set trashed_at = now(), trashed_by = %L, trash_from = %L where id = %L', v_sup, 'retired', 'rls41v7-a-pub')], 'exec', '23514'),
      ('K05 restricciones: papelera sin trash_from → 23514', '-', null, null, base,
         array[format('update public.products set trash_from = null where id = %L', 'rls41v7-a-trd')], 'exec', '23514'),
      -- ========== estado real tras la suite ==========
      ('Z01 fuera de los casos: interruptor encendido, permisos de 41-07, sin restos, auditoría sin cambios', '-', null, null, null::text[],
         array['select count(*) where mobau_private.product_lifecycle_enabled()'
               || ' and ' || format(acl_10, '{postgres=X/postgres,authenticated=X/postgres}') || ' = 10'
               || ' and not exists (select 1 from public.products where id like ''rls41v7%'')'
               || ' and not exists (select 1 from public.distributors where id like ''rls41v7%'')'
               || ' and not exists (select 1 from public.mobau_admins where granted_note like ''%41-07%'')'
               || ' and (select count(*) from mobau_private.product_lifecycle_events) = ' || n_ev0], 'count', '1')
    ) as c(name, role, sub, aal, setup, sql, kind, expect)
  loop
    v_got := null;
    begin
      if t.setup is not null then
        foreach v_stmt in array t.setup loop execute v_stmt; end loop;
      end if;
      if t.role <> '-' then execute format('set local role %I', t.role); end if;
      perform set_config('request.jwt.claim.sub', coalesce(t.sub, ''), true);
      perform set_config('request.jwt.claim.role', '', true);
      perform set_config('request.jwt.claims',
        case when t.sub is null then '' else json_build_object('sub', t.sub, 'role', t.role, 'aal', t.aal)::text end, true);
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
      else v_got = t.expect
    end;
    n_total := n_total + 1;
    if v_ok then n_ok := n_ok + 1; end if;
    r := r || jsonb_build_object('prueba', t.name, 'esperado', t.expect, 'obtenido', v_got, 'ok', coalesce(v_ok, false));
  end loop;

  raise exception 'MOBAU_41_07_SUITE total=% ok=% fallos=% :: %', n_total, n_ok, n_total - n_ok, r::text
    using errcode = 'MB999';
end $E7S$;

ROLLBACK;
