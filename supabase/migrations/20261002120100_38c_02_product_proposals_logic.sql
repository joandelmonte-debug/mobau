-- ============================================================
-- PROPUESTA NO EJECUTADA (38-C) — no ejecutar sin aprobación explícita
-- ============================================================
-- 38-C · 02 · Funciones y triggers de product_proposals
-- ------------------------------------------------------------
-- Requiere 38-C 01. Sigue sin dar ningún acceso de cliente (eso es 03):
-- aquí solo se definen las reglas que se aplicarán a cada INSERT/UPDATE.
--
-- Quién es "distribuidor": cualquier sesión de cliente, es decir, con
-- auth.uid() no nulo (mismo criterio que products_before_insert). Sin
-- auth.uid() (Mobau desde el editor SQL) no se aplican las reglas del
-- distribuidor, pero sí la validación de datos. El punto 39 (rol admin
-- con sesión propia) tendrá que ampliar este criterio.
--
-- Funciones (todas con search_path vacío):
--   fix_proposal_author()        BEFORE INSERT   distribuidor y autor fijados
--                                                 por el servidor; estado inicial
--                                                 draft; producto de la empresa.
--   validate_proposal_changes()  BEFORE INSERT/UPDATE  lista cerrada de campos,
--                                                 tipos, longitudes, URLs, enums,
--                                                 categoría y subcategoría.
--   transition_proposal_status() BEFORE UPDATE   transiciones del distribuidor
--                                                 (enviar y retirar) y campos que
--                                                 no puede tocar.
--   snapshot_product_on_submit() BEFORE UPDATE   (al pasar a submitted) copia del
--                                                 producto y su precio, fecha de
--                                                 envío y versión.
--   log_proposal_event()         AFTER INSERT/UPDATE de status  historial en
--                                                 proposal_events (SECURITY DEFINER:
--                                                 el cliente nunca escribe ahí).
-- Además, updated_at con la función existente public.set_updated_at().
--
-- Los triggers BEFORE se ejecutan por orden alfabético de nombre: el
-- prefijo numérico (10, 20, 30, 40, 50) fija el orden. La transición (20)
-- mira lo que envió el cliente ANTES de que la copia (40) rellene
-- product_snapshot, submitted_at y version.
--
-- Errores: 42501 (permiso / transición no permitida), 23514 (dato
-- inválido). Ejecutar completo (BEGIN … COMMIT).
-- ============================================================

BEGIN;

-- ---------- prechecks ----------
DO $$
declare
  v_col text;
begin
  if to_regclass('public.product_proposals') is null or to_regclass('public.proposal_events') is null then
    raise exception '38-C 02: falta 38-C 01 (tablas de propuestas)';
  end if;
  if exists (select 1 from pg_trigger
              where not tgisinternal
                and tgrelid in ('public.product_proposals'::regclass, 'public.proposal_events'::regclass)) then
    raise exception '38-C 02: ya hay triggers sobre las tablas de propuestas';
  end if;
  if exists (select 1 from pg_proc
              where pronamespace = 'public'::regnamespace
                and proname in ('fix_proposal_author', 'validate_proposal_changes', 'transition_proposal_status',
                                'snapshot_product_on_submit', 'log_proposal_event')) then
    raise exception '38-C 02: alguna de las funciones ya existe';
  end if;
  if to_regprocedure('public.set_updated_at()') is null or to_regprocedure('public.my_verified_distributor_id()') is null then
    raise exception '38-C 02: faltan public.set_updated_at() o public.my_verified_distributor_id()';
  end if;
  -- Las claves de la lista cerrada son columnas reales de products.
  foreach v_col in array array['name', 'description', 'category_id', 'subcategory', 'image_url', 'availability',
                               'lead_time', 'brand', 'measurements', 'materials', 'finishes',
                               'technical_sheet_url', 'cad_bim_3d_url', 'use_context', 'space'] loop
    if not exists (select 1 from information_schema.columns
                    where table_schema = 'public' and table_name = 'products' and column_name = v_col) then
      raise exception '38-C 02: products.% no existe', v_col;
    end if;
  end loop;
  if exists (select 1 from pg_policies where schemaname = 'public' and tablename in ('product_proposals', 'proposal_events')) then
    raise exception '38-C 02: las tablas de propuestas ya tienen políticas (03 no debe aplicarse antes que 02)';
  end if;
end $$;

-- ---------- 1. distribuidor y autor fijados por el servidor ----------
create function public.fix_proposal_author()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
begin
  if v_uid is not null then
    new.distributor_id := (select public.my_verified_distributor_id());
    if new.distributor_id is null then
      raise exception 'Tu empresa no está verificada: no puedes crear propuestas.' using errcode = '42501';
    end if;
    new.author_id := v_uid;
    if new.status is distinct from 'draft' then
      raise exception 'Una propuesta nueva empieza siempre como borrador.' using errcode = '42501';
    end if;
    -- Campos del sistema y de Mobau: nunca los fija el cliente.
    new.version := 1;
    new.product_snapshot := null;
    new.submitted_at := null;
    new.reviewed_at := null;
    new.reviewed_by := null;
    new.rejection_reason := null;
    new.created_at := now();
    new.updated_at := now();
  end if;
  if not exists (select 1 from public.products p
                  where p.id = new.product_id and p.distributor_id = new.distributor_id) then
    raise exception 'El producto no pertenece a la empresa de la propuesta.' using errcode = '42501';
  end if;
  return new;
end;
$$;

-- ---------- 2. validación de los datos propuestos ----------
create function public.validate_proposal_changes()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  k text;
  v jsonb;
  s text;
  allowed constant text[] := array['name', 'description', 'category_id', 'subcategory', 'image_url', 'availability',
                                   'lead_time', 'brand', 'measurements', 'materials', 'finishes',
                                   'technical_sheet_url', 'cad_bim_3d_url', 'use_context', 'space'];
  -- Mismos límites que products_text_lengths.
  max_len constant jsonb := '{"name":120, "brand":80, "description":2000, "measurements":200, "materials":200,
                              "finishes":200, "lead_time":160, "image_url":500, "technical_sheet_url":500,
                              "cad_bim_3d_url":500, "category_id":100, "subcategory":100}';
  -- Mismo patrón que products_urls_http.
  url_re constant text := '^https?://[^\s"''<>`]+$';
  v_cur_category text;
  v_cur_subcategory text;
  v_category text;
  v_subcategory text;
begin
  for k, v in select e.key, e.value from jsonb_each(new.proposed_changes) e loop
    if not (k = any (allowed)) then
      raise exception 'Campo no permitido en la propuesta: %.', k using errcode = '23514';
    end if;
    if jsonb_typeof(v) not in ('string', 'null') then
      raise exception 'El campo % debe ser texto.', k using errcode = '23514';
    end if;
    s := v #>> '{}';

    if k in ('name', 'category_id', 'availability') and (s is null or btrim(s) = '') then
      raise exception 'El campo % no puede quedar vacío.', k using errcode = '23514';
    end if;
    if s is not null and max_len ? k and char_length(s) > (max_len ->> k)::int then
      raise exception 'El campo % supera los % caracteres.', k, max_len ->> k using errcode = '23514';
    end if;
    if k in ('image_url', 'technical_sheet_url', 'cad_bim_3d_url') and s is not null and s !~* url_re then
      raise exception 'El campo % debe ser un enlace que empiece por http:// o https://.', k using errcode = '23514';
    end if;
    if k = 'availability' and s not in ('en-stock', 'bajo-pedido', 'por-confirmar') then
      raise exception 'Disponibilidad no válida: %.', s using errcode = '23514';
    end if;
    if k = 'use_context' and s is not null and s not in ('residencial', 'comercial', 'hospitality', 'oficina') then
      raise exception 'Uso no válido: %.', s using errcode = '23514';
    end if;
    if k = 'space' and s is not null
       and s not in ('sala', 'comedor', 'dormitorio', 'cocina', 'bano', 'oficina', 'areas-comunes', 'retail', 'exterior') then
      raise exception 'Espacio no válido: %.', s using errcode = '23514';
    end if;
    if k = 'category_id' and not exists (select 1 from public.categories c where c.id = s) then
      raise exception 'Categoría no válida: %.', s using errcode = '23514';
    end if;
  end loop;

  -- Subcategoría coherente con la categoría resultante (como
  -- products_validate_subcategory): lo propuesto o, si no se propone, lo actual.
  if new.proposed_changes ? 'category_id' or new.proposed_changes ? 'subcategory' then
    select p.category_id, p.subcategory into v_cur_category, v_cur_subcategory
      from public.products p where p.id = new.product_id;
    v_category := coalesce(new.proposed_changes ->> 'category_id', v_cur_category);
    v_subcategory := case when new.proposed_changes ? 'subcategory'
                          then new.proposed_changes ->> 'subcategory'
                          else v_cur_subcategory end;
    if v_subcategory is not null and not exists (
         select 1 from public.categories c
          where c.id = v_category and v_subcategory = any (c.subcategories)) then
      raise exception 'La subcategoría "%" no pertenece a la categoría "%": propón también la subcategoría (o vacíala).',
        v_subcategory, v_category using errcode = '23514';
    end if;
  end if;

  return new;
end;
$$;

-- ---------- 3. transiciones del distribuidor ----------
create function public.transition_proposal_status()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  -- Sin sesión de cliente (Mobau desde el editor SQL): sin reglas de distribuidor.
  if (select auth.uid()) is null then
    return new;
  end if;

  if old.distributor_id is distinct from (select public.my_verified_distributor_id()) then
    raise exception 'Esta propuesta no es de tu empresa verificada.' using errcode = '42501';
  end if;
  if new.id is distinct from old.id
     or new.product_id is distinct from old.product_id
     or new.distributor_id is distinct from old.distributor_id
     or new.author_id is distinct from old.author_id
     or new.created_at is distinct from old.created_at then
    raise exception 'No se puede cambiar el producto, la empresa ni el autor de una propuesta.' using errcode = '42501';
  end if;
  if new.rejection_reason is distinct from old.rejection_reason
     or new.reviewed_at is distinct from old.reviewed_at
     or new.reviewed_by is distinct from old.reviewed_by
     or new.product_snapshot is distinct from old.product_snapshot
     or new.submitted_at is distinct from old.submitted_at
     or new.version is distinct from old.version then
    raise exception 'Esos campos los gestiona Mobau o el sistema.' using errcode = '42501';
  end if;

  -- Sin cambio de estado: edición del contenido, solo en borrador o con cambios solicitados.
  if new.status = old.status then
    if old.status not in ('draft', 'changes_requested') then
      raise exception 'Una propuesta en estado % ya no se puede editar.', old.status using errcode = '42501';
    end if;
    return new;
  end if;

  if not ((old.status = 'draft' and new.status in ('submitted', 'withdrawn'))
          or (old.status = 'submitted' and new.status = 'withdrawn')
          or (old.status = 'changes_requested' and new.status in ('submitted', 'withdrawn'))) then
    raise exception 'Transición no permitida: % → %.', old.status, new.status using errcode = '42501';
  end if;

  if new.status = 'submitted'
     and new.proposed_changes = '{}'::jsonb and new.proposed_price_status is null then
    raise exception 'La propuesta no contiene ningún cambio.' using errcode = '23514';
  end if;

  return new;
end;
$$;

-- ---------- 4. copia del producto al enviar ----------
create function public.snapshot_product_on_submit()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_product jsonb;
  v_price jsonb;
begin
  select to_jsonb(p) into v_product from public.products p where p.id = new.product_id;
  if v_product is null then
    raise exception 'No se encontró el producto % para guardar la copia.', new.product_id using errcode = '42501';
  end if;
  select to_jsonb(pp) into v_price from public.product_prices pp where pp.product_id = new.product_id;

  new.product_snapshot := jsonb_build_object('product', v_product, 'price', v_price, 'taken_at', now());
  new.submitted_at := now();
  if old.status = 'changes_requested' then
    new.version := old.version + 1;
  end if;
  return new;
end;
$$;

-- ---------- 5. historial (solo anexar) ----------
-- SECURITY DEFINER: proposal_events no tendrá permisos de escritura para
-- ningún cliente; solo este trigger la escribe.
create function public.log_proposal_event()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
begin
  insert into public.proposal_events (proposal_id, actor_id, actor_kind, from_status, to_status, version, payload, note)
  values (
    new.id,
    v_uid,
    case when v_uid is null then 'mobau' else 'distributor' end,
    case when tg_op = 'INSERT' then null else old.status end,
    new.status,
    new.version,
    case when new.status = 'submitted' then
      jsonb_build_object('proposed_changes', new.proposed_changes,
                         'proposed_price_status', new.proposed_price_status,
                         'proposed_price_amount', new.proposed_price_amount,
                         'internal_note', new.internal_note)
    end,
    case when new.status in ('changes_requested', 'rejected') then new.rejection_reason end
  );
  return null;
end;
$$;

-- ---------- triggers (el prefijo numérico fija el orden) ----------
create trigger trg_product_proposals_10_author
  before insert on public.product_proposals
  for each row execute function public.fix_proposal_author();

create trigger trg_product_proposals_20_transition
  before update on public.product_proposals
  for each row execute function public.transition_proposal_status();

create trigger trg_product_proposals_30_validate
  before insert or update on public.product_proposals
  for each row execute function public.validate_proposal_changes();

create trigger trg_product_proposals_40_snapshot
  before update on public.product_proposals
  for each row
  when (new.status = 'submitted' and old.status is distinct from 'submitted')
  execute function public.snapshot_product_on_submit();

create trigger trg_product_proposals_50_updated_at
  before update on public.product_proposals
  for each row execute function public.set_updated_at();

create trigger trg_product_proposals_90_event_insert
  after insert on public.product_proposals
  for each row execute function public.log_proposal_event();

create trigger trg_product_proposals_91_event_status
  after update of status on public.product_proposals
  for each row
  when (old.status is distinct from new.status)
  execute function public.log_proposal_event();

-- ---------- sin EXECUTE para clientes (Supabase lo concede por defecto) ----------
-- Los triggers se disparan igual: PostgreSQL no comprueba EXECUTE al
-- ejecutar una función de trigger.
revoke all on function public.fix_proposal_author() from public, anon, authenticated;
revoke all on function public.validate_proposal_changes() from public, anon, authenticated;
revoke all on function public.transition_proposal_status() from public, anon, authenticated;
revoke all on function public.snapshot_product_on_submit() from public, anon, authenticated;
revoke all on function public.log_proposal_event() from public, anon, authenticated;

-- ---------- validación final ----------
DO $$
declare
  f text;
  r text;
  v_expected_triggers constant text[] := array[
    'trg_product_proposals_10_author', 'trg_product_proposals_20_transition', 'trg_product_proposals_30_validate',
    'trg_product_proposals_40_snapshot', 'trg_product_proposals_50_updated_at',
    'trg_product_proposals_90_event_insert', 'trg_product_proposals_91_event_status'];
begin
  if (select count(*) from pg_trigger
       where not tgisinternal and tgrelid = 'public.product_proposals'::regclass
         and tgname = any (v_expected_triggers)) <> 7
     or (select count(*) from pg_trigger
          where not tgisinternal and tgrelid = 'public.product_proposals'::regclass) <> 7 then
    raise exception '38-C 02: product_proposals no tiene exactamente los 7 triggers esperados';
  end if;
  if exists (select 1 from pg_trigger where not tgisinternal and tgrelid = 'public.proposal_events'::regclass) then
    raise exception '38-C 02: proposal_events no debería tener triggers';
  end if;

  foreach f in array array['public.fix_proposal_author()', 'public.validate_proposal_changes()',
                           'public.transition_proposal_status()', 'public.snapshot_product_on_submit()',
                           'public.log_proposal_event()'] loop
    if not exists (select 1 from pg_proc p
                    where p.oid = f::regprocedure
                      and p.proconfig @> array['search_path=""']) then
      raise exception '38-C 02: % no tiene search_path vacío', f;
    end if;
    foreach r in array array['anon', 'authenticated'] loop
      if has_function_privilege(r, f, 'EXECUTE') then
        raise exception '38-C 02: % puede ejecutar %', r, f;
      end if;
    end loop;
  end loop;

  if (select count(*) from pg_proc
       where oid in ('public.fix_proposal_author()'::regprocedure, 'public.validate_proposal_changes()'::regprocedure,
                     'public.transition_proposal_status()'::regprocedure, 'public.snapshot_product_on_submit()'::regprocedure)
         and prosecdef) <> 0 then
    raise exception '38-C 02: las funciones de validación no deben ser SECURITY DEFINER';
  end if;
  if not (select prosecdef from pg_proc where oid = 'public.log_proposal_event()'::regprocedure) then
    raise exception '38-C 02: log_proposal_event() debe ser SECURITY DEFINER';
  end if;

  if exists (select 1 from pg_policies where schemaname = 'public' and tablename in ('product_proposals', 'proposal_events')) then
    raise exception '38-C 02: las tablas de propuestas no deben tener políticas todavía';
  end if;
  if (select count(*) from pg_policies where schemaname = 'public') <> 40 then
    raise exception '38-C 02: el número de políticas de public ha cambiado (esperado 40)';
  end if;

  raise notice '38-C 02 OK: 5 funciones y 7 triggers; tablas aún cerradas para el cliente.';
end $$;

COMMIT;
