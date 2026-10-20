-- ============================================================
-- PROPUESTA NO EJECUTADA (43 · limpieza de la cuenta Hotmail del usuario, v2) — no ejecutar sin confirmación específica
-- ============================================================
-- Generado por generar_limpieza.py. Sustituye a 43_limpieza_46ea4397.sql
-- (a870a80a…), que esperaba totales fijos 10 / 31 / 2: desde entonces la
-- cuenta Individual e2a655c1 creó un proyecto (C3), así que los totales se
-- comprueban ahora de forma relativa.
-- Borra SOLO los dos proyectos de la cuenta 46ea4397-f881-4db8-89e7-f164293a1143:
--   * a078dbfe-939b-42e7-aa5b-abe4b50ce9ed «Casa Ruiz» (activo, 6 líneas)
--   * b3444724-d7aa-4bb4-8791-6b175365ebae «Casa Pedrá» (archivado, 2 líneas)
-- Las 8 líneas se borran en cascada (project_products ON DELETE CASCADE).
-- Antes de borrar exige que las filas sean exactamente las de la copia local
-- copia_46ea4397.json (huella 931b6f7abc65a175d4da71b89478fb38), sin solicitudes ni moodboards.
-- No toca la cuenta, su perfil, su plan ni datos de ninguna otra cuenta.
-- Es una operación de datos: no se registra como migración.
-- Recuperación: 43_limpieza_restaurar_46ea4397.sql (desde la copia local).
-- Ejecutar completo, con el control MD5.
-- ============================================================

BEGIN;

DO $$
begin
  if current_user <> 'postgres' then
    raise exception '43-L: ejecutar como postgres';
  end if;
  if not exists (select 1 from public.profiles where id = '46ea4397-f881-4db8-89e7-f164293a1143' and plan = 'free_trial' and plan_source = 'default') then
    raise exception '43-L: la cuenta no es la Gratis leída';
  end if;
  if (select count(*) from public.projects where owner_user_id = '46ea4397-f881-4db8-89e7-f164293a1143') <> 2
     or (select count(*) from public.projects where id = any (array['a078dbfe-939b-42e7-aa5b-abe4b50ce9ed', 'b3444724-d7aa-4bb4-8791-6b175365ebae']::uuid[]) and owner_user_id = '46ea4397-f881-4db8-89e7-f164293a1143') <> 2
     or (select count(*) from public.project_products where project_id = any (array['a078dbfe-939b-42e7-aa5b-abe4b50ce9ed', 'b3444724-d7aa-4bb4-8791-6b175365ebae']::uuid[])) <> 8 then
    raise exception '43-L: la cuenta no tiene exactamente los 2 proyectos y las 8 líneas leídos';
  end if;
  if md5(coalesce((select string_agg(to_jsonb(pr)::text, '|' order by pr.id) from public.projects pr where pr.owner_user_id = '46ea4397-f881-4db8-89e7-f164293a1143'), '')
      || '#' || coalesce((select string_agg(to_jsonb(pp)::text, '|' order by pp.id) from public.project_products pp where pp.project_id = any (array['a078dbfe-939b-42e7-aa5b-abe4b50ce9ed', 'b3444724-d7aa-4bb4-8791-6b175365ebae']::uuid[])), '')) <> '931b6f7abc65a175d4da71b89478fb38' then
    raise exception '43-L: las filas no coinciden con la copia local; no se borra nada';
  end if;
  if exists (select 1 from public.rfqs where project_id = any (array['a078dbfe-939b-42e7-aa5b-abe4b50ce9ed', 'b3444724-d7aa-4bb4-8791-6b175365ebae']::uuid[]) or requester_user_id = '46ea4397-f881-4db8-89e7-f164293a1143')
     or exists (select 1 from public.moodboards where project_id = any (array['a078dbfe-939b-42e7-aa5b-abe4b50ce9ed', 'b3444724-d7aa-4bb4-8791-6b175365ebae']::uuid[])) then
    raise exception '43-L: hay solicitudes o moodboards vinculados';
  end if;
  perform set_config('mobau.l43_resto', md5(coalesce((select string_agg(id::text || status || owner_user_id::text || name || updated_at::text, '|' order by id) from public.projects where not (id = any (array['a078dbfe-939b-42e7-aa5b-abe4b50ce9ed', 'b3444724-d7aa-4bb4-8791-6b175365ebae']::uuid[]))), '')
      || coalesce((select string_agg(id::text || project_id::text || quantity::text || coalesce(unit, '-'), '|' order by id) from public.project_products where not (project_id = any (array['a078dbfe-939b-42e7-aa5b-abe4b50ce9ed', 'b3444724-d7aa-4bb4-8791-6b175365ebae']::uuid[]))), '')
      || coalesce((select string_agg(id::text || status, '|' order by id) from public.rfqs), '')
      || (select count(*)::text from public.rfq_distributors)
      || (select count(*)::text from public.moodboards)
      || coalesce((select string_agg(id::text || plan || role || plan_source || subscription_status, '|' order by id) from public.profiles), '')), true);
  perform set_config('mobau.l43_proyectos', (select count(*)::text from public.projects), true);
  perform set_config('mobau.l43_lineas', (select count(*)::text from public.project_products), true);
  perform set_config('mobau.l43_solicitudes', (select count(*)::text from public.rfqs), true);
end $$;

delete from public.projects
 where id = any (array['a078dbfe-939b-42e7-aa5b-abe4b50ce9ed', 'b3444724-d7aa-4bb4-8791-6b175365ebae']::uuid[])
   and owner_user_id = '46ea4397-f881-4db8-89e7-f164293a1143';

DO $$
begin
  if exists (select 1 from public.projects where owner_user_id = '46ea4397-f881-4db8-89e7-f164293a1143')
     or exists (select 1 from public.project_products where project_id = any (array['a078dbfe-939b-42e7-aa5b-abe4b50ce9ed', 'b3444724-d7aa-4bb4-8791-6b175365ebae']::uuid[])) then
    raise exception '43-L: quedan proyectos o líneas de la cuenta';
  end if;
  if md5(coalesce((select string_agg(id::text || status || owner_user_id::text || name || updated_at::text, '|' order by id) from public.projects where not (id = any (array['a078dbfe-939b-42e7-aa5b-abe4b50ce9ed', 'b3444724-d7aa-4bb4-8791-6b175365ebae']::uuid[]))), '')
      || coalesce((select string_agg(id::text || project_id::text || quantity::text || coalesce(unit, '-'), '|' order by id) from public.project_products where not (project_id = any (array['a078dbfe-939b-42e7-aa5b-abe4b50ce9ed', 'b3444724-d7aa-4bb4-8791-6b175365ebae']::uuid[]))), '')
      || coalesce((select string_agg(id::text || status, '|' order by id) from public.rfqs), '')
      || (select count(*)::text from public.rfq_distributors)
      || (select count(*)::text from public.moodboards)
      || coalesce((select string_agg(id::text || plan || role || plan_source || subscription_status, '|' order by id) from public.profiles), '')) <> current_setting('mobau.l43_resto') then
    raise exception '43-L: ha cambiado algún dato de otra cuenta';
  end if;
  if (select count(*) from public.projects) <> current_setting('mobau.l43_proyectos')::int - 2
     or (select count(*) from public.project_products) <> current_setting('mobau.l43_lineas')::int - 8
     or (select count(*) from public.rfqs) <> current_setting('mobau.l43_solicitudes')::int then
    raise exception '43-L: los totales no bajan exactamente 2 proyectos y 8 líneas';
  end if;
end $$;

COMMIT;
