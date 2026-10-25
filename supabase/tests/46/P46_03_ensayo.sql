-- ============================================================
-- ENSAYO 46-03 (solo después de aplicar 46-03). Todo se revierte: termina
-- SIEMPRE con una excepción deliberada que lleva el informe. Productos y
-- propuestas sintéticos z46b-*; se ejecuta como postgres (las reglas que
-- dependen de una sesión de distribuidor o de Mobau quedan fuera: ver informe).
-- ============================================================
DO $$
declare
  r text := '';
  ok int := 0; ko int := 0;
  p_pend uuid; p_ok uuid; p_upd uuid; v_id uuid; v_id2 uuid;
  v text; v_n int;
  base jsonb;

begin
  insert into public.products (id, name, distributor_id, category_id, publication_status, catalog_role) values
    ('z46b-root',  'Z46B raíz',          'spectro', 'iluminacion', 'published', 'principal'),
    ('z46b-comp',  'Z46B componente',    'spectro', 'iluminacion', 'published', 'componente'),
    ('z46b-sub',   'Z46B subcomponente', 'spectro', 'iluminacion', 'published', 'ambos'),
    ('z46b-x',     'Z46B cuarto',        'spectro', 'iluminacion', 'published', 'componente'),
    ('z46b-new',   'Z46B nuevo aprobado','spectro', 'iluminacion', 'published', 'componente'),
    ('z46b-other', 'Z46B ajeno',         'charo',   'iluminacion', 'published', 'componente'),
    ('z46b-princ', 'Z46B solo principal','spectro', 'iluminacion', 'published', 'principal');
  insert into public.product_finishes (product_id, code, name, is_default, sort_order) values ('z46b-comp', 'k1', 'Negro', true, 1);

  -- Altas de componentes: una en borrador y otra ya aprobada (insertada como aprobada).
  insert into public.product_proposals (proposal_kind, distributor_id, status, proposed_changes, proposed_components)
    values ('create', 'spectro', 'draft', '{"name":"Z46B alta pendiente"}', '{"catalog_role":"componente"}') returning id into p_pend;
  insert into public.product_proposals (proposal_kind, distributor_id, status, proposed_changes, proposed_components, created_product_id)
    values ('create', 'spectro', 'approved', '{"name":"Z46B alta aprobada"}', '{"catalog_role":"componente"}', 'z46b-new') returning id into p_ok;
  r := r || E'\n[OK] A1 altas de componente con proposed_components {catalog_role} guardadas'; ok := ok + 1;

  base := pg_catalog.jsonb_build_object('groups', pg_catalog.jsonb_build_array(
    pg_catalog.jsonb_build_object('code', 'fuente', 'label', 'Fuente de luz', 'requirement', 'necesario', 'choice', 'una', 'options', pg_catalog.jsonb_build_array(
      pg_catalog.jsonb_build_object('code', 'comp', 'kind', 'componente', 'component', pg_catalog.jsonb_build_object('product_id', 'z46b-comp'), 'finish_code', 'k1', 'supply', 'aparte', 'quantity', 1, 'quantity_mode', 'fija',
                                    'attributes', '[{"label":"Potencia","value":"12 W"}]'::jsonb),
      pg_catalog.jsonb_build_object('code', 'nuevo', 'kind', 'componente', 'component', pg_catalog.jsonb_build_object('proposal_id', p_pend), 'supply', 'aparte', 'quantity', 1, 'quantity_mode', 'fija'),
      pg_catalog.jsonb_build_object('code', 'calida', 'kind', 'ajuste', 'setting_label', 'Cálida'))),
    pg_catalog.jsonb_build_object('code', 'lente', 'label', 'Lente', 'requirement', 'opcional', 'choice', 'varias',
                                  'depends_on', pg_catalog.jsonb_build_object('group', 'fuente', 'option', 'comp'),
                                  'options', pg_catalog.jsonb_build_array(
      pg_catalog.jsonb_build_object('code', 'perfil', 'kind', 'componente', 'component', pg_catalog.jsonb_build_object('product_id', 'z46b-sub'), 'supply', 'incluido', 'quantity_mode', 'a_calcular')))));

  -- B · guardar un borrador de cambio con componentes y reabrirlo igual.
  insert into public.product_proposals (proposal_kind, product_id, distributor_id, status, proposed_components)
    values ('update', 'z46b-root', 'spectro', 'draft', base) returning id into p_upd;
  if (select proposed_components from public.product_proposals where id = p_upd) = base then
    r := r || E'\n[OK] B1 borrador guardado y reabierto con el mismo manifiesto (claves estables)'; ok := ok + 1;
  else r := r || E'\n[FALLO] B1 el manifiesto cambió al guardar'; ko := ko + 1; end if;

  -- C · rechazos al guardar (cada uno en su subtransacción).
  declare
    casos text[][] := array[
      array['C1 campo desconocido', '{"groups":[],"extra":1}', 'Campo no permitido'],
      array['C2 rol no válido', '{"catalog_role":"otro"}', 'principal, componente o ambos'],
      array['C3 componente de otra empresa', '{"groups":[{"code":"g","label":"G","requirement":"opcional","choice":"una","options":[{"code":"o","kind":"componente","component":{"product_id":"z46b-other"},"supply":"aparte","quantity":1,"quantity_mode":"fija"}]}]}', 'no existe o no es de tu empresa'],
      array['C4 componente inexistente (mismo mensaje)', '{"groups":[{"code":"g","label":"G","requirement":"opcional","choice":"una","options":[{"code":"o","kind":"componente","component":{"product_id":"no-existe"},"supply":"aparte","quantity":1,"quantity_mode":"fija"}]}]}', 'no existe o no es de tu empresa'],
      array['C5 grupos con la misma clave', '{"groups":[{"code":"g","label":"G","requirement":"opcional","choice":"una"},{"code":"G","label":"H","requirement":"opcional","choice":"una"}]}', 'misma clave'],
      array['C6 ajuste con suministro', '{"groups":[{"code":"g","label":"G","requirement":"opcional","choice":"una","options":[{"code":"o","kind":"ajuste","setting_label":"X","supply":"aparte"}]}]}', 'Un ajuste solo lleva'],
      array['C7 cantidad no numérica', '{"groups":[{"code":"g","label":"G","requirement":"opcional","choice":"una","options":[{"code":"o","kind":"componente","component":{"product_id":"z46b-comp"},"supply":"aparte","quantity":"dos","quantity_mode":"fija"}]}]}', 'mayor que 0'],
      array['C8 condición a opción inexistente', '{"groups":[{"code":"g","label":"G","requirement":"opcional","choice":"una","depends_on":{"group":"h","option":"z"}},{"code":"h","label":"H","requirement":"opcional","choice":"una"}]}', 'condición del grupo'],
      array['C9 condiciones en círculo', '{"groups":[{"code":"g","label":"G","requirement":"opcional","choice":"una","depends_on":{"group":"h","option":"b"},"options":[{"code":"a","kind":"ajuste","setting_label":"A"}]},{"code":"h","label":"H","requirement":"opcional","choice":"una","depends_on":{"group":"g","option":"a"},"options":[{"code":"b","kind":"ajuste","setting_label":"B"}]}]}', 'círculo'],
      array['C10 características no válidas', '{"groups":[{"code":"g","label":"G","requirement":"opcional","choice":"una","options":[{"code":"o","kind":"ajuste","setting_label":"X","attributes":["texto"]}]}]}', 'características']
    ];
    i int;
    msg_c3 text; msg_c4 text;
  begin
    for i in 1 .. array_length(casos, 1) loop
      begin
        update public.product_proposals set proposed_components = casos[i][2]::jsonb where id = p_upd;
        r := r || E'\n[FALLO] ' || casos[i][1] || ': se aceptó'; ko := ko + 1;
        raise exception 'deshacer';
      exception when others then
        if sqlerrm = 'deshacer' then null;
        elsif position(casos[i][3] in sqlerrm) > 0 then
          r := r || E'\n[OK] ' || casos[i][1] || ' rechazado: ' || left(sqlerrm, 110); ok := ok + 1;
          if i = 3 then msg_c3 := sqlerrm; elsif i = 4 then msg_c4 := sqlerrm; end if;
        else r := r || E'\n[FALLO] ' || casos[i][1] || ' por otro motivo: ' || left(sqlerrm, 150); ko := ko + 1; end if;
      end;
    end loop;
    if msg_c3 = msg_c4 then r := r || E'\n[OK] C11 «ajeno» e «inexistente» dan el mismo mensaje (sin filtrar datos)'; ok := ok + 1;
    else r := r || E'\n[FALLO] C11 mensajes distintos: ' || coalesce(msg_c3, '∅') || ' / ' || coalesce(msg_c4, '∅'); ko := ko + 1; end if;
  end;
  begin
    insert into public.product_proposals (proposal_kind, product_id, distributor_id, status, proposed_components)
      values ('republish', 'z46b-root', 'spectro', 'draft', '{"groups":[]}');
    r := r || E'\n[FALLO] C12 republicación con componentes aceptada'; ko := ko + 1; raise exception 'deshacer';
  exception when others then
    if sqlerrm = 'deshacer' then null;
    elsif position('republicación no lleva componentes' in sqlerrm) > 0 or position('retirado' in sqlerrm) > 0 then r := r || E'\n[OK] C12 republicación con componentes rechazada: ' || left(sqlerrm, 90); ok := ok + 1;
    else r := r || E'\n[FALLO] C12 otro motivo: ' || left(sqlerrm, 150); ko := ko + 1; end if;
  end;

  -- D · al enviar.
  begin
    update public.product_proposals set proposed_components = '{"groups":[{"code":"g","label":"G","requirement":"necesario","choice":"una"}]}', status = 'submitted' where id = p_upd;
    r := r || E'\n[FALLO] D1 grupo necesario vacío enviado'; ko := ko + 1; raise exception 'deshacer';
  exception when others then
    if sqlerrm = 'deshacer' then null;
    elsif position('no tiene opciones' in sqlerrm) > 0 then r := r || E'\n[OK] D1 grupo necesario sin opciones rechazado al enviar'; ok := ok + 1;
    else r := r || E'\n[FALLO] D1 otro motivo: ' || left(sqlerrm, 150); ko := ko + 1; end if;
  end;
  begin
    update public.product_proposals set proposed_components = '{"groups":[{"code":"g","label":"G","requirement":"opcional","choice":"una","options":[{"code":"o","kind":"componente","component":{"product_id":"z46b-princ"},"supply":"aparte","quantity":1,"quantity_mode":"fija"}]}]}', status = 'submitted' where id = p_upd;
    r := r || E'\n[FALLO] D2 artículo solo principal enviado'; ko := ko + 1; raise exception 'deshacer';
  exception when others then
    if sqlerrm = 'deshacer' then null;
    elsif position('no está clasificado' in sqlerrm) > 0 then r := r || E'\n[OK] D2 artículo solo principal rechazado al enviar'; ok := ok + 1;
    else r := r || E'\n[FALLO] D2 otro motivo: ' || left(sqlerrm, 150); ko := ko + 1; end if;
  end;
  begin
    -- Estructura existente comp → sub → x (válida: 3 niveles desde comp). Enviar raíz → comp daría 4.
    insert into public.product_component_groups (product_id, code, label, requirement, choice) values ('z46b-comp', 'drv', 'Driver', 'opcional', 'una') returning id into v_id;
    insert into public.product_component_options (group_id, code, kind, component_product_id, supply, quantity, quantity_mode) values (v_id, 'd', 'componente', 'z46b-sub', 'aparte', 1, 'fija');
    insert into public.product_component_groups (product_id, code, label, requirement, choice) values ('z46b-sub', 'acc', 'Acc', 'opcional', 'una') returning id into v_id2;
    insert into public.product_component_options (group_id, code, kind, component_product_id, supply, quantity, quantity_mode) values (v_id2, 'x', 'componente', 'z46b-x', 'aparte', 1, 'fija');
    update public.product_proposals set status = 'submitted' where id = p_upd;
    r := r || E'\n[FALLO] D3 cuarto nivel enviado'; ko := ko + 1; raise exception 'deshacer';
  exception when others then
    if sqlerrm = 'deshacer' then null;
    elsif position('más de tres niveles' in sqlerrm) > 0 then r := r || E'\n[OK] D3 cuarto nivel detectado al enviar (con la estructura actual + manifiesto)'; ok := ok + 1;
    else r := r || E'\n[FALLO] D3 otro motivo: ' || left(sqlerrm, 150); ko := ko + 1; end if;
  end;

  update public.product_proposals set status = 'submitted' where id = p_upd;
  if (select product_snapshot ? 'components' from public.product_proposals where id = p_upd) then
    r := r || E'\n[OK] D4 enviado con alta pendiente referenciada; copia de la estructura actual guardada'; ok := ok + 1;
  else r := r || E'\n[FALLO] D4 sin copia de componentes'; ko := ko + 1; end if;

  -- E · aprobar.
  begin
    update public.product_proposals set status = 'approved' where id = p_upd;
    r := r || E'\n[FALLO] E1 aprobado con el componente nuevo sin aprobar'; ko := ko + 1; raise exception 'deshacer';
  exception when others then
    if sqlerrm = 'deshacer' then null;
    elsif position('aprueba su componente nuevo' in sqlerrm) > 0 then r := r || E'\n[OK] E1 aprobación bloqueada hasta aprobar el componente nuevo'; ok := ok + 1;
    else r := r || E'\n[FALLO] E1 otro motivo: ' || left(sqlerrm, 150); ko := ko + 1; end if;
  end;
  if not exists (select 1 from public.product_component_groups where product_id = 'z46b-root') then
    r := r || E'\n[OK] E2 aprobación fallida sin escritura parcial'; ok := ok + 1;
  else r := r || E'\n[FALLO] E2 quedó escritura parcial'; ko := ko + 1; end if;

  update public.product_proposals set status = 'changes_requested' where id = p_upd;
  update public.product_proposals
     set proposed_components = pg_catalog.jsonb_set(base, '{groups,0,options,1,component}', pg_catalog.jsonb_build_object('proposal_id', p_ok))
   where id = p_upd;
  update public.product_proposals set status = 'submitted' where id = p_upd;
  begin
    update public.product_proposals set status = 'approved' where id = p_upd;
    set constraints all immediate;
    set constraints all deferred;
    select id into v_id from public.product_component_options o
     where o.code = 'comp' and o.group_id = (select id from public.product_component_groups where product_id = 'z46b-root' and code = 'fuente');
    if (select count(*) from public.product_component_groups where product_id = 'z46b-root' and status = 'activo') = 2
       and (select component_product_id from public.product_component_options o join public.product_component_groups g on g.id = o.group_id
             where g.product_id = 'z46b-root' and o.code = 'nuevo') = 'z46b-new'
       and (select depends_on_option_id from public.product_component_groups where product_id = 'z46b-root' and code = 'lente') = v_id
       and (select catalog_role from public.products where id = 'z46b-root') = 'principal' then
      r := r || E'\n[OK] E3 aprobado: 2 grupos, alta resuelta a su producto, condición por claves, rol sin cambios'; ok := ok + 1;
    else r := r || E'\n[FALLO] E3 resultado inesperado'; ko := ko + 1; end if;
  exception when others then r := r || E'\n[FALLO] E3 aprobación: ' || left(sqlerrm, 160); ko := ko + 1; set constraints all deferred;
  end;

  -- F · segunda propuesta: quitar «lente» y «calida», cambiar la cantidad de «comp» (misma clave).
  insert into public.product_proposals (proposal_kind, product_id, distributor_id, status, proposed_components)
    values ('update', 'z46b-root', 'spectro', 'draft', mobau_private.component_structure_of('z46b-root') - 'catalog_role') returning id into p_upd;
  update public.product_proposals
     set proposed_components = pg_catalog.jsonb_build_object('groups', pg_catalog.jsonb_build_array(
           pg_catalog.jsonb_set(pg_catalog.jsonb_set(proposed_components -> 'groups' -> 0, '{options}',
             (select pg_catalog.jsonb_agg(x) from pg_catalog.jsonb_array_elements(proposed_components -> 'groups' -> 0 -> 'options') x where x ->> 'code' <> 'calida')),
             '{options,0,quantity}', '2'::jsonb)))
   where id = p_upd;
  update public.product_proposals set status = 'submitted' where id = p_upd;
  begin
    update public.product_proposals set status = 'approved' where id = p_upd;
    set constraints all immediate;
    set constraints all deferred;
    if (select status from public.product_component_groups where product_id = 'z46b-root' and code = 'lente') = 'retirado'
       and (select o.status from public.product_component_options o join public.product_component_groups g on g.id = o.group_id where g.product_id = 'z46b-root' and o.code = 'calida') = 'retirado'
       and (select quantity from public.product_component_options where id = v_id) = 2
       and (select count(*) from public.product_component_options o join public.product_component_groups g on g.id = o.group_id where g.product_id = 'z46b-root') = 4 then
      r := r || E'\n[OK] F1 lo quitado se retira (no se borra) y «comp» conserva su id con la cantidad nueva'; ok := ok + 1;
    else r := r || E'\n[FALLO] F1 resultado inesperado'; ko := ko + 1; end if;
  exception when others then r := r || E'\n[FALLO] F1: ' || left(sqlerrm, 160); ko := ko + 1; set constraints all deferred;
  end;

  -- N · «sin cambios»: manifiesto presente pero idéntico al estado actual.
  begin
    insert into public.product_proposals (proposal_kind, product_id, distributor_id, status, proposed_components)
      values ('update', 'z46b-root', 'spectro', 'draft', mobau_private.component_structure_of('z46b-root') - 'catalog_role') returning id into v_id2;
    update public.product_proposals set status = 'submitted' where id = v_id2;
    r := r || E'\n[FALLO] N1 grupos idénticos enviados como cambio'; ko := ko + 1; raise exception 'deshacer';
  exception when others then
    if sqlerrm = 'deshacer' then null;
    elsif position('no contiene ningún cambio' in sqlerrm) > 0 then r := r || E'\n[OK] N1 grupos idénticos al estado actual: «sin cambios»'; ok := ok + 1;
    else r := r || E'\n[FALLO] N1 otro motivo: ' || left(sqlerrm, 150); ko := ko + 1; end if;
  end;
  begin
    insert into public.product_proposals (proposal_kind, product_id, distributor_id, status, proposed_components)
      values ('update', 'z46b-root', 'spectro', 'draft', '{"catalog_role":"principal"}') returning id into v_id2;
    update public.product_proposals set status = 'submitted' where id = v_id2;
    r := r || E'\n[FALLO] N2 rol idéntico enviado como cambio'; ko := ko + 1; raise exception 'deshacer';
  exception when others then
    if sqlerrm = 'deshacer' then null;
    elsif position('no contiene ningún cambio' in sqlerrm) > 0 then r := r || E'\n[OK] N2 rol idéntico al actual: «sin cambios»'; ok := ok + 1;
    else r := r || E'\n[FALLO] N2 otro motivo: ' || left(sqlerrm, 150); ko := ko + 1; end if;
  end;

  -- G · misma clave apuntando a otro artículo → rechazo atómico.
  insert into public.product_proposals (proposal_kind, product_id, distributor_id, status, proposed_components)
    values ('update', 'z46b-root', 'spectro', 'submitted',
            pg_catalog.jsonb_build_object('groups', pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object('code', 'fuente', 'label', 'Fuente de luz', 'requirement', 'necesario', 'choice', 'una',
              'options', pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object('code', 'comp', 'kind', 'componente', 'component', pg_catalog.jsonb_build_object('product_id', 'z46b-sub'), 'supply', 'aparte', 'quantity', 1, 'quantity_mode', 'fija'))))))
    returning id into p_upd;
  begin
    update public.product_proposals set status = 'approved' where id = p_upd;
    r := r || E'\n[FALLO] G1 cambio de artículo bajo la misma clave aceptado'; ko := ko + 1; raise exception 'deshacer';
  exception when others then
    if sqlerrm = 'deshacer' then null;
    elsif position('cambió de artículo' in sqlerrm) > 0 then r := r || E'\n[OK] G1 cambio de artículo bajo la misma clave rechazado'; ok := ok + 1;
    else r := r || E'\n[FALLO] G1 otro motivo: ' || left(sqlerrm, 150); ko := ko + 1; end if;
  end;
  update public.product_proposals set status = 'withdrawn' where id = p_upd;

  -- H · conflicto: la estructura cambia después del envío.
  insert into public.product_proposals (proposal_kind, product_id, distributor_id, status, proposed_components)
    values ('update', 'z46b-root', 'spectro', 'draft', '{"catalog_role":"ambos"}') returning id into p_upd;
  update public.product_proposals set status = 'submitted' where id = p_upd;
  update public.product_component_groups set label = 'Fuente (cambiada)' where product_id = 'z46b-root' and code = 'fuente';
  begin
    update public.product_proposals set status = 'approved' where id = p_upd;
    r := r || E'\n[FALLO] H1 aprobado pese al conflicto'; ko := ko + 1; raise exception 'deshacer';
  exception when others then
    if sqlerrm = 'deshacer' then null;
    elsif position('cambiaron desde que se envió' in sqlerrm) > 0 then r := r || E'\n[OK] H1 conflicto detectado (la estructura cambió tras el envío)'; ok := ok + 1;
    else r := r || E'\n[FALLO] H1 otro motivo: ' || left(sqlerrm, 150); ko := ko + 1; end if;
  end;
  update public.product_component_groups set label = 'Fuente de luz' where product_id = 'z46b-root' and code = 'fuente';
  update public.product_proposals set status = 'withdrawn' where id = p_upd;

  -- I · ausencia, rol solo y vacío explícito.
  v := pg_catalog.md5(mobau_private.component_structure_of('z46b-root')::text);
  insert into public.product_proposals (proposal_kind, product_id, distributor_id, status, proposed_changes)
    values ('update', 'z46b-root', 'spectro', 'submitted', '{"description":"Cambio sin componentes para el ensayo."}') returning id into p_upd;
  update public.product_proposals set status = 'approved' where id = p_upd;
  if pg_catalog.md5(mobau_private.component_structure_of('z46b-root')::text) = v then
    r := r || E'\n[OK] I1 sin manifiesto (null): componentes sin cambios'; ok := ok + 1;
  else r := r || E'\n[FALLO] I1 cambió la estructura sin manifiesto'; ko := ko + 1; end if;

  insert into public.product_component_groups (product_id, code, label, requirement, choice) values ('z46b-sub', 'modo', 'Modo', 'opcional', 'una') returning id into v_id2;
  insert into public.product_component_options (group_id, code, kind, setting_label) values (v_id2, 'dali', 'ajuste', 'DALI');
  insert into public.product_proposals (proposal_kind, product_id, distributor_id, status, proposed_components)
    values ('update', 'z46b-sub', 'spectro', 'submitted', '{"catalog_role":"componente"}') returning id into p_upd;
  begin
    update public.product_proposals set status = 'approved' where id = p_upd;
    set constraints all immediate; set constraints all deferred;
    if (select catalog_role from public.products where id = 'z46b-sub') = 'componente'
       and (select count(*) from public.product_component_groups where product_id = 'z46b-sub' and status = 'activo') = 1 then
      r := r || E'\n[OK] I2 solo catalog_role: rol cambiado y grupos intactos'; ok := ok + 1;
    else r := r || E'\n[FALLO] I2 resultado inesperado'; ko := ko + 1; end if;
  exception when others then r := r || E'\n[FALLO] I2: ' || left(sqlerrm, 160); ko := ko + 1; set constraints all deferred;
  end;

  insert into public.product_proposals (proposal_kind, product_id, distributor_id, status, proposed_components)
    values ('update', 'z46b-root', 'spectro', 'submitted', '{"groups":[]}') returning id into p_upd;
  begin
    update public.product_proposals set status = 'approved' where id = p_upd;
    set constraints all immediate; set constraints all deferred;
    select count(*) into v_n from public.product_component_options o join public.product_component_groups g on g.id = o.group_id where g.product_id = 'z46b-root';
    if not exists (select 1 from public.product_component_groups where product_id = 'z46b-root' and status = 'activo') and v_n = 4 then
      r := r || E'\n[OK] I3 vacío explícito ({"groups":[]}): todos los grupos retirados, opciones conservadas'; ok := ok + 1;
    else r := r || E'\n[FALLO] I3 resultado inesperado'; ko := ko + 1; end if;
  exception when others then r := r || E'\n[FALLO] I3: ' || left(sqlerrm, 160); ko := ko + 1; set constraints all deferred;
  end;

  begin
    set constraints all immediate;
    r := r || E'\n[OK] Integridad diferida evaluada sin errores antes del cierre'; ok := ok + 1;
  exception when others then r := r || E'\n[FALLO] Integridad diferida al cierre: ' || sqlerrm; ko := ko + 1;
  end;

  r := r || E'\n[PENDIENTE] Reglas con sesión de distribuidor (permisos por columna, transición «sin cambios») y de Mobau (no modificar proposed_components al moderar, aprobación con moderate_product_proposal): necesitan identidades reales.';
  raise exception 'CIERRE DELIBERADO DEL ENSAYO 46-03 (todo revertido) · % correctos · % fallos inesperados%', ok, ko, r;
end $$;
