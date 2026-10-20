-- ============================================================
-- PROPUESTA NO EJECUTADA (43 · CC1 · ensayo P3-M de permisos de moodboards, revertido) — no ejecutar sin aprobación explícita
-- ============================================================
-- Generado por herramientas/generar_p3.py. En una sola transacción que
-- SIEMPRE termina con MB990: aplica D5, prueba los permisos, aplica R-D5 y
-- comprueba que los privilegios efectivos vuelven a los de partida.
-- Éxito: «P3M total=8 ok=8 fallos=0 identico=true».
-- Ejecutar completo, con el control MD5 del archivo.
-- ============================================================

BEGIN;

DO $P3M$
declare
  t_d5 text := $D5B$
DO $$
begin
  if current_user <> 'postgres' then
    raise exception '43-D5: ejecutar como postgres';
  end if;
  if (select relacl::text from pg_class where oid = 'public.moodboards'::regclass)
     <> '{postgres=arwdDxtm/postgres,anon=arwdDxtm/postgres,authenticated=arwdDxtm/postgres,service_role=arwdDxtm/postgres}' then
    raise exception '43-D5: los permisos de partida de moodboards no son los leídos';
  end if;
end $$;

revoke all on table public.moodboards from anon;
revoke delete, truncate, references, trigger on table public.moodboards from authenticated;

DO $$
declare
  p text;
begin
  foreach p in array array['SELECT', 'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER'] loop
    if has_table_privilege('anon', 'public.moodboards', p) then
      raise exception '43-D5: anon conserva %', p;
    end if;
    if has_table_privilege('authenticated', 'public.moodboards', p) <> (p in ('SELECT', 'INSERT', 'UPDATE')) then
      raise exception '43-D5: authenticated no tiene exactamente SELECT, INSERT y UPDATE (falla en %)', p;
    end if;
    if not has_table_privilege('service_role', 'public.moodboards', p) then
      raise exception '43-D5: service_role ha perdido %', p;
    end if;
  end loop;
end $$;
$D5B$;
  t_rd5 text := $RD5B$
DO $$
begin
  if current_user <> 'postgres' then
    raise exception '43-RD5: ejecutar como postgres';
  end if;
  if has_table_privilege('anon', 'public.moodboards', 'SELECT')
     or has_table_privilege('authenticated', 'public.moodboards', 'TRUNCATE') then
    raise exception '43-RD5: D5 no está aplicada';
  end if;
end $$;

grant all on table public.moodboards to anon;
grant delete, truncate, references, trigger on table public.moodboards to authenticated;

DO $$
declare
  p text;
begin
  -- Se comparan privilegios efectivos, no el texto del ACL (el orden de las
  -- entradas puede variar al volver a concederlas).
  foreach p in array array['SELECT', 'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER'] loop
    if not has_table_privilege('anon', 'public.moodboards', p)
       or not has_table_privilege('authenticated', 'public.moodboards', p)
       or not has_table_privilege('service_role', 'public.moodboards', p) then
      raise exception '43-RD5: falta % tras la recuperación', p;
    end if;
  end loop;
end $$;
$RD5B$;
  v_i uuid; p_act uuid := '3e533da7-1083-4295-a1de-15bfe6673bf3';
  priv0 text; priv1 text;
  r jsonb := '[]'::jsonb; t record; i int; v_got text; v_n bigint; v_ok boolean; v_stmt text;
  n_total int := 0; n_ok int := 0;
begin
  if md5(t_d5) <> '812353480e8756b4e298f66942d16779' or md5(t_rd5) <> '56c5905b9c8bab750fe42115fd12399c' then
    raise exception 'MOBAU_43_P3M: algún texto incrustado no coincide con su MD5' using errcode = 'MB997';
  end if;
  select id into v_i from public.profiles where id::text like 'e2a655c1%';
  if v_i is null or (select status from public.projects where id = p_act) <> 'active'
     or not exists (select 1 from public.profiles where id = v_i and plan_source = 'manual_pilot') then
    raise exception 'MOBAU_43_P3M: estado de partida inesperado' using errcode = 'MB998';
  end if;

  select string_agg(r2 || ':' || p || '=' || has_table_privilege(r2, 'public.moodboards', p)::text, '|' order by r2, p) into priv0
    from unnest(array['anon', 'authenticated', 'service_role']) r2,
         unnest(array['SELECT', 'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER']) p;

  execute t_d5;

  for t in
    select * from (values
      ('M01 sin sesión no lee moodboards', 'anon', null::text, array['select count(*) from public.moodboards'], 'exec', '42501'),
      ('M02 sin sesión no inserta', 'anon', null, array[format('insert into public.moodboards (project_id) values (%L)', p_act)], 'exec', '42501'),
      ('M03 con sesión no vacía la tabla (TRUNCATE)', 'authenticated', v_i::text, array['truncate public.moodboards'], 'exec', '42501'),
      ('M04 con sesión no borra (DELETE)', 'authenticated', v_i::text, array['delete from public.moodboards'], 'exec', '42501'),
      ('M05 Individual crea un moodboard en su proyecto', 'authenticated', v_i::text,
         array[format('insert into public.moodboards (project_id) values (%L)', p_act)], 'rows', 'ok rows=1'),
      ('M06 Individual lee su moodboard', 'authenticated', v_i::text,
         array[format('insert into public.moodboards (project_id) values (%L)', p_act), 'select count(*) from public.moodboards'], 'count', '1'),
      ('M07 Individual edita su moodboard', 'authenticated', v_i::text,
         array[format('insert into public.moodboards (project_id) values (%L)', p_act), 'update public.moodboards set title = ''P3M'''], 'rows', 'ok rows=1'),
      ('M08 service_role conserva todos los privilegios', '-', null,
         array['select bool_and(has_table_privilege(''service_role'', ''public.moodboards'', p))::text from unnest(array[''SELECT'', ''INSERT'', ''UPDATE'', ''DELETE'', ''TRUNCATE'', ''REFERENCES'', ''TRIGGER'']) p'],
         'text', 'true')
    ) as c(name, role, sub, sql, kind, expect)
  loop
    v_got := null;
    begin
      if t.role <> '-' then execute format('set local role %I', t.role); end if;
      perform set_config('request.jwt.claim.sub', coalesce(t.sub, ''), true);
      perform set_config('request.jwt.claims',
        case when t.sub is null then '' else json_build_object('sub', t.sub, 'role', t.role, 'aal', 'aal1')::text end, true);
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
      when others then v_got := sqlstate || ' ' || left(sqlerrm, 160);
    end;
    v_ok := case when t.kind = 'exec' then left(v_got, 6) = t.expect || ' ' else v_got = t.expect end;
    n_total := n_total + 1;
    if v_ok then n_ok := n_ok + 1; end if;
    r := r || jsonb_build_object('prueba', t.name, 'esperado', t.expect, 'obtenido', v_got, 'ok', coalesce(v_ok, false));
  end loop;

  execute t_rd5;

  select string_agg(r2 || ':' || p || '=' || has_table_privilege(r2, 'public.moodboards', p)::text, '|' order by r2, p) into priv1
    from unnest(array['anon', 'authenticated', 'service_role']) r2,
         unnest(array['SELECT', 'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER']) p;

  raise exception 'MOBAU_43_P3M total=% ok=% fallos=% identico=% :: %', n_total, n_ok, n_total - n_ok, (priv1 = priv0), r::text
    using errcode = 'MB990';
end $P3M$;

COMMIT;
