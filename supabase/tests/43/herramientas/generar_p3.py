"""Genera los ensayos revertidos de CC1 a partir de los archivos de servidor.

P3b : D3 (opción B; la A está descartada) + D4 -> suite P3-S -> R-D4 + R-D3 -> huella final = huella de partida -> MB990.
P3-M: D5 -> pruebas de permisos de moodboards -> R-D5 -> privilegios = los de partida -> MB990.

Cada texto incrustado lleva su MD5: si no coincide, el ensayo se detiene (MB997)
antes de aplicar nada. Uso: python3 generar_p3.py <carpeta servidor>
"""
from pathlib import Path
import hashlib, sys

srv = Path(sys.argv[1])

def read(name):
    return (srv / name).read_bytes().decode()

def body(text):
    b = text.index("\nBEGIN;\n") + len("\nBEGIN;\n")
    e = text.index("\nCOMMIT;\n")
    return text[b:e]

def md5(s):
    return hashlib.md5(s.encode()).hexdigest()

def quoted(tag, s):
    assert f"${tag}$" not in s, tag
    return f"${tag}${s}${tag}$"

d3_b = body(read("20261020130000_43_d3_gratis_sin_proyectos_opcion_b.sql"))
d4 = body(read("20261020130100_43_d4_nombre_apellidos.sql"))
rd3 = body(read("43_d3_recuperacion.sql"))
rd4 = body(read("43_d4_recuperacion.sql"))
suite = read("P3-S_suite_cc1.sql")
suite = suite[suite.index("DO $P3S$"):]
d5 = body(read("20261020130200_43_d5_moodboards_permisos.sql"))
rd5 = body(read("43_d5_recuperacion.sql"))

HUELLA = """md5(
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
   || (select count(*)::text || max(version) from supabase_migrations.schema_migrations))"""

def build_p3(d3, variante):
  return f"""-- ============================================================
-- PROPUESTA NO EJECUTADA (43 · CC1 · ensayo P3, opción {variante} de D3, revertido) — no ejecutar sin aprobación explícita
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
  t_d3 text := {quoted('D3B', d3)};
  t_d4 text := {quoted('D4B', d4)};
  t_suite text := {quoted('SUI', suite)};
  t_rd4 text := {quoted('RD4B', rd4)};
  t_rd3 text := {quoted('RD3B', rd3)};
  h0 text; h1 text; h2 text; res text := 'la suite no devolvió resultado';
begin
  if md5(t_d3) <> '{md5(d3)}' or md5(t_d4) <> '{md5(d4)}' or md5(t_suite) <> '{md5(suite)}'
     or md5(t_rd4) <> '{md5(rd4)}' or md5(t_rd3) <> '{md5(rd3)}' then
    raise exception 'MOBAU_43_P3: algún texto incrustado no coincide con su MD5' using errcode = 'MB997';
  end if;
  if not exists (select 1 from supabase_migrations.schema_migrations where version = '20261020120100')
     or exists (select 1 from supabase_migrations.schema_migrations where version in ('20261020130000', '20261020130100'))
     or exists (select 1 from pg_policies where policyname = 'projects_plan_select')
     or exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'professional_profiles' and column_name = 'first_name') then
    raise exception 'MOBAU_43_P3: estado de partida inesperado (T4 debe estar registrada; D3 y D4 sin aplicar)' using errcode = 'MB998';
  end if;

  h0 := {HUELLA};
  perform set_config('mobau.p3_nombres0',
    coalesce((select md5(string_agg(user_id::text || ':' || professional_name, '|' order by user_id)) from public.professional_profiles), '-'), true);

  execute t_d3;
  execute t_d4;
  h1 := {HUELLA};

  begin
    execute t_suite;
  exception when sqlstate 'MB999' then
    res := sqlerrm;
  end;

  execute t_rd4;
  execute t_rd3;
  h2 := {HUELLA};

  raise exception 'MOBAU_43_P3 cambia=% identico=% :: %', (h1 <> h0), (h2 = h0), res using errcode = 'MB990';
end $P3$;

COMMIT;
"""

p3b = build_p3(d3_b, "B")

p3m = f"""-- ============================================================
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
  t_d5 text := {quoted('D5B', d5)};
  t_rd5 text := {quoted('RD5B', rd5)};
  v_i uuid; p_act uuid := '3e533da7-1083-4295-a1de-15bfe6673bf3';
  priv0 text; priv1 text;
  r jsonb := '[]'::jsonb; t record; i int; v_got text; v_n bigint; v_ok boolean; v_stmt text;
  n_total int := 0; n_ok int := 0;
begin
  if md5(t_d5) <> '{md5(d5)}' or md5(t_rd5) <> '{md5(rd5)}' then
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
"""

for name, text in [("P3b_ensayo_cc1.sql", p3b), ("P3M_ensayo_moodboards.sql", p3m)]:
    (srv / name).write_bytes(text.encode())

for f in sorted(srv.glob("*.sql")):
    print(hashlib.md5(f.read_bytes()).hexdigest(), f.name)
