"""Genera C2 (suite sobre el servidor con T3 y T4) a partir de la suite P2, con reemplazos exactos y comprobados."""
from pathlib import Path
import hashlib, sys
base = Path(sys.argv[1]); out = Path(sys.argv[2])
s = base.read_text()

def rep(old, new, n=1):
    global s
    c = s.count(old)
    assert c == n, (old[:70], c, n)
    s = s.replace(old, new)

body_start = s.index("DO $P2S$")
s = s[body_start:]
header = """-- ============================================================
-- PROPUESTA NO EJECUTADA (43 · C2 suite sobre el servidor actualizado) — no ejecutar sin aprobación explícita
-- ============================================================
-- C2: la matriz de acceso de 43-D sobre el servidor REAL después de T3 y T4.
-- Derivada de P2-S_suite_43.sql (53 casos, superada en P2) con estos cambios:
--   * condiciones de partida: T4 aplicada (planes 1/2/20, 25 políticas) y T3
--     hecha (solo e2a655c1 con manual_pilot; 1 evento en plan_events);
--   * e2a655c1 ya está habilitada de verdad: los casos de Individual (A06,
--     A13, B02, D01–D08, E01–E03) ya no simulan la habilitación;
--   * los casos de Gratis que usan los proyectos de e2a655c1 (C11–C13)
--     retiran su habilitación DENTRO del caso (revertido);
--   * casos nuevos: A14 y B10 (habilitación retirada), H01 (límites) y
--     H02 (políticas de T4);
--   * Z01 comprueba que quedan exactamente la habilitación y el evento de T3.
-- Rol postgres; JWT simulado. Cada caso es una subtransacción que se deshace
-- (MB001). Termina SIEMPRE con MB990 (todo revertido) y el resultado en el
-- mensaje. Sin escrituras persistentes. Ejecutar completo, con el control MD5.
-- ============================================================

BEGIN;

"""
footer = "\nCOMMIT;\n"

rep("DO $P2S$", "DO $C2$")
rep("end $P2S$;", "end $C2$;")
rep("MOBAU_43_P2_SUITE: faltan actores", "MOBAU_43_C2: faltan actores")
rep("""  if to_regprocedure('public.my_professional_access()') is null
     or not exists (select 1 from pg_policies where policyname = 'projects_plan_insert') then
    raise exception 'MOBAU_43_P2_SUITE: T1 y T4 no están aplicadas' using errcode = 'MB998';
  end if;
  if exists (select 1 from public.studios) or exists (select 1 from public.profiles where plan_source <> 'default')
     or exists (select 1 from mobau_private.plan_events) then
    raise exception 'MOBAU_43_P2_SUITE: hay estudios, habilitaciones o eventos de partida inesperados' using errcode = 'MB998';
  end if;""",
"""  if to_regprocedure('public.my_professional_access()') is null
     or not exists (select 1 from pg_policies where policyname = 'projects_plan_insert')
     or (select string_agg(id || ':' || max_active_projects, '|' order by id) from public.plans) <> 'free_trial:1|individual_founder:2|studio_founder:20'
     or (select count(*) from pg_policies where schemaname = 'public' and tablename in ('projects', 'project_products', 'rfqs')) <> 25
     or not exists (select 1 from supabase_migrations.schema_migrations where version = '20261020120100') then
    raise exception 'MOBAU_43_C2: T4 no está aplicada y registrada' using errcode = 'MB998';
  end if;
  if exists (select 1 from public.studios)
     or (select count(*) from public.profiles where plan_source <> 'default') <> 1
     or not exists (select 1 from public.profiles where id = v_i and role = 'individual' and plan = 'individual_founder' and plan_source = 'manual_pilot')
     or (select count(*) from mobau_private.plan_events) <> 1
     or not exists (select 1 from mobau_private.plan_events where user_id = v_i and to_source = 'manual_pilot')
     or exists (select 1 from public.profiles where plan_source = 'subscription') then
    raise exception 'MOBAU_43_C2: estudios, habilitaciones o eventos distintos de los de T3' using errcode = 'MB998';
  end if;""")
rep("raise exception 'MOBAU_43_P2_SUITE: los proyectos de prueba no están como se leyeron'", "raise exception 'MOBAU_43_C2: los proyectos de prueba no están como se leyeron'")
rep("grant_i text; grant_f_req text;", "revoke_i text; grant_f_req text;")
rep("""  grant_i := format('update public.profiles set plan = %L, plan_source = %L, plan_granted_at = now(), plan_note = %L where id = %L',
                    'individual_founder', 'manual_pilot', 'Ensayo P2 (revertido)', v_i);""",
"""  -- Retirada simulada de la habilitación de e2a655c1, solo dentro de un caso (revertido).
  revoke_i := format('update public.profiles set plan = %L, plan_source = %L, plan_granted_at = null, plan_note = null where id = %L',
                     'free_trial', 'default', v_i);""")
# Individual: ya habilitada de verdad
n = s.count("array[grant_i]")
assert n == 11, n
s = s.replace("array[grant_i]", "null")
assert s.count("array[grant_i, ") == 3
s = s.replace("array[grant_i, ", "array[")
assert "grant_i" not in s
rep("('A06 Individual habilitado (manual_pilot) → todas las filas publicadas'", "('A06 Individual habilitado de verdad (T3, manual_pilot) → todas las filas publicadas'")
rep("""      -- ========== B · función de acceso y datos de plan ==========""",
"""      ('A14 Individual con la habilitación retirada → 42501[plan_required]', 'authenticated', v_i::text, 'aal1', array[revoke_i],
         array['select count(*) from public.catalog_published_prices()'], 'exec', '42501[plan_required]'),
      -- ========== B · función de acceso y datos de plan ==========""")
rep("""      -- ========== C · Gratis con datos (E5/E5b) ==========""",
"""      ('B10 my_professional_access() con la habilitación retirada = false', 'authenticated', v_i::text, 'aal1', array[revoke_i],
         array['select public.my_professional_access()::text'], 'text', 'false'),
      -- ========== C · Gratis con datos (E5/E5b) ==========""")
rep("""      ('C11 Gratis (cuenta Individual sin habilitar) lee su historial de solicitudes', 'authenticated', v_i::text, 'aal1', null,""",
    """      ('C11 Gratis (e2a655c1 con la habilitación retirada en el caso) lee su historial de solicitudes', 'authenticated', v_i::text, 'aal1', array[revoke_i],""")
rep("""      ('C12 Gratis elimina un archivado propio sin solicitudes; sus líneas se borran en cascada (E5b)', 'authenticated', v_i::text, 'aal1', null,""",
    """      ('C12 Gratis (e2a655c1 sin habilitación) elimina un archivado propio sin solicitudes; sus líneas se borran en cascada (E5b)', 'authenticated', v_i::text, 'aal1', array[revoke_i],""")
rep("""      ('C13 Gratis no elimina un archivado con solicitudes → 23503 (se respetan las solicitudes)', 'authenticated', v_i::text, 'aal1', null,""",
    """      ('C13 Gratis (e2a655c1 sin habilitación) no elimina un archivado con solicitudes → 23503', 'authenticated', v_i::text, 'aal1', array[revoke_i],""")
rep("""      -- ========== Z · fuera de los casos ==========""",
"""      -- ========== H · estado de T4 ==========
      ('H01 límites de T4: Gratis 1, Individual 2, Estudio 20', '-', null, null, null,
         array['select string_agg(id || '':'' || max_active_projects, ''|'' order by id) from public.plans'], 'text', 'free_trial:1|individual_founder:2|studio_founder:20'),
      ('H02 25 políticas en proyectos, líneas y solicitudes; las 8 de T4 RESTRICTIVE', '-', null, null, null,
         array['select count(*) from pg_policies where schemaname = ''public'' and tablename in (''projects'', ''project_products'', ''rfqs'')'
               || ' and (policyname not in (''projects_plan_insert'', ''projects_plan_update'', ''projects_studio_own_insert'', ''projects_studio_own_update'','
               || ' ''project_products_plan_insert'', ''project_products_plan_update'', ''project_products_plan_delete'', ''rfqs_plan_insert'') or permissive = ''RESTRICTIVE'')'],
         'count', '25'),
      -- ========== Z · fuera de los casos ==========""")
rep("""      ('Z01 sin restos: datos idénticos, sin estudios, habilitaciones ni eventos', '-', null, null, null,""",
    """      ('Z01 sin restos: datos idénticos, sin estudios; solo la habilitación y el evento de T3', '-', null, null, null,""")
rep("""                      || ' and not exists (select 1 from public.profiles where plan_source <> ''default'')'
                      || ' and not exists (select 1 from mobau_private.plan_events)'""",
"""                      || ' and (select count(*) from public.profiles where plan_source <> ''default'') = 1'
                      || ' and exists (select 1 from public.profiles where id = %L and plan = ''individual_founder'' and plan_source = ''manual_pilot'')'
                      || ' and (select count(*) from mobau_private.plan_events) = 1'""")
rep("""                      data_fp, data0, v_s, v_m)], 'count', '1')""", """                      data_fp, data0, v_i, v_s, v_m)], 'count', '1')""")
rep("""  raise exception 'MOBAU_43_P2_SUITE total=% ok=% fallos=% :: %', n_total, n_ok, n_total - n_ok, r::text
    using errcode = 'MB999';""",
"""  -- Siempre se revierte: el resultado viaja en el mensaje de MB990.
  raise exception 'MOBAU_43_C2 total=% ok=% fallos=% :: %', n_total, n_ok, n_total - n_ok, r::text
    using errcode = 'MB990';""")
assert "P2S" not in s and "MOBAU_43_P2" not in s
text = header + s.rstrip("\n") + "\n" + footer
out.write_bytes(text.encode())
print(out.name, hashlib.md5(text.encode()).hexdigest(), "casos:", text.count("\n      ('"))
