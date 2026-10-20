"""Genera el ensayo revertido de SEG-01 (O2 + O4) y su lectura de antes y después.

SEG01_ensayo.sql: en una sola transacción que SIEMPRE termina con MB990:
  1. huella semántica de partida y sondas de la web (base);
  2. aplica SEG-01 -> huella y sondas (tras) y prueba de objetos nuevos;
  3. aplica la recuperación -> huella y sondas (rec) y prueba de objetos nuevos.
Las sondas reproducen lo que hace la web (sin sesión, Individual y Gratis) y
deben dar lo mismo en las tres fases; solo TRUNCATE cambia (ok -> 42501 -> ok).
Uso: python3 generar_seg01.py <carpeta seguridad>
"""
from pathlib import Path
import hashlib, sys

d = Path(sys.argv[1])

def body(text):
    b = text.index("\nBEGIN;\n") + len("\nBEGIN;\n")
    e = text.index("\nCOMMIT;\n")
    return text[b:e]

def md5(s):
    return hashlib.md5(s.encode()).hexdigest()

def quoted(tag, s):
    assert f"${tag}$" not in s, tag
    return f"${tag}${s}${tag}$"

mig = body((d / "20261020180000_seg_01_privilegios.sql").read_bytes().decode())
rec = body((d / "seg_01_recuperacion.sql").read_bytes().decode())

PRIVS = "array['SELECT', 'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER', 'MAINTAIN']"

# Huella semántica: privilegios efectivos (no el texto de las ACL), privilegios
# por defecto y de funciones desglosados, políticas, datos y migraciones.
HUELLA = f"""md5(
      coalesce((select string_agg(c.relname || ':' || r || ':' || coalesce((select string_agg(p, ',' order by p) from unnest({PRIVS}) p where has_table_privilege(r, c.oid, p)), '-'), '|' order by c.relname, r)
                from pg_class c, unnest(array['anon', 'authenticated', 'service_role']) r
               where c.relnamespace = 'public'::regnamespace and c.relkind in ('r', 'v', 'm', 'p')), '')
   || coalesce((select string_agg(a.attname || ':' || r || ':' || has_column_privilege(r, 'public.project_products'::regclass, a.attname, 'UPDATE')::text, '|' order by a.attname, r)
                from pg_attribute a, unnest(array['anon', 'authenticated']) r
               where a.attrelid = 'public.project_products'::regclass and a.attnum > 0 and not a.attisdropped), '')
   || coalesce((select string_agg(d.defaclrole::regrole::text || ':' || d.defaclnamespace::text || ':' || d.defaclobjtype::text || ':'
                       || coalesce((select string_agg(x.grantee::text || '=' || x.privilege_type, ',' order by x.grantee, x.privilege_type) from aclexplode(d.defaclacl) x), ''), '|'
                       order by d.defaclrole::regrole::text, d.defaclnamespace, d.defaclobjtype::text)
                from pg_default_acl d), '')
   || coalesce((select string_agg(f.oid::regprocedure::text || ':' || coalesce((select string_agg(x.grantee::text || '=' || x.privilege_type, ',' order by x.grantee, x.privilege_type) from aclexplode(f.proacl) x), 'por-defecto'), '|' order by f.oid::regprocedure::text)
                from pg_proc f where f.pronamespace = 'public'::regnamespace), '')
   || coalesce((select string_agg(tablename || policyname || permissive || cmd || roles::text || coalesce(qual, '') || coalesce(with_check, ''), '|' order by tablename, policyname)
                from pg_policies where schemaname = 'public'), '')
   || coalesce((select string_agg(id::text || status || owner_user_id::text || name || updated_at::text, '|' order by id) from public.projects), '')
   || coalesce((select string_agg(id::text || quantity::text || coalesce(unit, '-'), '|' order by id) from public.project_products), '')
   || coalesce((select string_agg(id::text || status, '|' order by id) from public.rfqs), '')
   || coalesce((select string_agg(id::text || plan || role || plan_source || subscription_status, '|' order by id) from public.profiles), '')
   || (select count(*)::text || max(version) from supabase_migrations.schema_migrations))"""

# Sondas: (código, rol, sujeto, sentencias, tipo). Sujeto: None, 'ind' o 'gra'.
SONDAS = [
    ("P01", "anon", None, ["select count(*) from public.categories"], "count"),
    ("P02", "anon", None, ["select count(*) from public.plans"], "count"),
    ("P03", "anon", None, ["select count(*) from public.catalog_products"], "count"),
    ("P04", "anon", None, ["select count(*) from public.projects"], "count"),
    ("P05", "anon", None, ["select count(*) from public.professional_profiles"], "count"),
    ("P06", "authenticated", "ind", ["select count(*) from public.projects"], "count"),
    ("P07", "authenticated", "ind", ["select count(*) from public.project_products"], "count"),
    ("P08", "authenticated", "ind", ["select count(*) from public.rfqs"], "count"),
    ("P09", "authenticated", "ind", ["select count(*) from public.professional_profiles"], "count"),
    ("P10", "authenticated", "ind", ["select count(*) from public.plans"], "count"),
    ("P11", "authenticated", "ind", ["select count(*) from public.categories"], "count"),
    ("P12", "authenticated", "ind", ["format('update public.projects set name = name where id = %L', v_proj)"], "rows"),
    ("P13", "authenticated", "ind", [
        "format('insert into public.project_products (project_id, product_id, quantity, unit) values (%L, %L, 1, %L)', v_proj, v_prod, 'ud.')",
        "format('update public.project_products set quantity = 2 where project_id = %L and product_id = %L', v_proj, v_prod)",
        "format('delete from public.project_products where project_id = %L and product_id = %L', v_proj, v_prod)"], "seq"),
    ("P14", "authenticated", "ind", ["format('update public.professional_profiles set phone = phone where user_id = %L', v_ind)"], "rows"),
    ("P15", "authenticated", "gra", ["select count(*) from public.projects"], "count"),
    ("P16", "authenticated", "gra", ["select count(*) from public.project_products"], "count"),
    ("T01", "anon", None, ["truncate public.rfq_distributors"], "exec"),
    ("T02", "authenticated", "ind", ["truncate public.rfq_distributors"], "exec"),
    # LOCK TABLE: PostgreSQL lo permite en cualquier modo con MAINTAIN, UPDATE, DELETE o TRUNCATE.
    # L01 y L02: el rol solo conserva SELECT (y REFERENCES/TRIGGER), así que deja de poder bloquear.
    # L03 y L04: el rol conserva UPDATE o DELETE, así que sigue pudiendo (informativo).
    ("L01", "anon", None, ["lock table public.distributors in access exclusive mode"], "exec"),
    ("L02", "authenticated", "ind", ["lock table public.product_prices in access exclusive mode"], "exec"),
    ("L03", "authenticated", "ind", ["lock table public.moodboards in access exclusive mode"], "exec"),
    ("L04", "anon", None, ["lock table public.projects in access exclusive mode"], "exec"),
]

def sql_expr(s):
    return s if s.startswith("format(") else "'" + s.replace("'", "''") + "'"

def sondas(var):
    out = [f"  {var} := '';"]
    for code, role, sub, stmts, kind in SONDAS:
        subj = {"ind": "v_ind::text", "gra": "v_gra::text", None: "null::text"}[sub]
        lines = [f"  v_got := null; v_seq := '';",
                 "  begin",
                 "    execute 'set local lock_timeout = ''2s''';",
                 f"    execute format('set local role %I', '{role}');",
                 f"    perform set_config('request.jwt.claim.sub', coalesce({subj}, ''), true);",
                 f"    perform set_config('request.jwt.claims', case when {subj} is null then '' else json_build_object('sub', {subj}, 'role', '{role}', 'aal', 'aal1')::text end, true);"]
        for i, s in enumerate(stmts):
            e = sql_expr(s)
            last = i == len(stmts) - 1
            if kind == "count" and last:
                lines.append(f"    execute {e} into v_n; v_got := v_n::text;")
            elif kind == "rows" and last:
                lines.append(f"    execute {e}; get diagnostics v_n = row_count; v_got := 'rows=' || v_n;")
            elif kind == "seq":
                lines.append(f"    execute {e}; get diagnostics v_n = row_count; v_seq := v_seq || v_n::text || '/';")
                if last:
                    lines.append("    v_got := v_seq;")
            elif kind == "exec" and last:
                lines.append(f"    execute {e}; v_got := 'ok';")
            else:
                lines.append(f"    execute {e};")
        lines += ["    raise exception using errcode = 'MB001';",
                  "  exception",
                  "    when sqlstate 'MB001' then null;",
                  "    when others then v_got := sqlstate;",
                  "  end;",
                  f"  {var} := {var} || '{code}=' || coalesce(v_got, '-') || '|';"]
        out += lines
    return "\n".join(out)

def nuevos(var):
    return f"""  {var} := null;
  begin
    create table public.zz_seg01_prueba (id int);
    create function public.zz_seg01_fn() returns int language sql as 'select 1';
    {var} := 'tabla anon=' || coalesce((select string_agg(p, ',' order by p) from unnest({PRIVS}) p where has_table_privilege('anon', 'public.zz_seg01_prueba', p)), '-')
          || ' auth=' || coalesce((select string_agg(p, ',' order by p) from unnest({PRIVS}) p where has_table_privilege('authenticated', 'public.zz_seg01_prueba', p)), '-')
          || ' service=' || coalesce((select count(*)::text from unnest({PRIVS}) p where has_table_privilege('service_role', 'public.zz_seg01_prueba', p)), '-')
          || ' · funcion anon=' || has_function_privilege('anon', 'public.zz_seg01_fn()', 'EXECUTE')::text
          || ' auth=' || has_function_privilege('authenticated', 'public.zz_seg01_fn()', 'EXECUTE')::text
          || ' service=' || has_function_privilege('service_role', 'public.zz_seg01_fn()', 'EXECUTE')::text;
    raise exception using errcode = 'MB001';
  exception
    when sqlstate 'MB001' then null;
    when others then {var} := 'error ' || sqlstate || ' ' || left(sqlerrm, 120);
  end;"""

ESPERADO_TRAS = "tabla anon=DELETE,INSERT,SELECT,UPDATE auth=DELETE,INSERT,SELECT,UPDATE service=8 · funcion anon=false auth=false service=true"
ESPERADO_REC = "tabla anon=DELETE,INSERT,MAINTAIN,REFERENCES,SELECT,TRIGGER,TRUNCATE,UPDATE auth=DELETE,INSERT,MAINTAIN,REFERENCES,SELECT,TRIGGER,TRUNCATE,UPDATE service=8 · funcion anon=true auth=true service=true"

ensayo = f"""-- ============================================================
-- PROPUESTA NO EJECUTADA (SEG-01 · ensayo revertido de O2 + O4 y su recuperación) — no ejecutar sin aprobación explícita
-- ============================================================
-- Generado por generar_seg01.py. En una sola transacción que SIEMPRE termina
-- con MB990 (nada persiste):
--   1. huella de partida y 22 sondas (web, TRUNCATE y LOCK TABLE) (base);
--   2. SEG-01 -> huella, sondas (tras), MAINTAIN y prueba de tabla y función nuevas;
--   3. recuperación -> huella, sondas (rec) y la misma prueba.
-- Éxito: «SEG01E cambia=true identico=true web_igual=true truncate=true
--         sin_maintain=true lock=true nuevos_cerrados=true nuevos_recuperados=true».
-- Ejecutar completo, con el control MD5.
-- ============================================================

BEGIN;

DO $S01E$
declare
  t_m text := {quoted('MB', mig)};
  t_r text := {quoted('RB', rec)};
  h0 text; h1 text; h2 text;
  v_ind uuid; v_gra uuid := '46ea4397-f881-4db8-89e7-f164293a1143'; v_proj uuid; v_prod text;
  v_got text; v_seq text; v_n bigint;
  s_base text; s_tras text; s_rec text; n_tras text; n_rec text;
  w_base text; w_tras text; w_rec text; v_sin_m boolean;
begin
  if md5(t_m) <> '{md5(mig)}' or md5(t_r) <> '{md5(rec)}' then
    raise exception 'MOBAU_SEG01E: algún texto incrustado no coincide con su MD5' using errcode = 'MB997';
  end if;
  select id into v_ind from public.profiles where id::text like 'e2a655c1%' and plan = 'individual_founder' and plan_source = 'manual_pilot';
  select id into v_proj from public.projects where owner_user_id = v_ind and status = 'active' order by created_at limit 1;
  select p.id into v_prod from public.products p
   where p.publication_status = 'published' and not exists (select 1 from public.project_products pp where pp.project_id = v_proj and pp.product_id = p.id)
   order by p.id limit 1;
  if current_user <> 'postgres' or v_ind is null or v_proj is null or v_prod is null
     or not exists (select 1 from public.profiles where id = v_gra and plan = 'free_trial')
     or exists (select 1 from supabase_migrations.schema_migrations where version = '20261020180000')
     or not has_table_privilege('anon', 'public.projects', 'TRUNCATE')
     or exists (select 1 from pg_default_acl where defaclrole = 'postgres'::regrole and defaclnamespace = 0)
     or to_regclass('public.zz_seg01_prueba') is not null or to_regprocedure('public.zz_seg01_fn()') is not null then
    raise exception 'MOBAU_SEG01E: estado de partida inesperado' using errcode = 'MB998';
  end if;

  h0 := {HUELLA};
{sondas('s_base')}

  execute t_m;
  h1 := {HUELLA};
  v_sin_m := not exists (select 1 from pg_class c, unnest(array['anon', 'authenticated']) r2
                          where c.relnamespace = 'public'::regnamespace and c.relkind in ('r', 'v', 'm', 'p') and has_table_privilege(r2, c.oid, 'MAINTAIN'));
{sondas('s_tras')}
{nuevos('n_tras')}

  execute t_r;
  h2 := {HUELLA};
{sondas('s_rec')}
{nuevos('n_rec')}

  -- La web no cambia: todas las sondas salvo TRUNCATE (T01, T02) y LOCK (L01–L04) dan lo mismo en las tres fases.
  w_base := regexp_replace(s_base, '[TL]0[1-4]=[^|]*\\|', '', 'g');
  w_tras := regexp_replace(s_tras, '[TL]0[1-4]=[^|]*\\|', '', 'g');
  w_rec := regexp_replace(s_rec, '[TL]0[1-4]=[^|]*\\|', '', 'g');

  raise exception 'MOBAU_SEG01E cambia=% identico=% web_igual=% truncate=% sin_maintain=% lock=% nuevos_cerrados=% nuevos_recuperados=% :: base=% · tras=% · rec=% · nuevos_tras=% · nuevos_rec=%',
    (h1 <> h0), (h2 = h0), (w_base = w_tras and w_tras = w_rec),
    (s_base ~ 'T01=ok\\|T02=ok\\|' and s_tras ~ 'T01=42501\\|T02=42501\\|' and s_rec ~ 'T01=ok\\|T02=ok\\|'),
    v_sin_m,
    (s_base ~ 'L01=ok\\|L02=ok\\|L03=ok\\|L04=ok\\|' and s_tras ~ 'L01=42501\\|L02=42501\\|L03=ok\\|L04=ok\\|' and s_rec ~ 'L01=ok\\|L02=ok\\|L03=ok\\|L04=ok\\|'),
    (n_tras = '{ESPERADO_TRAS}'), (n_rec = '{ESPERADO_REC}'),
    s_base, s_tras, s_rec, n_tras, n_rec
    using errcode = 'MB990';
end $S01E$;

COMMIT;
"""

lectura = f"""-- SEG-01 · lectura de privilegios (solo SELECT). Antes y después del ensayo,
-- de la aplicación y ante cualquier respuesta ambigua. No escribe nada.
select 'migraciones' k, (select count(*)::text || ' / ' || max(version) from supabase_migrations.schema_migrations) v
union all select 'SEG-01 registrada', (select count(*)::text from supabase_migrations.schema_migrations where version = '20261020180000')
union all select 'privilegios en las 8 tablas (anon | authenticated)', (select string_agg(c.relname || ' ' ||
      coalesce((select string_agg(left(p, 2), '' order by p) from unnest({PRIVS}) p where has_table_privilege('anon', c.oid, p)), '-') || ' | ' ||
      coalesce((select string_agg(left(p, 2), '' order by p) from unnest({PRIVS}) p where has_table_privilege('authenticated', c.oid, p)), '-'), ' ; ' order by c.relname)
   from pg_class c where c.oid in ('public.categories'::regclass, 'public.plans'::regclass, 'public.professional_profiles'::regclass, 'public.projects'::regclass,
                                   'public.project_products'::regclass, 'public.rfqs'::regclass, 'public.rfq_distributors'::regclass, 'public.studios'::regclass))
union all select 'tablas con TRUNCATE para anon o authenticated', coalesce((select string_agg(c.relname, ', ' order by c.relname) from pg_class c
   where c.relnamespace = 'public'::regnamespace and c.relkind = 'r' and (has_table_privilege('anon', c.oid, 'TRUNCATE') or has_table_privilege('authenticated', c.oid, 'TRUNCATE'))), 'ninguna')
union all select 'tablas con MAINTAIN (anon | authenticated)', coalesce((select string_agg(c.relname, ',' order by c.relname) from pg_class c
   where c.relnamespace = 'public'::regnamespace and c.relkind in ('r', 'v', 'm', 'p') and has_table_privilege('anon', c.oid, 'MAINTAIN')), 'ninguna') || ' | ' ||
   coalesce((select string_agg(c.relname, ',' order by c.relname) from pg_class c
   where c.relnamespace = 'public'::regnamespace and c.relkind in ('r', 'v', 'm', 'p') and has_table_privilege('authenticated', c.oid, 'MAINTAIN')), 'ninguna')
union all select 'privilegios por defecto de postgres', coalesce((select string_agg(coalesce(n.nspname, '(global)') || '/' || d.defaclobjtype::text || ': '
      || coalesce((select string_agg(case when x.grantee = 0 then 'PUBLIC' else x.grantee::regrole::text end || '=' || x.privilege_type, ',' order by x.grantee, x.privilege_type) from aclexplode(d.defaclacl) x), ''), ' ; ' order by n.nspname nulls first, d.defaclobjtype::text)
   from pg_default_acl d left join pg_namespace n on n.oid = d.defaclnamespace where d.defaclrole = 'postgres'::regrole), 'ninguno')
union all select 'funciones SECURITY DEFINER ejecutables por anon', (select count(*)::text from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prosecdef and has_function_privilege('anon', p.oid, 'EXECUTE'))
union all select 'restos del ensayo', (to_regclass('public.zz_seg01_prueba') is not null)::text || ' / ' || (to_regprocedure('public.zz_seg01_fn()') is not null)::text
union all select 'huella semántica completa', {HUELLA};
"""

for name, text in [("SEG01_ensayo.sql", ensayo), ("seg_01_lectura.sql", lectura)]:
    (d / name).write_bytes(text.encode())

for f in sorted(d.glob("*")):
    print(hashlib.md5(f.read_bytes()).hexdigest(), f.name)
