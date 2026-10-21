#!/usr/bin/env python3
"""Genera los SQL del punto 44 (44-01) en ../servidor a partir de las plantillas.

  migración     20261021120000_44_01_archivos_producto.sql
  recuperación  20261021120000_44_01_archivos_producto.rollback.sql
  lectura       44_01_lectura.sql (solo SELECT)
  ensayo        P44_ensayo.sql (revertido, termina en MB990)

La función de transición nueva se obtiene del cuerpo vigente
(transicion_original.txt, md5 19d26a92…) con dos cambios exactos.
"""
import hashlib
import pathlib
import re

AQUI = pathlib.Path(__file__).resolve().parent
SALIDA = AQUI.parent / "servidor"
MD5_TRANSICION = "19d26a925b9d97c89715254f219fbe7e"


def md5(texto):
    return hashlib.md5(texto.encode("utf-8")).hexdigest()


def leer(nombre):
    return (AQUI / nombre).read_text(encoding="utf-8")


def reemplazar_una_vez(texto, viejo, nuevo):
    assert texto.count(viejo) == 1, f"no aparece exactamente una vez: {viejo[:60]!r}"
    return texto.replace(viejo, nuevo)


def sin_marcas(texto):
    restos = re.findall(r"\{\{[A-Z_:a-z0-9]+\}\}|^@@", texto, flags=re.M)
    assert not restos, f"quedan marcas sin sustituir: {restos[:5]}"
    return texto


# ---------- Transición ----------
original = leer("transicion_original.txt")
assert md5(original) == MD5_TRANSICION, "el cuerpo original no es el vigente"
nueva = reemplazar_una_vez(
    original,
    "       or new.internal_note is distinct from old.internal_note then\n",
    "       or new.internal_note is distinct from old.internal_note\n"
    "       or new.proposed_media is distinct from old.proposed_media then\n",
)
nueva = reemplazar_una_vez(
    nueva,
    "  -- update: al menos un cambio de información (incluida una subcategoría\n"
    "  -- nueva) o de precio. create: los obligatorios los exige el trigger 30.\n"
    "  if new.status = 'submitted' and new.proposal_kind = 'update'\n"
    "     and new.proposed_changes = '{}'::jsonb and new.proposed_new_subcategory is null\n"
    "     and new.proposed_price_status is null then\n",
    "  -- update: al menos un cambio de información (incluida una subcategoría\n"
    "  -- nueva), de precio o de archivos (44). create: los obligatorios los\n"
    "  -- exigen los triggers 30 y 35.\n"
    "  if new.status = 'submitted' and new.proposal_kind = 'update'\n"
    "     and new.proposed_changes = '{}'::jsonb and new.proposed_new_subcategory is null\n"
    "     and new.proposed_price_status is null and new.proposed_media is null then\n",
)
md5_nueva = md5(nueva)

# ---------- Migración y recuperación ----------
migracion = leer("plantilla_migracion.sql")
migracion = reemplazar_una_vez(migracion, "{{TRANSITION_NEW}}", nueva)
migracion = reemplazar_una_vez(migracion, "{{TRANSITION_NEW_MD5}}", md5_nueva)
migracion = sin_marcas(migracion)

recuperacion = leer("plantilla_recuperacion.sql")
recuperacion = reemplazar_una_vez(recuperacion, "{{TRANSITION_ORIG}}", original)
recuperacion = reemplazar_una_vez(recuperacion, "{{TRANSITION_NEW_MD5}}", md5_nueva)
recuperacion = sin_marcas(recuperacion)

for texto in (migracion, recuperacion):
    assert texto.count("\nBEGIN;\n") == 1 and texto.count("\nCOMMIT;\n") == 1
    assert "$M44$" not in texto and "$R44$" not in texto and "$P44$" not in texto and "$Q$" not in texto

lectura = sin_marcas(leer("plantilla_lectura.sql").replace("{{TRANSITION_NEW_MD5}}", md5_nueva))


# ---------- Ensayo ----------
def como(var, aal):
    return (
        "    execute 'reset role';\n"
        f"    perform set_config('request.jwt.claims', json_build_object('sub', {var}, 'role', 'authenticated', 'aal', '{aal}')::text, true);\n"
        f"    perform set_config('request.jwt.claim.sub', {var}::text, true);\n"
        "    execute 'set local role authenticated';"
    )


COMO_ANON = (
    "    execute 'reset role';\n"
    "    perform set_config('request.jwt.claims', '{\"role\": \"anon\"}', true);\n"
    "    perform set_config('request.jwt.claim.sub', '', true);\n"
    "    execute 'set local role anon';"
)
COMO_PG = (
    "    execute 'reset role';\n"
    "    perform set_config('request.jwt.claims', '', true);\n"
    "    perform set_config('request.jwt.claim.sub', '', true);"
)


def sondas(var):
    return "\n".join([
        COMO_ANON,
        f"    {var} := (select count(*)::text from public.catalog_products) || '|'",
        "          || (select md5(string_agg(id || ':' || name || ':' || coalesce(image_url, '-'), ',' order by id)) from public.catalog_products);",
        como("v_ind", "aal1"),
        f"    {var} := {var} || '|' || (select count(*) || ':' || coalesce(sum(quantity), 0) from public.project_products) || '|' || (select count(*) from public.projects);",
        como("v_gra", "aal1"),
        f"    {var} := {var} || '|' || (select count(*) from public.projects) || '|' || (select count(*) from public.catalog_products);",
        como("v_sup", "aal1"),
        f"    {var} := {var} || '|' || (select count(*) from public.products) || ':' || (select count(*) from public.product_proposals);",
        "    execute 'reset role';",
    ])


def check(caso, expr, esperado):
    return (
        f"    v_paso := '{caso}';\n"
        f"    v_t := ({expr})::text;\n"
        f"    res := res || ' {caso}=' || coalesce(v_t, '∅');\n"
        f"    if v_t is distinct from '{esperado}' then fallos := fallos + 1; res := res || '!'; end if;"
    )


def err(caso, sentencia, codigo):
    return (
        f"    v_paso := '{caso}';\n"
        "    begin\n"
        f"      {sentencia};\n"
        "      v_t := 'sin_error';\n"
        "    exception when others then\n"
        "      v_t := sqlstate;\n"
        "    end;\n"
        f"    res := res || ' {caso}=' || v_t;\n"
        f"    if v_t is distinct from '{codigo}' then fallos := fallos + 1; res := res || '!'; end if;"
    )


lineas = []
casos = []
for linea in leer("plantilla_ensayo.sql").split("\n"):
    if linea.startswith("@@CHECK ") or linea.startswith("@@ERR "):
        tipo, resto = linea[2:].split(" ", 1)
        caso, cuerpo, esperado = [p.strip() for p in resto.split(" | ", 2)] if resto.count(" | ") == 2 else (None, None, None)
        assert caso, f"línea de caso mal formada: {linea[:80]}"
        casos.append(caso)
        lineas.append(check(caso, cuerpo, esperado) if tipo == "CHECK" else err(caso, cuerpo, esperado))
        continue
    m = re.fullmatch(r"\{\{COMO:(v_[a-z]+):(aal[12])\}\}", linea)
    if m:
        lineas.append(como(m.group(1), m.group(2)))
    elif linea == "{{COMO_ANON}}":
        lineas.append(COMO_ANON)
    elif linea == "{{COMO_PG}}":
        lineas.append(COMO_PG)
    elif re.fullmatch(r"\{\{SONDAS:p[012]\}\}", linea):
        lineas.append(sondas(linea[9:11]))
    else:
        lineas.append(linea)
assert len(casos) == len(set(casos)), "hay casos repetidos"
ensayo = "\n".join(lineas)
ensayo = reemplazar_una_vez(ensayo, "{{MIGRACION_MD5}}", md5(migracion))
ensayo = reemplazar_una_vez(ensayo, "{{RECUPERACION_MD5}}", md5(recuperacion))
ensayo = reemplazar_una_vez(ensayo, "{{MIGRACION}}", migracion)
ensayo = reemplazar_una_vez(ensayo, "{{RECUPERACION}}", recuperacion)
sin_marcas(ensayo.replace(migracion, "").replace(recuperacion, ""))

# ---------- Escribir ----------
SALIDA.mkdir(exist_ok=True)
archivos = {
    "20261021120000_44_01_archivos_producto.sql": migracion,
    "20261021120000_44_01_archivos_producto.rollback.sql": recuperacion,
    "44_01_lectura.sql": lectura,
    "P44_ensayo.sql": ensayo,
}
for nombre, texto in archivos.items():
    (SALIDA / nombre).write_text(texto, encoding="utf-8")
    print(f"{md5(texto)}  {nombre}  ({len(texto.encode('utf-8'))} bytes)")
print(f"{md5_nueva}  (cuerpo nuevo de transition_proposal_status)")
print(f"casos del ensayo: {len(casos)} → {' '.join(casos)}")
