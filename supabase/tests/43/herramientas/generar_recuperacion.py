#!/usr/bin/env python3
"""Genera las recuperaciones de 43-D (T4 y T1) con los cuerpos de partida
exactos leídos del servidor el 2026-10-19 (pg_get_functiondef, en JSON).
enforce_active_project_limit tiene finales de línea CRLF: se conservan.
Las propias recuperaciones comprueban md5(prosrc) tras restaurar."""
import json, pathlib, hashlib

base = pathlib.Path(__file__).resolve().parent.parent / "servidor"

CATALOG_DEF = json.loads(r'''"CREATE OR REPLACE FUNCTION public.catalog_published_prices(p_product_ids text[] DEFAULT NULL::text[], p_after text DEFAULT NULL::text, p_limit integer DEFAULT 1000)\n RETURNS TABLE(product_id text, price_amount numeric, currency text, price_status text, includes_itbis boolean, itbis_rate numeric, es_demo boolean)\n LANGUAGE plpgsql\n STABLE SECURITY DEFINER\n SET search_path TO ''\nAS $function$\nbegin\n  if (select auth.uid()) is null then\n    raise exception 'Inicia sesión para consultar precios.' using errcode = '42501';\n  end if;\n  if p_limit is null or p_limit < 1 or p_limit > 1000 then\n    raise exception 'p_limit debe estar entre 1 y 1000.' using errcode = '22023';\n  end if;\n  if p_product_ids is not null and pg_catalog.cardinality(p_product_ids) > 200 then\n    raise exception 'Como máximo 200 productos por consulta.' using errcode = '22023';\n  end if;\n  if p_after is not null and pg_catalog.char_length(p_after) > 200 then\n    raise exception 'p_after no puede superar 200 caracteres.'\n      using errcode = '22023';\n  end if;\n\n  return query\n    select pp.product_id,\n           case when pp.price_status = 'published' then pp.price_amount end,\n           pp.currency,\n           pp.price_status,\n           pp.includes_itbis,\n           pp.itbis_rate,\n           coalesce(pp.price_source = 'demo', false)\n      from public.product_prices pp\n      join public.products p on p.id = pp.product_id\n     where p.publication_status = 'published'\n       -- 41-02: defensa redundante (las CHECK de 41-01 y el espejo de status ya\n       -- lo garantizan): nunca un producto inactivo, retirado o en papelera.\n       and p.status = 'active'\n       and p.retired_at is null\n       and p.trashed_at is null\n       and pp.price_status in ('published', 'quote_required', 'pending_confirmation', 'unavailable')\n       and (p_product_ids is null or pp.product_id = any (p_product_ids))\n       and (p_after is null or pp.product_id > p_after)\n     order by pp.product_id\n     limit p_limit;\nend;\n$function$\n"''')

ENFORCE_DEF = json.loads(r'''"CREATE OR REPLACE FUNCTION public.enforce_active_project_limit()\n RETURNS trigger\n LANGUAGE plpgsql\n SECURITY DEFINER\n SET search_path TO ''\nAS $function$\r\ndeclare\r\n  v_limit int;\r\n  v_current_count int;\r\n  v_is_reactivation boolean;\r\n  v_owner_max int;\r\nbegin\r\n  if new.status <> 'active' then\r\n    return new;\r\n  end if;\r\n\r\n  v_is_reactivation := (TG_OP = 'UPDATE' and old.status = 'archived' and new.status = 'active');\r\n\r\n  -- Bloquea toda reactivación cuando el plan del dueño (o del estudio,\r\n  -- si el proyecto pertenece a uno) permite un único proyecto activo.\r\n  if v_is_reactivation then\r\n    if new.studio_id is not null then\r\n      select pl.max_active_projects into v_owner_max\r\n      from public.studios s join public.plans pl on pl.id = s.plan\r\n      where s.id = new.studio_id;\r\n    else\r\n      select pl.max_active_projects into v_owner_max\r\n      from public.profiles pr join public.plans pl on pl.id = pr.plan\r\n      where pr.id = new.owner_user_id;\r\n    end if;\r\n\r\n    if v_owner_max = 1 then\r\n      raise exception 'Los proyectos archivados no se pueden reactivar en tu plan actual. Crea un proyecto nuevo en su lugar.';\r\n    end if;\r\n  end if;\r\n\r\n  if new.studio_id is not null then\r\n    select pl.max_active_projects into v_limit\r\n    from public.studios s join public.plans pl on pl.id = s.plan\r\n    where s.id = new.studio_id;\r\n    select count(*) into v_current_count\r\n    from public.projects p\r\n    where p.studio_id = new.studio_id and p.status = 'active'\r\n      and p.id <> coalesce(new.id, '00000000-0000-0000-0000-000000000000'::uuid);\r\n  else\r\n    select pl.max_active_projects into v_limit\r\n    from public.profiles pr join public.plans pl on pl.id = pr.plan\r\n    where pr.id = new.owner_user_id;\r\n    select count(*) into v_current_count\r\n    from public.projects p\r\n    where p.owner_user_id = new.owner_user_id and p.studio_id is null and p.status = 'active'\r\n      and p.id <> coalesce(new.id, '00000000-0000-0000-0000-000000000000'::uuid);\r\n  end if;\r\n\r\n  if v_current_count >= v_limit then\r\n    raise exception 'Límite de proyectos activos alcanzado (%). Archiva un proyecto existente o cambia de plan.', v_limit;\r\n  end if;\r\n\r\n  return new;\r\nend;\r\n$function$\n"''')

def body(defn):
    a = defn.index("$function$") + len("$function$")
    return defn[a:defn.rindex("$function$")]

assert hashlib.md5(body(CATALOG_DEF).encode()).hexdigest() == "366f275cf85ec6c10956cecfbbc92ed5"
assert hashlib.md5(body(ENFORCE_DEF).encode()).hexdigest() == "40e11d31467d9719f439ab5be096a92a"
assert hashlib.md5(CATALOG_DEF.encode()).hexdigest() == "af5def26d5fd93d9a7fe5b78e843f0db"
assert hashlib.md5(ENFORCE_DEF.encode()).hexdigest() == "c33106cd8a472be3517c0b806c5cabc2"

# El cuerpo de enforce_active_project_limit tiene CRLF: el archivo lo lleva
# con LF y el servidor lo reconstruye con replace(E'\\n', E'\\r\\n'); la
# comprobación md5(prosrc) posterior confirma que es idéntico.
ENF_HEADER = ENFORCE_DEF[:ENFORCE_DEF.index("$function$")]
ENF_BODY_LF = body(ENFORCE_DEF).replace("\r\n", "\n")
assert ENF_BODY_LF.replace("\n", "\r\n") == body(ENFORCE_DEF)
assert "$rb$" not in ENF_BODY_LF and "\r" not in ENF_HEADER
ENFORCE_SQL = ("DO $do$\nbegin\n  execute " + "$hd$" + ENF_HEADER + "$function$$hd$\n"
               "    || pg_catalog.replace($rb$" + ENF_BODY_LF + "$rb$, E'\\n', E'\\r\\n')\n"
               "    || '$function$';\nend $do$;")

POLICIES = ["projects_plan_insert on public.projects", "projects_plan_update on public.projects",
            "projects_studio_own_insert on public.projects", "projects_studio_own_update on public.projects",
            "project_products_plan_insert on public.project_products", "project_products_plan_update on public.project_products",
            "project_products_plan_delete on public.project_products", "rfqs_plan_insert on public.rfqs"]

rec_t4 = """-- ============================================================
-- RECUPERACIÓN NO EJECUTADA (43-D2 · inversa de T4) — no ejecutar sin aprobación explícita
-- ============================================================
-- Devuelve el servidor al estado de T1 (preparación): elimina las 8 políticas
-- RESTRICTIVE de T4, restaura catalog_published_prices y
-- enforce_active_project_limit con sus cuerpos de partida exactos
-- (comprobados por md5(prosrc)) y vuelve a los límites 1 y 5. No borra datos.
-- Si se ejecuta de verdad, se aplica como migración nueva y se registra
-- aparte tras su COMMIT. Antes, devolver la web a una versión que no dependa
-- del control por plan en el servidor.
-- ============================================================

BEGIN;

DO $$
begin
  if current_user <> 'postgres' then
    raise exception '43-R4: ejecutar como postgres';
  end if;
  if (select count(*) from pg_policies where schemaname = 'public' and policyname in
      ('projects_plan_insert', 'projects_plan_update', 'projects_studio_own_insert', 'projects_studio_own_update',
       'project_products_plan_insert', 'project_products_plan_update', 'project_products_plan_delete', 'rfqs_plan_insert')) <> 8 then
    raise exception '43-R4: T4 no está aplicada (faltan políticas)';
  end if;
end $$;

""" + "".join(f"drop policy {p};\n" for p in POLICIES) + """
update public.plans set max_active_projects = 1 where id = 'individual_founder';
update public.plans set max_active_projects = 5 where id = 'studio_founder';

""" + CATALOG_DEF.rstrip("\n") + ";\n\n" + ENFORCE_SQL + """

DO $$
begin
  if (select md5(prosrc) from pg_proc where oid = 'public.catalog_published_prices(text[], text, integer)'::regprocedure) <> '366f275cf85ec6c10956cecfbbc92ed5'
     or (select md5(prosrc) from pg_proc where oid = 'public.enforce_active_project_limit()'::regprocedure) <> '40e11d31467d9719f439ab5be096a92a' then
    raise exception '43-R4: las funciones no quedaron idénticas a las de partida';
  end if;
  if (select count(*) from pg_policies where schemaname = 'public' and tablename in ('projects', 'project_products', 'rfqs')) <> 17 then
    raise exception '43-R4: no quedaron las 17 políticas de partida';
  end if;
  if (select string_agg(id || ':' || max_active_projects, '|' order by id) from public.plans) <> 'free_trial:1|individual_founder:1|studio_founder:5' then
    raise exception '43-R4: límites no restaurados';
  end if;
  if (select proacl::text from pg_proc where oid = 'public.catalog_published_prices(text[], text, integer)'::regprocedure)
     <> '{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}' then
    raise exception '43-R4: permisos de catalog_published_prices cambiados';
  end if;
end $$;

COMMIT;
"""

rec_t1 = """-- ============================================================
-- RECUPERACIÓN NO EJECUTADA (43-D1 · inversa de T1) — no ejecutar sin aprobación explícita
-- ============================================================
-- Devuelve plans y profiles al estado de partida y elimina
-- my_professional_access() y mobau_private.plan_events. Requiere que T4 ya
-- esté revertida. Se niega si hay alguna habilitación (plan_source distinto
-- de 'default') o algún evento de habilitación: primero hay que revertir T3
-- con su SQL autorizado, para no perder la auditoría sin decidirlo.
-- ============================================================

BEGIN;

DO $$
begin
  if current_user <> 'postgres' then
    raise exception '43-R1: ejecutar como postgres';
  end if;
  if exists (select 1 from pg_policies where schemaname = 'public' and policyname in ('projects_plan_insert', 'projects_plan_update', 'projects_studio_own_insert', 'projects_studio_own_update',
             'project_products_plan_insert', 'project_products_plan_update', 'project_products_plan_delete', 'rfqs_plan_insert'))
     or (select md5(prosrc) from pg_proc where oid = 'public.catalog_published_prices(text[], text, integer)'::regprocedure) <> '366f275cf85ec6c10956cecfbbc92ed5' then
    raise exception '43-R1: T4 sigue aplicada; revertir T4 antes';
  end if;
  if exists (select 1 from public.profiles where plan_source <> 'default') or exists (select 1 from mobau_private.plan_events) then
    raise exception '43-R1: hay habilitaciones o eventos de habilitación; revertir T3 antes';
  end if;
end $$;

drop function public.my_professional_access();
drop table mobau_private.plan_events;
alter table public.profiles drop column plan_note;
alter table public.profiles drop column plan_granted_at;
alter table public.profiles drop column plan_source;
alter table public.plans drop column includes_professional_tools;
update public.plans set name = 'Prueba gratuita', trial_days = 14 where id = 'free_trial';
update public.plans set name = 'Profesional Fundador' where id = 'individual_founder';
update public.plans set name = 'Estudio Fundador' where id = 'studio_founder';

DO $$
begin
  if (select string_agg(id || ':' || name || ':' || max_active_projects || ':' || max_users || ':' || coalesce(trial_days::text, 'null'), '|' order by id) from public.plans)
     <> 'free_trial:Prueba gratuita:1:1:14|individual_founder:Profesional Fundador:1:1:null|studio_founder:Estudio Fundador:5:3:null' then
    raise exception '43-R1: plans no volvió al estado de partida';
  end if;
  if exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'profiles' and column_name in ('plan_source', 'plan_granted_at', 'plan_note'))
     or to_regprocedure('public.my_professional_access()') is not null or to_regclass('mobau_private.plan_events') is not null then
    raise exception '43-R1: quedan objetos de T1';
  end if;
end $$;

COMMIT;
"""

(base / "43_d2_recuperacion.sql").write_bytes(rec_t4.encode("utf-8"))
(base / "43_d1_recuperacion.sql").write_bytes(rec_t1.encode("utf-8"))
for f in ("43_d2_recuperacion.sql", "43_d1_recuperacion.sql"):
    print(f, hashlib.md5((base / f).read_bytes()).hexdigest())
