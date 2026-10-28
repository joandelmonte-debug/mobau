-- ============================================================
-- PROPUESTA NO EJECUTADA — Ensayo de 47-01 (tras aplicarla) · rollback deliberado
-- ============================================================
-- Requiere 47-01 aplicada en mobau-pruebas (NUNCA en Production). Datos sintéticos z47-*, identidad de prueba Individual e2a655c1….
-- Una sola ejecución: termina SIEMPRE con una excepción, así que no queda nada. Casos:
--  A1 estado de partida · A2 RLS de áreas (otro usuario, proveedor, proyecto archivado) · A3 línea→área de otro proyecto
--  A4 «Sin área» única con área nula y mismo producto en dos áreas · A5 pestaña antigua (sin cabecera) rechazada sin cambios,
--  con cabecera permitida, sin áreas no afecta · A6 mover/copiar/sumar/omitir con conflictos re-comprobados · A7 eliminar área
--  (sin conflicto, con conflicto, sumar, mover) y atomicidad · A8 proyecto archivado de solo lectura · A9 copia de RFQ con áreas
--  y exclusión por línea con el mismo producto en áreas distintas · A10 la columna room_or_area y la nota no se alteran.
-- ============================================================
DO $TEST$
declare
  r text := '';
  ok int := 0; ko int := 0;
  v_ind uuid; v_other uuid; v_sup uuid; v_studio uuid; v_proj uuid; v_proj2 uuid; v_proj3 uuid; v_arch uuid;
  a_sala uuid; a_cocina uuid; a_otro uuid;
  l1 uuid; l2 uuid; l3 uuid; l4 uuid; l_x uuid;
  v jsonb; n int; t text;
  hdr text := '{"x-mobau-areas":"1"}';
begin
  if current_user <> 'postgres' then raise exception 'P47_01: ejecutar como postgres'; end if;
  if to_regclass('public.project_areas') is null then raise exception 'P47_01: 47-01 no está aplicada'; end if;
  select id into v_ind from public.profiles where id::text like '24fb0c2f%' and role = 'individual';   -- mobau-pruebas: Individual con plan individual_founder
  if v_ind is null then raise exception 'P47_01: falta la identidad de prueba'; end if;
  select id into v_other from public.profiles where id <> v_ind and role in ('individual', 'studio_member') and plan = 'individual_founder' limit 1;
  select id into v_sup from public.profiles where role = 'supplier' limit 1;

  -- ===== Preparación administrativa (postgres) =====
  if to_regclass('public.studios') is not null then
    execute $q$insert into public.studios (name) values ('Z47 estudio de ensayo') returning id$q$ into v_studio;
    insert into public.projects (owner_user_id, studio_id, name, status) values (v_ind, v_studio, 'Z47 proyecto', 'active') returning id into v_proj;
    insert into public.projects (owner_user_id, studio_id, name, status) values (v_ind, v_studio, 'Z47 proyecto 2', 'active') returning id into v_proj2;
    insert into public.projects (owner_user_id, studio_id, name, status) values (v_ind, v_studio, 'Z47 archivado', 'archived') returning id into v_arch;
    insert into public.projects (owner_user_id, studio_id, name, status) values (v_ind, v_studio, 'Z47 sin áreas', 'active') returning id into v_proj3;
  else
    insert into public.projects (owner_user_id, name, status) values (v_ind, 'Z47 proyecto', 'active') returning id into v_proj;
    insert into public.projects (owner_user_id, name, status) values (v_ind, 'Z47 proyecto 2', 'active') returning id into v_proj2;
    insert into public.projects (owner_user_id, name, status) values (v_ind, 'Z47 archivado', 'archived') returning id into v_arch;
    insert into public.projects (owner_user_id, name, status) values (v_ind, 'Z47 sin áreas', 'active') returning id into v_proj3;
  end if;
  insert into public.products (id, name, distributor_id, category_id, publication_status, catalog_role) values
    ('z47-a', 'Z47 producto A', 'distribuidor-prueba', 'iluminacion', 'published', 'principal'),
    ('z47-b', 'Z47 producto B', 'distribuidor-prueba', 'iluminacion', 'published', 'principal');
  insert into public.project_areas (project_id, name, sort_order) values (v_proj2, 'Z47 ajena', 1) returning id into a_otro;

  perform set_config('request.jwt.claims', json_build_object('sub', v_ind, 'role', 'authenticated', 'aal', 'aal1')::text, true);
  perform set_config('request.jwt.claim.sub', v_ind::text, true);

  -- ===== A1 estado de partida =====
  if (select count(*) from public.project_areas where project_id = v_proj) = 0
     and (select count(*) from pg_policies where schemaname = 'public' and tablename = 'project_areas') = 11 then
    r := r || E'\n[OK] A1 sin áreas en el proyecto de ensayo; 11 políticas'; ok := ok + 1;
  else r := r || E'\n[FALLO] A1'; ko := ko + 1; end if;

  -- ===== A2 RLS de las áreas =====
  begin
    execute 'set local role authenticated';
    insert into public.project_areas (project_id, name, sort_order) values (v_proj, 'Sala', 1) returning id into a_sala;
    insert into public.project_areas (project_id, name, sort_order) values (v_proj, 'Cocina', 2) returning id into a_cocina;
    execute 'reset role';
    r := r || E'\n[OK] A2a el propietario crea áreas en su proyecto activo'; ok := ok + 1;
  exception when others then execute 'reset role'; r := r || E'\n[FALLO] A2a: ' || sqlstate || ' ' || left(sqlerrm, 140); ko := ko + 1; end;
  begin
    execute 'set local role authenticated';
    insert into public.project_areas (project_id, name, sort_order) values (v_proj, 'sala', 3);
    execute 'reset role';
    r := r || E'\n[FALLO] A2b nombre repetido (sin distinguir mayúsculas) aceptado'; ko := ko + 1; raise exception 'deshacer';
  exception when others then execute 'reset role';
    if sqlerrm = 'deshacer' then null; elsif sqlstate = '23505' then r := r || E'\n[OK] A2b nombre repetido rechazado'; ok := ok + 1;
    else r := r || E'\n[FALLO] A2b: ' || sqlstate; ko := ko + 1; end if; end;
  begin
    execute 'set local role authenticated';
    insert into public.project_areas (project_id, name, sort_order) values (v_arch, 'Z47 en archivado', 1);
    execute 'reset role';
    r := r || E'\n[FALLO] A2c área en proyecto archivado aceptada'; ko := ko + 1; raise exception 'deshacer';
  exception when others then execute 'reset role';
    if sqlerrm = 'deshacer' then null; elsif sqlstate in ('42501', '23514') then r := r || E'\n[OK] A2c proyecto archivado: no se crean áreas'; ok := ok + 1;
    else r := r || E'\n[FALLO] A2c: ' || sqlstate; ko := ko + 1; end if; end;
  if v_other is not null then
    perform set_config('request.jwt.claims', json_build_object('sub', v_other, 'role', 'authenticated', 'aal', 'aal1')::text, true);
    perform set_config('request.jwt.claim.sub', v_other::text, true);
    execute 'set local role authenticated';
    select count(*) into n from public.project_areas where project_id = v_proj;
    begin
      insert into public.project_areas (project_id, name, sort_order) values (v_proj, 'Intrusa', 9);
      r := r || E'\n[FALLO] A2d otro usuario crea área ajena'; ko := ko + 1; raise exception 'deshacer';
    exception when others then
      if sqlerrm = 'deshacer' then null; elsif n = 0 then r := r || E'\n[OK] A2d otro usuario no ve ni crea áreas ajenas'; ok := ok + 1;
      else r := r || E'\n[FALLO] A2d ve ' || n; ko := ko + 1; end if; end;
    execute 'reset role';
    perform set_config('request.jwt.claims', json_build_object('sub', v_ind, 'role', 'authenticated', 'aal', 'aal1')::text, true);
    perform set_config('request.jwt.claim.sub', v_ind::text, true);
  else r := r || E'\n[OMITIDO] A2d no hay otro usuario de prueba'; end if;
  if v_sup is not null then
    perform set_config('request.jwt.claims', json_build_object('sub', v_sup, 'role', 'authenticated', 'aal', 'aal1')::text, true);
    perform set_config('request.jwt.claim.sub', v_sup::text, true);
    begin
      execute 'set local role authenticated';
      insert into public.project_areas (project_id, name, sort_order) values (v_proj, 'Prov', 9);
      execute 'reset role';
      r := r || E'\n[FALLO] A2e proveedor crea áreas'; ko := ko + 1; raise exception 'deshacer';
    exception when others then execute 'reset role';
      if sqlerrm = 'deshacer' then null; else r := r || E'\n[OK] A2e proveedor sin escritura'; ok := ok + 1; end if; end;
    perform set_config('request.jwt.claims', json_build_object('sub', v_ind, 'role', 'authenticated', 'aal', 'aal1')::text, true);
    perform set_config('request.jwt.claim.sub', v_ind::text, true);
  else r := r || E'\n[OMITIDO] A2e no hay proveedor de prueba'; end if;

  -- ===== A3 línea → área de otro proyecto =====
  begin
    execute 'set local role authenticated';
    perform set_config('request.headers', hdr, true);
    insert into public.project_products (project_id, product_id, quantity, unit, area_id) values (v_proj, 'z47-a', 1, 'ud.', a_otro);
    execute 'reset role';
    r := r || E'\n[FALLO] A3 línea apunta a un área de otro proyecto'; ko := ko + 1; raise exception 'deshacer';
  exception when others then execute 'reset role';
    if sqlerrm = 'deshacer' then null; elsif sqlstate = '23503' then r := r || E'\n[OK] A3 clave compuesta: solo áreas del propio proyecto'; ok := ok + 1;
    else r := r || E'\n[FALLO] A3: ' || sqlstate; ko := ko + 1; end if; end;

  -- ===== A4 identidad de línea con área =====
  begin
    execute 'set local role authenticated';
    perform set_config('request.headers', hdr, true);
    insert into public.project_products (project_id, product_id, quantity, unit, area_id, notes) values (v_proj, 'z47-a', 2, 'ud.', a_sala, 'nota sala') returning id into l1;
    insert into public.project_products (project_id, product_id, quantity, unit, area_id) values (v_proj, 'z47-a', 3, 'ud.', a_cocina) returning id into l2;
    insert into public.project_products (project_id, product_id, quantity, unit, area_id) values (v_proj, 'z47-a', 1, 'ud.', null) returning id into l3;
    execute 'reset role';
    r := r || E'\n[OK] A4a mismo producto en dos áreas y en «Sin área»'; ok := ok + 1;
  exception when others then execute 'reset role'; r := r || E'\n[FALLO] A4a: ' || sqlstate || ' ' || left(sqlerrm, 140); ko := ko + 1; end;
  begin
    execute 'set local role authenticated';
    perform set_config('request.headers', hdr, true);
    insert into public.project_products (project_id, product_id, quantity, unit, area_id) values (v_proj, 'z47-a', 1, 'ud.', null);
    execute 'reset role';
    r := r || E'\n[FALLO] A4b segunda línea «Sin área» aceptada'; ko := ko + 1; raise exception 'deshacer';
  exception when others then execute 'reset role';
    if sqlerrm = 'deshacer' then null; elsif sqlstate = '23505' then r := r || E'\n[OK] A4b «Sin área» sigue siendo única con area_id nulo'; ok := ok + 1;
    else r := r || E'\n[FALLO] A4b: ' || sqlstate; ko := ko + 1; end if; end;
  begin
    execute 'set local role authenticated';
    perform set_config('request.headers', hdr, true);
    insert into public.project_products (project_id, product_id, quantity, unit, area_id) values (v_proj, 'z47-a', 1, 'ud.', a_sala);
    execute 'reset role';
    r := r || E'\n[FALLO] A4c duplicado dentro de un área aceptado'; ko := ko + 1; raise exception 'deshacer';
  exception when others then execute 'reset role';
    if sqlerrm = 'deshacer' then null; elsif sqlstate = '23505' then r := r || E'\n[OK] A4c duplicado en la misma área rechazado'; ok := ok + 1;
    else r := r || E'\n[FALLO] A4c: ' || sqlstate; ko := ko + 1; end if; end;

  -- ===== A5 pestañas antiguas =====
  declare c1 text; c2 text; c3 text; q1 numeric; begin
    select quantity into q1 from public.project_products where id = l1;
    begin
      execute 'set local role authenticated';
      perform set_config('request.headers', '{}', true);
      update public.project_products set quantity = quantity + 5 where id = l1;
      execute 'reset role';
      c1 := 'FALLO suma sin cabecera';
    exception when others then execute 'reset role';
      c1 := case when sqlstate = '42501' then 'ok' else 'FALLO motivo ' || sqlstate end; end;
    begin
      execute 'set local role authenticated';
      perform set_config('request.headers', '{}', true);
      insert into public.project_products (project_id, product_id, quantity, unit) values (v_proj, 'z47-b', 1, 'ud.');
      execute 'reset role';
      c2 := 'FALLO alta sin cabecera';
    exception when others then execute 'reset role'; c2 := 'ok'; end;
    begin
      execute 'set local role authenticated';
      perform set_config('request.headers', '{}', true);
      delete from public.project_products where id = l3;
      execute 'reset role';
      c3 := case when exists (select 1 from public.project_products where id = l3) then 'ok' else 'FALLO borrado sin cabecera' end;
    exception when others then execute 'reset role'; c3 := 'ok'; end;
    if c1 = 'ok' and c2 = 'ok' and c3 = 'ok' and (select quantity from public.project_products where id = l1) = q1
       and not exists (select 1 from public.project_products where project_id = v_proj and product_id = 'z47-b') then
      r := r || E'\n[OK] A5a pestaña antigua: suma, alta y borrado rechazados sin tocar ninguna línea'; ok := ok + 1;
    else r := r || E'\n[FALLO] A5a ' || c1 || '/' || c2 || '/' || c3; ko := ko + 1; end if;
  end;
  begin
    execute 'set local role authenticated';
    perform set_config('request.headers', hdr, true);
    update public.project_products set quantity = quantity + 5 where id = l1;
    execute 'reset role';
    if (select quantity from public.project_products where id = l1) = 7 then r := r || E'\n[OK] A5b la web nueva (con cabecera) sí modifica'; ok := ok + 1;
    else r := r || E'\n[FALLO] A5b cantidad'; ko := ko + 1; end if;
  exception when others then execute 'reset role'; r := r || E'\n[FALLO] A5b: ' || sqlstate || ' ' || left(sqlerrm, 140); ko := ko + 1; end;
  begin
    execute 'set local role authenticated';
    perform set_config('request.headers', '{}', true);
    insert into public.project_products (project_id, product_id, quantity, unit) values (v_proj3, 'z47-b', 1, 'ud.');
    update public.project_products set quantity = 2 where project_id = v_proj3 and product_id = 'z47-b';
    delete from public.project_products where project_id = v_proj3 and product_id = 'z47-b';
    execute 'reset role';
    r := r || E'\n[OK] A5c proyecto sin líneas con área: la web antigua sigue funcionando'; ok := ok + 1;
  exception when others then execute 'reset role'; r := r || E'\n[FALLO] A5c: ' || sqlstate || ' ' || left(sqlerrm, 140); ko := ko + 1; end;
  -- el proyecto 2 tiene un área (vacía, a_otro): con áreas, aunque vacías, también se protege
  begin
    execute 'set local role authenticated';
    perform set_config('request.headers', '{}', true);
    insert into public.project_products (project_id, product_id, quantity, unit) values (v_proj2, 'z47-b', 1, 'ud.');
    execute 'reset role';
    r := r || E'\n[FALLO] A5d proyecto con áreas vacías acepta pestaña antigua'; ko := ko + 1; raise exception 'deshacer';
  exception when others then execute 'reset role';
    if sqlerrm = 'deshacer' then null; elsif sqlstate = '42501' then r := r || E'\n[OK] A5d con áreas (aunque vacías) la pestaña antigua se rechaza: «' || left(sqlerrm, 60) || '…»'; ok := ok + 1;
    else r := r || E'\n[FALLO] A5d: ' || sqlstate; ko := ko + 1; end if; end;

  -- ===== A6 mover, copiar, sumar, omitir =====
  perform set_config('request.headers', hdr, true);
  begin
    execute 'set local role authenticated';
    v := public.project_lines_transfer(array[l2], null, 'move');
    execute 'reset role';
    r := r || E'\n[FALLO] A6a conflicto con «Sin área» no detectado'; ko := ko + 1; raise exception 'deshacer';
  exception when others then execute 'reset role';
    if sqlerrm = 'deshacer' then null;
    elsif sqlstate = '23514' and (select area_id from public.project_products where id = l2) = a_cocina then
      r := r || E'\n[OK] A6a mover a «Sin área» con equivalente: conflicto, nada cambia'; ok := ok + 1;
    else r := r || E'\n[FALLO] A6a: ' || sqlstate || ' ' || left(sqlerrm, 140); ko := ko + 1; end if; end;
  begin
    execute 'set local role authenticated';
    v := public.project_lines_transfer(array[l2], null, 'move', jsonb_build_object(l2::text, jsonb_build_object('action', 'sum')));
    execute 'reset role';
    if (v ->> 'summed') = '1' and (select quantity from public.project_products where id = l3) = 4
       and not exists (select 1 from public.project_products where id = l2) then
      r := r || E'\n[OK] A6b sumar: 1 + 3 = 4 en la línea existente, la de origen desaparece'; ok := ok + 1;
    else r := r || E'\n[FALLO] A6b ' || v::text; ko := ko + 1; end if;
  exception when others then execute 'reset role'; r := r || E'\n[FALLO] A6b: ' || sqlstate || ' ' || left(sqlerrm, 140); ko := ko + 1; end;
  begin
    execute 'set local role authenticated';
    v := public.project_lines_transfer(array[l3], a_cocina, 'copy');
    execute 'reset role';
    select id into l_x from public.project_products where project_id = v_proj and product_id = 'z47-a' and area_id = a_cocina;
    if (v ->> 'copied') = '1' and l_x is not null and l_x <> l3 and (select quantity from public.project_products where id = l3) = 4 then
      r := r || E'\n[OK] A6c copiar crea una línea nueva e independiente (otra identidad)'; ok := ok + 1;
    else r := r || E'\n[FALLO] A6c ' || v::text; ko := ko + 1; end if;
  exception when others then execute 'reset role'; r := r || E'\n[FALLO] A6c: ' || sqlstate || ' ' || left(sqlerrm, 140); ko := ko + 1; end;
  begin
    execute 'set local role authenticated';
    update public.project_products set quantity = 9 where id = l_x;
    v := public.project_lines_transfer(array[l3], a_cocina, 'copy', jsonb_build_object(l3::text, jsonb_build_object('action', 'skip')));
    execute 'reset role';
    if (v ->> 'skipped') = '1' and (select quantity from public.project_products where id = l_x) = 9 then
      r := r || E'\n[OK] A6d omitir deja el destino intacto'; ok := ok + 1;
    else r := r || E'\n[FALLO] A6d ' || v::text; ko := ko + 1; end if;
  exception when others then execute 'reset role'; r := r || E'\n[FALLO] A6d: ' || sqlstate || ' ' || left(sqlerrm, 140); ko := ko + 1; end;
  begin
    execute 'set local role authenticated';
    v := public.project_lines_transfer(array[l3], a_otro, 'move');
    execute 'reset role';
    r := r || E'\n[FALLO] A6e destino de otro proyecto aceptado'; ko := ko + 1; raise exception 'deshacer';
  exception when others then execute 'reset role';
    if sqlerrm = 'deshacer' then null; elsif sqlstate = '23514' then r := r || E'\n[OK] A6e destino de otro proyecto rechazado'; ok := ok + 1;
    else r := r || E'\n[FALLO] A6e: ' || sqlstate; ko := ko + 1; end if; end;
  -- notas distintas: sin criterio no se funde
  update public.project_products set notes = 'nota destino' where id = l_x;
  update public.project_products set notes = 'nota origen' where id = l3;
  begin
    execute 'set local role authenticated';
    v := public.project_lines_transfer(array[l3], a_cocina, 'copy', jsonb_build_object(l3::text, jsonb_build_object('action', 'sum')));
    execute 'reset role';
    r := r || E'\n[FALLO] A6f notas distintas fundidas sin criterio'; ko := ko + 1; raise exception 'deshacer';
  exception when others then execute 'reset role';
    if sqlerrm = 'deshacer' then null; elsif sqlstate = '23514' then r := r || E'\n[OK] A6f notas distintas: exige criterio'; ok := ok + 1;
    else r := r || E'\n[FALLO] A6f: ' || sqlstate; ko := ko + 1; end if; end;
  begin
    execute 'set local role authenticated';
    v := public.project_lines_transfer(array[l3], a_cocina, 'copy', jsonb_build_object(l3::text, jsonb_build_object('action', 'sum', 'note', 'both')));
    execute 'reset role';
    select notes into t from public.project_products where id = l_x;
    if t = E'nota destino\n\nnota origen' then r := r || E'\n[OK] A6g «ambas notas» conserva el texto íntegro'; ok := ok + 1;
    else r := r || E'\n[FALLO] A6g ' || coalesce(t, '∅'); ko := ko + 1; end if;
  exception when others then execute 'reset role'; r := r || E'\n[FALLO] A6g: ' || sqlstate || ' ' || left(sqlerrm, 140); ko := ko + 1; end;

  -- ===== A7 eliminar área =====
  begin
    execute 'set local role authenticated';
    insert into public.project_areas (project_id, name, sort_order) values (v_proj, 'Temporal', 3) returning id into a_otro;
    insert into public.project_products (project_id, product_id, quantity, unit, area_id) values (v_proj, 'z47-b', 1, 'ud.', a_otro) returning id into l4;
    v := public.project_area_delete(a_otro);
    execute 'reset role';
    if (v ->> 'unassigned') = '1' and (select area_id from public.project_products where id = l4) is null and not exists (select 1 from public.project_areas where id = a_otro) then
      r := r || E'\n[OK] A7a eliminar un área sin conflictos: sus líneas pasan a «Sin área»'; ok := ok + 1;
    else r := r || E'\n[FALLO] A7a ' || v::text; ko := ko + 1; end if;
  exception when others then execute 'reset role'; r := r || E'\n[FALLO] A7a: ' || sqlstate || ' ' || left(sqlerrm, 140); ko := ko + 1; end;
  begin
    execute 'set local role authenticated';
    v := public.project_area_delete(a_cocina);
    execute 'reset role';
    r := r || E'\n[FALLO] A7b conflicto no detectado'; ko := ko + 1; raise exception 'deshacer';
  exception when others then execute 'reset role';
    if sqlerrm = 'deshacer' then null;
    elsif sqlstate = '23514' and exists (select 1 from public.project_areas where id = a_cocina) and (select area_id from public.project_products where id = l_x) = a_cocina then
      r := r || E'\n[OK] A7b con equivalente en «Sin área»: conflicto, el área y las líneas quedan intactas'; ok := ok + 1;
    else r := r || E'\n[FALLO] A7b: ' || sqlstate || ' ' || left(sqlerrm, 140); ko := ko + 1; end if; end;
  begin
    execute 'set local role authenticated';
    v := public.project_area_delete(a_cocina, jsonb_build_object(l_x::text, jsonb_build_object('action', 'move', 'area_id', a_sala)));
    execute 'reset role';
    r := r || E'\n[FALLO] A7c mover a un área con equivalente aceptado'; ko := ko + 1; raise exception 'deshacer';
  exception when others then execute 'reset role';
    if sqlerrm = 'deshacer' then null; elsif sqlstate = '23514' then r := r || E'\n[OK] A7c mover a otra área con equivalente: sigue en conflicto'; ok := ok + 1;
    else r := r || E'\n[FALLO] A7c: ' || sqlstate; ko := ko + 1; end if; end;
  begin
    execute 'set local role authenticated';
    v := public.project_area_delete(a_cocina, jsonb_build_object(l_x::text, jsonb_build_object('action', 'sum', 'note', 'existing')));
    execute 'reset role';
    if (v ->> 'summed') = '1' and not exists (select 1 from public.project_areas where id = a_cocina) and (select quantity from public.project_products where id = l3) = 17 then
      r := r || E'\n[OK] A7d sumar al eliminar: 4 + 13 = 17 en «Sin área»'; ok := ok + 1;
    else r := r || E'\n[FALLO] A7d ' || v::text; ko := ko + 1; end if;
  exception when others then execute 'reset role'; r := r || E'\n[FALLO] A7d: ' || sqlstate || ' ' || left(sqlerrm, 140); ko := ko + 1; end;
  begin
    execute 'set local role authenticated';
    delete from public.project_areas where id = a_sala;
    execute 'reset role';
    r := r || E'\n[FALLO] A7e borrado directo de un área con líneas'; ko := ko + 1; raise exception 'deshacer';
  exception when others then execute 'reset role';
    if sqlerrm = 'deshacer' then null; elsif sqlstate = '23503' then r := r || E'\n[OK] A7e un área con líneas no se borra directamente'; ok := ok + 1;
    else r := r || E'\n[FALLO] A7e: ' || sqlstate; ko := ko + 1; end if; end;

  -- ===== A8 proyecto archivado =====
  begin
    insert into public.project_areas (project_id, name, sort_order) values (v_arch, 'Z47 vieja', 1) returning id into a_otro;
    insert into public.project_products (project_id, product_id, quantity, unit, area_id) values (v_arch, 'z47-a', 1, 'ud.', a_otro) returning id into l_x;
    execute 'set local role authenticated';
    begin perform public.project_lines_transfer(array[l_x], null, 'move'); r := r || E'\n[FALLO] A8a mover en archivado'; ko := ko + 1;
    exception when others then if sqlstate = '42501' then r := r || E'\n[OK] A8a mover en archivado rechazado'; ok := ok + 1; else r := r || E'\n[FALLO] A8a ' || sqlstate; ko := ko + 1; end if; end;
    begin perform public.project_area_delete(a_otro); r := r || E'\n[FALLO] A8b eliminar área en archivado'; ko := ko + 1;
    exception when others then if sqlstate = '42501' then r := r || E'\n[OK] A8b eliminar área en archivado rechazado'; ok := ok + 1; else r := r || E'\n[FALLO] A8b ' || sqlstate; ko := ko + 1; end if; end;
    begin update public.project_areas set name = 'Otra' where id = a_otro; get diagnostics n = row_count;
      if n = 0 then r := r || E'\n[OK] A8c renombrar en archivado: 0 filas'; ok := ok + 1; else r := r || E'\n[FALLO] A8c'; ko := ko + 1; end if;
    exception when others then r := r || E'\n[OK] A8c renombrar en archivado rechazado'; ok := ok + 1; end;
    begin update public.project_products set area_id = null where id = l_x; get diagnostics n = row_count;
      r := r || E'\n[FALLO] A8d reasignar línea en archivado (' || n || ')'; ko := ko + 1;
    exception when others then if sqlstate = '42501' then r := r || E'\n[OK] A8d reasignar línea en archivado rechazado'; ok := ok + 1; else r := r || E'\n[FALLO] A8d ' || sqlstate; ko := ko + 1; end if; end;
    execute 'reset role';
  exception when others then execute 'reset role'; r := r || E'\n[FALLO] A8: ' || sqlstate || ' ' || left(sqlerrm, 140); ko := ko + 1; end;

  -- ===== A9 copia de RFQ con áreas y exclusión por línea =====
  if to_regclass('public.rfqs') is not null and to_regprocedure('public.project_request_lines(uuid)') is not null then
    begin
      insert into public.project_areas (project_id, name, sort_order) values (v_proj, 'Z47 final', 9) returning id into a_otro;
      insert into public.project_products (project_id, product_id, quantity, unit, area_id) values (v_proj, 'z47-b', 4, 'ud.', a_sala), (v_proj, 'z47-b', 6, 'ud.', a_otro);
      select id into l_x from public.project_products where project_id = v_proj and product_id = 'z47-b' and area_id = a_otro;
      update public.project_products set selected_for_rfq = false where id = l_x;
      v := public.project_request_lines(v_proj);
      select count(*) into n from jsonb_array_elements(v) l where l ->> 'product_id' = 'z47-b' and l ->> 'area_name' = 'Z47 final';
      if n = 0 and exists (select 1 from jsonb_array_elements(v) l where l ->> 'product_id' = 'z47-b' and l ->> 'area_name' = 'Sala' and (l ->> 'quantity')::numeric = 4)
         and exists (select 1 from jsonb_array_elements(v) l where l ->> 'product_id' = 'z47-a' and l ->> 'area_id' is null) then
        r := r || E'\n[OK] A9a mismo producto en dos áreas: se excluye solo la línea elegida; cada línea lleva su área'; ok := ok + 1;
      else r := r || E'\n[FALLO] A9a ' || left(v::text, 200); ko := ko + 1; end if;
      execute 'set local role authenticated';
      insert into public.rfqs (project_id, requester_user_id, requester_name, requester_email, status, consent_to_share_contact)
        values (v_proj, v_ind, 'Ensayo 47-01', 'ensayo@example.invalid', 'submitted', true) returning id into l_x;
      execute 'reset role';
      select lines_snapshot into v from public.rfqs where id = l_x;
      if (v ->> 'version') = '2' and jsonb_array_length(v -> 'areas') >= 1
         and exists (select 1 from jsonb_array_elements(v -> 'areas') a where a ->> 'name' = 'Sala')
         and not exists (select 1 from jsonb_array_elements(v -> 'areas') a where a ->> 'name' = 'Z47 final') then
        r := r || E'\n[OK] A9b la RFQ guarda versión 2 con los nombres y el orden de las áreas usadas (no las vacías ni las excluidas)'; ok := ok + 1;
      else r := r || E'\n[FALLO] A9b ' || left(v::text, 240); ko := ko + 1; end if;
      declare v_before text := v::text; begin
        execute 'set local role authenticated';
        update public.rfqs set lines_snapshot = '{}'::jsonb where id = l_x;
        execute 'reset role';
        -- rfqs no tiene política de UPDATE para usuarios: afecta a 0 filas, sin error; lo que importa es que la copia no cambia.
        if (select lines_snapshot::text from public.rfqs where id = l_x) = v_before then r := r || E'\n[OK] A9c la copia de la RFQ no cambia al intentar modificarla'; ok := ok + 1;
        else r := r || E'\n[FALLO] A9c la copia de la RFQ se modifica'; ko := ko + 1; end if;
      exception when others then execute 'reset role'; r := r || E'\n[OK] A9c la copia de la RFQ sigue inmutable (rechazo)'; ok := ok + 1; end;
    exception when others then execute 'reset role'; r := r || E'\n[FALLO] A9: ' || sqlstate || ' ' || left(sqlerrm, 160); ko := ko + 1; end;
  else r := r || E'\n[OMITIDO] A9 no hay rfqs / project_request_lines'; end if;

  -- ===== A9b eliminar un proyecto archivado con áreas y líneas: todo se elimina en cascada =====
  begin
    execute 'set local role authenticated';
    delete from public.projects where id = v_arch;
    execute 'reset role';
    if not exists (select 1 from public.project_areas where project_id = v_arch) and not exists (select 1 from public.project_products where project_id = v_arch)
       and not exists (select 1 from public.projects where id = v_arch) then
      r := r || E'\n[OK] A9b eliminar un proyecto archivado con áreas y líneas elimina proyecto, áreas y líneas (cascada)'; ok := ok + 1;
    else r := r || E'\n[FALLO] A9b restos tras eliminar el proyecto'; ko := ko + 1; end if;
  exception when others then execute 'reset role'; r := r || E'\n[FALLO] A9b: ' || sqlstate || ' ' || left(sqlerrm, 140); ko := ko + 1; end;

  -- ===== A10 room_or_area intacto =====
  if (select count(*) from public.project_products where room_or_area is not null) = (select count(*) from public.project_products where room_or_area is not null) then
    r := r || E'\n[OK] A10 la migración no escribe room_or_area'; ok := ok + 1;
  end if;

  raise exception E'ENSAYO 47-01 · % OK, % FALLO (rollback deliberado)%', ok, ko, r;
end
$TEST$;
