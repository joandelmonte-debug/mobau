-- ============================================================
-- ENSAYO 46-01 (solo después de aplicar 46-01). Todo se revierte:
-- el bloque termina SIEMPRE con una excepción que lleva el informe.
-- Usa productos sintéticos z46-* creados y revertidos dentro del bloque.
-- No escribe nada de forma persistente.
-- ============================================================
DO $$
declare
  r text := '';
  ok int := 0; ko int := 0;
  g1 uuid; g2 uuid; g3 uuid; g4 uuid; g5 uuid; g6 uuid; o1 uuid; o2 uuid; o3 uuid; o4 uuid; o5 uuid; o6 uuid;
  v text;
begin
  -- Funciones auxiliares locales mediante bloques: cada caso en su subtransacción.
  insert into public.products (id, name, distributor_id, category_id, publication_status, catalog_role) values
    ('z46-root',   'Z46 raíz',            'spectro', 'iluminacion', 'published', 'principal'),
    ('z46-comp',   'Z46 componente',      'spectro', 'iluminacion', 'published', 'componente'),
    ('z46-sub',    'Z46 subcomponente',   'spectro', 'iluminacion', 'published', 'ambos'),
    ('z46-x',      'Z46 cuarto nivel',    'spectro', 'iluminacion', 'published', 'componente'),
    ('z46-hidden', 'Z46 no publicado',    'spectro', 'iluminacion', 'draft',     'componente'),
    ('z46-other',  'Z46 otro distribuidor','charo',  'iluminacion', 'published', 'componente'),
    ('z46-princ',  'Z46 solo principal',  'spectro', 'iluminacion', 'published', 'principal');
  insert into public.product_finishes (product_id, code, name, is_default, sort_order) values ('z46-comp', 'k1', 'Negro', true, 1);

  -- S1 · estructura válida de 3 niveles, creada en cualquier orden en la misma transacción.
  begin
    insert into public.product_component_groups (product_id, code, label, requirement, choice)
      values ('z46-root', 'fuente', 'Fuente de luz', 'necesario', 'una') returning id into g1;
    insert into public.product_component_options (group_id, code, kind, component_product_id, component_finish_code, supply, quantity, quantity_mode, attributes)
      values (g1, 'mod-aparte', 'componente', 'z46-comp', 'k1', 'aparte', 1, 'fija', '[{"label":"Potencia","value":"12 W"}]') returning id into o1;
    insert into public.product_component_options (group_id, code, kind, component_product_id, supply, quantity, quantity_mode)
      values (g1, 'mod-incluido', 'componente', 'z46-comp', 'incluido', 1, 'fija') returning id into o2;
    insert into public.product_component_options (group_id, code, kind, setting_label)
      values (g1, 'calida', 'ajuste', 'Cálida') returning id into o3;
    insert into public.product_component_groups (product_id, code, label, requirement, choice, depends_on_option_id)
      values ('z46-root', 'lente', 'Lente', 'opcional', 'varias', o1) returning id into g2;
    insert into public.product_component_groups (product_id, code, label, requirement, choice)
      values ('z46-comp', 'driver', 'Driver', 'necesario', 'una') returning id into g3;
    insert into public.product_component_options (group_id, code, kind, component_product_id, supply, quantity, quantity_mode)
      values (g3, 'drv', 'componente', 'z46-sub', 'aparte', 2, 'fija');
    insert into public.product_component_options (group_id, code, kind, component_product_id, supply, quantity_mode)
      values (g2, 'perfil', 'componente', 'z46-sub', 'aparte', 'a_calcular');
    insert into public.product_component_groups (product_id, code, label, requirement, choice)
      values ('z46-sub', 'modo', 'Modo', 'opcional', 'una') returning id into g4;
    insert into public.product_component_options (group_id, code, kind, setting_label) values (g4, 'dali', 'ajuste', 'DALI');
    set constraints all immediate;
    set constraints all deferred;
    r := r || E'\n[OK] S1 estructura válida de 3 niveles con ajustes, suministro por relación y cantidad a calcular'; ok := ok + 1;
  exception when others then
    r := r || E'\n[FALLO] S1 debía aceptarse: ' || sqlerrm; ko := ko + 1;
    raise exception 'ENSAYO 46-01 (revertido) detenido en S1:%', r;
  end;

  -- Casos que deben rechazarse (cada uno se deshace en su subtransacción).
  declare
    casos text[][] := array[
      array['S2 ciclo de componentes',          'insert into public.product_component_options (group_id, code, kind, component_product_id, supply, quantity, quantity_mode) values (''' || g4 || ''', ''vuelta'', ''componente'', ''z46-comp'', ''aparte'', 1, ''fija'')', 'ciclo'],
      array['S3 cuarto nivel',                  'insert into public.product_component_options (group_id, code, kind, component_product_id, supply, quantity, quantity_mode) values (''' || g4 || ''', ''x'', ''componente'', ''z46-x'', ''aparte'', 1, ''fija'')', 'niveles'],
      array['S4 otro distribuidor',             'insert into public.product_component_options (group_id, code, kind, component_product_id, supply, quantity, quantity_mode) values (''' || g1 || ''', ''otro'', ''componente'', ''z46-other'', ''aparte'', 1, ''fija'')', 'otro distribuidor'],
      array['S5 artículo solo principal',       'insert into public.product_component_options (group_id, code, kind, component_product_id, supply, quantity, quantity_mode) values (''' || g1 || ''', ''princ'', ''componente'', ''z46-princ'', ''aparte'', 1, ''fija'')', 'no está clasificado'],
      array['S6 grupo necesario sin opciones',  'insert into public.product_component_groups (product_id, code, label, requirement, choice) values (''z46-root'', ''vacio'', ''Vacío'', ''necesario'', ''una'')', 'sin opciones activas'],
      array['S7 dependencia de otro producto',  'update public.product_component_groups set depends_on_option_id = ''' || o1 || ''' where id = ''' || g3 || '''', 'opción no válida'],
      array['S8 acabado inexistente',           'insert into public.product_component_options (group_id, code, kind, component_product_id, component_finish_code, supply, quantity, quantity_mode) values (''' || g1 || ''', ''acab'', ''componente'', ''z46-comp'', ''zz'', ''aparte'', 1, ''fija'')', 'acabado'],
      array['S9 ajuste con producto',           'insert into public.product_component_options (group_id, code, kind, component_product_id, setting_label) values (''' || g1 || ''', ''aj2'', ''ajuste'', ''z46-comp'', ''Fría'')', 'product_component_options_shape'],
      array['S10 características no válidas',   'insert into public.product_component_options (group_id, code, kind, setting_label, attributes) values (''' || g1 || ''', ''aj3'', ''ajuste'', ''Neutra'', ''["texto"]'')', 'características'],
      array['S11 retirar todas las opciones de un grupo necesario', 'update public.product_component_options set status = ''retirado'' where group_id = ''' || g3 || '''', 'sin opciones activas'],
      array['S12 ciclo largo sub→x→sub (rechazo, sin truncar)', 'insert into public.product_component_groups (product_id, code, label, requirement, choice) values (''z46-x'', ''g'', ''G'', ''opcional'', ''una''); insert into public.product_component_options (group_id, code, kind, component_product_id, supply, quantity, quantity_mode) select id, ''y'', ''componente'', ''z46-sub'', ''aparte'', 1, ''fija'' from public.product_component_groups where product_id = ''z46-x''; insert into public.product_component_options (group_id, code, kind, component_product_id, supply, quantity, quantity_mode) values (''' || g4 || ''', ''x2'', ''componente'', ''z46-x'', ''aparte'', 1, ''fija'')', 'ciclo']
    ];
    i int;
  begin
    for i in 1 .. array_length(casos, 1) loop
      begin
        execute casos[i][2];
        set constraints all immediate;
        r := r || E'\n[FALLO] ' || casos[i][1] || ': se aceptó'; ko := ko + 1;
        raise exception 'deshacer';
      exception when others then
        if sqlerrm = 'deshacer' then
          null;
        elsif position(casos[i][3] in sqlerrm) > 0 then
          r := r || E'\n[OK] ' || casos[i][1] || ' rechazado: ' || left(sqlerrm, 140); ok := ok + 1;
        else
          r := r || E'\n[FALLO] ' || casos[i][1] || ' rechazado por otro motivo: ' || left(sqlerrm, 160); ko := ko + 1;
        end if;
      end;
      set constraints all deferred;
    end loop;
  end;

  -- S13 · dependencia circular entre grupos del mismo producto.
  begin
    insert into public.product_component_groups (product_id, code, label, requirement, choice) values ('z46-root', 'ga', 'GA', 'opcional', 'una') returning id into g5;
    insert into public.product_component_options (group_id, code, kind, setting_label) values (g5, 'a1', 'ajuste', 'A1') returning id into o4;
    insert into public.product_component_groups (product_id, code, label, requirement, choice, depends_on_option_id) values ('z46-root', 'gb', 'GB', 'opcional', 'una', o4) returning id into g6;
    insert into public.product_component_options (group_id, code, kind, setting_label) values (g6, 'b1', 'ajuste', 'B1') returning id into o5;
    update public.product_component_groups set depends_on_option_id = o5 where id = g5;
    set constraints all immediate;
    r := r || E'\n[FALLO] S13 dependencia circular aceptada'; ko := ko + 1;
    raise exception 'deshacer';
  exception when others then
    if sqlerrm = 'deshacer' then null;
    elsif position('dependencia circular' in sqlerrm) > 0 then r := r || E'\n[OK] S13 dependencia circular rechazada'; ok := ok + 1;
    else r := r || E'\n[FALLO] S13 otro motivo: ' || left(sqlerrm, 160); ko := ko + 1; end if;
  end;
  set constraints all deferred;

  -- S14 · retirar en vez de borrar: una opción retirada desaparece de la vista pública.
  begin
    update public.product_component_options set status = 'retirado' where id = o3;
    set constraints all immediate;
    set constraints all deferred;
    r := r || E'\n[OK] S14 retirar una opción (no borrar) aceptado'; ok := ok + 1;
  exception when others then r := r || E'\n[FALLO] S14: ' || sqlerrm; ko := ko + 1; set constraints all deferred;
  end;

  -- S15 · requisito con opciones no disponibles: grupo necesario cuya única opción es un componente no publicado.
  begin
    insert into public.product_component_groups (product_id, code, label, requirement, choice) values ('z46-root', 'oculto', 'Pendiente', 'necesario', 'una') returning id into g6;
    insert into public.product_component_options (group_id, code, kind, component_product_id, supply, quantity, quantity_mode) values (g6, 'h', 'componente', 'z46-hidden', 'aparte', 1, 'fija') returning id into o6;
    insert into public.product_component_groups (product_id, code, label, requirement, choice) values ('z46-hidden', 'priv', 'Privado', 'opcional', 'una') returning id into g5;
    insert into public.product_component_options (group_id, code, kind, setting_label) values (g5, 'p', 'ajuste', 'Privado');
    set constraints all immediate;
    set constraints all deferred;
    r := r || E'\n[OK] S15 grupo necesario cuya única opción es un componente no publicado: aceptado (activo ≠ publicado)'; ok := ok + 1;
  exception when others then r := r || E'\n[FALLO] S15 preparación: ' || sqlerrm; ko := ko + 1; set constraints all deferred;
  end;

  -- Lectura pública como anon (RLS real; sin postgres).
  execute 'set local role anon';
  perform set_config('t46.grupos', (select string_agg(code || ':' || available_options, ',' order by code) from public.catalog_component_groups where product_id like 'z46-%'), true);
  perform set_config('t46.opciones', (select string_agg(code, ',' order by code) from public.catalog_component_options where product_id like 'z46-%'), true);
  perform set_config('t46.tabla_opciones', (select count(*)::text from public.product_component_options o join public.product_component_groups g on g.id = o.group_id where g.product_id like 'z46-%'), true);
  perform set_config('t46.rol', (select string_agg(id || '=' || catalog_role, ',' order by id) from public.catalog_products where id like 'z46-%'), true);
  begin
    insert into public.product_component_groups (product_id, code, label, requirement, choice) values ('z46-root', 'anon', 'A', 'opcional', 'una');
    perform set_config('t46.anon_insert', 'aceptado', true);
  exception when others then perform set_config('t46.anon_insert', sqlstate || ' ' || left(sqlerrm, 60), true);
  end;
  execute 'reset role';

  -- Escritura directa como authenticated (identidad ficticia): debe denegarse.
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-8000-000000046001","role":"authenticated"}', true);
  begin
    update public.product_component_options set status = 'retirado' where group_id = g1;
    perform set_config('t46.auth_update', 'aceptado', true);
  exception when others then perform set_config('t46.auth_update', sqlstate || ' ' || left(sqlerrm, 60), true);
  end;
  begin
    delete from public.product_component_groups where id = g1;
    perform set_config('t46.auth_delete', 'aceptado', true);
  exception when others then perform set_config('t46.auth_delete', sqlstate || ' ' || left(sqlerrm, 60), true);
  end;
  execute 'reset role';

  v := current_setting('t46.grupos', true);
  if v = 'driver:1,fuente:2,lente:1,modo:1,oculto:0' then r := r || E'\n[OK] S16 grupos públicos (oculto:0 visible como requisito; el grupo del no publicado no aparece): ' || v; ok := ok + 1;
  else r := r || E'\n[FALLO] S16 grupos públicos: ' || coalesce(v, '∅'); ko := ko + 1; end if;
  v := current_setting('t46.opciones', true);
  if v = 'dali,drv,mod-aparte,mod-incluido,perfil' then r := r || E'\n[OK] S17 opciones públicas (sin la retirada ni la del no publicado; ajuste incluido): ' || v; ok := ok + 1;
  else r := r || E'\n[FALLO] S17 opciones públicas: ' || coalesce(v, '∅'); ko := ko + 1; end if;
  v := current_setting('t46.tabla_opciones', true);
  if v = '5' then r := r || E'\n[OK] S18 RLS de la tabla de opciones para anon: 5 visibles'; ok := ok + 1;
  else r := r || E'\n[FALLO] S18 RLS de la tabla de opciones: ' || coalesce(v, '∅'); ko := ko + 1; end if;
  v := current_setting('t46.rol', true);
  if v like '%z46-comp=componente%' and v like '%z46-root=principal%' and v not like '%z46-hidden%' then r := r || E'\n[OK] S19 catalog_products expone catalog_role'; ok := ok + 1;
  else r := r || E'\n[FALLO] S19 catalog_role: ' || coalesce(v, '∅'); ko := ko + 1; end if;
  foreach v in array array['anon_insert', 'auth_update', 'auth_delete'] loop
    if current_setting('t46.' || v, true) like '42501%' then r := r || E'\n[OK] S20 ' || v || ' denegado: ' || current_setting('t46.' || v, true); ok := ok + 1;
    else r := r || E'\n[FALLO] S20 ' || v || ': ' || coalesce(current_setting('t46.' || v, true), '∅'); ko := ko + 1; end if;
  end loop;

  -- S21 · despublicar un componente usado en grupos necesarios no se bloquea
  --       y el requisito sigue visible con 0 opciones disponibles.
  begin
    update public.products set publication_status = 'draft' where id = 'z46-sub';
    set constraints all immediate;
    set constraints all deferred;
    r := r || E'\n[OK] S21 despublicar un componente referenciado: aceptado'; ok := ok + 1;
  exception when others then r := r || E'\n[FALLO] S21 despublicar: ' || sqlerrm; ko := ko + 1; set constraints all deferred;
  end;
  execute 'set local role anon';
  perform set_config('t46.grupos2', (select string_agg(code || ':' || available_options, ',' order by code) from public.catalog_component_groups where product_id like 'z46-%'), true);
  perform set_config('t46.opciones2', (select string_agg(code, ',' order by code) from public.catalog_component_options where product_id like 'z46-%'), true);
  execute 'reset role';
  v := current_setting('t46.grupos2', true);
  if v = 'driver:0,fuente:2,lente:0,oculto:0' then r := r || E'\n[OK] S22 tras despublicar: requisito «driver» visible con 0 disponibles (y «modo» del no publicado oculto): ' || v; ok := ok + 1;
  else r := r || E'\n[FALLO] S22 grupos tras despublicar: ' || coalesce(v, '∅'); ko := ko + 1; end if;
  v := current_setting('t46.opciones2', true);
  if v = 'mod-aparte,mod-incluido' then r := r || E'\n[OK] S23 opciones tras despublicar (sin las del no publicado): ' || v; ok := ok + 1;
  else r := r || E'\n[FALLO] S23 opciones tras despublicar: ' || coalesce(v, '∅'); ko := ko + 1; end if;

  -- S24 · retirar un grupo necesario completo conservando sus opciones (historial).
  begin
    update public.product_component_groups set status = 'retirado' where id = g3;
    set constraints all immediate;
    set constraints all deferred;
    if (select count(*) from public.product_component_options where group_id = g3 and status = 'activo') = 1 then
      r := r || E'\n[OK] S24 retirar un grupo necesario completo: aceptado y su opción se conserva'; ok := ok + 1;
    else r := r || E'\n[FALLO] S24 la opción del grupo retirado no se conservó'; ko := ko + 1; end if;
  exception when others then r := r || E'\n[FALLO] S24 retirar grupo: ' || sqlerrm; ko := ko + 1; set constraints all deferred;
  end;

  -- Evaluación final forzada de toda la integridad diferida antes del cierre.
  begin
    set constraints all immediate;
    r := r || E'\n[OK] Integridad diferida evaluada sin errores antes del cierre'; ok := ok + 1;
  exception when others then r := r || E'\n[FALLO] Integridad diferida al cierre: ' || sqlerrm; ko := ko + 1;
  end;

  -- Cierre deliberado: la excepción revierte todo (incluidos los z46-*). No indica fallo por sí misma.
  raise exception 'CIERRE DELIBERADO DEL ENSAYO 46-01 (todo revertido) · % correctos · % fallos inesperados%', ok, ko, r;
end $$;
