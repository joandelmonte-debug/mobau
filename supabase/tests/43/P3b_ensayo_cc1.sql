-- ============================================================
-- PROPUESTA NO EJECUTADA (43 · CC1 · ensayo P3, opción B de D3, revertido) — no ejecutar sin aprobación explícita
-- ============================================================
-- Generado por herramientas/generar_p3.py. En una sola transacción que
-- SIEMPRE termina con MB990 (nada persiste):
--   1. comprueba el estado de partida (T4 registrada; D3 y D4 sin aplicar);
--   2. aplica D3 y D4 (textos incrustados, cada uno con su MD5);
--   3. ejecuta la suite P3-S (29 casos) y guarda su resultado;
--   4. aplica R-D4 y R-D3;
--   5. compara la huella final con la de partida.
-- Éxito: «P3 cambia=true identico=true» y la suite «total=29 ok=29 fallos=0».
-- Ejecutar completo, con el control MD5 del archivo.
-- ============================================================

BEGIN;

DO $P3$
declare
  t_d3 text := $D3B$
DO $$
begin
  if current_user <> 'postgres' then
    raise exception '43-D3: ejecutar como postgres';
  end if;
  if not exists (select 1 from supabase_migrations.schema_migrations where version = '20261020120100')
     or to_regprocedure('public.my_professional_access()') is null then
    raise exception '43-D3: T4 no está aplicada y registrada';
  end if;
  if (select count(*) from pg_policies where schemaname = 'public' and tablename in ('projects', 'project_products', 'rfqs')) <> 25 then
    raise exception '43-D3: el número de políticas de partida en projects/project_products/rfqs no es 25';
  end if;
  if exists (select 1 from pg_policies where schemaname = 'public' and policyname in
             ('projects_plan_select', 'projects_plan_delete', 'project_products_plan_select', 'rfqs_plan_select')) then
    raise exception '43-D3: ya existe alguna política de D3';
  end if;
end $$;

create policy projects_plan_select on public.projects as restrictive for select to authenticated
  using ((select public.my_professional_access())
         or not coalesce((select pr.role in ('individual', 'studio_member') from public.profiles pr where pr.id = (select auth.uid())), true));
create policy projects_plan_delete on public.projects as restrictive for delete to authenticated
  using ((select public.my_professional_access())
         or not coalesce((select pr.role in ('individual', 'studio_member') from public.profiles pr where pr.id = (select auth.uid())), true));
create policy project_products_plan_select on public.project_products as restrictive for select to authenticated
  using ((select public.my_professional_access())
         or not coalesce((select pr.role in ('individual', 'studio_member') from public.profiles pr where pr.id = (select auth.uid())), true));
create policy rfqs_plan_select on public.rfqs as restrictive for select to authenticated
  using ((select public.my_professional_access())
         or not coalesce((select pr.role in ('individual', 'studio_member') from public.profiles pr where pr.id = (select auth.uid())), true));

DO $$
begin
  if (select count(*) from pg_policies where schemaname = 'public' and tablename in ('projects', 'project_products', 'rfqs')) <> 29
     or (select count(*) from pg_policies where schemaname = 'public' and permissive = 'RESTRICTIVE' and policyname in
         ('projects_plan_select', 'projects_plan_delete', 'project_products_plan_select', 'rfqs_plan_select')) <> 4 then
    raise exception '43-D3: políticas no creadas como se esperaba';
  end if;
end $$;
$D3B$;
  t_d4 text := $D4B$
DO $$
begin
  if current_user <> 'postgres' then
    raise exception '43-D4: ejecutar como postgres';
  end if;
  if to_regclass('public.professional_profiles') is null
     or exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'professional_profiles'
                and column_name in ('first_name', 'last_name'))
     or to_regprocedure('public.professional_profiles_sync_name()') is not null
     or exists (select 1 from pg_constraint where conname = 'professional_profiles_name_parts_check') then
    raise exception '43-D4: el estado de partida no es el esperado (ya existen columnas, función o restricción de D4)';
  end if;
  -- Huella de los nombres actuales: la migración no debe cambiar ninguno.
  perform set_config('mobau.d4_nombres',
    coalesce((select md5(string_agg(user_id::text || ':' || professional_name, '|' order by user_id)) from public.professional_profiles), '-'),
    true);
end $$;

alter table public.professional_profiles
  add column first_name text,
  add column last_name text;

alter table public.professional_profiles
  add constraint professional_profiles_name_parts_check
  check ((first_name is null) = (last_name is null)
         and (first_name is null
              or (char_length(first_name) between 1 and 60 and char_length(last_name) between 1 and 60)));

CREATE OR REPLACE FUNCTION public.professional_profiles_sync_name()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
begin
  -- 43-C1: con nombre y apellidos, professional_name es siempre «Nombre Apellidos».
  if new.first_name is not null or new.last_name is not null then
    new.first_name := nullif(regexp_replace(btrim(coalesce(new.first_name, '')), '\s+', ' ', 'g'), '');
    new.last_name := nullif(regexp_replace(btrim(coalesce(new.last_name, '')), '\s+', ' ', 'g'), '');
    if new.first_name is null or new.last_name is null then
      raise exception 'Indica tu nombre y tus apellidos.' using errcode = '23514';
    end if;
    new.professional_name := new.first_name || ' ' || new.last_name;
  elsif tg_op = 'UPDATE' and old.first_name is not null then
    raise exception 'El nombre y los apellidos no pueden quedar vacíos.' using errcode = '23514';
  end if;
  return new;
end;
$function$;

revoke all on function public.professional_profiles_sync_name() from public, anon, authenticated;

create trigger trg_professional_profiles_sync_name
  before insert or update on public.professional_profiles
  for each row execute function public.professional_profiles_sync_name();

DO $$
begin
  if (select count(*) from information_schema.columns where table_schema = 'public' and table_name = 'professional_profiles'
      and column_name in ('first_name', 'last_name')) <> 2
     or not exists (select 1 from pg_constraint where conname = 'professional_profiles_name_parts_check')
     or not exists (select 1 from pg_trigger where tgname = 'trg_professional_profiles_sync_name' and tgrelid = 'public.professional_profiles'::regclass) then
    raise exception '43-D4: objetos no creados como se esperaba';
  end if;
  if exists (select 1 from public.professional_profiles where first_name is not null or last_name is not null) then
    raise exception '43-D4: algún perfil tiene ya nombre y apellidos (no debe dividirse ninguno)';
  end if;
  if coalesce((select md5(string_agg(user_id::text || ':' || professional_name, '|' order by user_id)) from public.professional_profiles), '-')
     <> current_setting('mobau.d4_nombres') then
    raise exception '43-D4: ha cambiado algún nombre existente';
  end if;
  if has_function_privilege('authenticated', 'public.professional_profiles_sync_name()', 'EXECUTE')
     or has_function_privilege('anon', 'public.professional_profiles_sync_name()', 'EXECUTE') then
    raise exception '43-D4: la función del trigger es ejecutable por clientes';
  end if;
end $$;
$D4B$;
  t_suite text := $SUI$DO $P3S$
declare
  v_i uuid; v_s uuid; v_m uuid;
  p_i_act uuid := '3e533da7-1083-4295-a1de-15bfe6673bf3';
  p_i_arch_free uuid := 'd13a3629-774a-4a06-89bb-9748ff2238b5';
  p_i_arch_rfq uuid := 'b08d8ecb-70e7-494f-b9c2-22ec05b20c07';
  n_i_proj bigint; n_i_lines bigint; n_i_rfqs bigint; name_i text; data0 text; x13_exp text; x13_name text;
  revoke_i text;
  long61 constant text := repeat('a', 61);
  ins_proj constant text := 'insert into public.projects (owner_user_id, name, studio_id) values (%L, %L, %s)';
  upd_pp constant text := 'update public.professional_profiles set %s where user_id = %L';
  sel_name constant text := 'select professional_name from public.professional_profiles where user_id = %L';
  data_fp constant text := 'select md5(coalesce((select string_agg(id::text || status || owner_user_id::text || name, ''|'' order by id) from public.projects), '''')'
                           || ' || coalesce((select string_agg(id::text || quantity::text || coalesce(unit, ''-''), ''|'' order by id) from public.project_products), '''')'
                           || ' || coalesce((select string_agg(id::text || status, ''|'' order by id) from public.rfqs), '''')'
                           || ' || coalesce((select string_agg(id::text || plan || role || plan_source, ''|'' order by id) from public.profiles), '''')'
                           || ' || coalesce((select string_agg(user_id::text || professional_name || coalesce(phone, ''-''), ''|'' order by user_id) from public.professional_profiles), '''')'
                           || ' || (select count(*)::text from public.moodboards))';
  r jsonb := '[]'::jsonb; t record; i int;
  v_got text; v_n bigint; v_ok boolean; v_stmt text; v_hint text;
  n_total int := 0; n_ok int := 0;
begin
  select id into v_i from public.profiles where id::text like 'e2a655c1%';
  select id into v_s from public.profiles where id::text like '392a9eb4%';
  select id into v_m from public.profiles where id::text like 'a8fe42e8%';
  if v_i is null or v_s is null or v_m is null then
    raise exception 'MOBAU_43_P3_SUITE: faltan actores' using errcode = 'MB998';
  end if;
  if (select count(*) from pg_policies where policyname in ('projects_plan_select', 'projects_plan_delete', 'project_products_plan_select', 'rfqs_plan_select')) <> 4
     or to_regprocedure('public.professional_profiles_sync_name()') is null then
    raise exception 'MOBAU_43_P3_SUITE: D3 y D4 no están aplicadas' using errcode = 'MB998';
  end if;
  if not exists (select 1 from public.profiles where id = v_i and plan = 'individual_founder' and plan_source = 'manual_pilot')
     or (select count(*) from public.projects where owner_user_id = v_i and status = 'active') <> 1
     or (select status from public.projects where id = p_i_act) <> 'active'
     or (select status from public.projects where id = p_i_arch_free) <> 'archived'
     or exists (select 1 from public.rfqs where project_id = p_i_arch_free)
     or not exists (select 1 from public.rfqs where project_id = p_i_arch_rfq)
     or not exists (select 1 from public.professional_profiles where user_id = v_i and first_name is null) then
    raise exception 'MOBAU_43_P3_SUITE: el estado de partida de e2a655c1 no es el leído' using errcode = 'MB998';
  end if;

  -- Valores esperados, calculados como postgres.
  select count(*) into n_i_proj from public.projects where owner_user_id = v_i;
  select count(*) into n_i_lines from public.project_products l join public.projects p on p.id = l.project_id where p.owner_user_id = v_i;
  select count(*) into n_i_rfqs from public.rfqs where requester_user_id = v_i;
  select professional_name into name_i from public.professional_profiles where user_id = v_i;
  execute data_fp into data0;
  -- D3 tiene dos opciones: A restringe a toda cuenta sin plan; B solo a las
  -- cuentas profesionales (el distribuidor sigue viendo su proyecto histórico).
  if (select qual from pg_policies where policyname = 'projects_plan_select') ~ 'studio_member' then
    select count(*)::text into x13_exp from public.projects where owner_user_id = v_s;
    x13_name := 'X13 [opción B] el distribuidor sigue viendo su proyecto histórico (sin cambio)';
  else
    x13_exp := '0';
    x13_name := 'X13 [opción A] el distribuidor deja de ver su proyecto histórico';
  end if;
  revoke_i := format('update public.profiles set plan = %L, plan_source = %L, plan_granted_at = null, plan_note = null where id = %L',
                     'free_trial', 'default', v_i);

  for t in
    select * from (values
      -- ========== X · D3: sin plan, nada de proyectos (e2a655c1 sin habilitación) ==========
      ('X01 sin plan no lee sus proyectos', 'authenticated', v_i::text, 'aal1', array[revoke_i]::text[],
         array[format('select count(*) from public.projects where owner_user_id = %L', v_i)], 'count', '0'),
      ('X02 sin plan no lee sus líneas', 'authenticated', v_i::text, 'aal1', array[revoke_i],
         array['select count(*) from public.project_products'], 'count', '0'),
      ('X03 sin plan no lee su historial de solicitudes', 'authenticated', v_i::text, 'aal1', array[revoke_i],
         array[format('select count(*) from public.rfqs where requester_user_id = %L', v_i)], 'count', '0'),
      ('X04 sin plan no elimina un archivado sin solicitudes (sigue existiendo)', 'authenticated', v_i::text, 'aal1', array[revoke_i],
         array[format('delete from public.projects where id = %L', p_i_arch_free), 'reset role',
               format('select count(*) from public.projects where id = %L', p_i_arch_free)], 'count', '1'),
      ('X05 sin plan no edita su proyecto', 'authenticated', v_i::text, 'aal1', array[revoke_i],
         array[format('update public.projects set name = name || %L where id = %L', ' (P3)', p_i_act)], 'rows', 'ok rows=0'),
      ('X06 sin plan no crea un moodboard en su proyecto (efecto de D3)', 'authenticated', v_i::text, 'aal1', array[revoke_i],
         array[format('insert into public.moodboards (project_id) values (%L)', p_i_act)], 'exec', '42501'),
      -- ========== Y · Individual habilitado: sin cambios ==========
      ('X07 Individual lee sus proyectos', 'authenticated', v_i::text, 'aal1', null,
         array[format('select count(*) from public.projects where owner_user_id = %L', v_i)], 'count', n_i_proj::text),
      ('X08 Individual lee sus líneas', 'authenticated', v_i::text, 'aal1', null,
         array['select count(*) from public.project_products'], 'count', n_i_lines::text),
      ('X09 Individual lee su historial de solicitudes', 'authenticated', v_i::text, 'aal1', null,
         array[format('select count(*) from public.rfqs where requester_user_id = %L', v_i)], 'count', n_i_rfqs::text),
      ('X10 Individual elimina un archivado sin solicitudes', 'authenticated', v_i::text, 'aal1', null,
         array[format('delete from public.projects where id = %L', p_i_arch_free), 'reset role',
               format('select count(*) from public.projects where id = %L', p_i_arch_free)], 'count', '0'),
      ('X11 Individual crea un segundo proyecto activo', 'authenticated', v_i::text, 'aal1', null,
         array[format(ins_proj, v_i, 'P3 Individual 2', 'null')], 'rows', 'ok rows=1'),
      ('X12 Individual crea un moodboard en su proyecto', 'authenticated', v_i::text, 'aal1', null,
         array[format('insert into public.moodboards (project_id) values (%L)', p_i_act)], 'rows', 'ok rows=1'),
      -- ========== Z · otros roles ==========
      (x13_name, 'authenticated', v_s::text, 'aal1', null,
         array['select count(*) from public.projects'], 'count', x13_exp),
      ('X14 Mobau con aal2 no lee proyectos', 'authenticated', v_m::text, 'aal2', null,
         array['select count(*) from public.projects'], 'count', '0'),
      ('X15 sin sesión no lee proyectos', 'anon', null, null, null,
         array['select count(*) from public.projects'], 'count', '0'),
      ('X16 29 políticas en proyectos, líneas y solicitudes; las 4 de D3 RESTRICTIVE', '-', null, null, null,
         array['select count(*) from pg_policies where schemaname = ''public'' and tablename in (''projects'', ''project_products'', ''rfqs'')'
               || ' and (policyname not in (''projects_plan_select'', ''projects_plan_delete'', ''project_products_plan_select'', ''rfqs_plan_select'') or permissive = ''RESTRICTIVE'')'],
         'count', '29'),
      -- ========== N · D4: nombre y apellidos (perfil de e2a655c1) ==========
      ('N01 nombre y apellidos calculan professional_name', 'authenticated', v_i::text, 'aal1', null,
         array[format(upd_pp, 'first_name = ''Ana'', last_name = ''Rosario''', v_i), 'reset role', format(sel_name, v_i)], 'text', 'Ana Rosario'),
      ('N02 se recortan y se unifican los espacios', 'authenticated', v_i::text, 'aal1', null,
         array[format(upd_pp, 'first_name = ''  Ana   María '', last_name = '' Rosario  Pérez ''', v_i), 'reset role', format(sel_name, v_i)], 'text', 'Ana María Rosario Pérez'),
      ('N03 solo el nombre, sin apellidos → 23514', 'authenticated', v_i::text, 'aal1', null,
         array[format(upd_pp, 'first_name = ''Ana''', v_i)], 'exec', '23514'),
      ('N04 con partes, professional_name no se puede contradecir', 'authenticated', v_i::text, 'aal1', null,
         array[format(upd_pp, 'first_name = ''Ana'', last_name = ''Rosario''', v_i),
               format(upd_pp, 'professional_name = ''Otro nombre''', v_i), 'reset role', format(sel_name, v_i)], 'text', 'Ana Rosario'),
      ('N05 con partes, no pueden volver a quedar vacías → 23514', 'authenticated', v_i::text, 'aal1', null,
         array[format(upd_pp, 'first_name = ''Ana'', last_name = ''Rosario''', v_i),
               format(upd_pp, 'first_name = null, last_name = null', v_i)], 'exec', '23514'),
      ('N06 perfil anterior: cambiar el teléfono conserva el nombre', 'authenticated', v_i::text, 'aal1', null,
         array[format(upd_pp, 'phone = phone', v_i), 'reset role', format(sel_name, v_i)], 'text', name_i),
      ('N07 perfil anterior: professional_name sigue siendo editable sin partes', 'authenticated', v_i::text, 'aal1', null,
         array[format(upd_pp, 'professional_name = professional_name', v_i)], 'rows', 'ok rows=1'),
      ('N08 nombre de 61 caracteres → 23514', 'authenticated', v_i::text, 'aal1', null,
         array[format(upd_pp, format('first_name = %L, last_name = %L', long61, 'Rosario'), v_i)], 'exec', '23514'),
      ('N09 nadie cambia el perfil de otra cuenta', 'authenticated', v_s::text, 'aal1', null,
         array[format(upd_pp, 'first_name = ''X'', last_name = ''Y''', v_i)], 'rows', 'ok rows=0'),
      ('N10 ningún perfil existente se ha dividido', '-', null, null, null,
         array['select count(*) from public.professional_profiles where first_name is not null or last_name is not null'], 'count', '0'),
      ('N11 ningún nombre existente ha cambiado con D4', '-', null, null, null,
         array['select (coalesce((select md5(string_agg(user_id::text || '':'' || professional_name, ''|'' order by user_id)) from public.professional_profiles), ''-'') = current_setting(''mobau.p3_nombres0''))::text'],
         'text', 'true'),
      ('N12 la función del trigger no es ejecutable por clientes', '-', null, null, null,
         array['select (has_function_privilege(''authenticated'', ''public.professional_profiles_sync_name()'', ''EXECUTE'')'
               || ' or has_function_privilege(''anon'', ''public.professional_profiles_sync_name()'', ''EXECUTE''))::text'], 'text', 'false'),
      -- ========== Z · fuera de los casos ==========
      ('Z01 sin restos: datos idénticos', '-', null, null, null,
         array[format('select count(*) where (%s) = %L', data_fp, data0)], 'count', '1')
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

  raise exception 'MOBAU_43_P3_SUITE total=% ok=% fallos=% :: %', n_total, n_ok, n_total - n_ok, r::text
    using errcode = 'MB999';
end $P3S$;
$SUI$;
  t_rd4 text := $RD4B$
DO $$
begin
  if current_user <> 'postgres' then
    raise exception '43-RD4: ejecutar como postgres';
  end if;
  if (select count(*) from information_schema.columns where table_schema = 'public' and table_name = 'professional_profiles'
      and column_name in ('first_name', 'last_name')) <> 2
     or to_regprocedure('public.professional_profiles_sync_name()') is null then
    raise exception '43-RD4: D4 no está aplicada';
  end if;
  perform set_config('mobau.rd4_nombres',
    coalesce((select md5(string_agg(user_id::text || ':' || professional_name, '|' order by user_id)) from public.professional_profiles), '-'),
    true);
end $$;

drop trigger trg_professional_profiles_sync_name on public.professional_profiles;
drop function public.professional_profiles_sync_name();
alter table public.professional_profiles drop constraint professional_profiles_name_parts_check;
alter table public.professional_profiles drop column first_name, drop column last_name;

DO $$
begin
  if exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'professional_profiles'
             and column_name in ('first_name', 'last_name'))
     or to_regprocedure('public.professional_profiles_sync_name()') is not null then
    raise exception '43-RD4: quedan objetos de D4';
  end if;
  if coalesce((select md5(string_agg(user_id::text || ':' || professional_name, '|' order by user_id)) from public.professional_profiles), '-')
     <> current_setting('mobau.rd4_nombres') then
    raise exception '43-RD4: ha cambiado algún nombre visible';
  end if;
end $$;
$RD4B$;
  t_rd3 text := $RD3B$
DO $$
begin
  if current_user <> 'postgres' then
    raise exception '43-RD3: ejecutar como postgres';
  end if;
  if (select count(*) from pg_policies where schemaname = 'public' and policyname in
      ('projects_plan_select', 'projects_plan_delete', 'project_products_plan_select', 'rfqs_plan_select')) <> 4 then
    raise exception '43-RD3: D3 no está aplicada (faltan políticas)';
  end if;
end $$;

drop policy projects_plan_select on public.projects;
drop policy projects_plan_delete on public.projects;
drop policy project_products_plan_select on public.project_products;
drop policy rfqs_plan_select on public.rfqs;

DO $$
begin
  if (select count(*) from pg_policies where schemaname = 'public' and tablename in ('projects', 'project_products', 'rfqs')) <> 25 then
    raise exception '43-RD3: no quedaron las 25 políticas de T4';
  end if;
end $$;
$RD3B$;
  h0 text; h1 text; h2 text; res text := 'la suite no devolvió resultado';
begin
  if md5(t_d3) <> 'ccaa8d3dd4429fe4e6c59c78e472708b' or md5(t_d4) <> 'dfa573bc1d4fc898254e17400aff42e1' or md5(t_suite) <> '5a0b963fb2275fe7343db5573417e284'
     or md5(t_rd4) <> 'dc0ebc3083712b09d13728539cf2234e' or md5(t_rd3) <> 'b6251d8675681e56cc5b5d95d60be817' then
    raise exception 'MOBAU_43_P3: algún texto incrustado no coincide con su MD5' using errcode = 'MB997';
  end if;
  if not exists (select 1 from supabase_migrations.schema_migrations where version = '20261020120100')
     or exists (select 1 from supabase_migrations.schema_migrations where version in ('20261020130000', '20261020130100'))
     or exists (select 1 from pg_policies where policyname = 'projects_plan_select')
     or exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'professional_profiles' and column_name = 'first_name') then
    raise exception 'MOBAU_43_P3: estado de partida inesperado (T4 debe estar registrada; D3 y D4 sin aplicar)' using errcode = 'MB998';
  end if;

  h0 := md5(
      coalesce((select string_agg(tablename || policyname || permissive || cmd || roles::text || coalesce(qual, '') || coalesce(with_check, ''), '|' order by tablename, policyname)
                from pg_policies where schemaname = 'public'), '')
   || coalesce((select string_agg(p.oid::regprocedure::text || md5(p.prosrc) || coalesce(p.proacl::text, ''), '|' order by p.oid::regprocedure::text)
                from pg_proc p where p.pronamespace = 'public'::regnamespace), '')
   || coalesce((select string_agg(table_name || '.' || column_name || ':' || data_type || ':' || coalesce(column_default, ''), '|' order by table_name, ordinal_position)
                from information_schema.columns where table_schema = 'public'), '')
   || coalesce((select string_agg(conrelid::regclass::text || conname || pg_get_constraintdef(oid), '|' order by conrelid::regclass::text, conname)
                from pg_constraint where connamespace = 'public'::regnamespace), '')
   || coalesce((select string_agg(tgrelid::regclass::text || tgname, '|' order by tgrelid::regclass::text, tgname)
                from pg_trigger where not tgisinternal and tgrelid in (select oid from pg_class where relnamespace = 'public'::regnamespace)), '')
   || coalesce((select string_agg(relname || coalesce(relacl::text, ''), '|' order by relname)
                from pg_class where relnamespace = 'public'::regnamespace and relkind = 'r'), '')
   || coalesce((select string_agg(id::text || status || owner_user_id::text || name || updated_at::text, '|' order by id) from public.projects), '')
   || coalesce((select string_agg(id::text || quantity::text || coalesce(unit, '-'), '|' order by id) from public.project_products), '')
   || coalesce((select string_agg(id::text || status, '|' order by id) from public.rfqs), '')
   || coalesce((select string_agg(id::text || plan || role || plan_source || subscription_status, '|' order by id) from public.profiles), '')
   || coalesce((select string_agg(user_id::text || professional_name || coalesce(phone, '-') || updated_at::text, '|' order by user_id) from public.professional_profiles), '')
   || (select count(*)::text from public.moodboards)
   || (select count(*)::text || max(version) from supabase_migrations.schema_migrations));
  perform set_config('mobau.p3_nombres0',
    coalesce((select md5(string_agg(user_id::text || ':' || professional_name, '|' order by user_id)) from public.professional_profiles), '-'), true);

  execute t_d3;
  execute t_d4;
  h1 := md5(
      coalesce((select string_agg(tablename || policyname || permissive || cmd || roles::text || coalesce(qual, '') || coalesce(with_check, ''), '|' order by tablename, policyname)
                from pg_policies where schemaname = 'public'), '')
   || coalesce((select string_agg(p.oid::regprocedure::text || md5(p.prosrc) || coalesce(p.proacl::text, ''), '|' order by p.oid::regprocedure::text)
                from pg_proc p where p.pronamespace = 'public'::regnamespace), '')
   || coalesce((select string_agg(table_name || '.' || column_name || ':' || data_type || ':' || coalesce(column_default, ''), '|' order by table_name, ordinal_position)
                from information_schema.columns where table_schema = 'public'), '')
   || coalesce((select string_agg(conrelid::regclass::text || conname || pg_get_constraintdef(oid), '|' order by conrelid::regclass::text, conname)
                from pg_constraint where connamespace = 'public'::regnamespace), '')
   || coalesce((select string_agg(tgrelid::regclass::text || tgname, '|' order by tgrelid::regclass::text, tgname)
                from pg_trigger where not tgisinternal and tgrelid in (select oid from pg_class where relnamespace = 'public'::regnamespace)), '')
   || coalesce((select string_agg(relname || coalesce(relacl::text, ''), '|' order by relname)
                from pg_class where relnamespace = 'public'::regnamespace and relkind = 'r'), '')
   || coalesce((select string_agg(id::text || status || owner_user_id::text || name || updated_at::text, '|' order by id) from public.projects), '')
   || coalesce((select string_agg(id::text || quantity::text || coalesce(unit, '-'), '|' order by id) from public.project_products), '')
   || coalesce((select string_agg(id::text || status, '|' order by id) from public.rfqs), '')
   || coalesce((select string_agg(id::text || plan || role || plan_source || subscription_status, '|' order by id) from public.profiles), '')
   || coalesce((select string_agg(user_id::text || professional_name || coalesce(phone, '-') || updated_at::text, '|' order by user_id) from public.professional_profiles), '')
   || (select count(*)::text from public.moodboards)
   || (select count(*)::text || max(version) from supabase_migrations.schema_migrations));

  begin
    execute t_suite;
  exception when sqlstate 'MB999' then
    res := sqlerrm;
  end;

  execute t_rd4;
  execute t_rd3;
  h2 := md5(
      coalesce((select string_agg(tablename || policyname || permissive || cmd || roles::text || coalesce(qual, '') || coalesce(with_check, ''), '|' order by tablename, policyname)
                from pg_policies where schemaname = 'public'), '')
   || coalesce((select string_agg(p.oid::regprocedure::text || md5(p.prosrc) || coalesce(p.proacl::text, ''), '|' order by p.oid::regprocedure::text)
                from pg_proc p where p.pronamespace = 'public'::regnamespace), '')
   || coalesce((select string_agg(table_name || '.' || column_name || ':' || data_type || ':' || coalesce(column_default, ''), '|' order by table_name, ordinal_position)
                from information_schema.columns where table_schema = 'public'), '')
   || coalesce((select string_agg(conrelid::regclass::text || conname || pg_get_constraintdef(oid), '|' order by conrelid::regclass::text, conname)
                from pg_constraint where connamespace = 'public'::regnamespace), '')
   || coalesce((select string_agg(tgrelid::regclass::text || tgname, '|' order by tgrelid::regclass::text, tgname)
                from pg_trigger where not tgisinternal and tgrelid in (select oid from pg_class where relnamespace = 'public'::regnamespace)), '')
   || coalesce((select string_agg(relname || coalesce(relacl::text, ''), '|' order by relname)
                from pg_class where relnamespace = 'public'::regnamespace and relkind = 'r'), '')
   || coalesce((select string_agg(id::text || status || owner_user_id::text || name || updated_at::text, '|' order by id) from public.projects), '')
   || coalesce((select string_agg(id::text || quantity::text || coalesce(unit, '-'), '|' order by id) from public.project_products), '')
   || coalesce((select string_agg(id::text || status, '|' order by id) from public.rfqs), '')
   || coalesce((select string_agg(id::text || plan || role || plan_source || subscription_status, '|' order by id) from public.profiles), '')
   || coalesce((select string_agg(user_id::text || professional_name || coalesce(phone, '-') || updated_at::text, '|' order by user_id) from public.professional_profiles), '')
   || (select count(*)::text from public.moodboards)
   || (select count(*)::text || max(version) from supabase_migrations.schema_migrations));

  raise exception 'MOBAU_43_P3 cambia=% identico=% :: %', (h1 <> h0), (h2 = h0), res using errcode = 'MB990';
end $P3$;

COMMIT;
