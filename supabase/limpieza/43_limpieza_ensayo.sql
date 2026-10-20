-- ============================================================
-- PROPUESTA NO EJECUTADA (43 · ensayo revertido de la limpieza Hotmail y su restauración) — no ejecutar sin aprobación explícita
-- ============================================================
-- Generado por generar_limpieza.py. En una sola transacción que SIEMPRE
-- termina con MB990 (nada persiste): limpieza v2 -> comprueba que no queda
-- nada de la cuenta -> restauración -> comprueba que las filas y la huella
-- global vuelven a ser las de partida.
-- Éxito: «L43E limpia=true restaurada=true identico=true».
-- Ejecutar completo, con el control MD5.
-- ============================================================

BEGIN;

DO $L43E$
declare
  t_l text := $LB$
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
$LB$;
  t_r text := $RB$
DO $$
begin
  if current_user <> 'postgres' then
    raise exception '43-LR: ejecutar como postgres';
  end if;
  if not exists (select 1 from public.profiles where id = '46ea4397-f881-4db8-89e7-f164293a1143') then
    raise exception '43-LR: no existe la cuenta';
  end if;
  if exists (select 1 from public.projects where id = any (array['a078dbfe-939b-42e7-aa5b-abe4b50ce9ed', 'b3444724-d7aa-4bb4-8791-6b175365ebae']::uuid[]))
     or exists (select 1 from public.project_products where id = any (array['1bfd6c77-a39f-488b-8852-ee5f7d01ab54', '43991251-1ffd-43fa-adcf-cec3e7cb150e', '8d2192f5-f6a5-4275-8021-cc6ca7d4b17b', 'a6998931-e281-451e-82f2-b8b0db12010b', 'cf88dc36-ea27-428b-864e-9bd16b0cfce6', 'ee8f925c-50ce-45bf-8ca0-0ddffcfdb828', 'f28ed362-80f0-4162-91f5-f281aeca599a', 'ff4840de-15e6-428d-a1cf-cf9e6c2c2f54']::uuid[])) then
    raise exception '43-LR: algún proyecto o línea ya existe; no se restaura nada';
  end if;
end $$;

insert into public.projects
select * from jsonb_populate_recordset(null::public.projects, $J$[{"id": "a078dbfe-939b-42e7-aa5b-abe4b50ce9ed", "name": "Casa Ruiz", "status": "active", "location": "Tena", "studio_id": null, "created_at": "2026-09-11T18:15:07.112514+00:00", "updated_at": "2026-09-11T18:16:22.827029+00:00", "client_name": "Familia Ruiz", "description": null, "project_type": "residencial", "owner_user_id": "46ea4397-f881-4db8-89e7-f164293a1143"}, {"id": "b3444724-d7aa-4bb4-8791-6b175365ebae", "name": "Casa Pedrá", "status": "archived", "location": "Barcelona", "studio_id": null, "created_at": "2026-09-11T17:14:53.437929+00:00", "updated_at": "2026-09-11T18:10:08.842209+00:00", "client_name": "Antonio Gaudí", "description": null, "project_type": "residencial", "owner_user_id": "46ea4397-f881-4db8-89e7-f164293a1143"}]$J$::jsonb);

insert into public.project_products
select * from jsonb_populate_recordset(null::public.project_products, $J$[{"id": "1bfd6c77-a39f-488b-8852-ee5f7d01ab54", "unit": "m²", "notes": null, "quantity": 4.00, "created_at": "2026-09-11T18:16:21.734064+00:00", "product_id": "p16", "project_id": "a078dbfe-939b-42e7-aa5b-abe4b50ce9ed", "room_or_area": null, "order_position": 0, "selected_for_rfq": true}, {"id": "43991251-1ffd-43fa-adcf-cec3e7cb150e", "unit": "ud.", "notes": null, "quantity": 1.00, "created_at": "2026-09-11T18:15:08.545855+00:00", "product_id": "p11", "project_id": "a078dbfe-939b-42e7-aa5b-abe4b50ce9ed", "room_or_area": null, "order_position": 0, "selected_for_rfq": true}, {"id": "8d2192f5-f6a5-4275-8021-cc6ca7d4b17b", "unit": "ud.", "notes": null, "quantity": 1.00, "created_at": "2026-09-11T18:16:22.27639+00:00", "product_id": "p19", "project_id": "a078dbfe-939b-42e7-aa5b-abe4b50ce9ed", "room_or_area": null, "order_position": 0, "selected_for_rfq": true}, {"id": "a6998931-e281-451e-82f2-b8b0db12010b", "unit": "ud.", "notes": null, "quantity": 1.00, "created_at": "2026-09-11T17:14:54.234462+00:00", "product_id": "p2", "project_id": "b3444724-d7aa-4bb4-8791-6b175365ebae", "room_or_area": null, "order_position": 0, "selected_for_rfq": true}, {"id": "cf88dc36-ea27-428b-864e-9bd16b0cfce6", "unit": "ud.", "notes": null, "quantity": 1.00, "created_at": "2026-09-11T18:15:07.730603+00:00", "product_id": "p1", "project_id": "a078dbfe-939b-42e7-aa5b-abe4b50ce9ed", "room_or_area": null, "order_position": 0, "selected_for_rfq": true}, {"id": "ee8f925c-50ce-45bf-8ca0-0ddffcfdb828", "unit": "ud.", "notes": null, "quantity": 1.00, "created_at": "2026-09-11T18:15:08.118923+00:00", "product_id": "p12", "project_id": "a078dbfe-939b-42e7-aa5b-abe4b50ce9ed", "room_or_area": null, "order_position": 0, "selected_for_rfq": true}, {"id": "f28ed362-80f0-4162-91f5-f281aeca599a", "unit": "ud.", "notes": null, "quantity": 1.00, "created_at": "2026-09-11T18:16:22.647917+00:00", "product_id": "p20", "project_id": "a078dbfe-939b-42e7-aa5b-abe4b50ce9ed", "room_or_area": null, "order_position": 0, "selected_for_rfq": true}, {"id": "ff4840de-15e6-428d-a1cf-cf9e6c2c2f54", "unit": "ud.", "notes": null, "quantity": 1.00, "created_at": "2026-09-11T17:14:53.845035+00:00", "product_id": "p1", "project_id": "b3444724-d7aa-4bb4-8791-6b175365ebae", "room_or_area": null, "order_position": 0, "selected_for_rfq": true}]$J$::jsonb);

DO $$
begin
  if md5(coalesce((select string_agg(to_jsonb(pr)::text, '|' order by pr.id) from public.projects pr where pr.owner_user_id = '46ea4397-f881-4db8-89e7-f164293a1143'), '')
      || '#' || coalesce((select string_agg(to_jsonb(pp)::text, '|' order by pp.id) from public.project_products pp where pp.project_id = any (array['a078dbfe-939b-42e7-aa5b-abe4b50ce9ed', 'b3444724-d7aa-4bb4-8791-6b175365ebae']::uuid[])), '')) <> '931b6f7abc65a175d4da71b89478fb38' then
    raise exception '43-LR: las filas restauradas no coinciden con la copia';
  end if;
end $$;
$RB$;
  h0 text; h1 text; f0 text; v_limpia boolean; v_rest boolean;
begin
  if md5(t_l) <> '7753afe8926d9895af1ee780dfeb9584' or md5(t_r) <> '9f96d6b23cd8688bfa6b91308e98b24d' then
    raise exception 'MOBAU_43_L43E: algún texto incrustado no coincide con su MD5' using errcode = 'MB997';
  end if;
  f0 := md5(coalesce((select string_agg(to_jsonb(pr)::text, '|' order by pr.id) from public.projects pr where pr.owner_user_id = '46ea4397-f881-4db8-89e7-f164293a1143'), '')
      || '#' || coalesce((select string_agg(to_jsonb(pp)::text, '|' order by pp.id) from public.project_products pp where pp.project_id = any (array['a078dbfe-939b-42e7-aa5b-abe4b50ce9ed', 'b3444724-d7aa-4bb4-8791-6b175365ebae']::uuid[])), ''));
  h0 := md5(md5(coalesce((select string_agg(id::text || status || owner_user_id::text || name || updated_at::text, '|' order by id) from public.projects where not (id = any (array['a078dbfe-939b-42e7-aa5b-abe4b50ce9ed', 'b3444724-d7aa-4bb4-8791-6b175365ebae']::uuid[]))), '')
      || coalesce((select string_agg(id::text || project_id::text || quantity::text || coalesce(unit, '-'), '|' order by id) from public.project_products where not (project_id = any (array['a078dbfe-939b-42e7-aa5b-abe4b50ce9ed', 'b3444724-d7aa-4bb4-8791-6b175365ebae']::uuid[]))), '')
      || coalesce((select string_agg(id::text || status, '|' order by id) from public.rfqs), '')
      || (select count(*)::text from public.rfq_distributors)
      || (select count(*)::text from public.moodboards)
      || coalesce((select string_agg(id::text || plan || role || plan_source || subscription_status, '|' order by id) from public.profiles), '')) || (select count(*)::text from public.projects) || ' / ' || (select count(*)::text from public.project_products) || ' / ' || (select count(*)::text from public.rfqs) || f0);
  execute t_l;
  v_limpia := not exists (select 1 from public.projects where owner_user_id = '46ea4397-f881-4db8-89e7-f164293a1143')
              and not exists (select 1 from public.project_products where project_id = any (array['a078dbfe-939b-42e7-aa5b-abe4b50ce9ed', 'b3444724-d7aa-4bb4-8791-6b175365ebae']::uuid[]));
  execute t_r;
  v_rest := md5(coalesce((select string_agg(to_jsonb(pr)::text, '|' order by pr.id) from public.projects pr where pr.owner_user_id = '46ea4397-f881-4db8-89e7-f164293a1143'), '')
      || '#' || coalesce((select string_agg(to_jsonb(pp)::text, '|' order by pp.id) from public.project_products pp where pp.project_id = any (array['a078dbfe-939b-42e7-aa5b-abe4b50ce9ed', 'b3444724-d7aa-4bb4-8791-6b175365ebae']::uuid[])), '')) = '931b6f7abc65a175d4da71b89478fb38';
  h1 := md5(md5(coalesce((select string_agg(id::text || status || owner_user_id::text || name || updated_at::text, '|' order by id) from public.projects where not (id = any (array['a078dbfe-939b-42e7-aa5b-abe4b50ce9ed', 'b3444724-d7aa-4bb4-8791-6b175365ebae']::uuid[]))), '')
      || coalesce((select string_agg(id::text || project_id::text || quantity::text || coalesce(unit, '-'), '|' order by id) from public.project_products where not (project_id = any (array['a078dbfe-939b-42e7-aa5b-abe4b50ce9ed', 'b3444724-d7aa-4bb4-8791-6b175365ebae']::uuid[]))), '')
      || coalesce((select string_agg(id::text || status, '|' order by id) from public.rfqs), '')
      || (select count(*)::text from public.rfq_distributors)
      || (select count(*)::text from public.moodboards)
      || coalesce((select string_agg(id::text || plan || role || plan_source || subscription_status, '|' order by id) from public.profiles), '')) || (select count(*)::text from public.projects) || ' / ' || (select count(*)::text from public.project_products) || ' / ' || (select count(*)::text from public.rfqs) || md5(coalesce((select string_agg(to_jsonb(pr)::text, '|' order by pr.id) from public.projects pr where pr.owner_user_id = '46ea4397-f881-4db8-89e7-f164293a1143'), '')
      || '#' || coalesce((select string_agg(to_jsonb(pp)::text, '|' order by pp.id) from public.project_products pp where pp.project_id = any (array['a078dbfe-939b-42e7-aa5b-abe4b50ce9ed', 'b3444724-d7aa-4bb4-8791-6b175365ebae']::uuid[])), '')));
  raise exception 'MOBAU_43_L43E limpia=% restaurada=% identico=% :: copia=% partida=%', v_limpia, v_rest, (h1 = h0), '931b6f7abc65a175d4da71b89478fb38', f0
    using errcode = 'MB990';
end $L43E$;

COMMIT;
