#!/usr/bin/env python3
"""Genera el ensayo P2 (T1 + T4 + suite + R4 + R1, todo revertido) y la
prueba de concurrencia P2-C a partir de los archivos de servidor/. Cada
texto incrustado se comprueba en el servidor por md5 antes de ejecutarse."""
import hashlib, pathlib, re

d = pathlib.Path(__file__).resolve().parent.parent / "servidor"
rd = lambda n: (d / n).read_bytes().decode("utf-8")
md5 = lambda s: hashlib.md5(s.encode("utf-8")).hexdigest()

T1 = rd("20261020120000_43_d1_preparacion.sql")
T4 = rd("20261020120100_43_d2_activacion.sql")
SX = rd("P2-S_suite_43.sql")
R4 = rd("43_d2_recuperacion.sql")
R1 = rd("43_d1_recuperacion.sql")
TAGS = ["$P2W$", "$P2A$", "$P2B$", "$P2C$", "$P2D$", "$P2E$"]
for name, txt in (("T1", T1), ("T4", T4), ("SX", SX), ("R4", R4), ("R1", R1)):
    assert "\r" not in txt, f"{name} contiene CR"
    for tag in TAGS:
        assert tag not in txt, f"{name} contiene {tag}"
for name, txt in (("T1", T1), ("T4", T4), ("R4", R4), ("R1", R1)):
    assert txt.count("\nBEGIN;\n") == 1 and txt.count("\nCOMMIT;\n") == 1, f"{name}: delimitadores"

N_CASES = len(re.findall(r"^      \('[A-Z][0-9]{2} ", SX, re.M))

BEH = ("pg_catalog.md5("
       "(select md5(prosrc) || proacl::text from pg_proc where oid = 'public.catalog_published_prices(text[], text, integer)'::regprocedure)"
       " || (select md5(prosrc) || proacl::text from pg_proc where oid = 'public.enforce_active_project_limit()'::regprocedure)"
       " || coalesce((select string_agg(tablename || policyname || permissive || cmd || roles::text || coalesce(qual, '') || coalesce(with_check, ''), '|' order by tablename, policyname)"
       "     from pg_policies where schemaname = 'public' and tablename in ('projects', 'project_products', 'rfqs')), '')"
       " || (select string_agg(id || ':' || max_active_projects || ':' || max_users, '|' order by id) from public.plans)"
       " || (select string_agg(tgname || pg_get_triggerdef(oid), '|' order by tgname) from pg_trigger where tgrelid = 'public.projects'::regclass and not tgisinternal))")
FULL = ("pg_catalog.md5(" + BEH +
        " || (select json_agg(p order by p.id)::text from public.plans p)"
        " || (select string_agg(table_name || '.' || column_name || ':' || data_type || ':' || coalesce(column_default, ''), '|' order by table_name, ordinal_position)"
        "     from information_schema.columns where table_schema = 'public' and table_name in ('plans', 'profiles'))"
        " || coalesce((select string_agg(n.nspname || '.' || p.proname || md5(p.prosrc) || coalesce(p.proacl::text, ''), '|' order by n.nspname, p.proname)"
        "     from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname in ('public', 'mobau_private')), '')"
        " || (select count(*)::text from pg_policies where schemaname in ('public', 'mobau_private'))"
        " || coalesce(to_regclass('mobau_private.plan_events')::text, 'sin-plan_events')"
        " || md5(coalesce((select string_agg(id::text || status || coalesce(studio_id::text, '-') || owner_user_id::text || name || updated_at::text, '|' order by id) from public.projects), '')"
        "     || coalesce((select string_agg(id::text || quantity::text || coalesce(unit, '-') || selected_for_rfq::text, '|' order by id) from public.project_products), '')"
        "     || coalesce((select string_agg(id::text || status, '|' order by id) from public.rfqs), '')"
        "     || coalesce((select string_agg(id::text || plan || role || subscription_status, '|' order by id) from public.profiles), '')"
        "     || coalesce((select string_agg(id::text, '|' order by id) from public.studios), '')))")

ensayo = f"""-- ============================================================
-- PROPUESTA NO EJECUTADA (43 · ensayo P2) — no ejecutar sin aprobación explícita
-- ============================================================
-- Ensayo transaccional de 43-D en producción, TODO REVERTIDO:
--   1. huellas de partida (comportamiento y completa);
--   2. T1 (preparación) → la huella de comportamiento debe ser idéntica (T1 inerte);
--   3. T4 (activación) → suite P2-S (matriz de acceso, {N_CASES} casos);
--   4. inversa de T4 (R4) → la huella de comportamiento vuelve a la de T1;
--   5. inversa de T1 (R1) → la huella completa vuelve a la de partida.
-- Termina SIEMPRE con MB990 (o con el error que lo interrumpa) y ROLLBACK:
-- no persiste nada. Efectos no transaccionales: avanzan secuencias
-- (plan_events_id_seq se crea y desaparece; projects y rfqs usan uuid) y
-- contadores de pg_stat.
-- md5: T1={md5(T1)} T4={md5(T4)} suite={md5(SX)} R4={md5(R4)} R1={md5(R1)}
-- ============================================================

BEGIN;

DO $P2W$
declare
  t1 text := $P2A${T1}$P2A$;
  t4 text := $P2B${T4}$P2B$;
  sx text := $P2C${SX}$P2C$;
  r4 text := $P2D${R4}$P2D$;
  r1 text := $P2E${R1}$P2E$;
  fp_a text; beh_a text; beh_t1 text; beh_t4 text; beh_r4 text; fp_b text; suite_msg text;
  b int; e int; v text;
begin
  if md5(t1) <> '{md5(T1)}' or md5(t4) <> '{md5(T4)}' or md5(sx) <> '{md5(SX)}'
     or md5(r4) <> '{md5(R4)}' or md5(r1) <> '{md5(R1)}' then
    raise exception 'MB997: algún texto recibido no coincide con su archivo' using errcode = 'MB997';
  end if;

  execute 'select ' || $q${FULL}$q$ into fp_a;
  execute 'select ' || $q${BEH}$q$ into beh_a;

  foreach v in array array[t1] loop
    b := strpos(v, E'\\nBEGIN;\\n'); e := strpos(v, E'\\nCOMMIT;\\n');
    execute substr(v, b + 8, e - (b + 8));
  end loop;
  execute 'select ' || $q${BEH}$q$ into beh_t1;

  b := strpos(t4, E'\\nBEGIN;\\n'); e := strpos(t4, E'\\nCOMMIT;\\n');
  execute substr(t4, b + 8, e - (b + 8));
  execute 'select ' || $q${BEH}$q$ into beh_t4;

  begin
    execute sx;
    suite_msg := 'la suite terminó sin MB999 (anómalo)';
  exception
    when sqlstate 'MB999' then suite_msg := sqlerrm;
    when others then suite_msg := 'SUITE INTERRUMPIDA ' || sqlstate || ': ' || sqlerrm;
  end;

  b := strpos(r4, E'\\nBEGIN;\\n'); e := strpos(r4, E'\\nCOMMIT;\\n');
  execute substr(r4, b + 8, e - (b + 8));
  execute 'select ' || $q${BEH}$q$ into beh_r4;

  b := strpos(r1, E'\\nBEGIN;\\n'); e := strpos(r1, E'\\nCOMMIT;\\n');
  execute substr(r1, b + 8, e - (b + 8));
  execute 'select ' || $q${FULL}$q$ into fp_b;

  raise exception 'MOBAU_43_P2 t1_inerte=% t4_cambia=% r4_vuelve_a_t1=% final_identico=% huella_partida=% huella_final=% :: %',
    (beh_t1 = beh_a), (beh_t4 <> beh_t1), (beh_r4 = beh_t1), (fp_b = fp_a), fp_a, fp_b, suite_msg
    using errcode = 'MB990';
end $P2W$;

ROLLBACK;
"""

conc = """-- ============================================================
-- PROPUESTA NO EJECUTADA (43 · P2-C concurrencia R1, protocolo) — no ejecutar sin aprobación explícita
-- ============================================================
-- Se lanzan DOS ejecuciones simultáneas de este mismo texto. Cada una toma,
-- como hará el trigger de T4, el bloqueo FOR UPDATE de la fila del perfil
-- de la cuenta Individual de prueba (e2a655c1), cuenta sus proyectos
-- activos, espera 5 s y termina con MB990 (rollback): no escribe nada.
-- Éxito: la que llega segunda obtiene el bloqueo después del «fin» de la
-- primera (espera ≈ 5 s). Aquí no se puede usar el trigger real: T4 no está
-- aplicada y aplicarla en dos transacciones a la vez las serializaría por
-- los bloqueos de la DDL. La comprobación con el trigger real queda para
-- después de aplicar T4 (C2-R1), también revertida.
-- ============================================================

DO $P2CC$
declare
  v_i uuid; t0 timestamptz; t_lock timestamptz; t_end timestamptz; n int; lim int;
begin
  select id into v_i from public.profiles where id::text like 'e2a655c1%';
  if v_i is null then
    raise exception 'MB998: no está la cuenta de prueba' using errcode = 'MB998';
  end if;
  t0 := clock_timestamp();
  select pl.max_active_projects into lim
    from public.profiles pr join public.plans pl on pl.id = pr.plan
   where pr.id = v_i
     for update of pr;
  t_lock := clock_timestamp();
  select count(*) into n from public.projects where owner_user_id = v_i and studio_id is null and status = 'active';
  perform pg_sleep(5);
  t_end := clock_timestamp();
  raise exception 'MOBAU_43_P2C pid=% inicio=% bloqueo=% fin=% espera_ms=% activos=% limite=%',
    pg_backend_pid(), t0, t_lock, t_end, round(extract(epoch from (t_lock - t0)) * 1000), n, lim
    using errcode = 'MB990';
end $P2CC$;
"""


lectura = """-- 43 · lectura de estado (solo SELECT). Antes y después de P2, de cada
-- aplicación y ante cualquier respuesta ambigua. Usa las mismas huellas que
-- el ensayo P2 (comportamiento y completa).
select 'huella_comportamiento' k, """ + BEH + """ v
union all select 'huella_completa', """ + FULL + """
union all select 'migraciones', (select count(*)::text || ' / ' || max(version) from supabase_migrations.schema_migrations)
union all select 'planes', (select string_agg(id || ':' || name || ':' || max_active_projects || ':' || max_users || ':' || coalesce(trial_days::text, 'null'), ' | ' order by id) from public.plans)
union all select 'objetos T1', coalesce(to_regprocedure('public.my_professional_access()')::text, 'sin función') || ' / ' || coalesce(to_regclass('mobau_private.plan_events')::text, 'sin plan_events')
union all select 'políticas projects/lines/rfqs', (select count(*)::text from pg_policies where schemaname = 'public' and tablename in ('projects', 'project_products', 'rfqs'))
union all select 'catalog_published_prices md5', (select md5(prosrc) from pg_proc where oid = 'public.catalog_published_prices(text[], text, integer)'::regprocedure)
union all select 'enforce_active_project_limit md5', (select md5(prosrc) from pg_proc where oid = 'public.enforce_active_project_limit()'::regprocedure)
union all select 'cuentas de prueba', (select string_agg(left(id::text, 8) || ':' || role || ':' || plan, ' | ' order by id::text) from public.profiles
                                        where left(id::text, 8) in ('e2a655c1', '743270cd', '5b4f13c8', '392a9eb4', 'a8fe42e8'))
union all select 'proyectos/líneas/solicitudes', (select count(*)::text from public.projects) || ' / ' || (select count(*)::text from public.project_products) || ' / ' || (select count(*)::text from public.rfqs)
union all select 'estudios', (select count(*)::text from public.studios);
"""
(d / "43_lectura.sql").write_bytes(lectura.encode("utf-8"))

(d / "P2_ensayo_43.sql").write_bytes(ensayo.encode("utf-8"))
(d / "P2-C_concurrencia_43.sql").write_bytes(conc.encode("utf-8"))
for n in ("20261020120000_43_d1_preparacion.sql", "20261020120100_43_d2_activacion.sql", "P2-S_suite_43.sql",
          "43_d2_recuperacion.sql", "43_d1_recuperacion.sql", "P2_ensayo_43.sql", "P2-C_concurrencia_43.sql", "43_lectura.sql"):
    data = (d / n).read_bytes()
    print(f"{n}\tmd5={hashlib.md5(data).hexdigest()}\tsha256={hashlib.sha256(data).hexdigest()}\tbytes={len(data)}")
