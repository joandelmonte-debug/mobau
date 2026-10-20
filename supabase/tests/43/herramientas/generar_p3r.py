"""Genera el ensayo revertido P3-R de la recuperación conservadora de D4 (R-D4C)
y su lectura de antes y después.

P3-R: en una sola transacción que SIEMPRE termina con MB990 (nada persiste),
cuatro casos, cada uno en su subtransacción revertida (MB001):
  R01 R-D4C se detiene si D4 no está aplicada;
  R02 D4 -> R-D4C sin perfiles separados: copia vacía y correcta;
  R03 D4 -> dos perfiles separados -> R-D4C: copia exacta, nombres conservados;
  R04 D4 -> la copia ya existe -> R-D4C se detiene sin tocar nada.
Al final compara la huella (public + mobau_private) con la de partida.

Los textos de D4 y R-D4C se incrustan con su MD5 (MB997 si no coinciden).
No modifica generar_p3.py ni regenera P3b ni P3-M.
Uso: python3 generar_p3r.py <carpeta servidor>
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

d4 = body(read("20261020130100_43_d4_nombre_apellidos.sql"))
rd4c = body(read("43_d4_recuperacion_conserva.sql"))

# Huella de P3b (public) más los objetos y permisos de mobau_private.
HUELLA = """md5(
      coalesce((select string_agg(tablename || policyname || permissive || cmd || roles::text || coalesce(qual, '') || coalesce(with_check, ''), '|' order by tablename, policyname)
                from pg_policies where schemaname in ('public', 'mobau_private')), '')
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
   || coalesce((select string_agg(relname || relkind::text || coalesce(relacl::text, ''), '|' order by relname)
                from pg_class where relnamespace = 'mobau_private'::regnamespace), '')
   || coalesce((select string_agg(id::text || status || owner_user_id::text || name || updated_at::text, '|' order by id) from public.projects), '')
   || coalesce((select string_agg(id::text || quantity::text || coalesce(unit, '-'), '|' order by id) from public.project_products), '')
   || coalesce((select string_agg(id::text || status, '|' order by id) from public.rfqs), '')
   || coalesce((select string_agg(id::text || plan || role || plan_source || subscription_status, '|' order by id) from public.profiles), '')
   || coalesce((select string_agg(user_id::text || professional_name || coalesce(phone, '-') || updated_at::text, '|' order by user_id) from public.professional_profiles), '')
   || (select count(*)::text from public.moodboards)
   || (select count(*)::text || max(version) from supabase_migrations.schema_migrations))"""

NOMBRES = """coalesce((select md5(string_agg(user_id::text || ':' || professional_name, '|' order by user_id)) from public.professional_profiles), '-')"""

# Comprobaciones comunes después de un R-D4C correcto (R02 y R03).
TRAS_RD4C = """
      if exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'professional_profiles'
                 and column_name in ('first_name', 'last_name')) then v_det := v_det || ' · quedan columnas'; end if;
      if to_regprocedure('public.professional_profiles_sync_name()') is not null then v_det := v_det || ' · queda la función'; end if;
      if exists (select 1 from pg_constraint where conname = 'professional_profiles_name_parts_check') then v_det := v_det || ' · queda la restricción'; end if;
      if exists (select 1 from pg_trigger where tgname = 'trg_professional_profiles_sync_name') then v_det := v_det || ' · queda el trigger'; end if;
      if to_regclass('mobau_private.professional_name_parts_backup') is null then v_det := v_det || ' · no hay copia'; end if;
      if not (select relrowsecurity from pg_class where oid = 'mobau_private.professional_name_parts_backup'::regclass) then v_det := v_det || ' · copia sin RLS'; end if;
      if exists (select 1 from pg_policies where schemaname = 'mobau_private' and tablename = 'professional_name_parts_backup') then v_det := v_det || ' · copia con políticas'; end if;
      if exists (select 1 from unnest(array['anon', 'authenticated']) r,
                               unnest(array['SELECT', 'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER']) p
                 where has_table_privilege(r, 'mobau_private.professional_name_parts_backup', p)) then v_det := v_det || ' · permisos de cliente'; end if;
      foreach v_rol in array array['anon', 'authenticated'] loop
        begin
          execute format('set local role %I', v_rol);
          perform 1 from mobau_private.professional_name_parts_backup;
          raise exception using errcode = 'MB002';
        exception
          when sqlstate 'MB002' then v_det := v_det || ' · ' || v_rol || ' lee la copia';
          when insufficient_privilege then null;
          when others then v_det := v_det || ' · ' || v_rol || ' ' || sqlstate;
        end;
      end loop;
      if current_user <> 'postgres' then v_det := v_det || ' · el rol no volvió a postgres'; end if;
      if """ + NOMBRES + """ <> v_nombres then v_det := v_det || ' · cambió algún nombre visible'; end if;"""

p3r = f"""-- ============================================================
-- PROPUESTA NO EJECUTADA (43 · CC1 · ensayo P3-R de la recuperación conservadora de D4, revertido) — no ejecutar sin aprobación explícita
-- ============================================================
-- Generado por herramientas/generar_p3r.py. En una sola transacción que
-- SIEMPRE termina con MB990 (nada persiste). Parte de D4 sin aplicar ni
-- registrar y de la copia inexistente. Cuatro casos, cada uno revertido:
--   R01 R-D4C se detiene si D4 no está aplicada;
--   R02 D4 -> R-D4C sin ningún perfil separado: copia vacía y correcta;
--   R03 D4 -> dos perfiles separados -> R-D4C: copia exacta de nombre y
--       apellidos, professional_name conservado, sin permisos de cliente;
--   R04 D4 -> la copia ya existe -> R-D4C se detiene y no cambia nada.
-- Éxito: «P3R total=4 ok=4 fallos=0 identico=true».
-- Ejecutar completo, con el control MD5 del archivo.
-- ============================================================

BEGIN;

DO $P3R$
declare
  t_d4 text := {quoted('D4B', d4)};
  t_rd4c text := {quoted('RD4CB', rd4c)};
  h0 text; h1 text;
  v_res jsonb := '[]'::jsonb; n_total int := 0; n_ok int := 0;
  v_det text; v_err text; v_nombres text; v_partes text; v_copia text; v_rol text;
  u uuid[];
begin
  if md5(t_d4) <> '{md5(d4)}' or md5(t_rd4c) <> '{md5(rd4c)}' then
    raise exception 'MOBAU_43_P3R: algún texto incrustado no coincide con su MD5' using errcode = 'MB997';
  end if;
  if current_user <> 'postgres'
     or not exists (select 1 from supabase_migrations.schema_migrations where version = '20261020120100')
     or exists (select 1 from supabase_migrations.schema_migrations where version = '20261020130100')
     or exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'professional_profiles'
                and column_name in ('first_name', 'last_name'))
     or to_regprocedure('public.professional_profiles_sync_name()') is not null
     or to_regclass('mobau_private.professional_name_parts_backup') is not null
     or (select count(*) from public.professional_profiles) < 2 then
    raise exception 'MOBAU_43_P3R: estado de partida inesperado (D4 sin aplicar ni registrar, sin copia, al menos 2 perfiles)' using errcode = 'MB998';
  end if;

  h0 := {HUELLA};
  select array_agg(user_id order by user_id) into u from public.professional_profiles;

  -- R01 · sin D4, R-D4C se detiene.
  v_det := ''; v_err := null;
  begin
    begin
      execute t_rd4c;
      v_det := ' · R-D4C continuó sin D4';
    exception when others then v_err := sqlerrm;
    end;
    if v_err is distinct from '43-RD4C: D4 no está aplicada' then v_det := v_det || ' · error: ' || coalesce(v_err, '-'); end if;
    if to_regclass('mobau_private.professional_name_parts_backup') is not null then v_det := v_det || ' · creó la copia'; end if;
    raise exception using errcode = 'MB001';
  exception
    when sqlstate 'MB001' then null;
    when others then v_det := v_det || ' · ' || sqlstate || ' ' || left(sqlerrm, 200);
  end;
  n_total := n_total + 1; if v_det = '' then n_ok := n_ok + 1; end if;
  v_res := v_res || jsonb_build_object('caso', 'R01 sin D4, R-D4C se detiene', 'ok', v_det = '', 'detalle', v_det);

  -- R02 · ningún perfil separado.
  v_det := '';
  begin
    execute t_d4;
    v_nombres := {NOMBRES};
    execute t_rd4c;
    if (select count(*) from mobau_private.professional_name_parts_backup) <> 0 then v_det := v_det || ' · la copia no está vacía'; end if;{TRAS_RD4C}
    raise exception using errcode = 'MB001';
  exception
    when sqlstate 'MB001' then null;
    when others then v_det := v_det || ' · ' || sqlstate || ' ' || left(sqlerrm, 200);
  end;
  n_total := n_total + 1; if v_det = '' then n_ok := n_ok + 1; end if;
  v_res := v_res || jsonb_build_object('caso', 'R02 sin perfiles separados', 'ok', v_det = '', 'detalle', v_det);

  -- R03 · dos perfiles separados (el trigger de D4 normaliza los espacios).
  v_det := '';
  begin
    execute t_d4;
    execute format('update public.professional_profiles set first_name = %L, last_name = %L where user_id = %L', '  José   Ángel ', 'Pérez D''Oleo', u[1]);
    execute format('update public.professional_profiles set first_name = %L, last_name = %L where user_id = %L', 'Ensayo', 'P3R Apellidos', u[2]);
    execute 'select string_agg(user_id::text || ''|'' || first_name || ''|'' || last_name || ''|'' || professional_name, ''#'' order by user_id)
               from public.professional_profiles where first_name is not null' into v_partes;
    if v_partes is distinct from u[1]::text || '|José Ángel|Pérez D''Oleo|José Ángel Pérez D''Oleo#' || u[2]::text || '|Ensayo|P3R Apellidos|Ensayo P3R Apellidos' then
      v_det := v_det || ' · separación inesperada: ' || coalesce(v_partes, '-');
    end if;
    v_nombres := {NOMBRES};
    execute t_rd4c;
    select string_agg(user_id::text || '|' || first_name || '|' || last_name || '|' || professional_name, '#' order by user_id) into v_copia
      from mobau_private.professional_name_parts_backup;
    if v_copia is distinct from v_partes then v_det := v_det || ' · la copia no es exacta: ' || coalesce(v_copia, '-'); end if;
    if (select professional_name from public.professional_profiles where user_id = u[1]) is distinct from 'José Ángel Pérez D''Oleo' then
      v_det := v_det || ' · professional_name no conservado';
    end if;{TRAS_RD4C}
    raise exception using errcode = 'MB001';
  exception
    when sqlstate 'MB001' then null;
    when others then v_det := v_det || ' · ' || sqlstate || ' ' || left(sqlerrm, 200);
  end;
  n_total := n_total + 1; if v_det = '' then n_ok := n_ok + 1; end if;
  v_res := v_res || jsonb_build_object('caso', 'R03 dos perfiles separados, copia exacta', 'ok', v_det = '', 'detalle', v_det);

  -- R04 · la copia ya existe: R-D4C se detiene y no cambia nada.
  v_det := ''; v_err := null;
  begin
    execute t_d4;
    create table mobau_private.professional_name_parts_backup (user_id uuid primary key, nota text);
    insert into mobau_private.professional_name_parts_backup values ('00000000-0000-0000-0000-000000000003'::uuid, 'P3R previa');
    v_nombres := {NOMBRES};
    begin
      execute t_rd4c;
      v_det := ' · R-D4C continuó con la copia existente';
    exception when others then v_err := sqlerrm;
    end;
    if v_err is distinct from '43-RD4C: ya existe la copia de nombres y apellidos; revísala antes de continuar' then
      v_det := v_det || ' · error: ' || coalesce(v_err, '-');
    end if;
    if (select count(*) from information_schema.columns where table_schema = 'public' and table_name = 'professional_profiles'
        and column_name in ('first_name', 'last_name')) <> 2
       or not exists (select 1 from pg_trigger where tgname = 'trg_professional_profiles_sync_name') then
      v_det := v_det || ' · D4 ya no está completa';
    end if;
    if (select string_agg(column_name, ',' order by ordinal_position) from information_schema.columns
        where table_schema = 'mobau_private' and table_name = 'professional_name_parts_backup') <> 'user_id,nota'
       or (select string_agg(nota, ',') from mobau_private.professional_name_parts_backup) is distinct from 'P3R previa' then
      v_det := v_det || ' · cambió la copia existente';
    end if;
    if {NOMBRES} <> v_nombres then v_det := v_det || ' · cambió algún nombre visible'; end if;
    raise exception using errcode = 'MB001';
  exception
    when sqlstate 'MB001' then null;
    when others then v_det := v_det || ' · ' || sqlstate || ' ' || left(sqlerrm, 200);
  end;
  n_total := n_total + 1; if v_det = '' then n_ok := n_ok + 1; end if;
  v_res := v_res || jsonb_build_object('caso', 'R04 la copia ya existe, se detiene', 'ok', v_det = '', 'detalle', v_det);

  h1 := {HUELLA};

  raise exception 'MOBAU_43_P3R total=% ok=% fallos=% identico=% :: %', n_total, n_ok, n_total - n_ok,
    (h1 = h0 and to_regclass('mobau_private.professional_name_parts_backup') is null), v_res::text
    using errcode = 'MB990';
end $P3R$;

COMMIT;
"""

lectura = f"""-- 43 · CC1 · lectura de antes y después de P3-R (solo SELECT). No escribe nada.
-- Las dos lecturas deben coincidir en todas las filas.
select 'migraciones (número / última)' k, (select count(*)::text || ' / ' || max(version) from supabase_migrations.schema_migrations) v
union all select 'D4 registrada', (select count(*)::text from supabase_migrations.schema_migrations where version = '20261020130100')
union all select 'objetos de D4 (columnas / función / restricción / trigger)',
  (select count(*)::text from information_schema.columns where table_schema = 'public' and table_name = 'professional_profiles' and column_name in ('first_name', 'last_name'))
  || ' / ' || (to_regprocedure('public.professional_profiles_sync_name()') is not null)::text
  || ' / ' || (select count(*)::text from pg_constraint where conname = 'professional_profiles_name_parts_check')
  || ' / ' || (select count(*)::text from pg_trigger where tgname = 'trg_professional_profiles_sync_name')
union all select 'copia de nombres existe', (to_regclass('mobau_private.professional_name_parts_backup') is not null)::text
union all select 'mobau_private (objetos y permisos)', md5(coalesce((select string_agg(relname || relkind::text || coalesce(relacl::text, ''), '|' order by relname)
                   from pg_class where relnamespace = 'mobau_private'::regnamespace), ''))
union all select 'perfiles profesionales (filas / huella)', (select count(*)::text from public.professional_profiles) || ' / '
  || md5(coalesce((select string_agg(user_id::text || professional_name || coalesce(phone, '-') || updated_at::text, '|' order by user_id) from public.professional_profiles), ''))
union all select 'restos de P3-R', (select count(*)::text from public.professional_profiles where professional_name like '%P3R%' or professional_name like 'Ensayo %')
union all select 'huella completa (public + mobau_private)', {HUELLA};
"""

for name, text in [("P3R_ensayo_rd4c.sql", p3r), ("P3R_lectura.sql", lectura)]:
    (srv / name).write_bytes(text.encode())

for f in sorted(srv.glob("*.sql")):
    print(hashlib.md5(f.read_bytes()).hexdigest(), f.name)
