-- ============================================================
-- Ensayo de 46-05 (tras aplicarla) · casos B1–B3 (rollback deliberado)
-- ============================================================
-- Requiere 46-05 aplicada (índice antiguo retirado). Mismos casos B1–B3 de
-- P46_04_ensayo.sql, con la preparación mínima que necesitan. Preparación
-- administrativa (postgres): estudio, proyecto, productos, acabados, grupos y
-- opciones sintéticos (z46c-*). Operaciones comprobadas: como authenticated
-- con Individual e2a655c1…. Termina con una excepción: no queda nada.
-- ============================================================
DO $TEST$
declare
  r text := '';
  ok int := 0; ko int := 0;
  v_ind uuid; v_studio uuid; v_proj uuid;
  g_fuente uuid; g_lente uuid; o_comp uuid; l_a uuid;
  cfg_a jsonb := '{"choices":[{"group":"fuente","options":["comp"]},{"path":[{"group":"fuente","option":"comp"}],"group":"drv","options":["d"]},{"group":"lente","options":["perfil","panel"]}]}';
  cfg_a2 jsonb := '{"choices":[{"options":["panel","perfil"],"group":"lente","path":[]},{"group":"drv","path":[{"option":"comp","group":"fuente"}],"options":["d"]},{"options":["comp"],"group":"fuente"}]}';
  cfg_b jsonb := '{"choices":[{"group":"fuente","options":["calida"]}]}';
begin
  if current_user <> 'postgres' then raise exception 'P46_05: ejecutar como postgres'; end if;
  if exists (select 1 from pg_indexes where schemaname = 'public' and indexname = 'project_products_line_unique')
     or not exists (select 1 from pg_indexes where schemaname = 'public' and indexname = 'project_products_config_line_unique') then
    raise exception 'P46_05: 46-05 no está aplicada';
  end if;
  select id into v_ind from public.profiles where id::text like 'e2a655c1%' and role = 'individual';
  if v_ind is null then raise exception 'P46_05: falta la identidad de prueba'; end if;

  -- ===== Preparación administrativa (postgres): todo sintético =====
  insert into public.studios (name) values ('Z46C estudio de ensayo') returning id into v_studio;
  insert into public.projects (owner_user_id, studio_id, name, status) values (v_ind, v_studio, 'Z46C proyecto de ensayo', 'active') returning id into v_proj;
  insert into public.products (id, name, distributor_id, category_id, publication_status, catalog_role) values
    ('z46c-root',  'Z46C raíz',          'spectro', 'iluminacion',    'published', 'principal'),
    ('z46c-comp',  'Z46C componente',    'spectro', 'iluminacion',    'published', 'componente'),
    ('z46c-sub',   'Z46C sub',           'spectro', 'iluminacion',    'published', 'componente'),
    ('z46c-rev',   'Z46C revestimiento', 'spectro', 'revestimientos', 'published', 'componente');
  insert into public.product_finishes (product_id, code, name, is_default, sort_order) values ('z46c-root', 'k1', 'Negro', true, 1);
  insert into public.product_component_groups (product_id, code, label, requirement, choice, sort_order) values ('z46c-root', 'fuente', 'Fuente', 'necesario', 'una', 1) returning id into g_fuente;
  insert into public.product_component_options (group_id, code, kind, component_product_id, supply, quantity, quantity_mode, sort_order)
    values (g_fuente, 'comp', 'componente', 'z46c-comp', 'incluido', 2, 'fija', 1) returning id into o_comp;
  insert into public.product_component_options (group_id, code, kind, setting_label, sort_order) values (g_fuente, 'calida', 'ajuste', 'Cálida', 2);
  insert into public.product_component_groups (product_id, code, label, requirement, choice, depends_on_option_id, sort_order)
    values ('z46c-root', 'lente', 'Lente', 'opcional', 'varias', o_comp, 2) returning id into g_lente;
  insert into public.product_component_options (group_id, code, kind, component_product_id, supply, quantity, quantity_mode, sort_order) values
    (g_lente, 'perfil', 'componente', 'z46c-sub', 'aparte', null, 'a_calcular', 1),
    (g_lente, 'panel',  'componente', 'z46c-rev', 'aparte', 1.5, 'fija', 2);
  with g as (insert into public.product_component_groups (product_id, code, label, requirement, choice) values ('z46c-comp', 'drv', 'Driver', 'necesario', 'una') returning id)
  insert into public.product_component_options (group_id, code, kind, component_product_id, supply, quantity, quantity_mode)
    select g.id, 'd', 'componente', 'z46c-sub', 'aparte', 1, 'fija' from g;
  set constraints all immediate; set constraints all deferred;

  perform set_config('request.jwt.claims', json_build_object('sub', v_ind, 'role', 'authenticated', 'aal', 'aal1')::text, true);
  perform set_config('request.jwt.claim.sub', v_ind::text, true);
  execute 'set local role authenticated';
  insert into public.project_products (project_id, product_id, finish_code, quantity, unit, configuration) values (v_proj, 'z46c-root', 'k1', 3, 'ud.', cfg_a2) returning id into l_a;
  execute 'reset role';

  -- ===== B1–B3 (con 46-05 aplicada) =====
  begin
    execute 'set local role authenticated';
    insert into public.project_products (project_id, product_id, finish_code, quantity, unit, configuration) values (v_proj, 'z46c-root', 'k1', 1, 'ud.', cfg_b);
    insert into public.project_products (project_id, product_id, finish_code, quantity, unit) values (v_proj, 'z46c-root', 'k1', 1, 'ud.');
    execute 'reset role';
    if (select count(*) from public.project_products where project_id = v_proj and product_id = 'z46c-root' and finish_code = 'k1') = 3 then
      r := r || E'\n[OK] B1 mismo producto y acabado con dos configuraciones y una línea sin configurar'; ok := ok + 1;
    else r := r || E'\n[FALLO] B1 líneas inesperadas'; ko := ko + 1; end if;
  exception when others then r := r || E'\n[FALLO] B1: ' || sqlstate || ' ' || left(sqlerrm, 160); ko := ko + 1;
  end;
  declare
    casos jsonb[] := array[null, cfg_a]::jsonb[];
    nombres text[] := array['B2 segunda línea sin configurar', 'B3 configuración equivalente en otro orden'];
    k int;
  begin
    for k in 1 .. 2 loop
      begin
        execute 'set local role authenticated';
        insert into public.project_products (project_id, product_id, finish_code, quantity, unit, configuration) values (v_proj, 'z46c-root', 'k1', 9, 'ud.', casos[k]);
        execute 'reset role';
        r := r || E'\n[FALLO] ' || nombres[k] || ' aceptada'; ko := ko + 1; raise exception 'deshacer';
      exception when others then
        if sqlerrm = 'deshacer' then null;
        elsif sqlstate = '23505' and position('project_products_config_line_unique' in sqlerrm) > 0 then
          r := r || E'\n[OK] ' || nombres[k] || ': rechazada como la misma línea'; ok := ok + 1;
        else r := r || E'\n[FALLO] ' || nombres[k] || ' otro motivo: ' || sqlstate || ' ' || left(sqlerrm, 150); ko := ko + 1; end if;
      end;
    end loop;
  end;
  if (select quantity from public.project_products where id = l_a) = 3 then
    r := r || E'\n[OK] La primera línea configurada no cambió con los intentos rechazados'; ok := ok + 1;
  else r := r || E'\n[FALLO] La primera línea configurada cambió'; ko := ko + 1; end if;

  begin
    set constraints all immediate;
    r := r || E'\n[OK] Integridad diferida evaluada sin errores antes del cierre'; ok := ok + 1;
  exception when others then r := r || E'\n[FALLO] Integridad diferida al cierre: ' || sqlerrm; ko := ko + 1;
  end;

  raise exception 'CIERRE DELIBERADO DEL ENSAYO 46-05 (todo revertido) · % correctos · % fallos inesperados%', ok, ko, r;
end $TEST$;
