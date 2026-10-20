-- ============================================================
-- PROPUESTA NO EJECUTADA (43 · suite P2) — no ejecutar sin aprobación explícita
-- ============================================================
-- Suite de la matriz de acceso de 43-D. Requiere T1 y T4 aplicadas (dentro
-- del ensayo P2 o, después, sobre el servidor actualizado). Rol postgres;
-- JWT simulado como en 39/41. Cada caso es una subtransacción que se deshace
-- (MB001); sus preparativos (habilitación simulada, estudio temporal,
-- distribuidor sin verificar, admin revocado) viven solo dentro del caso.
-- Al final, MB999 con el resultado. Cuentas (E8): e2a655c1 (Individual),
-- 743270cd (Gratis sin datos), 5b4f13c8 (Gratis con datos); distribuidor
-- 392a9eb4 y Mobau a8fe42e8 solo como actores de lectura, sin modificarlos
-- fuera de casos revertidos.
-- Formato de expect en 'exec': SQLSTATE (5) o SQLSTATE[hint] exactos.
-- ============================================================

DO $P2S$
declare
  v_i uuid; v_f uuid; v_g uuid; v_s uuid; v_m uuid; v_s_dist text;
  p_i_act uuid := '3e533da7-1083-4295-a1de-15bfe6673bf3';
  p_i_arch_free uuid := 'd13a3629-774a-4a06-89bb-9748ff2238b5';
  p_i_arch_free2 uuid := '957dc93c-143b-47d6-9700-a59a56eae5ff';
  p_i_arch_free3 uuid := 'ee137494-4eaf-447b-9245-72556c15b801';
  p_i_arch_rfq uuid := 'b08d8ecb-70e7-494f-b9c2-22ec05b20c07';
  p_g_act uuid := '7bece1b3-81b8-4086-8d22-22c06a1295f0';
  v_studio uuid := '00000000-0000-0000-0000-00000000043a';
  v_prod text; n_prices bigint; n_other bigint; n_own_prices bigint; n_all_prices bigint;
  n_g_proj bigint; n_g_lines bigint; n_i_rfqs bigint; data0 text;
  grant_i text; grant_f_req text; grant_f_sub text; grant_s text;
  ins_proj constant text := 'insert into public.projects (owner_user_id, name, studio_id) values (%L, %L, %s)';
  ins_rfq constant text := 'insert into public.rfqs (project_id, requester_user_id, requester_name, requester_email) values (%L, %L, %L, %L)';
  data_fp constant text := 'select md5(coalesce((select string_agg(id::text || status || coalesce(studio_id::text, ''-'') || owner_user_id::text || name, ''|'' order by id) from public.projects), '''')'
                           || ' || coalesce((select string_agg(id::text || quantity::text || coalesce(unit, ''-'') || selected_for_rfq::text, ''|'' order by id) from public.project_products), '''')'
                           || ' || coalesce((select string_agg(id::text || status, ''|'' order by id) from public.rfqs), '''')'
                           || ' || coalesce((select string_agg(id::text || plan || role || plan_source || subscription_status, ''|'' order by id) from public.profiles), ''''))';
  r jsonb := '[]'::jsonb; t record; i int;
  v_got text; v_n bigint; v_ok boolean; v_stmt text; v_hint text;
  n_total int := 0; n_ok int := 0;
begin
  select id into v_i from public.profiles where id::text like 'e2a655c1%';
  select id into v_f from public.profiles where id::text like '743270cd%';
  select id into v_g from public.profiles where id::text like '5b4f13c8%';
  select id into v_s from public.profiles where id::text like '392a9eb4%';
  select id into v_m from public.profiles where id::text like 'a8fe42e8%';
  select distributor_id into v_s_dist from public.distributor_profiles where user_id = v_s and verification_status = 'verified';
  -- Producto publicado que no está en ninguno de los dos proyectos donde se añaden líneas.
  select c.id into v_prod from public.catalog_products c
   where not exists (select 1 from public.project_products l where l.product_id = c.id and l.project_id in (p_i_act, p_g_act))
   order by c.id limit 1;
  if v_i is null or v_f is null or v_g is null or v_s is null or v_m is null or v_s_dist is null or v_prod is null then
    raise exception 'MOBAU_43_P2_SUITE: faltan actores o datos de partida' using errcode = 'MB998';
  end if;
  if to_regprocedure('public.my_professional_access()') is null
     or not exists (select 1 from pg_policies where policyname = 'projects_plan_insert') then
    raise exception 'MOBAU_43_P2_SUITE: T1 y T4 no están aplicadas' using errcode = 'MB998';
  end if;
  if exists (select 1 from public.studios) or exists (select 1 from public.profiles where plan_source <> 'default')
     or exists (select 1 from mobau_private.plan_events) then
    raise exception 'MOBAU_43_P2_SUITE: hay estudios, habilitaciones o eventos de partida inesperados' using errcode = 'MB998';
  end if;
  if (select count(*) from public.projects where id in (p_i_act, p_i_arch_free, p_i_arch_free2, p_i_arch_free3, p_i_arch_rfq, p_g_act)) <> 6
     or (select status from public.projects where id = p_i_act) <> 'active'
     or (select status from public.projects where id = p_g_act) <> 'active'
     or (select count(*) from public.projects where owner_user_id = v_i and status = 'active') <> 1
     or exists (select 1 from public.rfqs where project_id in (p_i_arch_free, p_i_arch_free2, p_i_arch_free3))
     or not exists (select 1 from public.rfqs where project_id = p_i_arch_rfq) then
    raise exception 'MOBAU_43_P2_SUITE: los proyectos de prueba no están como se leyeron' using errcode = 'MB998';
  end if;

  -- Valores esperados, calculados como postgres con la misma condición de la función.
  select count(*), count(*) filter (where p.distributor_id <> v_s_dist) into n_prices, n_other
    from public.product_prices pp join public.products p on p.id = pp.product_id
   where p.publication_status = 'published' and p.status = 'active' and p.retired_at is null and p.trashed_at is null
     and pp.price_status in ('published', 'quote_required', 'pending_confirmation', 'unavailable');
  select count(*) into n_own_prices from public.product_prices pp join public.products p on p.id = pp.product_id where p.distributor_id = v_s_dist;
  select count(*) into n_all_prices from public.product_prices;
  select count(*) into n_g_proj from public.projects where owner_user_id = v_g;
  select count(*) into n_g_lines from public.project_products l join public.projects p on p.id = l.project_id where p.owner_user_id = v_g;
  select count(*) into n_i_rfqs from public.rfqs where requester_user_id = v_i;
  execute data_fp into data0;

  grant_i := format('update public.profiles set plan = %L, plan_source = %L, plan_granted_at = now(), plan_note = %L where id = %L',
                    'individual_founder', 'manual_pilot', 'Ensayo P2 (revertido)', v_i);
  grant_f_req := format('update public.profiles set plan = %L where id = %L', 'individual_founder', v_f);
  grant_f_sub := format('update public.profiles set plan = %L, plan_source = %L where id = %L', 'individual_founder', 'subscription', v_f);
  grant_s := format('update public.profiles set plan = %L, plan_source = %L where id = %L', 'individual_founder', 'manual_pilot', v_s);

  for t in
    select * from (values
      -- ========== A · precios del catálogo ==========
      ('A01 sin sesión: la función no es ejecutable por anon', 'anon', null::text, null::text, null::text[],
         array['select count(*) from public.catalog_published_prices()'], 'exec', '42501'),
      ('A02 Gratis con datos → 42501[plan_required], ninguna fila ni estado', 'authenticated', v_g::text, 'aal1', null,
         array['select count(*) from public.catalog_published_prices()'], 'exec', '42501[plan_required]'),
      ('A03 Gratis sin datos → 42501[plan_required]', 'authenticated', v_f::text, 'aal1', null,
         array['select count(*) from public.catalog_published_prices()'], 'exec', '42501[plan_required]'),
      ('A04 plan solicitado sin habilitar (individual_founder + default) → 42501[plan_required]', 'authenticated', v_f::text, 'aal1', array[grant_f_req],
         array['select count(*) from public.catalog_published_prices()'], 'exec', '42501[plan_required]'),
      ('A05 suscripción reservada (subscription) todavía no concede → 42501[plan_required]', 'authenticated', v_f::text, 'aal1', array[grant_f_sub],
         array['select count(*) from public.catalog_published_prices()'], 'exec', '42501[plan_required]'),
      ('A06 Individual habilitado (manual_pilot) → todas las filas publicadas', 'authenticated', v_i::text, 'aal1', array[grant_i],
         array['select count(*) from public.catalog_published_prices()'], 'count', n_prices::text),
      ('A07 distribuidor verificado → todas las filas, también de otras empresas (D4)', 'authenticated', v_s::text, 'aal1', null,
         array[format('select count(*) from public.catalog_published_prices() c join public.products p on p.id = c.product_id where p.distributor_id <> %L', v_s_dist)],
         'count', n_other::text),
      ('A08 distribuidor sin verificar → 42501[distributor_unverified] (E3)', 'authenticated', v_s::text, 'aal1',
         array[format('update public.distributor_profiles set verification_status = %L where user_id = %L', 'pending_verification', v_s)],
         array['select count(*) from public.catalog_published_prices()'], 'exec', '42501[distributor_unverified]'),
      ('A09 Mobau con aal2 → todas las filas', 'authenticated', v_m::text, 'aal2', null,
         array['select count(*) from public.catalog_published_prices()'], 'count', n_prices::text),
      ('A10 Mobau sin aal2 → todas las filas (E4)', 'authenticated', v_m::text, 'aal1', null,
         array['select count(*) from public.catalog_published_prices()'], 'count', n_prices::text),
      ('A11 Mobau revocado → 42501[plan_required]', 'authenticated', v_m::text, 'aal2',
         array[format('update public.mobau_admins set revoked_at = now() where user_id = %L', v_m)],
         array['select count(*) from public.catalog_published_prices()'], 'exec', '42501[plan_required]'),
      ('A12 Gratis no lee product_prices directamente (sin cambio)', 'authenticated', v_g::text, 'aal1', null,
         array['select count(*) from public.product_prices'], 'count', '0'),
      ('A13 Individual habilitado tampoco lee product_prices directamente (solo la función)', 'authenticated', v_i::text, 'aal1', array[grant_i],
         array['select count(*) from public.product_prices'], 'count', '0'),
      -- ========== B · función de acceso y datos de plan ==========
      ('B01 my_professional_access() Gratis = false', 'authenticated', v_g::text, 'aal1', null,
         array['select public.my_professional_access()::text'], 'text', 'false'),
      ('B02 my_professional_access() Individual habilitado = true', 'authenticated', v_i::text, 'aal1', array[grant_i],
         array['select public.my_professional_access()::text'], 'text', 'true'),
      ('B03 plan solicitado sin habilitar = false', 'authenticated', v_f::text, 'aal1', array[grant_f_req],
         array['select public.my_professional_access()::text'], 'text', 'false'),
      ('B04 distribuidor con plan habilitado = false (rol supplier excluido)', 'authenticated', v_s::text, 'aal1', array[grant_s],
         array['select public.my_professional_access()::text'], 'text', 'false'),
      ('B05 anon no ejecuta my_professional_access()', 'anon', null, null, null,
         array['select public.my_professional_access()'], 'exec', '42501'),
      ('B06 el cliente no escribe su plan_source', 'authenticated', v_g::text, 'aal1', null,
         array[format('update public.profiles set plan_source = %L where id = %L', 'manual_pilot', v_g)], 'exec', '42501'),
      ('B07 el cliente no escribe su plan', 'authenticated', v_g::text, 'aal1', null,
         array[format('update public.profiles set plan = %L where id = %L', 'individual_founder', v_g)], 'exec', '42501'),
      ('B08 el cliente no cambia plans (RLS sin política de escritura)', 'authenticated', v_g::text, 'aal1', null,
         array['update public.plans set includes_professional_tools = true where id = ''free_trial'''], 'rows', 'ok rows=0'),
      ('B09 el cliente no lee la auditoría de habilitaciones', 'authenticated', v_g::text, 'aal1', null,
         array['select count(*) from mobau_private.plan_events'], 'exec', '42501'),
      -- ========== C · Gratis con datos (E5/E5b) ==========
      ('C01 Gratis lee sus proyectos (solo lectura)', 'authenticated', v_g::text, 'aal1', null,
         array[format('select count(*) from public.projects where owner_user_id = %L', v_g)], 'count', n_g_proj::text),
      ('C02 Gratis lee sus líneas', 'authenticated', v_g::text, 'aal1', null,
         array[format('select count(*) from public.project_products l join public.projects p on p.id = l.project_id where p.owner_user_id = %L', v_g)], 'count', n_g_lines::text),
      ('C03 Gratis sin proyectos no crea uno → 42501 (política de plan)', 'authenticated', v_f::text, 'aal1', null,
         array[format(ins_proj, v_f, 'P2 Gratis', 'null')], 'exec', '42501'),
      ('C04 Gratis con 1 activo no crea otro → P0001 (el trigger, BEFORE, actúa antes que la RLS)', 'authenticated', v_g::text, 'aal1', null,
         array[format(ins_proj, v_g, 'P2 Gratis 2', 'null')], 'exec', 'P0001'),
      ('C05 Gratis no edita su proyecto', 'authenticated', v_g::text, 'aal1', null,
         array[format('update public.projects set name = name || %L where id = %L', ' (P2)', p_g_act)], 'rows', 'ok rows=0'),
      ('C06 Gratis no archiva su proyecto', 'authenticated', v_g::text, 'aal1', null,
         array[format('update public.projects set status = %L where id = %L', 'archived', p_g_act)], 'rows', 'ok rows=0'),
      ('C07 Gratis no añade líneas', 'authenticated', v_g::text, 'aal1', null,
         array[format('insert into public.project_products (project_id, product_id, quantity, unit) values (%L, %L, 1, %L)', p_g_act, v_prod, 'ud.')], 'exec', '42501'),
      ('C08 Gratis no edita líneas', 'authenticated', v_g::text, 'aal1', null,
         array[format('update public.project_products set quantity = quantity + 1 where project_id = %L', p_g_act)], 'rows', 'ok rows=0'),
      ('C09 Gratis no borra líneas', 'authenticated', v_g::text, 'aal1', null,
         array[format('delete from public.project_products where project_id = %L', p_g_act)], 'rows', 'ok rows=0'),
      ('C10 Gratis no envía solicitudes', 'authenticated', v_g::text, 'aal1', null,
         array[format(ins_rfq, p_g_act, v_g, 'P2', 'p2@example.test')], 'exec', '42501'),
      ('C11 Gratis (cuenta Individual sin habilitar) lee su historial de solicitudes', 'authenticated', v_i::text, 'aal1', null,
         array[format('select count(*) from public.rfqs where requester_user_id = %L', v_i)], 'count', n_i_rfqs::text),
      ('C12 Gratis elimina un archivado propio sin solicitudes; sus líneas se borran en cascada (E5b)', 'authenticated', v_i::text, 'aal1', null,
         array[format('delete from public.projects where id = %L', p_i_arch_free), 'reset role',
               format('select (select count(*) from public.projects where id = %L) + (select count(*) from public.project_products where project_id = %L)', p_i_arch_free, p_i_arch_free)],
         'count', '0'),
      ('C13 Gratis no elimina un archivado con solicitudes → 23503 (se respetan las solicitudes)', 'authenticated', v_i::text, 'aal1', null,
         array[format('delete from public.projects where id = %L', p_i_arch_rfq)], 'exec', '23503'),
      ('C14 Gratis no elimina un proyecto activo (sin cambio)', 'authenticated', v_g::text, 'aal1', null,
         array[format('delete from public.projects where id = %L', p_g_act)], 'rows', 'ok rows=0'),
      -- ========== D · Individual habilitado (E9) ==========
      ('D01 Individual con 1 activo crea un segundo', 'authenticated', v_i::text, 'aal1', array[grant_i],
         array[format(ins_proj, v_i, 'P2 Individual 2', 'null')], 'rows', 'ok rows=1'),
      ('D02 Individual no crea un tercero activo → P0001', 'authenticated', v_i::text, 'aal1', array[grant_i],
         array[format(ins_proj, v_i, 'P2 Individual 2', 'null'), format(ins_proj, v_i, 'P2 Individual 3', 'null')], 'exec', 'P0001'),
      ('D03 Individual reactiva un archivado dentro del cupo (sin el bloqueo antiguo)', 'authenticated', v_i::text, 'aal1', array[grant_i],
         array[format('update public.projects set status = %L where id = %L', 'active', p_i_arch_free2)], 'rows', 'ok rows=1'),
      ('D04 Individual no reactiva por encima del cupo → P0001', 'authenticated', v_i::text, 'aal1', array[grant_i],
         array[format('update public.projects set status = %L where id = %L', 'active', p_i_arch_free2),
               format('update public.projects set status = %L where id = %L', 'active', p_i_arch_free3)], 'exec', 'P0001'),
      ('D05 Individual edita su proyecto', 'authenticated', v_i::text, 'aal1', array[grant_i],
         array[format('update public.projects set name = name || %L where id = %L', ' (P2)', p_i_act)], 'rows', 'ok rows=1'),
      ('D06 Individual archiva su proyecto', 'authenticated', v_i::text, 'aal1', array[grant_i],
         array[format('update public.projects set status = %L where id = %L', 'archived', p_i_act)], 'rows', 'ok rows=1'),
      ('D07 Individual añade una línea con un producto publicado', 'authenticated', v_i::text, 'aal1', array[grant_i],
         array[format('insert into public.project_products (project_id, product_id, quantity, unit) values (%L, %L, 1, %L)', p_i_act, v_prod, 'ud.')], 'rows', 'ok rows=1'),
      ('D08 Individual envía una solicitud de su proyecto activo', 'authenticated', v_i::text, 'aal1', array[grant_i],
         array[format(ins_rfq, p_i_act, v_i, 'P2', 'p2@example.test')], 'rows', 'ok rows=1'),
      -- ========== E · studio_id (R2) ==========
      ('E01 nadie crea un proyecto en el estudio de otra persona → 42501', 'authenticated', v_i::text, 'aal1',
         array[grant_i, format('insert into public.studios (id, name) values (%L, %L)', v_studio, 'Estudio ensayo P2')],
         array[format(ins_proj, v_i, 'P2 en otro estudio', quote_literal(v_studio))], 'exec', '42501'),
      ('E02 nadie mueve un proyecto propio al estudio de otra persona → 42501', 'authenticated', v_i::text, 'aal1',
         array[grant_i, format('insert into public.studios (id, name) values (%L, %L)', v_studio, 'Estudio ensayo P2')],
         array[format('update public.projects set studio_id = %L where id = %L', v_studio, p_i_act)], 'exec', '42501'),
      ('E03 sí en el estudio propio (el trigger cuenta por estudio y bloquea su fila)', 'authenticated', v_i::text, 'aal1',
         array[grant_i, format('insert into public.studios (id, name) values (%L, %L)', v_studio, 'Estudio ensayo P2'),
               format('update public.profiles set studio_id = %L where id = %L', v_studio, v_i)],
         array[format(ins_proj, v_i, 'P2 en mi estudio', quote_literal(v_studio))], 'rows', 'ok rows=1'),
      -- ========== F · trigger (R1, E9) ==========
      ('F01 el trigger bloquea la fila antes de contar y no tiene el bloqueo antiguo de reactivación', '-', null, null, null,
         array['select count(*) from pg_proc where oid = ''public.enforce_active_project_limit()''::regprocedure'
               || ' and prosrc ~ ''for update of s'' and prosrc ~ ''for update of pr'' and prosrc !~ ''v_owner_max'''], 'count', '1'),
      -- ========== G · distribuidor y Mobau sin cambios ==========
      -- G01: su proyecto activo histórico hace que el trigger (BEFORE) rechace
      -- primero con P0001; la RLS (proveedor, plan) también lo rechazaría. Es
      -- el comportamiento de hoy, sin cambio.
      ('G01 distribuidor no crea proyectos (sin cambio: P0001 del trigger, antes que la RLS)', 'authenticated', v_s::text, 'aal1', null,
         array[format(ins_proj, v_s, 'P2 distribuidor', 'null')], 'exec', 'P0001'),
      ('G02 distribuidor lee sus propios precios (sin cambio)', 'authenticated', v_s::text, 'aal1', null,
         array['select count(*) from public.product_prices'], 'count', n_own_prices::text),
      ('G03 Mobau con aal2 lee todos los precios en moderación (sin cambio)', 'authenticated', v_m::text, 'aal2', null,
         array['select count(*) from public.product_prices'], 'count', n_all_prices::text),
      ('G04 Mobau sin aal2 no lee product_prices directamente (sin cambio)', 'authenticated', v_m::text, 'aal1', null,
         array['select count(*) from public.product_prices'], 'count', '0'),
      -- ========== Z · fuera de los casos ==========
      ('Z01 sin restos: datos idénticos, sin estudios, habilitaciones ni eventos', '-', null, null, null,
         array[format('select count(*) where (%s) = %L and not exists (select 1 from public.studios)'
                      || ' and not exists (select 1 from public.profiles where plan_source <> ''default'')'
                      || ' and not exists (select 1 from mobau_private.plan_events)'
                      || ' and (select verification_status from public.distributor_profiles where user_id = %L) = ''verified'''
                      || ' and (select revoked_at from public.mobau_admins where user_id = %L) is null',
                      data_fp, data0, v_s, v_m)], 'count', '1')
    ) as c(name, role, sub, aal, setup, sql, kind, expect)
  loop
    v_got := null;
    begin
      if t.setup is not null then
        foreach v_stmt in array t.setup loop execute v_stmt; end loop;
      end if;
      if t.role <> '-' then execute format('set local role %I', t.role); end if;
      perform set_config('request.jwt.claim.sub', coalesce(t.sub, ''), true);
      perform set_config('request.jwt.claim.role', '', true);
      perform set_config('request.jwt.claims',
        case when t.sub is null then '' else json_build_object('sub', t.sub, 'role', t.role, 'aal', t.aal)::text end, true);
      for i in 1 .. array_length(t.sql, 1) loop
        if i < array_length(t.sql, 1) then
          execute t.sql[i];
        elsif t.kind = 'count' then
          execute t.sql[i] into v_n; v_got := v_n::text;
        elsif t.kind = 'text' then
          execute t.sql[i] into v_got;
        else
          execute t.sql[i]; get diagnostics v_n = row_count; v_got := 'ok rows=' || v_n;
        end if;
      end loop;
      raise exception using errcode = 'MB001';
    exception
      when sqlstate 'MB001' then null;
      when others then
        get stacked diagnostics v_hint = pg_exception_hint;
        v_got := sqlstate || ' [' || coalesce(v_hint, '') || '] ' || left(sqlerrm, 160);
    end;
    v_ok := case
      when t.kind = 'exec' and t.expect ~ '^[0-9A-Z]{5}\[' then left(v_got, length(t.expect) + 1) = substr(t.expect, 1, 5) || ' ' || substr(t.expect, 6)
      when t.kind = 'exec' and t.expect ~ '^[0-9A-Z]{5}$' then left(v_got, 6) = t.expect || ' '
      else v_got = t.expect
    end;
    n_total := n_total + 1;
    if v_ok then n_ok := n_ok + 1; end if;
    r := r || jsonb_build_object('prueba', t.name, 'esperado', t.expect, 'obtenido', v_got, 'ok', coalesce(v_ok, false));
  end loop;

  raise exception 'MOBAU_43_P2_SUITE total=% ok=% fallos=% :: %', n_total, n_ok, n_total - n_ok, r::text
    using errcode = 'MB999';
end $P2S$;
