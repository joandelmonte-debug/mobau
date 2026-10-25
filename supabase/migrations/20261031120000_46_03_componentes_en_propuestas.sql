-- ============================================================
-- PROPUESTA NO EJECUTADA (46-03 · componentes en el circuito de propuestas) — no ejecutar sin aprobación explícita
-- ============================================================
-- Punto 46 · bloque 2. Integra catalog_role y los grupos/opciones (46-01)
-- en product_proposals, reutilizando el circuito existente.
--   * product_proposals.proposed_components (jsonb):
--       null                      → no modificar nada de componentes;
--       {"catalog_role": …}       → solo cambia el uso en el catálogo;
--       {"groups": [...]}         → lista COMPLETA de grupos (retira lo que falte);
--       {"groups": []}            → explícitamente vacío: retira todos los grupos.
--     Claves estables: code de grupo y de opción. Una opción de componente
--     apunta a {"product_id"} (producto propio existente) o {"proposal_id"}
--     (alta propia de un componente nuevo).
--   * Validación (trigger 36): forma, claves, referencias propias; al enviar,
--     grupos necesarios con opciones, rol de los componentes, niveles y ciclos.
--   * Copia al enviar (trigger 41): product_snapshot.components = estructura
--     actual del producto (para diferencias y para detectar conflictos).
--   * Aplicación al aprobar (trigger 61, después de los archivos): conflicto
--     si la estructura cambió desde el envío; componentes nuevos aprobados
--     antes; mismo artículo por clave; upsert por clave, retirada (no
--     borrado) de lo que falte; comprobación final. Cualquier error revierte
--     toda la aprobación.
--   * transition_proposal_status: Mobau no puede cambiar proposed_components
--     al moderar, y un cambio con solo componentes no cuenta como vacío.
-- Mobau no certifica compatibilidad técnica: solo guarda lo declarado.
-- Si se aplica, se registra como migración NUEVA tras confirmar su COMMIT.
-- Ejecutar completo.
-- ============================================================

BEGIN;

create function pg_temp.r4603(t text, a text, b text) returns text language plpgsql as $$
begin
  if (length(t) - length(replace(t, a, ''))) <> length(a) then
    raise exception '46-03: el fragmento no aparece exactamente una vez: %', left(a, 80);
  end if;
  return replace(t, a, b);
end $$;

DO $$
begin
  if current_user <> 'postgres' then
    raise exception '46-03: ejecutar como postgres';
  end if;
  if not exists (select 1 from supabase_migrations.schema_migrations where version = '20261030130000')
     or exists (select 1 from supabase_migrations.schema_migrations where version = '20261031120000') then
    raise exception '46-03: el registro de migraciones no es el esperado (46-02 registrada y 46-03 sin registrar)';
  end if;
  if exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'product_proposals' and column_name = 'proposed_components') then
    raise exception '46-03: proposed_components ya existe';
  end if;
  if (select md5(prosrc) from pg_proc where oid = 'public.transition_proposal_status()'::regprocedure) <> '3eef0e1ad9a754c54fcc1ac536301b53' then
    raise exception '46-03: transition_proposal_status no es la esperada';
  end if;
  perform set_config('mobau.p4603_propuestas', md5(coalesce((select string_agg(to_jsonb(x)::text, '|' order by x.id) from public.product_proposals x), '')), true);
end $$;

-- 1. Columna y permisos (como proposed_media)
alter table public.product_proposals add column proposed_components jsonb;
comment on column public.product_proposals.proposed_components is
  'Punto 46: null = no modificar componentes. {"catalog_role"?, "groups"?}: groups es la lista completa; [] retira todos.';
grant insert (proposed_components), update (proposed_components) on public.product_proposals to authenticated;

-- 2. Estructura actual de un producto, con la misma forma que el manifiesto
create function mobau_private.component_structure_of(p_product text) returns jsonb
  language sql stable security definer set search_path = '' as $$
  select pg_catalog.jsonb_build_object(
    'catalog_role', p.catalog_role,
    'groups', coalesce((
      select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
               'code', g.code, 'label', g.label, 'requirement', g.requirement, 'choice', g.choice,
               'depends_on', (select pg_catalog.jsonb_build_object('group', dg.code, 'option', d.code)
                                from public.product_component_options d
                                join public.product_component_groups dg on dg.id = d.group_id
                               where d.id = g.depends_on_option_id),
               'options', coalesce((
                 select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
                          'code', o.code, 'kind', o.kind,
                          'component', case when o.component_product_id is null then null
                                            else pg_catalog.jsonb_build_object('product_id', o.component_product_id) end,
                          'finish_code', o.component_finish_code, 'setting_label', o.setting_label,
                          'supply', o.supply, 'quantity', o.quantity, 'quantity_mode', o.quantity_mode,
                          'attributes', o.attributes) order by o.sort_order, o.code)
                   from public.product_component_options o
                  where o.group_id = g.id and o.status = 'activo'), '[]'::jsonb))
             order by g.sort_order, g.code)
        from public.product_component_groups g
       where g.product_id = p.id and g.status = 'activo'), '[]'::jsonb))
    from public.products p where p.id = p_product
$$;

-- 2b. Manifiesto normalizado con la misma forma que la estructura (grupos).
--     Un alta ya aprobada se resuelve a su producto; una pendiente queda como
--     {"proposal_id"} y nunca coincide con la estructura actual.
create function mobau_private.component_manifest_normalized(p_m jsonb) returns jsonb
  language sql stable security definer set search_path = '' as $$
  select coalesce(pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
           'code', g.e ->> 'code', 'label', g.e ->> 'label', 'requirement', g.e ->> 'requirement', 'choice', g.e ->> 'choice',
           'depends_on', case when pg_catalog.jsonb_typeof(g.e -> 'depends_on') = 'object'
                              then pg_catalog.jsonb_build_object('group', g.e -> 'depends_on' ->> 'group', 'option', g.e -> 'depends_on' ->> 'option') end,
           'options', coalesce((
             select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
                      'code', o.e ->> 'code', 'kind', o.e ->> 'kind',
                      'component', case when o.e ->> 'kind' <> 'componente' then null
                                        when o.e -> 'component' ? 'product_id'
                                          then pg_catalog.jsonb_build_object('product_id', o.e -> 'component' ->> 'product_id')
                                        else coalesce((select pg_catalog.jsonb_build_object('product_id', pp.created_product_id)
                                                         from public.product_proposals pp
                                                        where pp.id::text = o.e -> 'component' ->> 'proposal_id'
                                                          and pp.status = 'approved' and pp.created_product_id is not null),
                                                      pg_catalog.jsonb_build_object('proposal_id', o.e -> 'component' ->> 'proposal_id')) end,
                      'finish_code', nullif(o.e ->> 'finish_code', ''), 'setting_label', o.e ->> 'setting_label',
                      'supply', o.e ->> 'supply',
                      'quantity', case when pg_catalog.jsonb_typeof(o.e -> 'quantity') = 'number' then (o.e ->> 'quantity')::numeric end,
                      'quantity_mode', o.e ->> 'quantity_mode',
                      'attributes', coalesce(nullif(o.e -> 'attributes', 'null'::jsonb), '[]'::jsonb)) order by o.ord)
               from pg_catalog.jsonb_array_elements(coalesce(g.e -> 'options', '[]'::jsonb)) with ordinality as o(e, ord)), '[]'::jsonb))
         order by g.ord), '[]'::jsonb)
    from pg_catalog.jsonb_array_elements(coalesce(p_m -> 'groups', '[]'::jsonb)) with ordinality as g(e, ord)
$$;

-- 3. Niveles y ciclos con el manifiesto en lugar de la estructura actual del producto
create function mobau_private.component_manifest_graph_violations(p_src text, p_m jsonb, p_distributor text) returns text
  language plpgsql stable security definer set search_path = '' as $$
declare
  v text;
begin
  if p_m is null or not (p_m ? 'groups') then
    return null;
  end if;
  with recursive cur as (
    select distinct g.product_id as src, o.component_product_id as dst
      from public.product_component_groups g
      join public.product_component_options o on o.group_id = g.id
      join public.products p on p.id = g.product_id
     where g.status = 'activo' and o.status = 'activo' and o.kind = 'componente'
       and p.distributor_id = p_distributor and g.product_id <> p_src
  ), man as (
    select distinct p_src as src,
           coalesce(t.opt -> 'component' ->> 'product_id',
                    (select coalesce(pp.created_product_id, 'propuesta:' || pp.id::text)
                       from public.product_proposals pp
                      where pp.id::text = t.opt -> 'component' ->> 'proposal_id' and pp.distributor_id = p_distributor)) as dst
      from pg_catalog.jsonb_array_elements(p_m -> 'groups') as gr(g),
           pg_catalog.jsonb_array_elements(coalesce(gr.g -> 'options', '[]'::jsonb)) as t(opt)
     where t.opt ->> 'kind' = 'componente'
  ), e as (
    select src, dst from cur union select src, dst from man where dst is not null
  ), walk as (
    select e.src as root, e.dst as node, 1 as depth, array[e.src, e.dst] as path, e.src = e.dst as cyc from e
    union all
    select w.root, e.dst, w.depth + 1, w.path || e.dst, e.dst = any (w.path)
      from walk w join e on e.src = w.node
     where not w.cyc and w.depth < 3
  )
  select string_agg(distinct case when w.cyc then 'ciclo de componentes'
                                   else 'más de tres niveles (principal → componente → subcomponente)' end, '; ') into v
    from walk w where (w.cyc or w.depth >= 3) and p_src = any (w.path);
  return v;
end $$;

-- 4. Validación (trigger 36, después de los archivos)
create function public.validate_proposal_components() returns trigger
  language plpgsql security definer set search_path = '' as $$
declare
  m jsonb := new.proposed_components;
  v_entering boolean;
  g jsonb; o jsonb; c jsonb; a jsonb;
  k text; v text; v_code text; v_cur text;
  v_gcodes text[] := '{}'::text[];
  v_ocodes text[];
  v_pid uuid; v_st text; v_role text; v_created text;
  v_steps integer;
  v_now jsonb;
begin
  -- Durante la decisión de Mobau el contenido no cambia: se vuelve a validar al aplicar.
  if tg_op = 'UPDATE' and (select public.mobau_moderating(new.id)) then
    return new;
  end if;
  if tg_op = 'UPDATE' then
    v_entering := new.status = 'submitted' and old.status is distinct from 'submitted';
  else
    v_entering := new.status = 'submitted';
  end if;
  if tg_op = 'UPDATE' and not v_entering and new.proposed_components is not distinct from old.proposed_components then
    return new;
  end if;
  if m is null then
    return new;
  end if;
  if new.proposal_kind = 'republish' then
    raise exception 'Una solicitud de republicación no lleva componentes.' using errcode = '23514';
  end if;
  if pg_catalog.jsonb_typeof(m) <> 'object' or pg_catalog.pg_column_size(m) > 200000 then
    raise exception 'Los componentes de la propuesta no son válidos.' using errcode = '23514';
  end if;
  for k in select pg_catalog.jsonb_object_keys(m) loop
    if k not in ('catalog_role', 'groups') then
      raise exception 'Campo no permitido en los componentes: %.', k using errcode = '23514';
    end if;
  end loop;
  if m ? 'catalog_role' and (pg_catalog.jsonb_typeof(m -> 'catalog_role') <> 'string'
                             or m ->> 'catalog_role' not in ('principal', 'componente', 'ambos')) then
    raise exception 'El uso en el catálogo debe ser principal, componente o ambos.' using errcode = '23514';
  end if;
  -- «Sin cambios»: un manifiesto presente pero idéntico al estado actual no es un cambio.
  if v_entering and new.proposal_kind = 'update' and new.product_id is not null
     and new.proposed_changes = '{}'::jsonb and new.proposed_new_subcategory is null
     and new.proposed_price_status is null and new.proposed_media is null then
    v_now := mobau_private.component_structure_of(new.product_id);
    if not ((m ? 'catalog_role' and m ->> 'catalog_role' is distinct from v_now ->> 'catalog_role')
            or (m ? 'groups' and pg_catalog.jsonb_typeof(m -> 'groups') = 'array'
                and mobau_private.component_manifest_normalized(m) is distinct from v_now -> 'groups')) then
      raise exception 'La propuesta no contiene ningún cambio.' using errcode = '23514';
    end if;
  end if;
  if not (m ? 'groups') then
    return new;
  end if;
  if pg_catalog.jsonb_typeof(m -> 'groups') <> 'array' or pg_catalog.jsonb_array_length(m -> 'groups') > 30 then
    raise exception 'La lista de grupos de componentes no es válida (máximo 30).' using errcode = '23514';
  end if;

  for g in select e from pg_catalog.jsonb_array_elements(m -> 'groups') e loop
    if (case when pg_catalog.jsonb_typeof(g) <> 'object' then true
            else exists (select 1 from pg_catalog.jsonb_object_keys(g) x where x not in ('code', 'label', 'requirement', 'choice', 'depends_on', 'options')) end)
       or pg_catalog.jsonb_typeof(g -> 'code') is distinct from 'string'
       or pg_catalog.jsonb_typeof(g -> 'label') is distinct from 'string'
       or coalesce(g ->> 'requirement', '') not in ('necesario', 'opcional')
       or coalesce(g ->> 'choice', '') not in ('una', 'varias')
       or (g ? 'depends_on' and pg_catalog.jsonb_typeof(g -> 'depends_on') not in ('object', 'null'))
       or (g ? 'options' and pg_catalog.jsonb_typeof(g -> 'options') <> 'array') then
      raise exception 'Algún grupo de componentes no es válido.' using errcode = '23514';
    end if;
    v_code := g ->> 'code';
    if v_code <> pg_catalog.btrim(v_code) or pg_catalog.char_length(v_code) not between 1 and 40
       or (g ->> 'label') <> pg_catalog.btrim(g ->> 'label') or pg_catalog.char_length(g ->> 'label') not between 1 and 80 then
      raise exception 'Revisa el nombre (1–80 caracteres) de cada grupo de componentes.' using errcode = '23514';
    end if;
    if pg_catalog.lower(v_code) = any (v_gcodes) then
      raise exception 'Hay dos grupos de componentes con la misma clave.' using errcode = '23514';
    end if;
    v_gcodes := v_gcodes || pg_catalog.lower(v_code);
    if pg_catalog.jsonb_array_length(coalesce(g -> 'options', '[]'::jsonb)) > 40 then
      raise exception 'El grupo «%» tiene demasiadas opciones (máximo 40).', g ->> 'label' using errcode = '23514';
    end if;

    v_ocodes := '{}'::text[];
    for o in select e from pg_catalog.jsonb_array_elements(coalesce(g -> 'options', '[]'::jsonb)) e loop
      if (case when pg_catalog.jsonb_typeof(o) <> 'object' then true
              else exists (select 1 from pg_catalog.jsonb_object_keys(o) x
                            where x not in ('code', 'kind', 'component', 'finish_code', 'setting_label', 'supply', 'quantity', 'quantity_mode', 'attributes')) end)
         or pg_catalog.jsonb_typeof(o -> 'code') is distinct from 'string'
         or coalesce(o ->> 'kind', '') not in ('componente', 'ajuste') then
        raise exception 'Alguna opción del grupo «%» no es válida.', g ->> 'label' using errcode = '23514';
      end if;
      v_code := o ->> 'code';
      if v_code <> pg_catalog.btrim(v_code) or pg_catalog.char_length(v_code) not between 1 and 40 then
        raise exception 'Alguna opción del grupo «%» no es válida.', g ->> 'label' using errcode = '23514';
      end if;
      if pg_catalog.lower(v_code) = any (v_ocodes) then
        raise exception 'El grupo «%» tiene dos opciones con la misma clave.', g ->> 'label' using errcode = '23514';
      end if;
      v_ocodes := v_ocodes || pg_catalog.lower(v_code);

      if o ->> 'kind' = 'componente' then
        c := o -> 'component';
        if (case when pg_catalog.jsonb_typeof(c) is distinct from 'object' then true
                else (select count(*) from pg_catalog.jsonb_object_keys(c)) <> 1
                     or not (c ? 'product_id' or c ? 'proposal_id')
                     or pg_catalog.jsonb_typeof(coalesce(c -> 'product_id', c -> 'proposal_id')) <> 'string' end) then
          raise exception 'Indica el artículo de cada opción de componente del grupo «%».', g ->> 'label' using errcode = '23514';
        end if;
        if coalesce(o ->> 'supply', '') not in ('incluido', 'aparte') then
          raise exception 'Indica si cada componente del grupo «%» va incluido o se solicita aparte.', g ->> 'label' using errcode = '23514';
        end if;
        if coalesce(o ->> 'quantity_mode', '') not in ('fija', 'a_calcular') then
          raise exception 'Indica la cantidad (fija o a calcular) de cada componente del grupo «%».', g ->> 'label' using errcode = '23514';
        end if;
        if o ->> 'quantity_mode' = 'fija' then
          if (case when pg_catalog.jsonb_typeof(o -> 'quantity') is distinct from 'number' then true
                  else (o ->> 'quantity')::numeric <= 0 or (o ->> 'quantity')::numeric > 9999999.999
                       or (o ->> 'quantity')::numeric <> pg_catalog.round((o ->> 'quantity')::numeric, 3) end) then
            raise exception 'La cantidad por unidad de cada componente debe ser mayor que 0 (hasta 3 decimales).' using errcode = '23514';
          end if;
        elsif o ? 'quantity' and pg_catalog.jsonb_typeof(o -> 'quantity') <> 'null' then
          raise exception 'Una cantidad «a calcular» no lleva número.' using errcode = '23514';
        end if;
        if o ? 'setting_label' and pg_catalog.jsonb_typeof(o -> 'setting_label') <> 'null' then
          raise exception 'Una opción de componente no lleva nombre de ajuste.' using errcode = '23514';
        end if;
        if o ? 'finish_code' and pg_catalog.jsonb_typeof(o -> 'finish_code') <> 'null'
           and (pg_catalog.jsonb_typeof(o -> 'finish_code') <> 'string'
                or (o ->> 'finish_code') <> pg_catalog.btrim(o ->> 'finish_code')
                or pg_catalog.char_length(o ->> 'finish_code') not between 1 and 20) then
          raise exception 'El acabado de algún componente no es válido.' using errcode = '23514';
        end if;
        -- Referencias propias. El mismo mensaje para «no existe» y «no es tuyo».
        if c ? 'product_id' then
          if not exists (select 1 from public.products p
                          where p.id = c ->> 'product_id' and p.distributor_id = new.distributor_id
                            and p.id is distinct from new.product_id) then
            raise exception 'Algún componente no existe o no es de tu empresa.' using errcode = '23514';
          end if;
          if v_entering and not exists (select 1 from public.products p
                                         where p.id = c ->> 'product_id' and p.catalog_role in ('componente', 'ambos')) then
            raise exception 'El artículo % no está clasificado como componente o ambos.', c ->> 'product_id' using errcode = '23514';
          end if;
          if v_entering and o ? 'finish_code' and pg_catalog.jsonb_typeof(o -> 'finish_code') = 'string'
             and not exists (select 1 from public.product_finishes f where f.product_id = c ->> 'product_id' and f.code = o ->> 'finish_code') then
            raise exception 'El acabado elegido no existe en el artículo %.', c ->> 'product_id' using errcode = '23514';
          end if;
        else
          begin
            v_pid := (c ->> 'proposal_id')::uuid;
          exception when invalid_text_representation then
            raise exception 'Algún componente no existe o no es de tu empresa.' using errcode = '23514';
          end;
          select pp.status, pp.proposed_components ->> 'catalog_role', pp.created_product_id into v_st, v_role, v_created
            from public.product_proposals pp
           where pp.id = v_pid and pp.distributor_id = new.distributor_id and pp.proposal_kind = 'create' and pp.id <> new.id;
          if not found or v_st not in ('draft', 'submitted', 'changes_requested', 'approved') then
            raise exception 'Algún componente no existe o no es de tu empresa.' using errcode = '23514';
          end if;
          if v_entering and v_st <> 'approved' and coalesce(v_role, 'principal') not in ('componente', 'ambos') then
            raise exception 'Cada componente nuevo debe proponerse con uso «componente» o «ambos».' using errcode = '23514';
          end if;
          if v_entering and v_st = 'approved'
             and not exists (select 1 from public.products p where p.id = v_created and p.catalog_role in ('componente', 'ambos')) then
            raise exception 'Algún componente nuevo ya aprobado no está clasificado como componente o ambos.' using errcode = '23514';
          end if;
        end if;
      else
        if (o ? 'component' and pg_catalog.jsonb_typeof(o -> 'component') <> 'null')
           or (o ? 'finish_code' and pg_catalog.jsonb_typeof(o -> 'finish_code') <> 'null')
           or (o ? 'supply' and pg_catalog.jsonb_typeof(o -> 'supply') <> 'null')
           or (o ? 'quantity' and pg_catalog.jsonb_typeof(o -> 'quantity') <> 'null')
           or (o ? 'quantity_mode' and pg_catalog.jsonb_typeof(o -> 'quantity_mode') <> 'null') then
          raise exception 'Un ajuste solo lleva su nombre y, si acaso, características.' using errcode = '23514';
        end if;
        if pg_catalog.jsonb_typeof(o -> 'setting_label') is distinct from 'string'
           or (o ->> 'setting_label') <> pg_catalog.btrim(o ->> 'setting_label')
           or pg_catalog.char_length(o ->> 'setting_label') not between 1 and 80 then
          raise exception 'Indica el nombre (1–80 caracteres) de cada ajuste del grupo «%».', g ->> 'label' using errcode = '23514';
        end if;
      end if;

      if o ? 'attributes' and pg_catalog.jsonb_typeof(o -> 'attributes') <> 'null' then
        if pg_catalog.jsonb_typeof(o -> 'attributes') <> 'array' or pg_catalog.jsonb_array_length(o -> 'attributes') > 8 then
          raise exception 'Las características de una opción no son válidas (máximo 8).' using errcode = '23514';
        end if;
        for a in select e from pg_catalog.jsonb_array_elements(o -> 'attributes') e loop
          if (case when pg_catalog.jsonb_typeof(a) <> 'object' then true
                  else exists (select 1 from pg_catalog.jsonb_object_keys(a) x where x not in ('label', 'value'))
                       or pg_catalog.jsonb_typeof(a -> 'label') is distinct from 'string'
                       or pg_catalog.jsonb_typeof(a -> 'value') is distinct from 'string'
                       or pg_catalog.char_length(pg_catalog.btrim(a ->> 'label')) not between 1 and 60
                       or pg_catalog.char_length(pg_catalog.btrim(a ->> 'value')) not between 1 and 120 end) then
            raise exception 'Las características de una opción no son válidas.' using errcode = '23514';
          end if;
        end loop;
      end if;
    end loop;

    if v_entering and g ->> 'requirement' = 'necesario' and pg_catalog.jsonb_array_length(coalesce(g -> 'options', '[]'::jsonb)) = 0 then
      raise exception 'El grupo necesario «%» no tiene opciones.', g ->> 'label' using errcode = '23514';
    end if;
  end loop;

  -- Condiciones: una opción de otro grupo del mismo manifiesto; sin ciclos.
  for g in select e from pg_catalog.jsonb_array_elements(m -> 'groups') e loop
    if pg_catalog.jsonb_typeof(g -> 'depends_on') = 'object' then
      if (select count(*) from pg_catalog.jsonb_object_keys(g -> 'depends_on')) <> 2
         or pg_catalog.jsonb_typeof(g -> 'depends_on' -> 'group') is distinct from 'string'
         or pg_catalog.jsonb_typeof(g -> 'depends_on' -> 'option') is distinct from 'string'
         or g -> 'depends_on' ->> 'group' = g ->> 'code'
         or not exists (select 1 from pg_catalog.jsonb_array_elements(m -> 'groups') og,
                                      pg_catalog.jsonb_array_elements(coalesce(og -> 'options', '[]'::jsonb)) oo
                         where og ->> 'code' = g -> 'depends_on' ->> 'group' and oo ->> 'code' = g -> 'depends_on' ->> 'option') then
        raise exception 'La condición del grupo «%» no es válida: elige una opción de otro grupo.', g ->> 'label' using errcode = '23514';
      end if;
      v_cur := g -> 'depends_on' ->> 'group';
      v_steps := 0;
      while v_cur is not null and v_steps <= 31 loop
        if v_cur = g ->> 'code' then
          raise exception 'Las condiciones de los grupos forman un círculo.' using errcode = '23514';
        end if;
        select og -> 'depends_on' ->> 'group' into v_cur
          from pg_catalog.jsonb_array_elements(m -> 'groups') og
         where og ->> 'code' = v_cur and pg_catalog.jsonb_typeof(og -> 'depends_on') = 'object';
        v_steps := v_steps + 1;
      end loop;
    end if;
  end loop;

  -- Al enviar: niveles y ciclos con la estructura propuesta.
  if v_entering then
    v := mobau_private.component_manifest_graph_violations(coalesce(new.product_id, 'propuesta:' || new.id::text), m, new.distributor_id);
    if v is not null then
      raise exception 'Componentes: %.', v using errcode = '23514';
    end if;
  end if;
  return new;
end $$;

-- 5. Copia de la estructura actual al enviar (trigger 41, después de la copia del producto)
create function public.snapshot_proposal_components() returns trigger
  language plpgsql security definer set search_path = '' as $$
begin
  if new.proposal_kind = 'update' and new.product_id is not null then
    new.product_snapshot := coalesce(new.product_snapshot, '{}'::jsonb)
                            || pg_catalog.jsonb_build_object('components', mobau_private.component_structure_of(new.product_id));
  end if;
  return new;
end $$;

-- 6. Aplicación al aprobar (trigger 61, después de los archivos). Todo o nada.
create function public.apply_proposal_components() returns trigger
  language plpgsql security definer set search_path = '' as $$
declare
  m jsonb := new.proposed_components;
  v_product text := coalesce(new.product_id, new.created_product_id);
  g jsonb; o jsonb; c jsonb;
  v_gord bigint; v_oord bigint;
  v_gid uuid; v_comp text; v_st text; v_name text;
  v_old_kind text; v_old_comp text;
  v_gcodes text[] := '{}'::text[];
  v_ocodes text[];
  v text;
begin
  if new.status <> 'approved' or old.status = 'approved' or m is null then
    return null;
  end if;
  if v_product is null then
    raise exception 'Componentes: no se encontró el producto de la propuesta.' using errcode = '55000', hint = 'components_no_product';
  end if;

  -- Conflicto: la estructura cambió desde el envío (otra aprobación o un cambio directo).
  if new.proposal_kind = 'update' and new.product_snapshot ? 'components'
     and mobau_private.component_structure_of(v_product) is distinct from new.product_snapshot -> 'components' then
    raise exception 'Los componentes del producto cambiaron desde que se envió la propuesta: solicita cambios para que la empresa la revise.'
      using errcode = '40001', hint = 'components_conflict';
  end if;

  if m ? 'catalog_role' then
    update public.products set catalog_role = m ->> 'catalog_role' where id = v_product;
  end if;

  if m ? 'groups' then
    for g, v_gord in select t.e, t.o from pg_catalog.jsonb_array_elements(m -> 'groups') with ordinality as t(e, o) loop
      insert into public.product_component_groups (product_id, code, label, requirement, choice, sort_order, status, depends_on_option_id)
      values (v_product, g ->> 'code', g ->> 'label', g ->> 'requirement', g ->> 'choice', v_gord::integer, 'activo', null)
      on conflict (product_id, code) do update
        set label = excluded.label, requirement = excluded.requirement, choice = excluded.choice,
            sort_order = excluded.sort_order, status = 'activo', depends_on_option_id = null
      returning id into v_gid;
      v_gcodes := v_gcodes || (g ->> 'code');
      v_ocodes := '{}'::text[];

      for o, v_oord in select t.e, t.o from pg_catalog.jsonb_array_elements(coalesce(g -> 'options', '[]'::jsonb)) with ordinality as t(e, o) loop
        v_comp := null;
        if o ->> 'kind' = 'componente' then
          c := o -> 'component';
          if c ? 'product_id' then
            v_comp := c ->> 'product_id';
          else
            select pp.status, pp.created_product_id, pp.proposed_changes ->> 'name' into v_st, v_comp, v_name
              from public.product_proposals pp
             where pp.id::text = c ->> 'proposal_id' and pp.distributor_id = new.distributor_id and pp.proposal_kind = 'create';
            if v_st is distinct from 'approved' or v_comp is null then
              raise exception 'Antes de aprobar este producto, aprueba su componente nuevo «%».', coalesce(v_name, 'sin nombre')
                using errcode = '55000', hint = 'component_pending';
            end if;
          end if;
          if o ? 'finish_code' and pg_catalog.jsonb_typeof(o -> 'finish_code') = 'string'
             and not exists (select 1 from public.product_finishes f where f.product_id = v_comp and f.code = o ->> 'finish_code') then
            raise exception 'El acabado elegido para un componente del grupo «%» ya no existe: solicita cambios.', g ->> 'label'
              using errcode = '55000', hint = 'component_finish_missing';
          end if;
        end if;
        -- Misma clave = mismo artículo: no se reasigna una opción existente a otro artículo.
        select x.kind, x.component_product_id into v_old_kind, v_old_comp
          from public.product_component_options x where x.group_id = v_gid and x.code = o ->> 'code';
        if found and (v_old_kind is distinct from o ->> 'kind' or v_old_comp is distinct from v_comp) then
          raise exception 'La opción «%» del grupo «%» cambió de artículo: debe proponerse como opción nueva.', o ->> 'code', g ->> 'label'
            using errcode = '55000', hint = 'option_identity_changed';
        end if;
        insert into public.product_component_options (group_id, code, kind, component_product_id, component_finish_code, setting_label,
                                                      supply, quantity, quantity_mode, attributes, status, sort_order)
        values (v_gid, o ->> 'code', o ->> 'kind', v_comp, nullif(o ->> 'finish_code', ''), o ->> 'setting_label',
                o ->> 'supply', (o ->> 'quantity')::numeric, o ->> 'quantity_mode',
                coalesce(nullif(o -> 'attributes', 'null'::jsonb), '[]'::jsonb), 'activo', v_oord::integer)
        on conflict (group_id, code) do update
          set component_finish_code = excluded.component_finish_code, setting_label = excluded.setting_label,
              supply = excluded.supply, quantity = excluded.quantity, quantity_mode = excluded.quantity_mode,
              attributes = excluded.attributes, status = 'activo', sort_order = excluded.sort_order;
        v_ocodes := v_ocodes || (o ->> 'code');
      end loop;

      -- Opciones que ya no están en este grupo: se retiran (no se borran).
      update public.product_component_options
         set status = 'retirado'
       where group_id = v_gid and status = 'activo' and not (code = any (v_ocodes));
    end loop;

    -- Grupos que ya no están en la lista: se retiran (no se borran).
    update public.product_component_groups
       set status = 'retirado'
     where product_id = v_product and status = 'activo' and not (code = any (v_gcodes));

    -- Condiciones, por claves.
    update public.product_component_groups gg
       set depends_on_option_id = (select x.id from public.product_component_options x
                                     join public.product_component_groups xg on xg.id = x.group_id
                                    where xg.product_id = v_product and xg.code = t.e -> 'depends_on' ->> 'group'
                                      and x.code = t.e -> 'depends_on' ->> 'option')
      from pg_catalog.jsonb_array_elements(m -> 'groups') as t(e)
     where gg.product_id = v_product and gg.code = t.e ->> 'code' and pg_catalog.jsonb_typeof(t.e -> 'depends_on') = 'object';
  end if;

  -- Comprobación final explícita (además de la diferida de 46-01).
  v := mobau_private.component_structure_violations();
  if v is not null then
    raise exception 'Componentes: %.', v using errcode = '23514', hint = 'components_invalid';
  end if;
  return null;
end $$;

revoke all on function mobau_private.component_structure_of(text) from public, anon, authenticated;
revoke all on function mobau_private.component_manifest_normalized(jsonb) from public, anon, authenticated;
revoke all on function mobau_private.component_manifest_graph_violations(text, jsonb, text) from public, anon, authenticated;
revoke all on function public.validate_proposal_components() from public, anon, authenticated;
revoke all on function public.snapshot_proposal_components() from public, anon, authenticated;
revoke all on function public.apply_proposal_components() from public, anon, authenticated;

create trigger trg_product_proposals_36_components
  before insert or update on public.product_proposals
  for each row execute function public.validate_proposal_components();
create trigger trg_product_proposals_41_components_snapshot
  before update on public.product_proposals
  for each row when (new.status = 'submitted' and old.status is distinct from 'submitted')
  execute function public.snapshot_proposal_components();
create trigger trg_product_proposals_61_components_apply
  after update of status on public.product_proposals
  for each row execute function public.apply_proposal_components();

-- 7. Transición: Mobau no cambia proposed_components y un cambio de componentes no es «vacío».
DO $$
declare
  d text;
begin
  d := pg_get_functiondef('public.transition_proposal_status()'::regprocedure);
  d := pg_temp.r4603(d, $a$or new.proposed_media is distinct from old.proposed_media then$a$,
                        $a$or new.proposed_media is distinct from old.proposed_media
       or new.proposed_components is distinct from old.proposed_components then$a$);
  d := pg_temp.r4603(d, $a$and new.proposed_price_status is null and new.proposed_media is null then$a$,
                        $a$and new.proposed_price_status is null and new.proposed_media is null
     and new.proposed_components is null then$a$);
  execute d;
end $$;

-- 8. Comprobaciones finales
DO $$
begin
  if md5(coalesce((select string_agg((to_jsonb(x) - 'proposed_components')::text, '|' order by x.id) from public.product_proposals x), ''))
       <> current_setting('mobau.p4603_propuestas')
     or exists (select 1 from public.product_proposals where proposed_components is not null) then
    raise exception '46-03: las propuestas cambiaron';
  end if;
  if not has_column_privilege('authenticated', 'public.product_proposals', 'proposed_components', 'INSERT')
     or not has_column_privilege('authenticated', 'public.product_proposals', 'proposed_components', 'UPDATE')
     or has_column_privilege('anon', 'public.product_proposals', 'proposed_components', 'INSERT')
     or has_column_privilege('anon', 'public.product_proposals', 'proposed_components', 'UPDATE') then
    raise exception '46-03: permisos de proposed_components no esperados';
  end if;
  if (select count(*) from pg_trigger where tgrelid = 'public.product_proposals'::regclass and not tgisinternal
        and tgname in ('trg_product_proposals_36_components', 'trg_product_proposals_41_components_snapshot', 'trg_product_proposals_61_components_apply')) <> 3 then
    raise exception '46-03: faltan triggers';
  end if;
  if (select md5(prosrc) from pg_proc where oid = 'public.transition_proposal_status()'::regprocedure) <> '96691e0bf640fdf97992255d09b191d2' then
    raise exception '46-03: transition_proposal_status no quedó como se esperaba';
  end if;
  if exists (select 1 from pg_proc p where p.oid in ('mobau_private.component_structure_of(text)'::regprocedure,
                                                     'mobau_private.component_manifest_normalized(jsonb)'::regprocedure,
                                                     'mobau_private.component_manifest_graph_violations(text, jsonb, text)'::regprocedure,
                                                     'public.validate_proposal_components()'::regprocedure,
                                                     'public.snapshot_proposal_components()'::regprocedure,
                                                     'public.apply_proposal_components()'::regprocedure)
              and (not p.prosecdef or has_function_privilege('anon', p.oid, 'EXECUTE') or has_function_privilege('authenticated', p.oid, 'EXECUTE'))) then
    raise exception '46-03: funciones nuevas sin security definer o con ejecución pública';
  end if;
end $$;

COMMIT;
