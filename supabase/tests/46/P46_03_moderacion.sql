-- ============================================================
-- Ensayo 46-03 · moderación de Mobau (rollback deliberado)
-- ============================================================
-- Identidad: el admin real a8fe42e8… como authenticated con sesión aal2
-- (sin cambiar permisos, credenciales ni datos). Productos, archivos y
-- propuestas sintéticos (z46m-*), preparados como postgres; las acciones
-- comprobadas se ejecutan con la identidad. Todo se deshace al final.
-- ============================================================
DO $$
declare
  r text := '';
  ok int := 0; ko int := 0;
  v_adm uuid; v_sup uuid;
  a1 uuid; a2 uuid; g uuid; pc uuid; pp uuid;
  m_pp jsonb; m_pc jsonb; v_res jsonb; v_x text; v_n int; v_ev int;
  v_spectro int;
  f text := '00000000-0000-4046-8000-000000004603';
begin
  if current_user <> 'postgres' then raise exception 'P46_03_M: ejecutar como postgres'; end if;
  select id into v_adm from public.profiles where id::text like 'a8fe42e8%' and role = 'admin';
  select id into v_sup from public.profiles where id::text like '392a9eb4%' and role = 'supplier';
  if v_adm is null or v_sup is null
     or not exists (select 1 from public.mobau_admins where user_id = v_adm and revoked_at is null)
     or exists (select 1 from public.distributor_profiles where user_id = v_adm and distributor_id = 'spectro') then
    raise exception 'P46_03_M: faltan identidades';
  end if;

  -- Fixtures sintéticos (administración)
  insert into public.products (id, name, distributor_id, category_id, publication_status, catalog_role, description) values
    ('z46m-root', 'Z46M raíz',       'spectro', 'iluminacion', 'published', 'principal',  'Original Z46M'),
    ('z46m-comp', 'Z46M componente', 'spectro', 'iluminacion', 'published', 'componente', null);
  insert into public.product_component_groups (product_id, code, label, requirement, choice) values ('z46m-root', 'fuente', 'Fuente', 'necesario', 'una') returning id into g;
  insert into public.product_component_options (group_id, code, kind, component_product_id, supply, quantity, quantity_mode) values (g, 'comp', 'componente', 'z46m-comp', 'aparte', 1, 'fija');
  insert into public.product_assets (distributor_id, kind, bucket, path, variants, original_name, format, bytes, width, height)
  values ('spectro', 'foto', 'productos-imagenes', 'spectro/' || f || '/raiz.jpg', jsonb_build_object('card', 'spectro/' || f || '/raiz-card.jpg'), 'raiz.jpg', 'jpg', 100000, 1600, 2000) returning id into a1;
  insert into public.product_assets (distributor_id, kind, bucket, path, variants, original_name, format, bytes, width, height)
  values ('spectro', 'foto', 'productos-imagenes', 'spectro/' || f || '/nuevo.jpg', jsonb_build_object('card', 'spectro/' || f || '/nuevo-card.jpg'), 'nuevo.jpg', 'jpg', 100000, 1600, 2000) returning id into a2;
  set constraints all immediate; set constraints all deferred;

  insert into public.product_proposals (proposal_kind, distributor_id, status, proposed_changes, proposed_price_status, proposed_media, proposed_components)
  values ('create', 'spectro', 'submitted',
          jsonb_build_object('name', 'Z46M componente nuevo', 'brand', 'Z46M', 'description', 'Componente nuevo del ensayo 46-03 (se deshace).',
                             'category_id', 'iluminacion', 'subcategory', 'Decorativa', 'availability', 'bajo-pedido',
                             'measurements', 'Ø 80 × 60 mm'),
          'quote_required',
          jsonb_build_object('reference_code', 'Z46M-NUEVO', 'cover_asset_id', a2, 'assets', jsonb_build_array(jsonb_build_object('id', a2))),
          '{"catalog_role":"componente"}')
  returning id into pc;
  insert into public.product_proposals (proposal_kind, product_id, distributor_id, status, proposed_changes, proposed_media, proposed_components)
  values ('update', 'z46m-root', 'spectro', 'draft',
          '{"description":"Descripción nueva Z46M"}',
          jsonb_build_object('reference_code', 'Z46M-RAIZ', 'cover_asset_id', a1, 'assets', jsonb_build_array(jsonb_build_object('id', a1))),
          jsonb_build_object('groups', jsonb_build_array(jsonb_build_object('code', 'fuente', 'label', 'Fuente', 'requirement', 'necesario', 'choice', 'una',
            'options', jsonb_build_array(
              jsonb_build_object('code', 'comp',  'kind', 'componente', 'component', jsonb_build_object('product_id', 'z46m-comp'), 'supply', 'aparte', 'quantity', 1, 'quantity_mode', 'fija'),
              jsonb_build_object('code', 'nuevo', 'kind', 'componente', 'component', jsonb_build_object('proposal_id', pc), 'supply', 'aparte', 'quantity', 2, 'quantity_mode', 'fija'))))))
  returning id into pp;
  -- Envío como transición (las copias del producto y de los componentes se toman al pasar a submitted).
  update public.product_proposals set status = 'submitted' where id = pp;
  select proposed_components into m_pp from public.product_proposals where id = pp;
  select proposed_components into m_pc from public.product_proposals where id = pc;
  select count(*) into v_spectro from public.products where distributor_id = 'spectro';

  perform set_config('request.jwt.claims', json_build_object('sub', v_adm, 'role', 'authenticated', 'aal', 'aal2')::text, true);
  perform set_config('request.jwt.claim.sub', v_adm::text, true);

  -- M1 Mobau no puede alterar proposed_components (escritura directa como admin)
  begin
    execute 'set local role authenticated';
    update public.product_proposals set proposed_components = '{"groups":[]}' where id in (pp, pc);
    get diagnostics v_n = row_count;
    execute 'reset role';
    if v_n = 0 and (select proposed_components from public.product_proposals where id = pp) = m_pp
       and (select proposed_components from public.product_proposals where id = pc) = m_pc then
      r := r || E'\n[OK] M1 admin no puede alterar proposed_components (0 filas, manifiestos intactos)'; ok := ok + 1;
    else r := r || E'\n[FALLO] M1 filas cambiadas: ' || v_n; ko := ko + 1; end if;
  exception when others then
    if sqlstate = '42501' then r := r || E'\n[OK] M1 admin no puede alterar proposed_components: ' || left(sqlerrm, 90); ok := ok + 1;
    else r := r || E'\n[FALLO] M1: ' || sqlstate || ' ' || left(sqlerrm, 160); ko := ko + 1; end if;
  end;

  -- M2 Aprobar el padre con el componente nuevo sin aprobar: bloqueado
  select count(*) into v_ev from public.proposal_events where proposal_id = pp;
  begin
    execute 'set local role authenticated';
    v_res := public.moderate_product_proposal(pp, 'approve', null, (select version from public.product_proposals where id = pp));
    execute 'reset role';
    r := r || E'\n[FALLO] M2 padre aprobado con el componente nuevo pendiente: ' || v_res::text; ko := ko + 1; raise exception 'deshacer';
  exception when others then
    if sqlerrm = 'deshacer' then null;
    elsif position('aprueba su componente nuevo' in sqlerrm) > 0 then r := r || E'\n[OK] M2 aprobación bloqueada: ' || left(sqlerrm, 120); ok := ok + 1;
    else r := r || E'\n[FALLO] M2 otro motivo: ' || sqlstate || ' ' || left(sqlerrm, 160); ko := ko + 1; end if;
  end;

  -- M3 El fallo revierte toda la aprobación (estado, producto, archivos, componentes, eventos)
  if (select status from public.product_proposals where id = pp) = 'submitted'
     and (select reviewed_by is null from public.product_proposals where id = pp)
     and (select description = 'Original Z46M' and reference_code is null and cover_asset_id is null from public.products where id = 'z46m-root')
     and (select status = 'pendiente' and product_id is null from public.product_assets where id = a1)
     and (select count(*) from public.product_component_groups where product_id = 'z46m-root') = 1
     and (select count(*) from public.product_component_options where group_id = g) = 1
     and (select quantity from public.product_component_options where group_id = g) = 1
     and (select count(*) from public.proposal_events where proposal_id = pp) = v_ev
     and not exists (select 1 from public.mobau_moderation_context where proposal_id = pp) then
    r := r || E'\n[OK] M3 fallo sin efectos: estado, producto, archivos, componentes y eventos intactos'; ok := ok + 1;
  else r := r || E'\n[FALLO] M3 quedó escritura parcial'; ko := ko + 1; end if;

  -- M4 Aprobar el componente nuevo con moderate_product_proposal
  begin
    execute 'set local role authenticated';
    v_res := public.moderate_product_proposal(pc, 'approve', null, (select version from public.product_proposals where id = pc));
    execute 'reset role';
    set constraints all immediate; set constraints all deferred;
    select created_product_id into v_x from public.product_proposals where id = pc;
    if v_res ->> 'result' = 'approved' and v_x is not null
       and (select catalog_role from public.products where id = v_x) = 'componente'
       and (select proposed_components from public.product_proposals where id = pc) = m_pc then
      r := r || E'\n[OK] M4 componente nuevo aprobado (' || v_x || ', componente; manifiesto sin alterar)'; ok := ok + 1;
    else r := r || E'\n[FALLO] M4 resultado inesperado: ' || coalesce(v_res::text, '∅'); ko := ko + 1; end if;
  exception when others then r := r || E'\n[FALLO] M4: ' || sqlstate || ' ' || left(sqlerrm, 160); ko := ko + 1;
  end;

  -- M5 Aprobar el padre: enlaza el producto creado sin duplicarlo
  begin
    execute 'set local role authenticated';
    v_res := public.moderate_product_proposal(pp, 'approve', null, (select version from public.product_proposals where id = pp));
    execute 'reset role';
    set constraints all immediate; set constraints all deferred;
    if v_res ->> 'result' = 'approved'
       and (select status from public.product_proposals where id = pp) = 'approved'
       and (select description = 'Descripción nueva Z46M' and reference_code = 'Z46M-RAIZ' and cover_asset_id = a1 from public.products where id = 'z46m-root')
       and (select status = 'aprobado' and product_id = 'z46m-root' from public.product_assets where id = a1)
       and (select o.component_product_id from public.product_component_options o where o.group_id = g and o.code = 'nuevo') = v_x
       and (select quantity from public.product_component_options where group_id = g and code = 'nuevo') = 2
       and (select o.id from public.product_component_options o where o.group_id = g and o.code = 'comp') is not null
       and (select count(*) from public.products where name = 'Z46M componente nuevo') = 1
       and (select count(*) from public.products where distributor_id = 'spectro') = v_spectro + 1
       and (select proposed_components from public.product_proposals where id = pp) = m_pp then
      r := r || E'\n[OK] M5 padre aprobado: enlaza ' || v_x || ' (1 solo producto creado), cambios y archivos aplicados, manifiesto sin alterar'; ok := ok + 1;
    else r := r || E'\n[FALLO] M5 resultado inesperado: ' || coalesce(v_res::text, '∅'); ko := ko + 1; end if;
  exception when others then r := r || E'\n[FALLO] M5: ' || sqlstate || ' ' || left(sqlerrm, 160); ko := ko + 1;
  end;

  begin
    set constraints all immediate;
    r := r || E'\n[OK] Integridad diferida evaluada sin errores antes del cierre'; ok := ok + 1;
  exception when others then r := r || E'\n[FALLO] Integridad diferida al cierre: ' || sqlerrm; ko := ko + 1;
  end;

  raise exception 'CIERRE DELIBERADO MODERACIÓN 46-03 (todo revertido) · % correctos · % fallos inesperados%', ok, ko, r;
end $$;
