-- ============================================================
-- PROPUESTA NO EJECUTADA (V4 · humo) — no ejecutar sin aprobación explícita
-- ============================================================
-- Ventana V4 · PRUEBAS DE HUMO del ciclo de vida, en una transacción
-- revertida. Ejecutar DESPUÉS de 41-06 (interruptor encendido y EXECUTE de
-- authenticated ya concedidos de verdad): esta suite NO concede permisos ni
-- enciende nada; usa el estado real. Rol postgres; JWT simulado como en 39/41.
--
-- En cada caso, DENTRO de su subtransacción (se deshace con MB001):
--   · auxiliares rls41v4-* (3 productos de A y un precio);
--   · fila temporal en mobau_admins para Mobau (1.er perfil individual sin
--     empresa ni admin), con aal2;
--   · en los casos K, la PARADA se aplica dentro del caso (mismas sentencias
--     que parada/41_06_parada.sql) y se deshace con el caso.
-- Grupos: H (activación: lecturas, acciones, republish, Mobau, regresión),
--         K (parada: bloqueos, cierre de republish, moderación ordinaria
--            intacta y sin cambios de datos), Z (estado real intacto).
-- Efectos no transaccionales: avanzan las secuencias proposal_events_id_seq y
-- product_lifecycle_events_id_seq, y los contadores de pg_stat. Nada más.
-- Formato de expect en 'exec': SQLSTATE (5) o SQLSTATE[hint] exactos.
-- ============================================================

BEGIN;

DO $H4$
declare
  v_sup uuid; v_sup_dist text; v_pro uuid; v_cat1 text; v_sub1 text; n_ev0 bigint;
  v_admin text; s_aux text[]; base text[]; as_admin text; stop_sw text; stop_all text[];
  ins_p constant text := 'insert into public.products (id, name, distributor_id, category_id, subcategory, publication_status, retired_at, retired_by, retired_reason, trashed_at, trashed_by, trash_from, purge_after, updated_at)'
                         || ' values (%L, %L, %L, %L, %L, %L, %s, %L, %L, %s, %L, %L, %s, now() - interval ''1 hour'')';
  rep_ins constant text := 'insert into public.product_proposals (proposal_kind, product_id, proposed_changes) values (''republish'', %L, ''{}'')';
  rep_id constant text := '(select pr.id from public.product_proposals pr where pr.product_id = %L and pr.proposal_kind = ''republish'')';
  rep_submit constant text := 'update public.product_proposals set status = ''submitted'' where product_id = %L and proposal_kind = ''republish''';
  moderate constant text := 'public.moderate_product_proposal(%s, %L, %L, %s)';
  s_upd constant text := 'select set_config(''mobau.upd'', (select updated_at::text from public.products where id = %L), true)';
  upd constant text := 'current_setting(''mobau.upd'')::timestamptz';
  save constant text := 'select set_config(''mobau.test_result'', (%s)::text, true)';
  res constant text := 'current_setting(''mobau.test_result'')::jsonb';
  fn_try constant text := 'do $t$ declare h text; begin perform %s; perform set_config(''mobau.test_result'', ''sin error'', true);'
                          || ' exception when others then get stacked diagnostics h = pg_exception_hint;'
                          || ' perform set_config(''mobau.test_result'', sqlstate || ''['' || coalesce(h, '''') || '']'', true); end $t$';
  fp_ret constant text := '(select md5((to_jsonb(p) - ''updated_at'')::text) || ''/'' || coalesce(md5(to_jsonb(pp)::text), ''-'')'
                          || ' from public.products p left join public.product_prices pp on pp.product_id = p.id where p.id = %L)';
  q_data constant text := '(select md5(coalesce((select string_agg(x::text, ''|'' order by x::text) from public.products x), ''''))'
                          || ' || md5(coalesce((select string_agg(x::text, ''|'' order by x::text) from public.product_prices x), ''''))'
                          || ' || md5(coalesce((select string_agg(x::text, ''|'' order by x::text) from public.product_proposals x), ''''))'
                          || ' || md5(coalesce((select string_agg(x::text, ''|'' order by x::text) from public.proposal_events x), ''''))'
                          || ' || md5(coalesce((select string_agg(x::text, ''|'' order by x::text) from mobau_private.product_lifecycle_events x), '''')))';
  acl_on constant text := '(select count(*) from pg_proc p where p.oid in (''public.my_products_lifecycle()''::regprocedure, ''public.my_product_lifecycle_events(text)''::regprocedure,'
                          || ' ''public.distributor_retire_product(text, text, timestamptz)''::regprocedure, ''public.distributor_trash_product(text, timestamptz)''::regprocedure,'
                          || ' ''public.distributor_restore_product(text, timestamptz)''::regprocedure, ''public.mobau_product_lifecycle(text, text, text, timestamptz)''::regprocedure,'
                          || ' ''public.mobau_purge_product(text, text, text, boolean, timestamptz)''::regprocedure, ''public.mobau_product_references(text)''::regprocedure,'
                          || ' ''public.mobau_product_lifecycle_view(text)''::regprocedure) and p.proacl::text = %L)';
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
  select c.id, c.subcategories[1] into v_cat1, v_sub1 from public.categories c where cardinality(c.subcategories) >= 1 order by c.id limit 1;
  select count(*) into n_ev0 from mobau_private.product_lifecycle_events;
  if v_sup is null or v_pro is null or v_cat1 is null then
    raise exception 'MOBAU_V4_HUMO: faltan datos de partida' using errcode = 'MB998';
  end if;
  -- solo tiene sentido con 41-06 aplicada: interruptor encendido y EXECUTE de authenticated reales
  if not mobau_private.product_lifecycle_enabled()
     or not has_function_privilege('authenticated', 'public.distributor_retire_product(text, text, timestamptz)', 'EXECUTE')
     or has_function_privilege('anon', 'public.distributor_retire_product(text, text, timestamptz)', 'EXECUTE') then
    raise exception 'MOBAU_V4_HUMO: 41-06 no está aplicada (interruptor o EXECUTE)' using errcode = 'MB998';
  end if;
  if exists (select 1 from public.products where id like 'rls41v4%') or exists (select 1 from public.mobau_admins where granted_note like '%41 V4%') then
    raise exception 'MOBAU_V4_HUMO: ya existen auxiliares rls41v4' using errcode = 'MB998';
  end if;

  -- ---------- auxiliares (como postgres, dentro de cada caso) ----------
  v_admin := format('insert into public.mobau_admins (user_id, granted_note) values (%L, %L)', v_pro, 'Admin temporal de humo 41 V4');
  s_aux := array[
    format(ins_p, 'rls41v4-a-pub', 'A publicado 41 V4', v_sup_dist, v_cat1, v_sub1, 'published', 'null', null, null, 'null', null, null, 'null'),
    format(ins_p, 'rls41v4-a-ret', 'A retirado 41 V4', v_sup_dist, v_cat1, v_sub1, 'archived', 'now() - interval ''2 days''', v_sup, 'Motivo de A 41 V4', 'null', null, null, 'null'),
    format(ins_p, 'rls41v4-a-trd', 'A papelera (borrador) 41 V4', v_sup_dist, v_cat1, v_sub1, 'draft', 'null', null, null,
           'now() - interval ''1 day''', v_sup, 'draft', 'now() - interval ''1 day'' + interval ''30 days'''),
    format('insert into public.product_prices (product_id, price_status, price_amount, currency, includes_itbis) values (%L, %L, 60, %L, true)', 'rls41v4-a-ret', 'published', 'USD')];
  base := s_aux || v_admin;
  as_admin := format('select set_config(%L, %L, true), set_config(%L, %L, true)', 'request.jwt.claims',
                     json_build_object('sub', v_pro, 'role', 'authenticated', 'aal', 'aal2')::text, 'request.jwt.claim.sub', v_pro);
  -- parada: mismas sentencias que parada/41_06_parada.sql (sin BEGIN/COMMIT ni lock_timeout)
  stop_sw := 'update mobau_private.product_lifecycle_settings set enabled = false, changed_at = now(), changed_by = null, note = ''41-06 parada: interruptor apagado y EXECUTE revocado (ventana V4)'' where id = 1';
  stop_all := array[stop_sw,
    'revoke all on function public.my_products_lifecycle() from public, anon, authenticated, service_role',
    'revoke all on function public.my_product_lifecycle_events(text) from public, anon, authenticated, service_role',
    'revoke all on function public.distributor_retire_product(text, text, timestamptz) from public, anon, authenticated, service_role',
    'revoke all on function public.distributor_trash_product(text, timestamptz) from public, anon, authenticated, service_role',
    'revoke all on function public.distributor_restore_product(text, timestamptz) from public, anon, authenticated, service_role',
    'revoke all on function public.mobau_product_lifecycle(text, text, text, timestamptz) from public, anon, authenticated, service_role',
    'revoke all on function public.mobau_purge_product(text, text, text, boolean, timestamptz) from public, anon, authenticated, service_role',
    'revoke all on function public.mobau_product_references(text) from public, anon, authenticated, service_role',
    'revoke all on function public.mobau_product_lifecycle_view(text) from public, anon, authenticated, service_role'];

  for t in
    select * from (values
      -- ========== H · activación ==========
      ('H01 estado real: interruptor encendido, 9 ACL {postgres=X/postgres,authenticated=X/postgres}, sin EXECUTE de anon ni service_role', '-', null::text, null::text, null::text[],
         array['select count(*) where mobau_private.product_lifecycle_enabled()'
               || ' and ' || format(acl_on, '{postgres=X/postgres,authenticated=X/postgres}') || ' = 9'
               || ' and not has_function_privilege(''anon'', ''public.mobau_purge_product(text, text, text, boolean, timestamptz)'', ''EXECUTE'')'
               || ' and not has_function_privilege(''service_role'', ''public.mobau_purge_product(text, text, text, boolean, timestamptz)'', ''EXECUTE'')']::text[], 'count', '1'),
      ('H02 anon no puede llamar a las funciones (42501)', 'anon', null, null, base,
         array['select count(*) from public.my_products_lifecycle()'], 'exec', '42501'),
      ('H03 A lee su ciclo de vida: estados y acciones de los auxiliares', 'authenticated', v_sup::text, 'aal1', base,
         array['select string_agg(substr(m.id, 9) || ''='' || m.lifecycle_state || '':'' || m.allowed_actions::text, '';'' order by m.id) from public.my_products_lifecycle() m where m.id like ''rls41v4-a-%'''],
         'text', 'a-pub=published:{retire};a-ret=retired:{request_republish,trash};a-trd=trashed:{restore}'),
      ('H04 A retira su publicado: archived, retired_by = A, evento retire de distributor; lo ve en sus eventos', 'authenticated', v_sup::text, 'aal1', base || format(s_upd, 'rls41v4-a-pub'),
         array[format(save, format('public.distributor_retire_product(%L, %L, %s)', 'rls41v4-a-pub', 'Motivo humo 41 V4', upd)),
               'select set_config(''mobau.ev'', (select count(*)::text from public.my_product_lifecycle_events(''rls41v4-a-pub'') e where e.action = ''retire'' and e.actor_kind = ''distributor''), true)',
               'reset role',
               format('select count(*) from public.products p where p.id = %L and p.publication_status = %L and p.retired_by = %L and p.retired_at is not null'
                      || ' and (%s ->> %L)::boolean and current_setting(%L) = %L'
                      || ' and exists (select 1 from mobau_private.product_lifecycle_events e where e.product_id = p.id and e.action = %L and e.actor_kind = %L and e.actor_id = %L)',
                      'rls41v4-a-pub', 'archived', v_sup, res, 'ok', 'mobau.ev', '1', 'retire', 'distributor', v_sup)], 'count', '1'),
      ('H05 A mueve a la papelera su retirado y lo restaura: producto (sin updated_at) y precio idénticos, sigue archived', 'authenticated', v_sup::text, 'aal1',
         base || format(s_upd, 'rls41v4-a-ret') || format('select set_config(%L, %s, true)', 'mobau.fp0', format(fp_ret, 'rls41v4-a-ret')),
         array[format('select set_config(%L, (public.distributor_trash_product(%L, %s) ->> %L), true)', 'mobau.u2', 'rls41v4-a-ret', upd, 'updated_at'),
               format('select public.distributor_restore_product(%L, current_setting(%L)::timestamptz)', 'rls41v4-a-ret', 'mobau.u2'), 'reset role',
               format('select count(*) where %s = current_setting(%L) and (select publication_status from public.products where id = %L) = %L',
                      format(fp_ret, 'rls41v4-a-ret'), 'mobau.fp0', 'rls41v4-a-ret', 'archived')], 'count', '1'),
      ('H06 republish: A la crea y la envía; Mobau aal2 aprueba → published, retired_* a null, evento republish de mobau', 'authenticated', v_sup::text, 'aal1', base,
         array[format(rep_ins, 'rls41v4-a-ret'), format(rep_submit, 'rls41v4-a-ret'), as_admin,
               format(save, format(moderate, format(rep_id, 'rls41v4-a-ret'), 'approve', 'Republicación aprobada (humo 41 V4)', '1')), 'reset role',
               format('select count(*) from public.products p where p.id = %L and p.publication_status = %L and p.retired_at is null and p.retired_by is null'
                      || ' and %s ->> %L = %L'
                      || ' and exists (select 1 from public.product_proposals pr where pr.product_id = p.id and pr.proposal_kind = %L and pr.status = %L)'
                      || ' and exists (select 1 from mobau_private.product_lifecycle_events e where e.product_id = p.id and e.action = %L and e.actor_kind = %L and e.actor_id = %L)',
                      'rls41v4-a-ret', 'published', res, 'result', 'approved', 'republish', 'approved', 'republish', 'mobau', v_pro)], 'count', '1'),
      ('H07 republish: A retira su solicitud (draft → withdrawn), el producto sigue retirado', 'authenticated', v_sup::text, 'aal1', base,
         array[format(rep_ins, 'rls41v4-a-ret'),
               'update public.product_proposals set status = ''withdrawn'' where product_id = ''rls41v4-a-ret'' and proposal_kind = ''republish''', 'reset role',
               'select count(*) from public.products p where p.id = ''rls41v4-a-ret'' and p.publication_status = ''archived'' and p.retired_at is not null'
               || ' and exists (select 1 from public.product_proposals pr where pr.product_id = p.id and pr.proposal_kind = ''republish'' and pr.status = ''withdrawn'')'], 'count', '1'),
      ('H08 Mobau aal2: vista del retirado (estado y acciones)', 'authenticated', v_pro::text, 'aal2', base,
         array['select (v ->> ''lifecycle_state'') || '':'' || (v -> ''allowed_actions'')::text from public.mobau_product_lifecycle_view(''rls41v4-a-ret'') v'],
         'text', 'retired:["trash"]'),
      ('H09 Mobau aal2: referencias del publicado (sin tablas desconocidas)', 'authenticated', v_pro::text, 'aal2', base,
         array['select count(*) from public.mobau_product_references(''rls41v4-a-pub'') r where r ->> ''product_id'' = ''rls41v4-a-pub'' and jsonb_array_length(r -> ''unknown_reference_tables'') = 0'], 'count', '1'),
      ('H10 Mobau aal2 retira el publicado: archived, retired_by = admin, evento mobau', 'authenticated', v_pro::text, 'aal2', base || format(s_upd, 'rls41v4-a-pub'),
         array[format('select public.mobau_product_lifecycle(%L, %L, %L, %s)', 'rls41v4-a-pub', 'retire', 'Motivo Mobau humo 41 V4', upd), 'reset role',
               format('select count(*) from public.products p where p.id = %L and p.publication_status = %L and p.retired_by = %L'
                      || ' and exists (select 1 from mobau_private.product_lifecycle_events e where e.product_id = p.id and e.action = %L and e.actor_kind = %L)',
                      'rls41v4-a-pub', 'archived', v_pro, 'retire', 'mobau')], 'count', '1'),
      ('H11 Mobau aal2 elimina definitivamente (anticipada) el borrador de la papelera: producto borrado, auditoría purge', 'authenticated', v_pro::text, 'aal2', base || format(s_upd, 'rls41v4-a-trd'),
         array[format('select public.mobau_purge_product(%L, %L, %L, true, %s)', 'rls41v4-a-trd', 'rls41v4-a-trd', 'Eliminación de humo 41 V4', upd), 'reset role',
               'select count(*) where not exists (select 1 from public.products where id = ''rls41v4-a-trd'')'
               || ' and exists (select 1 from mobau_private.product_lifecycle_events e where e.product_id = ''rls41v4-a-trd'' and e.action = ''purge'' and e.actor_kind = ''mobau'')'], 'count', '1'),
      ('H12 regresión: una update de A aprobada con el interruptor encendido cambia solo el nombre', 'authenticated', v_sup::text, 'aal1', base,
         array['insert into public.product_proposals (proposal_kind, product_id, proposed_changes) values (''update'', ''rls41v4-a-pub'', ''{"name": "Nombre aprobado 41 V4"}'')',
               'update public.product_proposals set status = ''submitted'' where product_id = ''rls41v4-a-pub'' and proposal_kind = ''update''', as_admin,
               format('select %s', format(moderate, '(select pr.id from public.product_proposals pr where pr.product_id = ''rls41v4-a-pub'' and pr.proposal_kind = ''update'')', 'approve', null, '1')),
               'reset role',
               'select count(*) from public.products where id = ''rls41v4-a-pub'' and name = ''Nombre aprobado 41 V4'' and publication_status = ''published'' and retired_at is null'], 'count', '1'),
      -- ========== K · parada (dentro del caso) ==========
      ('K01 solo interruptor apagado: A retira → 55000[feature_disabled]', 'authenticated', v_sup::text, 'aal1', base || format(s_upd, 'rls41v4-a-pub') || stop_sw,
         array[format('select public.distributor_retire_product(%L, %L, %s)', 'rls41v4-a-pub', 'Motivo humo 41 V4', upd)], 'exec', '55000[feature_disabled]'),
      ('K02 parada completa: A retira → 42501 (sin EXECUTE)', 'authenticated', v_sup::text, 'aal1', base || format(s_upd, 'rls41v4-a-pub') || stop_all,
         array[format('select public.distributor_retire_product(%L, %L, %s)', 'rls41v4-a-pub', 'Motivo humo 41 V4', upd)], 'exec', '42501'),
      ('K03 parada completa: lectura del distribuidor → 42501 (también las 2 lecturas que no consultan el interruptor)', 'authenticated', v_sup::text, 'aal1', base || stop_all,
         array['select count(*) from public.my_product_lifecycle_events(null)'], 'exec', '42501'),
      ('K04 parada completa: vista de Mobau → 42501', 'authenticated', v_pro::text, 'aal2', base || stop_all,
         array['select public.mobau_product_lifecycle_view(''rls41v4-a-ret'')'], 'exec', '42501'),
      ('K05 parada completa: A crea una republish → 55000[feature_disabled] (puerta, no depende de EXECUTE)', 'authenticated', v_sup::text, 'aal1', base || stop_all,
         array[format(rep_ins, 'rls41v4-a-ret')], 'exec', '55000[feature_disabled]'),
      ('K06 republish enviada antes de la parada: Mobau aprueba después → 55000[feature_disabled]; producto sigue retirado y propuesta submitted', 'authenticated', v_sup::text, 'aal1', base,
         array[format(rep_ins, 'rls41v4-a-ret'), format(rep_submit, 'rls41v4-a-ret'), 'reset role'] || stop_all
               || array['set local role authenticated', as_admin,
                        format(fn_try, format(moderate, format(rep_id, 'rls41v4-a-ret'), 'approve', 'Aprobación tras parada (humo 41 V4)', '1')), 'reset role',
                        'select count(*) where current_setting(''mobau.test_result'') = ''55000[feature_disabled]'''
                        || ' and exists (select 1 from public.products where id = ''rls41v4-a-ret'' and publication_status = ''archived'' and retired_at is not null)'
                        || ' and exists (select 1 from public.product_proposals where product_id = ''rls41v4-a-ret'' and proposal_kind = ''republish'' and status = ''submitted'')'], 'count', '1'),
      ('K07 republish enviada antes de la parada: Mobau rechaza después → permitido (rejected), producto intacto', 'authenticated', v_sup::text, 'aal1', base,
         array[format(rep_ins, 'rls41v4-a-ret'), format(rep_submit, 'rls41v4-a-ret'), 'reset role'] || stop_all
               || array['set local role authenticated', as_admin,
                        format('select %s', format(moderate, format(rep_id, 'rls41v4-a-ret'), 'reject', 'Rechazo tras parada (humo 41 V4)', '1')), 'reset role',
                        'select count(*) from public.product_proposals pr where pr.product_id = ''rls41v4-a-ret'' and pr.proposal_kind = ''republish'' and pr.status = ''rejected'''
                        || ' and exists (select 1 from public.products where id = ''rls41v4-a-ret'' and publication_status = ''archived'' and retired_at is not null)'], 'count', '1'),
      ('K08 republish en borrador antes de la parada: A la retira después → permitido (withdrawn)', 'authenticated', v_sup::text, 'aal1', base,
         array[format(rep_ins, 'rls41v4-a-ret'), 'reset role'] || stop_all
               || array['set local role authenticated',
                        format('select set_config(%L, %L, true), set_config(%L, %L, true)', 'request.jwt.claims',
                               json_build_object('sub', v_sup, 'role', 'authenticated', 'aal', 'aal1')::text, 'request.jwt.claim.sub', v_sup),
                        'update public.product_proposals set status = ''withdrawn'' where product_id = ''rls41v4-a-ret'' and proposal_kind = ''republish''', 'reset role',
                        'select count(*) from public.product_proposals where product_id = ''rls41v4-a-ret'' and proposal_kind = ''republish'' and status = ''withdrawn'''], 'count', '1'),
      ('K09 parada completa: una update de A se modera con normalidad (moderación ordinaria intacta)', 'authenticated', v_sup::text, 'aal1', base || stop_all,
         array['insert into public.product_proposals (proposal_kind, product_id, proposed_changes) values (''update'', ''rls41v4-a-pub'', ''{"name": "Nombre tras parada 41 V4"}'')',
               'update public.product_proposals set status = ''submitted'' where product_id = ''rls41v4-a-pub'' and proposal_kind = ''update''', as_admin,
               format('select %s', format(moderate, '(select pr.id from public.product_proposals pr where pr.product_id = ''rls41v4-a-pub'' and pr.proposal_kind = ''update'')', 'approve', null, '1')),
               'reset role',
               'select count(*) from public.products where id = ''rls41v4-a-pub'' and name = ''Nombre tras parada 41 V4'' and publication_status = ''published'''], 'count', '1'),
      ('K10 parada completa: una create de A se aprueba con normalidad (40-01)', 'authenticated', v_sup::text, 'aal1', base || stop_all,
         array[format('insert into public.product_proposals (proposal_kind, proposed_changes) values (%L, %L)', 'create',
                      json_build_object('name', 'Nuevo tras parada 41 V4', 'description', 'Descripción 41 V4', 'category_id', v_cat1,
                                        'subcategory', v_sub1, 'availability', 'por-confirmar')::text),
               'update public.product_proposals set status = ''submitted'' where proposal_kind = ''create'' and proposed_changes ->> ''name'' = ''Nuevo tras parada 41 V4''', as_admin,
               format(save, format(moderate, '(select pr.id from public.product_proposals pr where pr.proposal_kind = ''create'' and pr.proposed_changes ->> ''name'' = ''Nuevo tras parada 41 V4'')', 'approve', null, '1')),
               'reset role',
               format('select count(*) from public.products where id = %s ->> %L and publication_status = %L', res, 'created_product_id', 'published')], 'count', '1'),
      ('K11 la parada no cambia datos: productos, precios, propuestas, eventos y auditoría idénticos; interruptor apagado; 9 ACL de V3', '-', null, null, base,
         array[format('select set_config(%L, %s, true)', 'mobau.d0', q_data)] || stop_all
               || array[format('select count(*) where %s = current_setting(%L) and not mobau_private.product_lifecycle_enabled() and %s = 9',
                               q_data, 'mobau.d0', format(acl_on, '{postgres=X/postgres}'))], 'count', '1'),
      -- ========== estado real tras la suite ==========
      ('Z01 fuera de los casos: interruptor encendido, 9 ACL con authenticated, sin restos, auditoría sin cambios', '-', null, null, null::text[],
         array['select count(*) where mobau_private.product_lifecycle_enabled()'
               || ' and ' || format(acl_on, '{postgres=X/postgres,authenticated=X/postgres}') || ' = 9'
               || ' and not exists (select 1 from public.products where id like ''rls41v4%'' or name in (''Nuevo tras parada 41 V4''))'
               || ' and not exists (select 1 from public.mobau_admins where granted_note like ''%41 V4%'')'
               || ' and (select count(*) from mobau_private.product_lifecycle_events) = ' || n_ev0], 'count', '1')
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

  raise exception 'MOBAU_V4_HUMO total=% ok=% fallos=% :: %', n_total, n_ok, n_total - n_ok, r::text
    using errcode = 'MB999';
end $H4$;

ROLLBACK;
