-- ============================================================
-- PROPUESTA NO EJECUTADA (41-04 · republish) — no ejecutar sin aprobación explícita
-- ============================================================
-- 41 · 04 · Propuestas republish con el interruptor ENCENDIDO DENTRO de cada
-- caso (fuera, apagado: lo prueba la suite CL), en una transacción revertida.
-- Ejecutar después de 41-05 (V3 completa). Rol postgres; JWT simulado.
--
-- Identidades: A (distribuidor verificado real), B (vínculo temporal como
-- supplier verificado de rls41v3-dist-b), Mobau (1.er perfil individual con
-- fila temporal en mobau_admins; aal2 salvo donde se indique).
-- Grupos: creación y envío (T3), bloqueos de la puerta, aprobación (T4) con
-- y sin conflicto (N7), rechazo y cambios (T5), autoaprobación (N6), aal2
-- (N4) y regresiones de update y create (las ramas existentes no cambian).
-- Formato de expect en 'exec': SQLSTATE (5) o SQLSTATE[hint] exactos.
-- ============================================================

BEGIN;

DO $$
declare
  v_sup uuid; v_sup_dist text; v_pro uuid; v_pro2 uuid; v_cat1 text; v_sub1 text;
  s_on text; v_admin text; v_admin_sup text; s_b text[]; s_aux text[]; base text[]; s_open_ret text; s_rep_pg text;
  as_admin text; as_admin_aal1 text; as_sup_aal2 text;
  ins_p constant text := 'insert into public.products (id, name, distributor_id, category_id, subcategory, publication_status, retired_at, retired_by, retired_reason, trashed_at, trashed_by, trash_from, purge_after, updated_at)'
                         || ' values (%L, %L, %L, %L, %L, %L, %s, %L, %L, %s, %L, %L, %s, now() - interval ''1 hour'')';
  dp_cols constant text := 'insert into public.distributor_profiles (user_id, nombre_comercial, razon_social, rnc, direccion_fiscal, telefono, email_contacto, nombre_contacto, cargo_contacto, verification_status, verified_at, distributor_id)'
                           || ' values (%L, %L, %L, %L, %L, %L, %L, %L, %L, %L, now(), %L)';
  rep_ins constant text := 'insert into public.product_proposals (proposal_kind, product_id, proposed_changes) values (''republish'', %L, ''{}'')';
  rep_id constant text := '(select pr.id from public.product_proposals pr where pr.product_id = %L and pr.proposal_kind = ''republish'')';
  rep_submit constant text := 'update public.product_proposals set status = ''submitted'' where product_id = %L and proposal_kind = ''republish''';
  moderate constant text := 'public.moderate_product_proposal(%s, %L, %L, %s)';
  save constant text := 'select set_config(''mobau.test_result'', (%s)::text, true)';
  res constant text := 'current_setting(''mobau.test_result'')::jsonb';
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
  select c.id, c.subcategories[1] into v_cat1, v_sub1 from public.categories c where cardinality(c.subcategories) >= 1 order by c.id limit 1;
  if v_sup is null or v_pro is null or v_pro2 is null or v_cat1 is null then
    raise exception 'MOBAU_41_04: faltan datos de partida' using errcode = 'MB998';
  end if;
  if to_regprocedure('mobau_private.product_proposals_lifecycle_gate()') is null then
    raise exception 'MOBAU_41_04: falta 41-04' using errcode = 'MB998';
  end if;

  s_on := 'update mobau_private.product_lifecycle_settings set enabled = true where id = 1';
  v_admin := format('insert into public.mobau_admins (user_id, granted_note) values (%L, %L)', v_pro, 'Admin temporal de prueba 41 V3');
  v_admin_sup := format('insert into public.mobau_admins (user_id, granted_note) values (%L, %L)', v_sup, 'Admin temporal (autoaprobación) 41 V3');
  s_b := array[
    format('insert into public.distributors (id, name) values (%L, %L)', 'rls41v3-dist-b', 'Distribuidor B (prueba 41 V3)'),
    format(dp_cols, v_pro2, 'Prueba 41 V3 B', 'Prueba 41 V3 B SRL', '999999943', 'Calle de prueba 41', '0000000043',
           'prueba41v3@example.invalid', 'Contacto prueba 41', 'Prueba', 'verified', 'rls41v3-dist-b'),
    format('update public.profiles set role = %L where id = %L', 'supplier', v_pro2)];
  s_aux := array[
    format(ins_p, 'rls41v3-a-ret', 'A retirado 41 V3', v_sup_dist, v_cat1, v_sub1, 'archived', 'now()', v_sup, 'Motivo de A 41 V3', 'null', null, null, 'null'),
    format(ins_p, 'rls41v3-a-pub', 'A publicado 41 V3', v_sup_dist, v_cat1, v_sub1, 'published', 'null', null, null, 'null', null, null, 'null'),
    format(ins_p, 'rls41v3-a-leg', 'A heredado 41 V3', v_sup_dist, v_cat1, v_sub1, 'archived', 'null', null, null, 'null', null, null, 'null'),
    format(ins_p, 'rls41v3-a-draft', 'A borrador 41 V3', v_sup_dist, v_cat1, v_sub1, 'draft', 'null', null, null, 'null', null, null, 'null'),
    format(ins_p, 'rls41v3-a-trr', 'A papelera 41 V3', v_sup_dist, v_cat1, v_sub1, 'archived', 'now()', v_sup, 'Motivo de A 41 V3',
           'now()', v_sup, 'retired', 'now() + interval ''30 days'''),
    format(ins_p, 'rls41v3-b-ret', 'B retirado 41 V3', 'rls41v3-dist-b', v_cat1, v_sub1, 'archived', 'now()', v_pro2, 'Motivo de B 41 V3', 'null', null, null, 'null'),
    format('insert into public.product_prices (product_id, price_status, price_amount, currency, includes_itbis) values (%L, %L, 60, %L, true)', 'rls41v3-a-ret', 'published', 'USD')];
  base := s_b || s_aux || s_on || v_admin;
  s_open_ret := format('insert into public.product_proposals (proposal_kind, product_id, distributor_id, status, proposed_changes) values (%L, %L, %L, %L, %L)',
                       'update', 'rls41v3-a-ret', v_sup_dist, 'draft', '{"name": "Propuesta abierta 41 V3"}');
  s_rep_pg := format('insert into public.product_proposals (proposal_kind, product_id, distributor_id, status, proposed_changes) values (%L, %L, %L, %L, %L)',
                     'republish', 'rls41v3-a-ret', v_sup_dist, 'draft', '{}');
  as_admin := format('select set_config(%L, %L, true), set_config(%L, %L, true)', 'request.jwt.claims',
                     json_build_object('sub', v_pro, 'role', 'authenticated', 'aal', 'aal2')::text, 'request.jwt.claim.sub', v_pro);
  as_admin_aal1 := format('select set_config(%L, %L, true), set_config(%L, %L, true)', 'request.jwt.claims',
                          json_build_object('sub', v_pro, 'role', 'authenticated', 'aal', 'aal1')::text, 'request.jwt.claim.sub', v_pro);
  as_sup_aal2 := format('select set_config(%L, %L, true), set_config(%L, %L, true)', 'request.jwt.claims',
                        json_build_object('sub', v_sup, 'role', 'authenticated', 'aal', 'aal2')::text, 'request.jwt.claim.sub', v_sup);

  for t in
    select * from (values
      -- ========== T3 · crear y enviar ==========
      ('P01 A crea un borrador republish de su retirado', 'authenticated', v_sup::text, 'aal1', base,
         array[format(rep_ins, 'rls41v3-a-ret')]::text[], 'exec', 'ok'),
      ('P02 A lo envía: copia de 22 columnas (sin ciclo de vida) y precio; versión 1', 'authenticated', v_sup::text, 'aal1', base,
         array[format(rep_ins, 'rls41v3-a-ret'), format(rep_submit, 'rls41v3-a-ret'), 'reset role',
               format('select count(*) from public.product_proposals pr where pr.product_id = %L and pr.proposal_kind = %L and pr.status = %L and pr.version = 1'
                      || ' and pr.distributor_id = %L and pr.author_id = %L'
                      || ' and (select count(*) from jsonb_object_keys(pr.product_snapshot -> %L)) = 22 and not (pr.product_snapshot -> %L ? %L)'
                      || ' and (pr.product_snapshot -> %L ->> %L)::numeric = 60',
                      'rls41v3-a-ret', 'republish', 'submitted', v_sup_dist, v_sup, 'product', 'product', 'retired_at', 'price', 'price_amount')], 'count', '1'),
      ('P03 republish de un publicado → 55000[republish_requires_retired]', 'authenticated', v_sup::text, 'aal1', base,
         array[format(rep_ins, 'rls41v3-a-pub')], 'exec', '55000[republish_requires_retired]'),
      ('P04 republish de un heredado → 55000[legacy_pending_review] (N9)', 'authenticated', v_sup::text, 'aal1', base,
         array[format(rep_ins, 'rls41v3-a-leg')], 'exec', '55000[legacy_pending_review]'),
      ('P05 republish de uno en la papelera → 55000[republish_requires_retired]', 'authenticated', v_sup::text, 'aal1', base,
         array[format(rep_ins, 'rls41v3-a-trr')], 'exec', '55000[republish_requires_retired]'),
      ('P06 republish de un borrador → 55000[republish_requires_retired] (A3: publicar borradores queda fuera)', 'authenticated', v_sup::text, 'aal1', base,
         array[format(rep_ins, 'rls41v3-a-draft')], 'exec', '55000[republish_requires_retired]'),
      ('P07 A pide republish de un producto de B → 42501[product_not_found]', 'authenticated', v_sup::text, 'aal1', base,
         array[format(rep_ins, 'rls41v3-b-ret')], 'exec', '42501[product_not_found]'),
      ('P08 republish de un id inexistente → 42501[product_not_found] (igual que P07)', 'authenticated', v_sup::text, 'aal1', base,
         array[format(rep_ins, 'rls41v3-no-existe')], 'exec', '42501[product_not_found]'),
      ('P09 republish con cambios → 23514 (product_proposals_republish_empty)', 'authenticated', v_sup::text, 'aal1', base,
         array['insert into public.product_proposals (proposal_kind, product_id, proposed_changes) values (''republish'', ''rls41v3-a-ret'', ''{"name": "Otro nombre"}'')'], 'exec', '23514'),
      ('P10 republish con precio propuesto → 23514', 'authenticated', v_sup::text, 'aal1', base,
         array['insert into public.product_proposals (proposal_kind, product_id, proposed_changes, proposed_price_status, proposed_price_amount) values (''republish'', ''rls41v3-a-ret'', ''{}'', ''published'', 10)'], 'exec', '23514'),
      ('P11 con una update abierta del mismo producto → 23505 (una abierta por producto)', 'authenticated', v_sup::text, 'aal1', base || s_open_ret,
         array[format(rep_ins, 'rls41v3-a-ret')], 'exec', '23505'),
      ('P12 con una republish abierta, la papelera del distribuidor se bloquea → 55000[open_proposal] (D3)', 'authenticated', v_sup::text, 'aal1',
         base || s_rep_pg || 'grant execute on function public.distributor_trash_product(text, timestamptz) to authenticated'::text
              || 'select set_config(''mobau.upd'', (select updated_at::text from public.products where id = ''rls41v3-a-ret''), true)'::text,
         array['select public.distributor_trash_product(''rls41v3-a-ret'', current_setting(''mobau.upd'')::timestamptz)'], 'exec', '55000[open_proposal]'),
      ('P13 A retira (withdrawn) su republish', 'authenticated', v_sup::text, 'aal1', base,
         array[format(rep_ins, 'rls41v3-a-ret'), 'update public.product_proposals set status = ''withdrawn'' where product_id = ''rls41v3-a-ret'' and proposal_kind = ''republish'''], 'exec', 'ok'),
      ('P14 B verificado supplier crea republish de su retirado', 'authenticated', v_pro2::text, 'aal1', base,
         array[format(rep_ins, 'rls41v3-b-ret')], 'exec', 'ok'),
      -- ========== T4 · aprobar ==========
      ('A01 Mobau aal2 aprueba: published/active, retired_* a null, evento republish de mobau, propuesta approved', 'authenticated', v_sup::text, 'aal1', base,
         array[format(rep_ins, 'rls41v3-a-ret'), format(rep_submit, 'rls41v3-a-ret'), as_admin,
               format(save, format(moderate, format(rep_id, 'rls41v3-a-ret'), 'approve', 'Republicación aprobada 41 V3', '1')), 'reset role',
               format('select count(*) from public.products p where p.id = %L and p.publication_status = %L and p.status = %L'
                      || ' and p.retired_at is null and p.retired_by is null and p.retired_reason is null and p.trashed_at is null'
                      || ' and (%s ->> %L)::boolean and %s ->> %L = %L and %s ->> %L = %L'
                      || ' and exists (select 1 from public.product_proposals pr where pr.product_id = p.id and pr.proposal_kind = %L and pr.status = %L and pr.reviewed_by = %L)'
                      || ' and exists (select 1 from mobau_private.product_lifecycle_events e where e.product_id = p.id and e.action = %L'
                      || '             and e.from_state = %L and e.to_state = %L and e.actor_kind = %L and e.actor_id = %L and e.reason = %L)',
                      'rls41v3-a-ret', 'published', 'active', res, 'ok', res, 'result', 'approved', res, 'publication_status', 'published',
                      'republish', 'approved', v_pro, 'republish', 'retired', 'published', 'mobau', v_pro, 'Republicación aprobada 41 V3')], 'count', '1'),
      ('A02 tras aprobar, anon lo ve en catalog_products', 'authenticated', v_sup::text, 'aal1', base,
         array[format(rep_ins, 'rls41v3-a-ret'), format(rep_submit, 'rls41v3-a-ret'), as_admin,
               format('select %s', format(moderate, format(rep_id, 'rls41v3-a-ret'), 'approve', null, '1')), 'reset role', 'set local role anon',
               'select count(*) from public.catalog_products where id = ''rls41v3-a-ret'''], 'count', '1'),
      ('A03 Mobau sin aal2 → 42501[aal2_required] (N4)', 'authenticated', v_sup::text, 'aal1', base,
         array[format(rep_ins, 'rls41v3-a-ret'), format(rep_submit, 'rls41v3-a-ret'), as_admin_aal1,
               format('select %s', format(moderate, format('(select pr.id from public.product_proposals pr where pr.product_id = %L and pr.proposal_kind = %L)', 'rls41v3-a-ret', 'republish'), 'approve', null, '1'))],
         'exec', '42501[aal2_required]'),
      ('A04 autoaprobación: admin de la propia empresa → 42501[self_moderation_forbidden] (N6)', 'authenticated', v_sup::text, 'aal1', base || v_admin_sup,
         array[format(rep_ins, 'rls41v3-a-ret'), format(rep_submit, 'rls41v3-a-ret'), as_sup_aal2,
               format('select %s', format(moderate, format(rep_id, 'rls41v3-a-ret'), 'approve', null, '1'))], 'exec', '42501[self_moderation_forbidden]'),
      ('A05 conflicto de producto tras el envío → snapshot_conflict auditado; nada se publica (N7)', 'authenticated', v_sup::text, 'aal1', base,
         array[format(rep_ins, 'rls41v3-a-ret'), format(rep_submit, 'rls41v3-a-ret'), 'reset role',
               'update public.products set name = ''Nombre cambiado 41 V3'' where id = ''rls41v3-a-ret''', 'set local role authenticated', as_admin,
               format(save, format(moderate, format(rep_id, 'rls41v3-a-ret'), 'approve', null, '1')), 'reset role',
               format('select count(*) where %s ->> %L = %L and (select publication_status from public.products where id = %L) = %L'
                      || ' and (select status from public.product_proposals where product_id = %L and proposal_kind = %L) = %L'
                      || ' and exists (select 1 from public.proposal_events e join public.product_proposals pr on pr.id = e.proposal_id'
                      || '             where pr.product_id = %L and e.payload ->> %L = %L)'
                      || ' and not exists (select 1 from mobau_private.product_lifecycle_events where action = %L)',
                      res, 'code', 'snapshot_conflict', 'rls41v3-a-ret', 'archived', 'rls41v3-a-ret', 'republish', 'submitted',
                      'rls41v3-a-ret', 'type', 'snapshot_conflict', 'republish')], 'count', '1'),
      ('A06 conflicto de precio tras el envío → snapshot_conflict con campo price (N7)', 'authenticated', v_sup::text, 'aal1', base,
         array[format(rep_ins, 'rls41v3-a-ret'), format(rep_submit, 'rls41v3-a-ret'), 'reset role',
               'update public.product_prices set price_amount = 61 where product_id = ''rls41v3-a-ret''', 'set local role authenticated', as_admin,
               format(save, format(moderate, format(rep_id, 'rls41v3-a-ret'), 'approve', null, '1')), 'reset role',
               format('select count(*) where %s ->> %L = %L and exists (select 1 from jsonb_array_elements(%s -> %L) c where c ->> %L = %L)'
                      || ' and (select publication_status from public.products where id = %L) = %L',
                      res, 'code', 'snapshot_conflict', res, 'conflicts', 'field', 'price', 'rls41v3-a-ret', 'archived')], 'count', '1'),
      ('A07 el producto ya no está retirado al aprobar (papelera) → 55000[republish_requires_retired]', 'authenticated', v_sup::text, 'aal1', base,
         array[format(rep_ins, 'rls41v3-a-ret'), format(rep_submit, 'rls41v3-a-ret'), 'reset role',
               'update public.products set trashed_at = now(), trashed_by = ''' || v_sup || ''', trash_from = ''retired'', purge_after = now() + interval ''30 days'' where id = ''rls41v3-a-ret''',
               'set local role authenticated', as_admin,
               format('select %s', format(moderate, format(rep_id, 'rls41v3-a-ret'), 'approve', null, '1'))], 'exec', '55000[republish_requires_retired]'),
      ('A08 versión distinta → version_conflict (como en update), sin publicar', 'authenticated', v_sup::text, 'aal1', base,
         array[format(rep_ins, 'rls41v3-a-ret'), format(rep_submit, 'rls41v3-a-ret'), as_admin,
               format(save, format(moderate, format(rep_id, 'rls41v3-a-ret'), 'approve', null, '2')), 'reset role',
               format('select count(*) where %s ->> %L = %L and (select publication_status from public.products where id = %L) = %L',
                      res, 'code', 'version_conflict', 'rls41v3-a-ret', 'archived')], 'count', '1'),
      -- ========== T5 · rechazar / solicitar cambios ==========
      ('C01 rechazar: rejected, el producto sigue retirado y sin evento de ciclo de vida', 'authenticated', v_sup::text, 'aal1', base,
         array[format(rep_ins, 'rls41v3-a-ret'), format(rep_submit, 'rls41v3-a-ret'), as_admin,
               format('select %s', format(moderate, format(rep_id, 'rls41v3-a-ret'), 'reject', 'Motivo de rechazo 41 V3', '1')), 'reset role',
               format('select count(*) from public.products p where p.id = %L and p.publication_status = %L and p.retired_at is not null'
                      || ' and (select status from public.product_proposals where product_id = p.id and proposal_kind = %L) = %L'
                      || ' and not exists (select 1 from mobau_private.product_lifecycle_events)',
                      'rls41v3-a-ret', 'archived', 'republish', 'rejected')], 'count', '1'),
      ('C02 solicitar cambios y reenviar: submitted con versión 2 (la puerta vuelve a comprobar el estado)', 'authenticated', v_sup::text, 'aal1', base,
         array[format(rep_ins, 'rls41v3-a-ret'), format(rep_submit, 'rls41v3-a-ret'), as_admin,
               format('select %s', format(moderate, format(rep_id, 'rls41v3-a-ret'), 'request_changes', 'Revisa 41 V3', '1')),
               format('select set_config(%L, %L, true), set_config(%L, %L, true)', 'request.jwt.claims',
                      json_build_object('sub', v_sup, 'role', 'authenticated', 'aal', 'aal1')::text, 'request.jwt.claim.sub', v_sup),
               format(rep_submit, 'rls41v3-a-ret'), 'reset role',
               format('select count(*) from public.product_proposals where product_id = %L and proposal_kind = %L and status = %L and version = 2',
                      'rls41v3-a-ret', 'republish', 'submitted')], 'count', '1'),
      -- ========== regresiones: update y create no cambian ==========
      ('G01 update de A aprobada: cambia solo el nombre y sigue publicado', 'authenticated', v_sup::text, 'aal1', base,
         array['insert into public.product_proposals (proposal_kind, product_id, proposed_changes) values (''update'', ''rls41v3-a-pub'', ''{"name": "Nombre aprobado 41 V3"}'')',
               'update public.product_proposals set status = ''submitted'' where product_id = ''rls41v3-a-pub'' and proposal_kind = ''update''', as_admin,
               format('select %s', format(moderate, '(select pr.id from public.product_proposals pr where pr.product_id = ''rls41v3-a-pub'' and pr.proposal_kind = ''update'')', 'approve', null, '1')),
               'reset role',
               'select count(*) from public.products where id = ''rls41v3-a-pub'' and name = ''Nombre aprobado 41 V3'' and publication_status = ''published'' and retired_at is null'], 'count', '1'),
      ('G02 create de A aprobada: producto nuevo publicado (40-01)', 'authenticated', v_sup::text, 'aal1', base,
         array[format('insert into public.product_proposals (proposal_kind, proposed_changes) values (%L, %L)', 'create',
                      json_build_object('name', 'Nuevo 41 V3 republish', 'description', 'Descripción 41 V3', 'category_id', v_cat1,
                                        'subcategory', v_sub1, 'availability', 'por-confirmar')::text),
               'update public.product_proposals set status = ''submitted'' where proposal_kind = ''create'' and proposed_changes ->> ''name'' = ''Nuevo 41 V3 republish''', as_admin,
               format(save, format(moderate, '(select pr.id from public.product_proposals pr where pr.proposal_kind = ''create'' and pr.proposed_changes ->> ''name'' = ''Nuevo 41 V3 republish'')', 'approve', null, '1')),
               'reset role',
               format('select count(*) from public.products where id = %s ->> %L and publication_status = %L and retired_at is null', res, 'created_product_id', 'published')], 'count', '1'),
      ('G03 tipo desconocido sigue rechazado (23514)', 'authenticated', v_sup::text, 'aal1', base,
         array['insert into public.product_proposals (proposal_kind, product_id, proposed_changes) values (''otro'', ''rls41v3-a-ret'', ''{}'')'], 'exec', '23514'),
      -- ========== estado tras la suite ==========
      ('Z01 fuera de los casos: apagado, sin republish, sin eventos, sin restos', '-', null, null, null::text[],
         array['select count(*) where not mobau_private.product_lifecycle_enabled()'
               || ' and not exists (select 1 from public.product_proposals where proposal_kind = ''republish'')'
               || ' and not exists (select 1 from mobau_private.product_lifecycle_events)'
               || ' and not exists (select 1 from public.products where id like ''rls41v3%'' or name = ''Nuevo 41 V3 republish'')'], 'count', '1')
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

  raise exception 'MOBAU_41_04_REPUBLISH total=% ok=% fallos=% :: %', n_total, n_ok, n_total - n_ok, r::text
    using errcode = 'MB999';
end $$;

ROLLBACK;
