-- ============================================================
-- PROPUESTA NO EJECUTADA (46-04 · configuraciones en proyecto y copia de RFQ) — no ejecutar sin aprobación explícita
-- ============================================================
-- Punto 46 · bloque 3 (base de datos). Aditiva: la web actual sigue
-- funcionando igual; el índice único antiguo (producto + acabado) se
-- mantiene hasta 46-05, que solo se aplica con la web compatible publicada.
--   * project_products.configuration (jsonb, lo escribe el cliente):
--       null → sin configuración (comportamiento actual).
--       {"choices": [{"path": [{"group","option"}...], "group", "options": [...]}]}
--       Elecciones por ruta con las claves estables de 46-01. El servidor la
--       normaliza (solo el orden), de modo que el orden de los clics o de las
--       claves no crea líneas distintas. Nada se descarta: un grupo o una
--       opción repetidos se rechazan, no se fusionan.
--   * config_key (servidor): '' sin configuración; md5 de la forma normal.
--     Identidad de línea: proyecto + producto + acabado + config_key.
--   * config_snapshot (servidor): resumen conservado al guardar (elecciones
--     resueltas con producto, acabado, ajuste, suministro, cantidad por
--     unidad del padre y por unidad de la línea, motivos y avisos).
--   * line_configuration_resolve: estado contra el catálogo actual
--     (no_requiere | completa | pendiente, con motivos). «Completa» = las
--     elecciones necesarias están hechas; no es validación técnica.
--   * project_line_states: estado de cada línea y revisión (sin_cambios |
--     informativo | revisar) respecto al resumen guardado.
--   * rfqs.lines_snapshot: copia inmutable generada en el servidor al crear
--     la RFQ con las líneas autorizadas del proyecto (se ignora lo que envíe
--     el navegador). Bloquea configuraciones pendientes; admite cantidades
--     «a calcular» identificadas como tales. Las RFQ anteriores quedan sin
--     copia (null): no se les inventa una.
--   * product_reference_counts: configuraciones y copias de RFQ cuentan
--     como referencias (bloquean la purga).
-- Las líneas existentes no se convierten: quedan sin configuración.
-- Si se aplica, se registra como migración NUEVA tras confirmar su COMMIT.
-- Ejecutar completo.
-- ============================================================

BEGIN;

create function pg_temp.r4604(t text, a text, b text) returns text language plpgsql as $$
begin
  if (length(t) - length(replace(t, a, ''))) <> length(a) then
    raise exception '46-04: el fragmento no aparece exactamente una vez: %', left(a, 80);
  end if;
  return replace(t, a, b);
end $$;

DO $$
begin
  if current_user <> 'postgres' then
    raise exception '46-04: ejecutar como postgres';
  end if;
  if not exists (select 1 from supabase_migrations.schema_migrations where version = '20261031120000')
     or exists (select 1 from supabase_migrations.schema_migrations where version = '20261101120000') then
    raise exception '46-04: el registro de migraciones no es el esperado (46-03 registrada y 46-04 sin registrar)';
  end if;
  if exists (select 1 from information_schema.columns where table_schema = 'public'
               and ((table_name = 'project_products' and column_name in ('configuration', 'config_key', 'config_snapshot'))
                    or (table_name = 'rfqs' and column_name = 'lines_snapshot'))) then
    raise exception '46-04: alguna columna nueva ya existe';
  end if;
  if (select indexdef from pg_indexes where schemaname = 'public' and indexname = 'project_products_line_unique')
       is distinct from 'CREATE UNIQUE INDEX project_products_line_unique ON public.project_products USING btree (project_id, product_id, COALESCE(finish_code, ''''::text))' then
    raise exception '46-04: el índice único de líneas no es el esperado';
  end if;
  if exists (select 1 from pg_trigger where not tgisinternal and tgrelid in ('public.project_products'::regclass, 'public.rfqs'::regclass)) then
    raise exception '46-04: project_products o rfqs ya tienen triggers';
  end if;
  if (select md5(prosrc) from pg_proc where oid = 'mobau_private.product_reference_counts(text)'::regprocedure) <> '69f5ee71cbed763b505986669083c09c' then
    raise exception '46-04: product_reference_counts no es la esperada';
  end if;
  perform set_config('mobau.p4604_lineas', md5(coalesce((select string_agg(to_jsonb(x)::text, '|' order by x.id) from public.project_products x), '')), true);
  perform set_config('mobau.p4604_rfqs', md5(coalesce((select string_agg(to_jsonb(x)::text, '|' order by x.id) from public.rfqs x), '')), true);
end $$;

-- 1. Columnas
alter table public.project_products
  add column configuration jsonb,
  add column config_key text not null default '',
  add column config_snapshot jsonb;
alter table public.project_products
  add constraint project_products_configuration_shape
    check (configuration is null or (jsonb_typeof(configuration) = 'object' and pg_column_size(configuration) <= 16384)),
  add constraint project_products_config_key_format
    check (config_key = '' or config_key ~ '^[0-9a-f]{32}$'),
  add constraint project_products_config_key_consistent
    check ((configuration is null) = (config_key = ''));
comment on column public.project_products.configuration is
  '46-04: elecciones por ruta ({"choices":[{"path":[{"group","option"}],"group","options":[...]}]}); null = sin configuración. El servidor la normaliza.';
comment on column public.project_products.config_key is
  '46-04: identidad de la configuración (servidor): '''' sin configuración; md5 de la forma normal.';
comment on column public.project_products.config_snapshot is
  '46-04: resumen resuelto al guardar la configuración (servidor).';

alter table public.rfqs add column lines_snapshot jsonb;
alter table public.rfqs add constraint rfqs_lines_snapshot_shape
  check (lines_snapshot is null or jsonb_typeof(lines_snapshot) = 'object');
comment on column public.rfqs.lines_snapshot is
  '46-04: copia inmutable de lo solicitado, generada en el servidor al crear la RFQ; null en las RFQ anteriores.';

-- 2. Permisos: el cliente escribe la configuración; config_key y config_snapshot
--    los fija siempre el trigger (al insertar se ignora lo enviado: authenticated
--    tiene INSERT de tabla) y no son actualizables por el cliente.
grant insert (configuration), update (configuration) on table public.project_products to authenticated;

-- 3. Forma normal de una configuración (pura)
create function public.line_configuration_normalized(p jsonb) returns jsonb
  language plpgsql immutable set search_path = '' as $$
declare
  ch jsonb;
  el jsonb;
  k text;
  s text;
  v_path jsonb;
  v_opts jsonb;
  v_key text;
  v_seen text[] := '{}'::text[];
  v_out jsonb := '[]'::jsonb;
begin
  if p is null then
    return null;
  end if;
  if pg_catalog.jsonb_typeof(p) <> 'object' then
    raise exception 'La configuración no es válida.' using errcode = '23514';
  end if;
  for k in select pg_catalog.jsonb_object_keys(p) loop
    if k <> 'choices' then
      raise exception 'Campo no permitido en la configuración: %.', k using errcode = '23514';
    end if;
  end loop;
  if not (p ? 'choices') then
    return null;
  end if;
  if pg_catalog.jsonb_typeof(p -> 'choices') <> 'array' then
    raise exception 'Las elecciones de la configuración no son válidas.' using errcode = '23514';
  end if;
  if pg_catalog.jsonb_array_length(p -> 'choices') > 60 then
    raise exception 'La configuración tiene demasiadas elecciones (máximo 60).' using errcode = '23514';
  end if;

  for ch in select e from pg_catalog.jsonb_array_elements(p -> 'choices') as e loop
    if pg_catalog.jsonb_typeof(ch) <> 'object' then
      raise exception 'Alguna elección de la configuración no es válida.' using errcode = '23514';
    end if;
    for k in select pg_catalog.jsonb_object_keys(ch) loop
      if k not in ('path', 'group', 'options') then
        raise exception 'Alguna elección de la configuración no es válida.' using errcode = '23514';
      end if;
    end loop;
    -- grupo
    if pg_catalog.jsonb_typeof(ch -> 'group') is distinct from 'string' then
      raise exception 'Alguna elección no indica su grupo.' using errcode = '23514';
    end if;
    s := ch ->> 'group';
    if s <> pg_catalog.btrim(s) or pg_catalog.char_length(s) not between 1 and 40 then
      raise exception 'Alguna elección no indica su grupo.' using errcode = '23514';
    end if;
    -- ruta: pares grupo/opción desde el producto principal (máximo dos niveles)
    v_path := '[]'::jsonb;
    if ch ? 'path' then
      if pg_catalog.jsonb_typeof(ch -> 'path') <> 'array' then
        raise exception 'La ruta de alguna elección no es válida.' using errcode = '23514';
      end if;
      if pg_catalog.jsonb_array_length(ch -> 'path') > 2 then
        raise exception 'La ruta de alguna elección no es válida.' using errcode = '23514';
      end if;
      for el in select e from pg_catalog.jsonb_array_elements(ch -> 'path') as e loop
        if pg_catalog.jsonb_typeof(el) <> 'object' then
          raise exception 'La ruta de alguna elección no es válida.' using errcode = '23514';
        end if;
        for k in select pg_catalog.jsonb_object_keys(el) loop
          if k not in ('group', 'option') then
            raise exception 'La ruta de alguna elección no es válida.' using errcode = '23514';
          end if;
        end loop;
        if pg_catalog.jsonb_typeof(el -> 'group') is distinct from 'string'
           or pg_catalog.jsonb_typeof(el -> 'option') is distinct from 'string' then
          raise exception 'La ruta de alguna elección no es válida.' using errcode = '23514';
        end if;
        if (el ->> 'group') <> pg_catalog.btrim(el ->> 'group') or pg_catalog.char_length(el ->> 'group') not between 1 and 40
           or (el ->> 'option') <> pg_catalog.btrim(el ->> 'option') or pg_catalog.char_length(el ->> 'option') not between 1 and 40 then
          raise exception 'La ruta de alguna elección no es válida.' using errcode = '23514';
        end if;
        v_path := v_path || pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object('group', el ->> 'group', 'option', el ->> 'option'));
      end loop;
    end if;
    -- opciones: al menos una; una opción repetida se rechaza (no se descarta); orden fijo (intercalación "C")
    if pg_catalog.jsonb_typeof(ch -> 'options') is distinct from 'array' then
      raise exception 'Cada elección necesita al menos una opción.' using errcode = '23514';
    end if;
    if pg_catalog.jsonb_array_length(ch -> 'options') not between 1 and 30 then
      raise exception 'Cada elección necesita entre 1 y 30 opciones.' using errcode = '23514';
    end if;
    for el in select e from pg_catalog.jsonb_array_elements(ch -> 'options') as e loop
      if pg_catalog.jsonb_typeof(el) <> 'string' then
        raise exception 'Alguna opción elegida no es válida.' using errcode = '23514';
      end if;
      s := el #>> '{}';
      if s <> pg_catalog.btrim(s) or pg_catalog.char_length(s) not between 1 and 40 then
        raise exception 'Alguna opción elegida no es válida.' using errcode = '23514';
      end if;
    end loop;
    if (select count(distinct e) from pg_catalog.jsonb_array_elements_text(ch -> 'options') as e)
       <> pg_catalog.jsonb_array_length(ch -> 'options') then
      raise exception 'Una opción aparece dos veces en la misma elección.' using errcode = '23514';
    end if;
    select pg_catalog.jsonb_agg(e order by e collate "C") into v_opts
      from pg_catalog.jsonb_array_elements_text(ch -> 'options') as e;
    v_key := v_path::text || '|' || (ch ->> 'group');
    if v_key = any (v_seen) then
      raise exception 'Hay dos elecciones para el mismo grupo.' using errcode = '23514';
    end if;
    v_seen := v_seen || v_key;
    v_out := v_out || pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object('path', v_path, 'group', ch ->> 'group', 'options', v_opts));
  end loop;

  if pg_catalog.jsonb_array_length(v_out) = 0 then
    return null;
  end if;
  return pg_catalog.jsonb_build_object('choices',
    (select pg_catalog.jsonb_agg(x order by (x -> 'path')::text collate "C", (x ->> 'group') collate "C")
       from pg_catalog.jsonb_array_elements(v_out) as x));
end $$;

-- 4. Resolución contra el catálogo actual (solo vistas públicas del catálogo;
--    con permisos de quien llama). No sustituye ni descarta elecciones: lo que
--    no encaja se devuelve como motivo.
create function public.line_configuration_resolve(p_product_id text, p_configuration jsonb) returns jsonb
  language plpgsql stable set search_path = '' as $$
declare
  v_cfg jsonb := public.line_configuration_normalized(p_configuration);
  v_choices jsonb;
  v_items jsonb := '[]'::jsonb;
  v_reasons jsonb := '[]'::jsonb;
  v_notices jsonb := '[]'::jsonb;
  v_handled text[] := '{}'::text[];
  v_level jsonb;
  v_next jsonb;
  v_depth integer := 0;
  c jsonb;
  ch jsonb;
  g record;
  o record;
  v_pname text;
  v_pbrand text;
  v_pref text;
  v_pcat text;
  v_opts jsonb;
  v_code text;
  v_valid integer;
  v_applicable boolean;
  v_factor numeric;
  v_finish_name text;
  v_where text;
begin
  v_choices := coalesce(v_cfg -> 'choices', '[]'::jsonb);
  if v_cfg is null and not exists (select 1 from public.catalog_component_groups cg where cg.product_id = p_product_id) then
    return pg_catalog.jsonb_build_object('status', 'no_requiere', 'reasons', '[]'::jsonb, 'notices', '[]'::jsonb,
                                         'items', '[]'::jsonb, 'summary', '');
  end if;

  -- Recorrido por niveles: principal → componente → subcomponente.
  v_level := pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object(
               'product_id', p_product_id, 'product_name', null, 'path', '[]'::jsonb, 'factor', 1));
  while pg_catalog.jsonb_array_length(v_level) > 0 and v_depth < 3 loop
    v_depth := v_depth + 1;
    v_next := '[]'::jsonb;
    for c in select e from pg_catalog.jsonb_array_elements(v_level) as e loop
      v_where := case when (c ->> 'product_name') is null then '' else ' (en ' || (c ->> 'product_name') || ')' end;
      for g in select cg.id, cg.code, cg.label, cg.requirement, cg.choice, cg.depends_on_option_id
                 from public.catalog_component_groups cg
                where cg.product_id = (c ->> 'product_id')
                order by cg.sort_order, cg.code loop
        v_handled := v_handled || ((c -> 'path')::text || '|' || g.code);
        select x into ch from pg_catalog.jsonb_array_elements(v_choices) as x
         where (x -> 'path') = (c -> 'path') and (x ->> 'group') = g.code;
        v_opts := coalesce(ch -> 'options', '[]'::jsonb);

        v_applicable := true;
        if g.depends_on_option_id is not null then
          select exists (
            select 1 from public.catalog_component_options dopt
              join public.catalog_component_groups dg on dg.id = dopt.group_id
              join pg_catalog.jsonb_array_elements(v_choices) as y
                on (y -> 'path') = (c -> 'path') and (y ->> 'group') = dg.code
             where dopt.id = g.depends_on_option_id and (y -> 'options') ? dopt.code) into v_applicable;
        end if;
        if not v_applicable then
          if pg_catalog.jsonb_array_length(v_opts) > 0 then
            v_reasons := v_reasons || pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object(
              'code', 'eleccion_no_aplicable', 'path', c -> 'path', 'group', g.code,
              'message', pg_catalog.format('«%s»%s ya no aplica con las demás elecciones: revísalo.', g.label, v_where)));
          end if;
          continue;
        end if;

        v_valid := 0;
        for v_code in select pg_catalog.jsonb_array_elements_text(v_opts) loop
          select co.id, co.code, co.kind, co.component_product_id, co.component_finish_code, co.setting_label,
                 co.supply, co.quantity, co.quantity_mode, co.attributes
            into o
            from public.catalog_component_options co
           where co.group_id = g.id and co.code = v_code;
          if not found then
            v_reasons := v_reasons || pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object(
              'code', 'opcion_no_disponible', 'path', c -> 'path', 'group', g.code, 'option', v_code,
              'message', pg_catalog.format('Una opción elegida en «%s»%s ya no está disponible.', g.label, v_where)));
            continue;
          end if;
          v_valid := v_valid + 1;
          if o.kind = 'ajuste' then
            v_items := v_items || pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object(
              'path', c -> 'path', 'group', g.code, 'group_label', g.label, 'option', o.code, 'kind', 'ajuste',
              'setting_label', o.setting_label, 'attributes', o.attributes));
          else
            select cp.name, cp.brand, cp.reference_code, cp.category_id into v_pname, v_pbrand, v_pref, v_pcat
              from public.catalog_products cp where cp.id = o.component_product_id;
            v_finish_name := null;
            if o.component_finish_code is not null then
              select f.name into v_finish_name from public.product_finishes f
               where f.product_id = o.component_product_id and f.code = o.component_finish_code;
              if v_finish_name is null then
                v_notices := v_notices || pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object(
                  'code', 'acabado_no_disponible', 'path', c -> 'path', 'group', g.code, 'option', o.code,
                  'message', pg_catalog.format('El acabado indicado para «%s» ya no figura en el catálogo.', coalesce(v_pname, o.component_product_id))));
              end if;
            end if;
            -- Cantidad por unidad de la línea = producto de las cantidades de la
            -- ruta; «a calcular» en cualquier tramo la deja sin calcular.
            v_factor := case when o.quantity_mode = 'fija' and o.quantity is not null
                                  and pg_catalog.jsonb_typeof(c -> 'factor') = 'number'
                             then pg_catalog.trim_scale((c ->> 'factor')::numeric * o.quantity) end;
            v_items := v_items || pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object(
              'path', c -> 'path', 'group', g.code, 'group_label', g.label, 'option', o.code, 'kind', 'componente',
              'product_id', o.component_product_id, 'product_name', v_pname, 'brand', v_pbrand,
              'reference_code', v_pref, 'finish_code', o.component_finish_code, 'finish_name', v_finish_name,
              'supply', o.supply, 'quantity', pg_catalog.trim_scale(o.quantity), 'quantity_mode', o.quantity_mode, 'factor', v_factor,
              'unit', case when v_pcat = 'revestimientos' then 'm²' else 'ud.' end,
              'attributes', o.attributes));
            v_next := v_next || pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object(
              'product_id', o.component_product_id, 'product_name', v_pname,
              'path', (c -> 'path') || pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object('group', g.code, 'option', o.code)),
              'factor', v_factor));
          end if;
        end loop;

        if g.choice = 'una' and v_valid > 1 then
          v_reasons := v_reasons || pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object(
            'code', 'varias_en_una', 'path', c -> 'path', 'group', g.code,
            'message', pg_catalog.format('En «%s»%s solo se puede elegir una opción.', g.label, v_where)));
        end if;
        if g.requirement = 'necesario' and v_valid = 0 then
          v_reasons := v_reasons || pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object(
            'code', 'falta_eleccion', 'path', c -> 'path', 'group', g.code,
            'message', pg_catalog.format('Falta elegir «%s»%s.', g.label, v_where)));
        end if;
      end loop;
    end loop;
    v_level := v_next;
  end loop;

  for ch in select x from pg_catalog.jsonb_array_elements(v_choices) as x
             where not (((x -> 'path')::text || '|' || (x ->> 'group')) = any (v_handled)) loop
    v_reasons := v_reasons || pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object(
      'code', 'eleccion_huerfana', 'path', ch -> 'path', 'group', ch ->> 'group',
      'message', 'Una elección guardada ya no corresponde a las opciones de este producto: revísala.'));
  end loop;

  return pg_catalog.jsonb_build_object(
    'status', case when pg_catalog.jsonb_array_length(v_reasons) > 0 then 'pendiente' else 'completa' end,
    'reasons', v_reasons, 'notices', v_notices, 'items', v_items,
    'summary', coalesce((select pg_catalog.string_agg((t.i ->> 'group_label') || ': '
                                 || coalesce(t.i ->> 'product_name', t.i ->> 'setting_label', t.i ->> 'option'), ' · ' order by t.n)
                           from pg_catalog.jsonb_array_elements(v_items) with ordinality as t(i, n)), ''));
end $$;

-- 5. Estructura comparable (sin textos informativos) para distinguir cambios
create function public.line_configuration_structure(p_items jsonb) returns jsonb
  language sql immutable set search_path = '' as $$
  select coalesce(pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
           'path', i -> 'path', 'group', i -> 'group', 'option', i -> 'option', 'kind', i -> 'kind',
           'product_id', i -> 'product_id', 'finish_code', i -> 'finish_code', 'supply', i -> 'supply',
           'quantity', i -> 'quantity', 'quantity_mode', i -> 'quantity_mode')
         order by (i -> 'path')::text collate "C", (i ->> 'group') collate "C", (i ->> 'option') collate "C"), '[]'::jsonb)
    from pg_catalog.jsonb_array_elements(coalesce(p_items, '[]'::jsonb)) as i
$$;

-- 6. Estado de las líneas de un proyecto (RLS de project_products)
create function public.project_line_states(p_project_id uuid)
  returns table (line_id uuid, product_id text, finish_code text, config_key text, status text, review text,
                 reasons jsonb, notices jsonb, items jsonb, summary text)
  language sql stable set search_path = '' as $$
  select pp.id, pp.product_id, pp.finish_code, pp.config_key, s.r ->> 'status',
         case when s.r ->> 'status' = 'pendiente' then 'revisar'
              when pp.config_snapshot is null then 'sin_cambios'
              when public.line_configuration_structure(pp.config_snapshot -> 'items')
                   is distinct from public.line_configuration_structure(s.r -> 'items') then 'revisar'
              when (pp.config_snapshot -> 'items') is distinct from (s.r -> 'items') then 'informativo'
              else 'sin_cambios' end,
         s.r -> 'reasons', s.r -> 'notices', s.r -> 'items', s.r ->> 'summary'
    from public.project_products pp
    cross join lateral (select public.line_configuration_resolve(pp.product_id, pp.configuration) as r) s
   where pp.project_id = p_project_id
   order by pp.order_position, pp.created_at, pp.id
$$;

-- 7. Líneas autorizadas de un proyecto, en la forma de la copia de RFQ
--    (RLS de project_products; también sirve de vista previa)
create function public.project_request_lines(p_project_id uuid) returns jsonb
  language sql stable set search_path = '' as $$
  select coalesce(pg_catalog.jsonb_agg(x.line order by x.ord1, x.ord2, x.ord3), '[]'::jsonb)
    from (
      select pp.order_position as ord1, pp.created_at as ord2, pp.id as ord3,
             pg_catalog.jsonb_build_object(
               'line_id', pp.id, 'product_id', pp.product_id, 'product_name', cp.name, 'brand', cp.brand,
               'reference_code', cp.reference_code, 'category_id', cp.category_id,
               'distributor_id', cp.distributor_id, 'distributor_name', d.name,
               'finish_code', pp.finish_code, 'finish_name', pf.name, 'finish_reference_code', pf.reference_code,
               'quantity', pp.quantity, 'unit', pp.unit, 'room_or_area', pp.room_or_area, 'notes', pp.notes,
               'configuration', pp.configuration, 'config_key', pp.config_key,
               'config_status', s.r ->> 'status', 'config_reasons', s.r -> 'reasons',
               'config_notices', s.r -> 'notices', 'config_summary', s.r ->> 'summary',
               'items', (select coalesce(pg_catalog.jsonb_agg(i.e || pg_catalog.jsonb_build_object(
                                  'total_quantity',
                                    case when (i.e ->> 'kind') = 'componente' and pg_catalog.jsonb_typeof(i.e -> 'factor') = 'number'
                                              and pp.quantity is not null
                                         then pg_catalog.trim_scale(pg_catalog.round(pp.quantity * (i.e ->> 'factor')::numeric, 3)) end,
                                  'quantity_status',
                                    case when (i.e ->> 'kind') = 'ajuste' then 'no_aplica'
                                         when pg_catalog.jsonb_typeof(i.e -> 'factor') = 'number' and pp.quantity is not null then 'calculada'
                                         else 'a_calcular' end)
                                order by i.n), '[]'::jsonb)
                           from pg_catalog.jsonb_array_elements(s.r -> 'items') with ordinality as i(e, n))
             ) as line
        from public.project_products pp
        left join public.catalog_products cp on cp.id = pp.product_id
        left join public.distributors d on d.id = cp.distributor_id
        left join public.product_finishes pf on pf.product_id = pp.product_id and pf.code = pp.finish_code
        cross join lateral (select public.line_configuration_resolve(pp.product_id, pp.configuration) as r) s
       where pp.project_id = p_project_id and pp.selected_for_rfq
    ) x
$$;

-- 8. Trigger de líneas: normaliza la configuración y fija clave y resumen.
--    Si la configuración no cambia (p. ej. solo la cantidad), conserva lo guardado.
create function public.project_products_configuration() returns trigger
  language plpgsql set search_path = '' as $$
declare
  v jsonb;
  v_msg text;
begin
  if tg_op = 'UPDATE'
     and new.configuration is not distinct from old.configuration
     and new.product_id is not distinct from old.product_id
     and new.finish_code is not distinct from old.finish_code then
    new.config_key := old.config_key;
    new.config_snapshot := old.config_snapshot;
    return new;
  end if;
  new.configuration := public.line_configuration_normalized(new.configuration);
  if new.configuration is null then
    new.config_key := '';
    new.config_snapshot := null;
    return new;
  end if;
  v := public.line_configuration_resolve(new.product_id, new.configuration);
  -- Al guardar se rechazan elecciones que no existen o no encajan (nunca se
  -- sustituyen); faltar elecciones sí se admite: la línea queda pendiente.
  select r ->> 'message' into v_msg
    from pg_catalog.jsonb_array_elements(v -> 'reasons') as r
   where (r ->> 'code') in ('opcion_no_disponible', 'eleccion_huerfana', 'eleccion_no_aplicable', 'varias_en_una')
   limit 1;
  if v_msg is not null then
    raise exception '%', v_msg using errcode = '23514', hint = 'configuration_invalid';
  end if;
  new.config_key := pg_catalog.md5(new.configuration::text);
  new.config_snapshot := pg_catalog.jsonb_build_object(
    'taken_at', pg_catalog.now(), 'status', v -> 'status', 'summary', v -> 'summary',
    'items', v -> 'items', 'reasons', v -> 'reasons', 'notices', v -> 'notices');
  return new;
end $$;
create trigger trg_project_products_10_configuration before insert or update on public.project_products
  for each row execute function public.project_products_configuration();

-- 9. Trigger de RFQ: copia generada en el servidor e inmutable
create function public.rfqs_lines_snapshot() returns trigger
  language plpgsql set search_path = '' as $$
declare
  v_lines jsonb;
  v_pending text;
begin
  if tg_op = 'UPDATE' then
    if new.lines_snapshot is distinct from old.lines_snapshot then
      raise exception 'La copia de lo solicitado en una RFQ no se puede modificar.'
        using errcode = '42501', hint = 'rfq_snapshot_immutable';
    end if;
    return new;
  end if;

  -- INSERT: lo que envíe el navegador en lines_snapshot se ignora.
  v_lines := public.project_request_lines(new.project_id);
  select pg_catalog.string_agg(coalesce(l ->> 'product_name', l ->> 'product_id'), ', ') into v_pending
    from pg_catalog.jsonb_array_elements(v_lines) as l
   where (l ->> 'config_status') = 'pendiente';
  if v_pending is not null then
    raise exception 'Completa la configuración antes de enviar la solicitud: %.', v_pending
      using errcode = '23514', hint = 'configuration_pending';
  end if;
  new.lines_snapshot := pg_catalog.jsonb_build_object(
    'version', 1, 'taken_at', pg_catalog.now(), 'project_id', new.project_id,
    'distributors', (select coalesce(pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
                                 'distributor_id', gd.did, 'distributor_name', gd.dname, 'lines', gd.lines)
                               order by gd.did), '[]'::jsonb)
                       from (select (t.l ->> 'distributor_id') as did, max(t.l ->> 'distributor_name') as dname,
                                    pg_catalog.jsonb_agg(t.l order by t.n) as lines
                               from pg_catalog.jsonb_array_elements(v_lines) with ordinality as t(l, n)
                              group by (t.l ->> 'distributor_id')) gd));
  return new;
end $$;
create trigger trg_rfqs_10_lines_snapshot before insert or update on public.rfqs
  for each row execute function public.rfqs_lines_snapshot();

-- 10. Permisos de las funciones nuevas
revoke all on function public.line_configuration_normalized(jsonb) from public, anon, authenticated;
revoke all on function public.line_configuration_resolve(text, jsonb) from public, anon, authenticated;
revoke all on function public.line_configuration_structure(jsonb) from public, anon, authenticated;
revoke all on function public.project_line_states(uuid) from public, anon, authenticated;
revoke all on function public.project_request_lines(uuid) from public, anon, authenticated;
revoke all on function public.project_products_configuration() from public, anon, authenticated;
revoke all on function public.rfqs_lines_snapshot() from public, anon, authenticated;
grant execute on function public.line_configuration_normalized(jsonb) to authenticated;
grant execute on function public.line_configuration_resolve(text, jsonb) to authenticated;
grant execute on function public.line_configuration_structure(jsonb) to authenticated;
grant execute on function public.project_line_states(uuid) to authenticated;
grant execute on function public.project_request_lines(uuid) to authenticated;

-- 11. Identidad de línea con configuración (convive con el índice antiguo hasta 46-05)
create unique index project_products_config_line_unique
  on public.project_products (project_id, product_id, coalesce(finish_code, ''), config_key);

-- 12. Referencias para la purga: configuraciones guardadas y copias de RFQ
DO $$
declare
  d text := pg_get_functiondef('mobau_private.product_reference_counts(text)'::regprocedure);
begin
  d := pg_temp.r4604(d, $a$  v_unknown text[] := '{}'::text[];
begin
$a$, $a$  v_unknown text[] := '{}'::text[];
  v_cfg bigint;
  v_snap bigint;
begin
$a$);
  d := pg_temp.r4604(d, $a$  end loop;
  return pg_catalog.jsonb_build_object(
$a$, $a$  end loop;
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
$a$);
  execute d;
end $$;

-- 13. Comprobaciones finales
DO $$
begin
  if md5(coalesce((select string_agg((to_jsonb(x) - 'configuration' - 'config_key' - 'config_snapshot')::text, '|' order by x.id) from public.project_products x), ''))
       <> current_setting('mobau.p4604_lineas')
     or exists (select 1 from public.project_products where configuration is not null or config_key <> '' or config_snapshot is not null) then
    raise exception '46-04: las líneas de proyecto cambiaron';
  end if;
  if md5(coalesce((select string_agg((to_jsonb(x) - 'lines_snapshot')::text, '|' order by x.id) from public.rfqs x), ''))
       <> current_setting('mobau.p4604_rfqs')
     or exists (select 1 from public.rfqs where lines_snapshot is not null) then
    raise exception '46-04: las RFQ cambiaron';
  end if;
  if (select count(*) from pg_indexes where schemaname = 'public' and tablename = 'project_products'
        and indexname in ('project_products_line_unique', 'project_products_config_line_unique')) <> 2 then
    raise exception '46-04: faltan índices de línea';
  end if;
  if (select count(*) from pg_trigger where not tgisinternal
        and tgname in ('trg_project_products_10_configuration', 'trg_rfqs_10_lines_snapshot')) <> 2 then
    raise exception '46-04: faltan triggers';
  end if;
  if (select md5(prosrc) from pg_proc where oid = 'mobau_private.product_reference_counts(text)'::regprocedure) <> '6a9b5efb565babc8e06016d58dd99288' then
    raise exception '46-04: product_reference_counts no quedó como se esperaba';
  end if;
  if not has_column_privilege('authenticated', 'public.project_products', 'configuration', 'INSERT')
     or not has_column_privilege('authenticated', 'public.project_products', 'configuration', 'UPDATE')
     or has_column_privilege('authenticated', 'public.project_products', 'config_key', 'UPDATE')
     or has_column_privilege('authenticated', 'public.project_products', 'config_snapshot', 'UPDATE') then
    raise exception '46-04: permisos por columna no esperados';
  end if;
  if exists (select 1 from pg_proc p where p.oid in ('public.line_configuration_normalized(jsonb)'::regprocedure,
                                                     'public.line_configuration_resolve(text, jsonb)'::regprocedure,
                                                     'public.line_configuration_structure(jsonb)'::regprocedure,
                                                     'public.project_line_states(uuid)'::regprocedure,
                                                     'public.project_request_lines(uuid)'::regprocedure,
                                                     'public.project_products_configuration()'::regprocedure,
                                                     'public.rfqs_lines_snapshot()'::regprocedure)
              and (p.prosecdef or has_function_privilege('anon', p.oid, 'EXECUTE'))) then
    raise exception '46-04: funciones nuevas con security definer o ejecutables por anon';
  end if;
end $$;

COMMIT;
