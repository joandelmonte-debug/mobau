-- ============================================================
-- Ensayo de 46-04 (tras aplicarla) (rollback deliberado; incluye los objetos creados)
-- ============================================================
-- Requiere 46-04 aplicada y 46-05 sin aplicar. Termina con una excepción:
-- no queda ningún dato sintético.
-- Fase A = 46-04 sola (índice antiguo presente). Fase B = estado final de
-- 46-05 (índice antiguo retirado dentro de la misma transacción).
-- Preparación administrativa (postgres): estudio, proyecto, productos,
-- acabados, grupos y opciones sintéticos (z46c-*). Operaciones comprobadas:
-- como authenticated con Individual e2a655c1…, Gratis 46ea4397…, el
-- distribuidor 392a9eb4… y anon. Recuperaciones: solo sus comprobaciones
-- previas (se espera que se detengan); nunca se ejecuta una recuperación.
-- ============================================================
DO $TEST$
declare
  r text := '';
  ok int := 0; ko int := 0;
  t_rb4 text := $R4$-- ============================================================
-- PROPUESTA NO EJECUTADA (recuperación de 46-04) — no ejecutar sin aprobación explícita
-- ============================================================
-- Deshace 46-04 SOLO si:
--   * el índice antiguo existe (46-05 sin aplicar o ya recuperada), y
--   * ninguna línea tiene configuración (si no, se perderían elecciones), y
--   * ninguna RFQ tiene copia (si no, se perdería lo solicitado).
-- Devuelve product_reference_counts a su texto anterior (MD5 69f5ee71…).
-- Sin CASCADE. Si se aplica, se registra como migración NUEVA tras confirmar su COMMIT.
-- Ejecutar completo.
-- ============================================================

BEGIN;

create function pg_temp.r4604b(t text, a text, b text) returns text language plpgsql as $$
begin
  if (length(t) - length(replace(t, a, ''))) <> length(a) then
    raise exception 'recuperación 46-04: el fragmento no aparece exactamente una vez: %', left(a, 80);
  end if;
  return replace(t, a, b);
end $$;

DO $$
begin
  if current_user <> 'postgres' then
    raise exception 'recuperación 46-04: ejecutar como postgres';
  end if;
  if not exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'project_products' and column_name = 'configuration') then
    raise exception 'recuperación 46-04: no existe project_products.configuration; no se toca nada';
  end if;
  if not exists (select 1 from pg_indexes where schemaname = 'public' and indexname = 'project_products_line_unique') then
    raise exception 'recuperación 46-04: falta el índice antiguo (recupera antes 46-05); no se toca nada';
  end if;
  if exists (select 1 from public.project_products where configuration is not null) then
    raise exception 'recuperación 46-04: hay líneas con configuración que se perderían; no se toca nada';
  end if;
  if exists (select 1 from public.rfqs where lines_snapshot is not null) then
    raise exception 'recuperación 46-04: hay RFQ con copia de lo solicitado que se perdería; no se toca nada';
  end if;
  if (select md5(prosrc) from pg_proc where oid = 'mobau_private.product_reference_counts(text)'::regprocedure) <> '6a9b5efb565babc8e06016d58dd99288' then
    raise exception 'recuperación 46-04: product_reference_counts no es la de 46-04; no se toca nada';
  end if;
end $$;

-- 1. Triggers
drop trigger trg_rfqs_10_lines_snapshot on public.rfqs;
drop trigger trg_project_products_10_configuration on public.project_products;

-- 2. product_reference_counts a su texto anterior
DO $$
declare
  d text := pg_get_functiondef('mobau_private.product_reference_counts(text)'::regprocedure);
begin
  d := pg_temp.r4604b(d, $a$  v_unknown text[] := '{}'::text[];
  v_cfg bigint;
  v_snap bigint;
begin
$a$, $a$  v_unknown text[] := '{}'::text[];
begin
$a$);
  d := pg_temp.r4604b(d, $a$  end loop;
  -- 46-04: las configuraciones guardadas y las copias de RFQ (jsonb, sin
  -- clave ajena) también cuentan como referencias: bloquean la purga.
  select count(*) into v_cfg from public.project_products pp
   where pp.config_snapshot is not null
     and pg_catalog.jsonb_path_exists(pp.config_snapshot, '$.items[*] ? (@.product_id == $p)', pg_catalog.jsonb_build_object('p', p_product_id));
  select count(*) into v_snap from public.rfqs r
   where r.lines_snapshot is not null
     and pg_catalog.jsonb_path_exists(r.lines_snapshot, '$.**.product_id ? (@ == $p)', pg_catalog.jsonb_build_object('p', p_product_id));
  v_other := v_other + v_cfg + v_snap;
  return pg_catalog.jsonb_build_object(
    'configured_lines', v_cfg,
    'rfq_snapshots', v_snap,
$a$, $a$  end loop;
  return pg_catalog.jsonb_build_object(
$a$);
  execute d;
end $$;

-- 3. Índice y funciones
drop index public.project_products_config_line_unique;
drop function public.rfqs_lines_snapshot();
drop function public.project_products_configuration();
drop function public.project_request_lines(uuid);
drop function public.project_line_states(uuid);
drop function public.line_configuration_structure(jsonb);
drop function public.line_configuration_resolve(text, jsonb);
drop function public.line_configuration_normalized(jsonb);

-- 4. Columnas (sus permisos por columna desaparecen con ellas)
alter table public.rfqs drop constraint rfqs_lines_snapshot_shape;
alter table public.rfqs drop column lines_snapshot;
alter table public.project_products
  drop constraint project_products_configuration_shape,
  drop constraint project_products_config_key_format,
  drop constraint project_products_config_key_consistent;
alter table public.project_products
  drop column config_snapshot,
  drop column config_key,
  drop column configuration;

-- 5. Comprobaciones finales
DO $$
begin
  if (select md5(prosrc) from pg_proc where oid = 'mobau_private.product_reference_counts(text)'::regprocedure) <> '69f5ee71cbed763b505986669083c09c' then
    raise exception 'recuperación 46-04: product_reference_counts no volvió a su texto anterior';
  end if;
  if exists (select 1 from information_schema.columns where table_schema = 'public'
               and ((table_name = 'project_products' and column_name in ('configuration', 'config_key', 'config_snapshot'))
                    or (table_name = 'rfqs' and column_name = 'lines_snapshot')))
     or exists (select 1 from pg_trigger where not tgisinternal and tgrelid in ('public.project_products'::regclass, 'public.rfqs'::regclass))
     or exists (select 1 from pg_proc where pronamespace = 'public'::regnamespace
                  and proname in ('line_configuration_normalized', 'line_configuration_resolve', 'line_configuration_structure',
                                  'project_line_states', 'project_request_lines', 'project_products_configuration', 'rfqs_lines_snapshot'))
     or not exists (select 1 from pg_indexes where schemaname = 'public' and indexname = 'project_products_line_unique') then
    raise exception 'recuperación 46-04: el estado final no es el esperado';
  end if;
end $$;

COMMIT;
$R4$;
  t_rb5 text := $R5$-- ============================================================
-- PROPUESTA NO EJECUTADA (recuperación de 46-05) — no ejecutar sin aprobación explícita
-- ============================================================
-- Vuelve a crear el índice único antiguo (proyecto + producto + acabado)
-- SOLO si no hay dos líneas del mismo producto y acabado en un proyecto
-- (si las hay, se detiene: no borra ni fusiona líneas).
-- Si se aplica, se registra como migración NUEVA tras confirmar su COMMIT.
-- Ejecutar completo.
-- ============================================================

BEGIN;

DO $$
begin
  if current_user <> 'postgres' then
    raise exception 'recuperación 46-05: ejecutar como postgres';
  end if;
  if exists (select 1 from pg_indexes where schemaname = 'public' and indexname = 'project_products_line_unique') then
    raise exception 'recuperación 46-05: el índice antiguo ya existe; no se toca nada';
  end if;
  if exists (select 1 from public.project_products
              group by project_id, product_id, coalesce(finish_code, '') having count(*) > 1) then
    raise exception 'recuperación 46-05: hay líneas con configuraciones distintas del mismo producto y acabado; no se toca nada';
  end if;
end $$;

create unique index project_products_line_unique
  on public.project_products (project_id, product_id, coalesce(finish_code, ''));

DO $$
begin
  if (select indexdef from pg_indexes where schemaname = 'public' and indexname = 'project_products_line_unique')
       is distinct from 'CREATE UNIQUE INDEX project_products_line_unique ON public.project_products USING btree (project_id, product_id, COALESCE(finish_code, ''''::text))' then
    raise exception 'recuperación 46-05: el índice no quedó como se esperaba';
  end if;
end $$;

COMMIT;
$R5$;
  v_ind uuid; v_gra uuid; v_sup uuid; v_studio uuid; v_proj uuid;
  g_fuente uuid; g_lente uuid; o_comp uuid;
  l_a uuid; l_b uuid; l_p uuid; l_u uuid; l_plain uuid; l_other uuid;
  v_rfq1 uuid; v_rfq2 uuid; v_md5_rfq1 text;
  cfg_a jsonb := '{"choices":[{"group":"fuente","options":["comp"]},{"path":[{"group":"fuente","option":"comp"}],"group":"drv","options":["d"]},{"group":"lente","options":["perfil","panel"]}]}';
  -- misma elección: otro orden de elecciones, de claves y de opciones; ruta vacía explícita
  cfg_a2 jsonb := '{"choices":[{"options":["panel","perfil"],"group":"lente","path":[]},{"group":"drv","path":[{"option":"comp","group":"fuente"}],"options":["d"]},{"options":["comp"],"group":"fuente"}]}';
  cfg_b jsonb := '{"choices":[{"group":"fuente","options":["calida"]}]}';
  cfg_p jsonb := '{"choices":[{"group":"fuente","options":["comp"]}]}';
  v jsonb; v_t text; v_n int; v_key text; v_taken text;
  v_i int; v_j int; v_rest text;
  claims_ind text; claims_gra text; claims_sup text;
begin
  if current_user <> 'postgres' then raise exception 'P46_04: ejecutar como postgres'; end if;
  if md5(t_rb4) <> 'a42d712bdbadb45a17e1f42c8f7ababd' or md5(t_rb5) <> '40b48e819c31e7960c142236dcd880cc' then
    raise exception 'P46_04: las recuperaciones incrustadas no coinciden con su MD5';
  end if;
  -- (46-04 ya aplicada)
  if not exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'project_products' and column_name = 'configuration') then
    raise exception 'P46_04: 46-04 no está aplicada';
  end if;
  if not exists (select 1 from pg_indexes where schemaname = 'public' and indexname = 'project_products_line_unique') then
    raise exception 'P46_04: la fase A necesita el índice antiguo (46-05 sin aplicar)';
  end if;

  -- Identidades de prueba ya autorizadas (solo con datos sintéticos)
  select id into v_ind from public.profiles where id::text like 'e2a655c1%' and role = 'individual';
  select id into v_gra from public.profiles where id::text like '46ea4397%' and role = 'individual';
  select id into v_sup from public.profiles where id::text like '392a9eb4%' and role = 'supplier';
  if v_ind is null or v_gra is null or v_sup is null then raise exception 'P46_04: faltan identidades'; end if;
  claims_ind := json_build_object('sub', v_ind, 'role', 'authenticated', 'aal', 'aal1')::text;
  claims_gra := json_build_object('sub', v_gra, 'role', 'authenticated', 'aal', 'aal1')::text;
  claims_sup := json_build_object('sub', v_sup, 'role', 'authenticated', 'aal', 'aal1')::text;

  -- ===== Preparación administrativa (postgres): todo sintético =====
  insert into public.studios (name) values ('Z46C estudio de ensayo') returning id into v_studio;
  insert into public.projects (owner_user_id, studio_id, name, status) values (v_ind, v_studio, 'Z46C proyecto de ensayo', 'active') returning id into v_proj;
  insert into public.products (id, name, distributor_id, category_id, publication_status, catalog_role) values
    ('z46c-root',  'Z46C raíz',          'spectro', 'iluminacion',    'published', 'principal'),
    ('z46c-root2', 'Z46C raíz 2',        'spectro', 'iluminacion',    'published', 'principal'),
    ('z46c-comp',  'Z46C componente',    'spectro', 'iluminacion',    'published', 'componente'),
    ('z46c-sub',   'Z46C sub',           'spectro', 'iluminacion',    'published', 'componente'),
    ('z46c-rev',   'Z46C revestimiento', 'spectro', 'revestimientos', 'published', 'componente'),
    ('z46c-plain', 'Z46C sin opciones',  'spectro', 'mobiliario',     'published', 'principal'),
    ('z46c-other', 'Z46C de otra empresa', 'charo', 'mobiliario',     'published', 'principal');
  insert into public.product_finishes (product_id, code, name, is_default, sort_order) values
    ('z46c-root', 'k1', 'Negro', true, 1), ('z46c-root', 'k2', 'Blanco', false, 2), ('z46c-root', 'k3', 'Gris', false, 3);
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
  with g as (insert into public.product_component_groups (product_id, code, label, requirement, choice) values ('z46c-root2', 'fuente2', 'Modo', 'necesario', 'una') returning id)
  insert into public.product_component_options (group_id, code, kind, setting_label)
    select g.id, 'x', 'ajuste', 'Única' from g;
  set constraints all immediate; set constraints all deferred;

  -- ===== Identidad canónica en el servidor (para comparar con el navegador) =====
  r := r || E'\n[NORM] a '  || md5(public.line_configuration_normalized(cfg_a)::text)  || ' ' || public.line_configuration_normalized(cfg_a)::text;
  r := r || E'\n[NORM] a2 ' || md5(public.line_configuration_normalized(cfg_a2)::text) || ' ' || public.line_configuration_normalized(cfg_a2)::text;
  r := r || E'\n[NORM] b '  || md5(public.line_configuration_normalized(cfg_b)::text)  || ' ' || public.line_configuration_normalized(cfg_b)::text;
  if public.line_configuration_normalized(cfg_a) = public.line_configuration_normalized(cfg_a2)
     and public.line_configuration_normalized(cfg_a) <> public.line_configuration_normalized(cfg_b)
     and public.line_configuration_normalized('{"choices":[]}') is null and public.line_configuration_normalized('{}') is null then
    r := r || E'\n[OK] I1 forma normal: el orden y las rutas omitidas no cambian la identidad; vacío = sin configuración'; ok := ok + 1;
  else r := r || E'\n[FALLO] I1 forma normal inesperada'; ko := ko + 1; end if;
  declare
    casos text[][] := array[
      array['I2 opción repetida', '{"choices":[{"group":"fuente","options":["comp","comp"]}]}', 'aparece dos veces'],
      array['I3 grupo repetido (elecciones contradictorias)', '{"choices":[{"group":"fuente","options":["comp"]},{"group":"fuente","path":[],"options":["calida"]}]}', 'mismo grupo'],
      array['I4 campo desconocido', '{"choices":[],"label":"x"}', 'Campo no permitido']];
    k int;
  begin
    for k in 1 .. array_length(casos, 1) loop
      begin
        perform public.line_configuration_normalized(casos[k][2]::jsonb);
        r := r || E'\n[FALLO] ' || casos[k][1] || ': se aceptó'; ko := ko + 1;
      exception when others then
        if position(casos[k][3] in sqlerrm) > 0 then r := r || E'\n[OK] ' || casos[k][1] || ' rechazado (no se descarta): ' || left(sqlerrm, 80); ok := ok + 1;
        else r := r || E'\n[FALLO] ' || casos[k][1] || ' otro motivo: ' || left(sqlerrm, 120); ko := ko + 1; end if;
      end;
    end loop;
  end;

  perform set_config('request.jwt.claims', claims_ind, true);
  perform set_config('request.jwt.claim.sub', v_ind::text, true);

  -- ===== FASE A · 46-04 sola (índice antiguo presente) =====
  begin
    execute 'set local role authenticated';
    insert into public.project_products (project_id, product_id, finish_code, quantity, unit, configuration) values (v_proj, 'z46c-root', 'k1', 3, 'ud.', cfg_a2) returning id into l_a;
    insert into public.project_products (project_id, product_id, finish_code, quantity, unit, configuration) values (v_proj, 'z46c-root', 'k2', 1, 'ud.', cfg_b) returning id into l_b;
    insert into public.project_products (project_id, product_id, finish_code, quantity, unit, configuration) values (v_proj, 'z46c-root', 'k3', 2, 'ud.', cfg_p) returning id into l_p;
    insert into public.project_products (project_id, product_id, quantity, unit) values (v_proj, 'z46c-root2', 1, 'ud.') returning id into l_u;
    -- clave y resumen falsificados por el cliente: el servidor los sustituye
    insert into public.project_products (project_id, product_id, quantity, unit, config_key, config_snapshot)
      values (v_proj, 'z46c-plain', 1, 'ud.', md5('falsa'), '{"falsa":true}') returning id into l_plain;
    insert into public.project_products (project_id, product_id, quantity, unit) values (v_proj, 'z46c-other', 2, 'ud.') returning id into l_other;
    execute 'reset role';
    select config_key, configuration into v_key, v from public.project_products where id = l_a;
    if v_key = md5(public.line_configuration_normalized(cfg_a)::text) and v = public.line_configuration_normalized(cfg_a)
       and (select config_key = '' and config_snapshot is null from public.project_products where id = l_plain) then
      r := r || E'\n[OK] A1 líneas guardadas como Individual: forma normal y clave del servidor; clave y resumen enviados por el cliente, ignorados'; ok := ok + 1;
    else r := r || E'\n[FALLO] A1 clave o forma inesperada'; ko := ko + 1; end if;
  exception when others then r := r || E'\n[FALLO] A1: ' || sqlstate || ' ' || left(sqlerrm, 160); ko := ko + 1;
  end;

  begin
    execute 'set local role authenticated';
    insert into public.project_products (project_id, product_id, finish_code, quantity, unit, configuration) values (v_proj, 'z46c-root', 'k1', 1, 'ud.', cfg_b);
    execute 'reset role';
    r := r || E'\n[FALLO] A2 con 46-04 sola se aceptó otra configuración del mismo producto y acabado'; ko := ko + 1; raise exception 'deshacer';
  exception when others then
    if sqlerrm = 'deshacer' then null;
    elsif sqlstate = '23505' and position('project_products_line_unique' in sqlerrm) > 0 then
      r := r || E'\n[OK] A2 con 46-04 sola, otra configuración del mismo producto y acabado choca con el índice antiguo (requiere 46-05)'; ok := ok + 1;
    else r := r || E'\n[FALLO] A2 otro motivo: ' || sqlstate || ' ' || left(sqlerrm, 160); ko := ko + 1; end if;
  end;

  begin
    execute 'set local role authenticated';
    select string_agg(s.status || ':' || s.review || ':' || coalesce((select string_agg(x ->> 'code', ',') from jsonb_array_elements(s.reasons) x), ''), '|'
             order by case s.line_id when l_a then 1 when l_b then 2 when l_p then 3 when l_u then 4 when l_plain then 5 when l_other then 6 end)
      into v_t from public.project_line_states(v_proj) s;
    execute 'reset role';
    if v_t = 'completa:sin_cambios:|completa:sin_cambios:|pendiente:revisar:falta_eleccion|pendiente:revisar:falta_eleccion|no_requiere:sin_cambios:|no_requiere:sin_cambios:' then
      r := r || E'\n[OK] A3 estados: completa, completa, pendiente (falta Driver), pendiente (sin configurar), no requiere ×2'; ok := ok + 1;
    else r := r || E'\n[FALLO] A3 estados: ' || coalesce(v_t, '∅'); ko := ko + 1; end if;
  exception when others then r := r || E'\n[FALLO] A3: ' || sqlstate || ' ' || left(sqlerrm, 160); ko := ko + 1;
  end;

  begin
    execute 'set local role authenticated';
    select l into v from jsonb_array_elements(public.project_request_lines(v_proj)) l where (l ->> 'line_id')::uuid = l_a;
    execute 'reset role';
    select string_agg((i ->> 'option') || ':' || (i ->> 'supply') || ':' || coalesce(i ->> 'factor', '-') || ':' || coalesce(i ->> 'total_quantity', '-')
                      || ':' || (i ->> 'quantity_status') || ':' || (i ->> 'unit'), '|' order by i ->> 'option')
      into v_t from jsonb_array_elements(v -> 'items') i;
    if v_t = 'comp:incluido:2:6:calculada:ud.|d:aparte:2:6:calculada:ud.|panel:aparte:1.5:4.5:calculada:m²|perfil:aparte:-:-:a_calcular:ud.' then
      r := r || E'\n[OK] A4 cantidades por ruta (2, 2×1, 1,5; «a calcular» sin total) y suministro propio de cada relación'; ok := ok + 1;
    else r := r || E'\n[FALLO] A4 elementos: ' || coalesce(v_t, '∅'); ko := ko + 1; end if;
  exception when others then r := r || E'\n[FALLO] A4: ' || sqlstate || ' ' || left(sqlerrm, 160); ko := ko + 1;
  end;

  declare
    casos text[][] := array[
      array['A5a opción inexistente', '{"choices":[{"group":"fuente","options":["zzz"]}]}'],
      array['A5b elección huérfana',  '{"choices":[{"group":"fuente","options":["calida"]},{"path":[{"group":"fuente","option":"calida"}],"group":"drv","options":["d"]}]}'],
      array['A5c no aplicable',       '{"choices":[{"group":"fuente","options":["calida"]},{"group":"lente","options":["panel"]}]}'],
      array['A5d dos en «una»',       '{"choices":[{"group":"fuente","options":["comp","calida"]}]}'],
      array['A5e mal formada',        '{"choices":"x"}']];
    k int;
  begin
    for k in 1 .. array_length(casos, 1) loop
      begin
        execute 'set local role authenticated';
        update public.project_products set configuration = casos[k][2]::jsonb where id = l_b;
        execute 'reset role';
        r := r || E'\n[FALLO] ' || casos[k][1] || ': se aceptó'; ko := ko + 1;
        raise exception 'deshacer';
      exception when others then
        if sqlerrm = 'deshacer' then null;
        elsif sqlstate = '23514' then r := r || E'\n[OK] ' || casos[k][1] || ' rechazada al guardar: ' || left(sqlerrm, 90); ok := ok + 1;
        else r := r || E'\n[FALLO] ' || casos[k][1] || ' otro motivo: ' || sqlstate || ' ' || left(sqlerrm, 150); ko := ko + 1; end if;
      end;
    end loop;
  end;

  begin
    execute 'set local role authenticated';
    update public.project_products set config_key = '' where id = l_a;
    execute 'reset role';
    r := r || E'\n[FALLO] A6 clave escrita por el cliente'; ko := ko + 1; raise exception 'deshacer';
  exception when others then
    if sqlerrm = 'deshacer' then null;
    elsif sqlstate = '42501' then r := r || E'\n[OK] A6 config_key no es escribible por Individual'; ok := ok + 1;
    else r := r || E'\n[FALLO] A6 otro motivo: ' || sqlstate || ' ' || left(sqlerrm, 150); ko := ko + 1; end if;
  end;

  begin
    select config_key, config_snapshot ->> 'taken_at' into v_key, v_taken from public.project_products where id = l_a;
    execute 'set local role authenticated';
    update public.project_products set quantity = 4 where id = l_a;
    execute 'reset role';
    if (select config_key = v_key and config_snapshot ->> 'taken_at' = v_taken and quantity = 4 from public.project_products where id = l_a) then
      r := r || E'\n[OK] A7 cambiar la cantidad conserva configuración, clave y resumen'; ok := ok + 1;
    else r := r || E'\n[FALLO] A7 la configuración cambió'; ko := ko + 1; end if;
  exception when others then r := r || E'\n[FALLO] A7: ' || sqlstate || ' ' || left(sqlerrm, 160); ko := ko + 1;
  end;

  -- Cambios del catálogo (administración): opción retirada → revisar; etiqueta → informativo; la clave no depende de etiquetas ni del resumen
  begin
    update public.product_component_options set status = 'retirado' where group_id = g_lente and code = 'perfil';
    update public.product_component_groups set label = 'Fuente de luz' where id = g_fuente;
    set constraints all immediate; set constraints all deferred;
    execute 'set local role authenticated';
    select string_agg(s.status || ':' || s.review, '|' order by case s.line_id when l_a then 1 else 2 end) into v_t
      from public.project_line_states(v_proj) s where s.line_id in (l_a, l_b);
    execute 'reset role';
    if v_t = 'pendiente:revisar|completa:informativo'
       and (select configuration = public.line_configuration_normalized(cfg_a) and config_key = v_key from public.project_products where id = l_a) then
      r := r || E'\n[OK] A8 opción retirada → pendiente/revisar con la elección y la clave intactas; etiqueta cambiada → informativo'; ok := ok + 1;
    else r := r || E'\n[FALLO] A8 estados: ' || coalesce(v_t, '∅'); ko := ko + 1; end if;
  exception when others then r := r || E'\n[FALLO] A8: ' || sqlstate || ' ' || left(sqlerrm, 160); ko := ko + 1;
  end;

  begin
    execute 'set local role authenticated';
    insert into public.rfqs (project_id, requester_user_id, requester_name, requester_email, status, consent_to_share_contact)
      values (v_proj, v_ind, 'Ensayo 46-04', 'ensayo@example.invalid', 'submitted', true);
    execute 'reset role';
    r := r || E'\n[FALLO] A9 RFQ con configuraciones pendientes aceptada'; ko := ko + 1; raise exception 'deshacer';
  exception when others then
    if sqlerrm = 'deshacer' then null;
    elsif sqlstate = '23514' and position('Completa la configuración' in sqlerrm) > 0 then r := r || E'\n[OK] A9 RFQ bloqueada: ' || left(sqlerrm, 110); ok := ok + 1;
    else r := r || E'\n[FALLO] A9 otro motivo: ' || sqlstate || ' ' || left(sqlerrm, 160); ko := ko + 1; end if;
  end;

  begin
    update public.product_component_options set status = 'activo' where group_id = g_lente and code = 'perfil';
    set constraints all immediate; set constraints all deferred;
    execute 'set local role authenticated';
    update public.project_products set selected_for_rfq = false where id in (l_p, l_u);
    insert into public.rfqs (project_id, requester_user_id, requester_name, requester_email, status, consent_to_share_contact, lines_snapshot)
      values (v_proj, v_ind, 'Ensayo 46-04', 'ensayo@example.invalid', 'submitted', true, '{"falsa":true}') returning id into v_rfq1;
    execute 'reset role';
    select lines_snapshot into v from public.rfqs where id = v_rfq1;
    v_md5_rfq1 := md5(v::text);
    select string_agg((d ->> 'distributor_id') || '=' || (select string_agg(l ->> 'product_id' || ':' || (l ->> 'config_status'), ',' order by l ->> 'product_id', l ->> 'config_status')
                                                            from jsonb_array_elements(d -> 'lines') l), '|' order by d ->> 'distributor_id')
      into v_t from jsonb_array_elements(v -> 'distributors') d;
    if not (v ? 'falsa') and (v ->> 'version') = '1'
       and v_t = 'charo=z46c-other:no_requiere|spectro=z46c-plain:no_requiere,z46c-root:completa,z46c-root:completa'
       and jsonb_path_exists(v, '$.distributors[*].lines[*].items[*] ? (@.option == "perfil" && @.quantity_status == "a_calcular")')
       and jsonb_path_exists(v, '$.distributors[*].lines[*].items[*] ? (@.option == "comp" && @.total_quantity == 8)') then
      r := r || E'\n[OK] A10 RFQ creada por Individual con copia del servidor (sin lo enviado por el navegador), «a calcular» identificado'; ok := ok + 1;
    else r := r || E'\n[FALLO] A10 copia inesperada: ' || coalesce(v_t, '∅'); ko := ko + 1; end if;
    -- cada distribuidor solo recibe lo suyo: líneas y componentes de su empresa
    select count(*) into v_n
      from jsonb_array_elements(v -> 'distributors') d, jsonb_array_elements(d -> 'lines') l
     where (select pr.distributor_id from public.products pr where pr.id = l ->> 'product_id') is distinct from (d ->> 'distributor_id')
        or exists (select 1 from jsonb_array_elements(l -> 'items') i join public.products pr on pr.id = i ->> 'product_id'
                    where pr.distributor_id <> (d ->> 'distributor_id'));
    if v_n = 0 and jsonb_array_length(v -> 'distributors') = 2 then
      r := r || E'\n[OK] A11 copia separada por distribuidor: cada sección solo contiene líneas y componentes de esa empresa'; ok := ok + 1;
    else r := r || E'\n[FALLO] A11 elementos fuera de su distribuidor: ' || v_n; ko := ko + 1; end if;
  exception when others then r := r || E'\n[FALLO] A10: ' || sqlstate || ' ' || left(sqlerrm, 160); ko := ko + 1;
  end;

  begin
    update public.rfqs set lines_snapshot = '{}'::jsonb where id = v_rfq1;
    r := r || E'\n[FALLO] A12 copia modificada'; ko := ko + 1; raise exception 'deshacer';
  exception when others then
    if sqlerrm = 'deshacer' then null;
    elsif sqlstate = '42501' then r := r || E'\n[OK] A12 copia inmutable (ni siquiera como administración): ' || left(sqlerrm, 70); ok := ok + 1;
    else r := r || E'\n[FALLO] A12 otro motivo: ' || sqlstate || ' ' || left(sqlerrm, 150); ko := ko + 1; end if;
  end;

  -- Varias RFQ del mismo proyecto: cada una conserva su copia
  begin
    execute 'set local role authenticated';
    update public.project_products set quantity = 5 where id = l_a;
    insert into public.rfqs (project_id, requester_user_id, requester_name, requester_email, status, consent_to_share_contact)
      values (v_proj, v_ind, 'Ensayo 46-04', 'ensayo@example.invalid', 'submitted', true) returning id into v_rfq2;
    execute 'reset role';
    if md5((select lines_snapshot from public.rfqs where id = v_rfq1)::text) = v_md5_rfq1
       and jsonb_path_exists((select lines_snapshot from public.rfqs where id = v_rfq2), '$.distributors[*].lines[*].items[*] ? (@.option == "comp" && @.total_quantity == 10)') then
      r := r || E'\n[OK] A13 segunda RFQ del mismo proyecto con su propia copia; la primera no cambia'; ok := ok + 1;
    else r := r || E'\n[FALLO] A13 copias inesperadas'; ko := ko + 1; end if;
  exception when others then r := r || E'\n[FALLO] A13: ' || sqlstate || ' ' || left(sqlerrm, 160); ko := ko + 1;
  end;

  if (select count(*) from public.rfqs where id not in (v_rfq1, v_rfq2) and lines_snapshot is not null) = 0
     and (mobau_private.product_reference_counts('z46c-sub') ->> 'configured_lines')::int >= 1
     and (mobau_private.product_reference_counts('z46c-sub') ->> 'rfq_snapshots')::int = 2
     and (mobau_private.product_reference_counts('z46c-other') ->> 'rfq_snapshots')::int = 2 then
    r := r || E'\n[OK] A14 RFQ anteriores sin copia; configuraciones y copias cuentan como referencias para la purga'; ok := ok + 1;
  else r := r || E'\n[FALLO] A14 ' || coalesce(mobau_private.product_reference_counts('z46c-sub')::text, '∅'); ko := ko + 1; end if;

  -- Permisos con roles efectivos: otro particular, el distribuidor y anon
  begin
    perform set_config('request.jwt.claims', claims_gra, true);
    perform set_config('request.jwt.claim.sub', v_gra::text, true);
    execute 'set local role authenticated';
    select (select count(*) from public.project_products where project_id = v_proj)
         + (select count(*) from public.project_line_states(v_proj))
         + jsonb_array_length(public.project_request_lines(v_proj))
         + (select count(*) from public.rfqs where id in (v_rfq1, v_rfq2)) into v_n;
    execute 'reset role';
    if v_n = 0 then r := r || E'\n[OK] A15 otro particular (Gratis) no ve líneas, estados, vista previa ni copias'; ok := ok + 1;
    else r := r || E'\n[FALLO] A15 visibles: ' || v_n; ko := ko + 1; end if;
  exception when others then r := r || E'\n[FALLO] A15: ' || sqlstate || ' ' || left(sqlerrm, 160); ko := ko + 1;
  end;
  begin
    perform set_config('request.jwt.claims', claims_sup, true);
    perform set_config('request.jwt.claim.sub', v_sup::text, true);
    execute 'set local role authenticated';
    select (select count(*) from public.project_products where project_id = v_proj)
         + jsonb_array_length(public.project_request_lines(v_proj))
         + (select count(*) from public.rfqs where id in (v_rfq1, v_rfq2)) into v_n;
    execute 'reset role';
    if v_n = 0 then r := r || E'\n[OK] A16 el distribuidor (spectro) no lee líneas ni copias de RFQ (sin acceso de distribuidor a RFQ)'; ok := ok + 1;
    else r := r || E'\n[FALLO] A16 visibles: ' || v_n; ko := ko + 1; end if;
  exception when others then r := r || E'\n[FALLO] A16: ' || sqlstate || ' ' || left(sqlerrm, 160); ko := ko + 1;
  end;
  begin
    perform set_config('request.jwt.claims', '{"role":"anon"}', true);
    perform set_config('request.jwt.claim.sub', '', true);
    execute 'set local role anon';
    perform public.line_configuration_resolve('z46c-root', null);
    execute 'reset role';
    r := r || E'\n[FALLO] A17 anon ejecutó el resolvedor'; ko := ko + 1; raise exception 'deshacer';
  exception when others then
    if sqlerrm = 'deshacer' then null;
    elsif sqlstate = '42501' then r := r || E'\n[OK] A17 anon no ejecuta las funciones nuevas'; ok := ok + 1;
    else r := r || E'\n[FALLO] A17 otro motivo: ' || sqlstate || ' ' || left(sqlerrm, 150); ko := ko + 1; end if;
  end;

  -- Recuperaciones: solo se ejecutan sus comprobaciones previas (nunca la recuperación)
  v_i := strpos(t_rb4, E'\nDO $$\n'); v_rest := substr(t_rb4, v_i + 1); v_j := strpos(v_rest, E'\nend $$;');
  begin
    execute substr(v_rest, 1, v_j + 7);
    r := r || E'\n[FALLO] R1 la recuperación de 46-04 no se detuvo con configuraciones'; ko := ko + 1;
  exception when others then
    if position('hay líneas con configuración' in sqlerrm) > 0 then r := r || E'\n[OK] R1 recuperación de 46-04: se detiene si perdería configuraciones'; ok := ok + 1;
    else r := r || E'\n[FALLO] R1 otro motivo: ' || left(sqlerrm, 150); ko := ko + 1; end if;
  end;
  begin
    delete from public.project_products where project_id = v_proj and configuration is not null;
    begin
      execute substr(v_rest, 1, v_j + 7);
      r := r || E'\n[FALLO] R2 la recuperación de 46-04 no se detuvo con copias de RFQ'; ko := ko + 1;
    exception when others then
      if position('copia de lo solicitado' in sqlerrm) > 0 then r := r || E'\n[OK] R2 recuperación de 46-04: se detiene si perdería copias de RFQ'; ok := ok + 1;
      else r := r || E'\n[FALLO] R2 otro motivo: ' || left(sqlerrm, 150); ko := ko + 1; end if;
    end;
    raise exception 'deshacer';
  exception when others then
    if sqlerrm <> 'deshacer' then r := r || E'\n[FALLO] R2: ' || left(sqlerrm, 150); ko := ko + 1; end if;
  end;
  v_i := strpos(t_rb5, E'\nDO $$\n'); v_rest := substr(t_rb5, v_i + 1); v_j := strpos(v_rest, E'\nend $$;');
  begin
    execute substr(v_rest, 1, v_j + 7);
    r := r || E'\n[FALLO] R3 la recuperación de 46-05 no se detuvo con el índice antiguo presente'; ko := ko + 1;
  exception when others then
    if position('el índice antiguo ya existe' in sqlerrm) > 0 then r := r || E'\n[OK] R3 recuperación de 46-05: no actúa mientras 46-05 no esté aplicada'; ok := ok + 1;
    else r := r || E'\n[FALLO] R3 otro motivo: ' || left(sqlerrm, 150); ko := ko + 1; end if;
  end;

  -- ===== FASE B · estado final de 46-05 (índice antiguo retirado DENTRO de esta transacción) =====
  drop index public.project_products_line_unique;
  r := r || E'\n[INFO] fase B: índice antiguo retirado dentro de la transacción (se restaura con el rollback)';
  perform set_config('request.jwt.claims', claims_ind, true);
  perform set_config('request.jwt.claim.sub', v_ind::text, true);
  begin
    execute 'set local role authenticated';
    insert into public.project_products (project_id, product_id, finish_code, quantity, unit, configuration) values (v_proj, 'z46c-root', 'k1', 1, 'ud.', cfg_b);
    insert into public.project_products (project_id, product_id, finish_code, quantity, unit) values (v_proj, 'z46c-root', 'k1', 1, 'ud.');
    execute 'reset role';
    if (select count(*) from public.project_products where project_id = v_proj and product_id = 'z46c-root' and finish_code = 'k1') = 3 then
      r := r || E'\n[OK] B1 (requiere 46-05) mismo producto y acabado con dos configuraciones y una línea sin configurar'; ok := ok + 1;
    else r := r || E'\n[FALLO] B1 líneas inesperadas'; ko := ko + 1; end if;
  exception when others then r := r || E'\n[FALLO] B1: ' || sqlstate || ' ' || left(sqlerrm, 160); ko := ko + 1;
  end;
  declare
    casos jsonb[] := array[null, cfg_a]::jsonb[];
    nombres text[] := array['B2 (requiere 46-05) segunda línea sin configurar', 'B3 (requiere 46-05) configuración equivalente en otro orden'];
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
        elsif sqlstate = '23505' then r := r || E'\n[OK] ' || nombres[k] || ': rechazada como la misma línea'; ok := ok + 1;
        else r := r || E'\n[FALLO] ' || nombres[k] || ' otro motivo: ' || sqlstate || ' ' || left(sqlerrm, 150); ko := ko + 1; end if;
      end;
    end loop;
  end;
  begin
    execute substr(v_rest, 1, v_j + 7);
    r := r || E'\n[FALLO] R4 la recuperación de 46-05 no se detuvo con líneas que impiden el índice antiguo'; ko := ko + 1;
  exception when others then
    if position('configuraciones distintas del mismo producto y acabado' in sqlerrm) > 0 then r := r || E'\n[OK] R4 recuperación de 46-05: se detiene si hay líneas que impedirían el índice antiguo'; ok := ok + 1;
    else r := r || E'\n[FALLO] R4 otro motivo: ' || left(sqlerrm, 150); ko := ko + 1; end if;
  end;

  begin
    set constraints all immediate;
    r := r || E'\n[OK] Integridad diferida evaluada sin errores antes del cierre'; ok := ok + 1;
  exception when others then r := r || E'\n[FALLO] Integridad diferida al cierre: ' || sqlerrm; ko := ko + 1;
  end;

  raise exception 'CIERRE DELIBERADO DEL ENSAYO 46-04 (todo revertido) · % correctos · % fallos inesperados%', ok, ko, r;
end $TEST$;
