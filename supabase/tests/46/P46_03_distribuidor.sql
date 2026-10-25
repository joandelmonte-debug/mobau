DO $$
declare
  r text := '';
  ok int := 0; ko int := 0;
  g uuid; p uuid; v text; d text;
  m_same jsonb; m_changed jsonb; m_foreign jsonb;
  claims text := '{"sub":"392a9eb4-254d-423b-baae-bbeba928b02b","role":"authenticated"}';
begin
  -- Fixtures sintéticos (administración)
  insert into public.products (id, name, distributor_id, category_id, publication_status, catalog_role) values
    ('z46d-root',  'Z46D raíz',       'spectro', 'iluminacion', 'published', 'principal'),
    ('z46d-comp',  'Z46D componente', 'spectro', 'iluminacion', 'published', 'componente'),
    ('z46d-other', 'Z46D ajeno',      'charo',   'iluminacion', 'published', 'componente');
  insert into public.product_component_groups (product_id, code, label, requirement, choice) values ('z46d-root', 'fuente', 'Fuente', 'necesario', 'una') returning id into g;
  insert into public.product_component_options (group_id, code, kind, component_product_id, supply, quantity, quantity_mode) values (g, 'comp', 'componente', 'z46d-comp', 'aparte', 1, 'fija');
  set constraints all immediate; set constraints all deferred;
  m_same := mobau_private.component_structure_of('z46d-root') - 'catalog_role';
  m_changed := pg_catalog.jsonb_set(m_same, '{groups,0,options,0,quantity}', '2'::jsonb);
  m_foreign := '{"groups":[{"code":"g","label":"G","requirement":"opcional","choice":"una","options":[{"code":"o","kind":"componente","component":{"product_id":"z46d-other"},"supply":"aparte","quantity":1,"quantity_mode":"fija"}]}]}';

  -- R1 alta de borrador con proposed_components (permiso por columna + RLS)
  begin
    perform set_config('request.jwt.claims', claims, true);
    perform set_config('request.jwt.claim.sub', '392a9eb4-254d-423b-baae-bbeba928b02b', true);
    execute 'set local role authenticated';
    insert into public.product_proposals (proposal_kind, product_id, proposed_components) values ('update', 'z46d-root', m_same) returning id into p;
    select distributor_id || '/' || status into v from public.product_proposals where id = p;
    execute 'reset role';
    if v = 'spectro/draft' then r := r || E'\n[OK] R1 borrador con componentes creado como distribuidor (spectro/draft)'; ok := ok + 1;
    else r := r || E'\n[FALLO] R1 estado inesperado: ' || coalesce(v, '∅'); ko := ko + 1; end if;
  exception when others then r := r || E'\n[FALLO] R1: ' || left(sqlerrm, 160); ko := ko + 1;
  end;

  -- R2 editar el borrador (update por columna)
  begin
    execute 'set local role authenticated';
    update public.product_proposals set proposed_components = m_changed where id = p;
    update public.product_proposals set proposed_components = m_same where id = p;
    get diagnostics v = row_count;
    execute 'reset role';
    if v = '1' then r := r || E'\n[OK] R2 borrador editado como distribuidor'; ok := ok + 1;
    else r := r || E'\n[FALLO] R2 filas: ' || v; ko := ko + 1; end if;
  exception when others then r := r || E'\n[FALLO] R2: ' || left(sqlerrm, 160); ko := ko + 1;
  end;

  -- R3 referencia a otra empresa: mensaje genérico
  begin
    execute 'set local role authenticated';
    update public.product_proposals set proposed_components = m_foreign where id = p;
    execute 'reset role';
    r := r || E'\n[FALLO] R3 referencia ajena aceptada'; ko := ko + 1; raise exception 'deshacer';
  exception when others then
    if sqlerrm = 'deshacer' then null;
    elsif sqlerrm = 'Algún componente no existe o no es de tu empresa.' then r := r || E'\n[OK] R3 referencia a otra empresa: mensaje genérico'; ok := ok + 1;
    else r := r || E'\n[FALLO] R3 otro motivo: ' || left(sqlerrm, 160); ko := ko + 1; end if;
  end;

  -- R4 enviar con manifiesto idéntico al estado actual
  begin
    execute 'set local role authenticated';
    update public.product_proposals set status = 'submitted' where id = p;
    execute 'reset role';
    r := r || E'\n[FALLO] R4 manifiesto idéntico enviado'; ko := ko + 1; raise exception 'deshacer';
  exception when others then
    if sqlerrm = 'deshacer' then null;
    elsif sqlerrm = 'La propuesta no contiene ningún cambio.' then r := r || E'\n[OK] R4 manifiesto idéntico: «La propuesta no contiene ningún cambio.»'; ok := ok + 1;
    else r := r || E'\n[FALLO] R4 otro motivo: ' || left(sqlerrm, 160); ko := ko + 1; end if;
  end;

  -- R5 enviar con un cambio solo de componentes
  begin
    execute 'set local role authenticated';
    update public.product_proposals set proposed_components = m_changed where id = p;
    update public.product_proposals set status = 'submitted' where id = p;
    select status into v from public.product_proposals where id = p;
    execute 'reset role';
    if v = 'submitted' and (select product_snapshot ? 'components' from public.product_proposals where id = p) then
      r := r || E'\n[OK] R5 cambio solo de componentes enviado (copia de estructura guardada)'; ok := ok + 1;
    else r := r || E'\n[FALLO] R5 estado: ' || coalesce(v, '∅'); ko := ko + 1; end if;
  exception when others then r := r || E'\n[FALLO] R5: ' || left(sqlerrm, 160); ko := ko + 1;
  end;

  -- R6 editar componentes de una propuesta enviada
  begin
    execute 'set local role authenticated';
    update public.product_proposals set proposed_components = m_same where id = p;
    execute 'reset role';
    r := r || E'\n[FALLO] R6 edición tras enviar aceptada'; ko := ko + 1; raise exception 'deshacer';
  exception when others then
    if sqlerrm = 'deshacer' then null;
    elsif position('ya no se puede editar' in sqlerrm) > 0 then r := r || E'\n[OK] R6 edición tras enviar rechazada: ' || sqlerrm; ok := ok + 1;
    else r := r || E'\n[FALLO] R6 otro motivo: ' || left(sqlerrm, 160); ko := ko + 1; end if;
  end;

  -- R7 autoaprobación
  begin
    execute 'set local role authenticated';
    update public.product_proposals set status = 'approved' where id = p;
    execute 'reset role';
    r := r || E'\n[FALLO] R7 autoaprobación aceptada'; ko := ko + 1; raise exception 'deshacer';
  exception when others then
    if sqlerrm = 'deshacer' then null;
    elsif sqlstate = '42501' then r := r || E'\n[OK] R7 autoaprobación rechazada: ' || left(sqlerrm, 110); ok := ok + 1;
    else r := r || E'\n[FALLO] R7 otro motivo: ' || sqlstate || ' ' || left(sqlerrm, 160); ko := ko + 1; end if;
  end;
  if not exists (select 1 from public.product_component_options where group_id = g and quantity <> 1) then
    r := r || E'\n[OK] R8 estructura del producto sin cambios tras los intentos'; ok := ok + 1;
  else r := r || E'\n[FALLO] R8 la estructura cambió'; ko := ko + 1; end if;

  -- R9 escritura directa en grupos y opciones
  begin
    execute 'set local role authenticated';
    insert into public.product_component_groups (product_id, code, label, requirement, choice) values ('z46d-root', 'x', 'X', 'opcional', 'una');
    execute 'reset role';
    r := r || E'\n[FALLO] R9 alta directa de grupo aceptada'; ko := ko + 1; raise exception 'deshacer';
  exception when others then
    if sqlerrm = 'deshacer' then null;
    elsif sqlstate = '42501' then r := r || E'\n[OK] R9 alta directa de grupo: ' || left(sqlerrm, 90); ok := ok + 1;
    else r := r || E'\n[FALLO] R9 otro motivo: ' || sqlstate || ' ' || left(sqlerrm, 160); ko := ko + 1; end if;
  end;
  begin
    execute 'set local role authenticated';
    update public.product_component_options set quantity = 5 where group_id = g;
    execute 'reset role';
    r := r || E'\n[FALLO] R10 edición directa de opción aceptada'; ko := ko + 1; raise exception 'deshacer';
  exception when others then
    if sqlerrm = 'deshacer' then null;
    elsif sqlstate = '42501' then r := r || E'\n[OK] R10 edición directa de opción: ' || left(sqlerrm, 90); ok := ok + 1;
    else r := r || E'\n[FALLO] R10 otro motivo: ' || sqlstate || ' ' || left(sqlerrm, 160); ko := ko + 1; end if;
  end;

  -- R11 la empresa no se puede elegir al crear
  begin
    execute 'set local role authenticated';
    insert into public.product_proposals (proposal_kind, product_id, distributor_id, proposed_components) values ('update', 'z46d-root', 'charo', m_changed);
    execute 'reset role';
    r := r || E'\n[FALLO] R11 alta con empresa elegida aceptada'; ko := ko + 1; raise exception 'deshacer';
  exception when others then
    if sqlerrm = 'deshacer' then null;
    elsif sqlstate = '42501' then r := r || E'\n[OK] R11 empresa no elegible al crear: ' || left(sqlerrm, 90); ok := ok + 1;
    else r := r || E'\n[FALLO] R11 otro motivo: ' || sqlstate || ' ' || left(sqlerrm, 160); ko := ko + 1; end if;
  end;

  begin
    set constraints all immediate;
    r := r || E'\n[OK] Integridad diferida evaluada sin errores antes del cierre'; ok := ok + 1;
  exception when others then r := r || E'\n[FALLO] Integridad diferida al cierre: ' || sqlerrm; ko := ko + 1;
  end;

  raise exception 'CIERRE DELIBERADO PRUEBAS DISTRIBUIDOR 46-03 (todo revertido) · % correctos · % fallos inesperados%', ok, ko, r;
end $$;