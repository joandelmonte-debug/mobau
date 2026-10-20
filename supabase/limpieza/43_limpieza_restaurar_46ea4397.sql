-- ============================================================
-- RECUPERACIÓN NO EJECUTADA (43 · restaurar los proyectos de la cuenta Hotmail desde la copia local) — no ejecutar sin aprobación explícita
-- ============================================================
-- Generado por generar_limpieza.py a partir de copia_46ea4397.json.
-- Vuelve a insertar los 2 proyectos y las 8 líneas con sus identificadores,
-- fechas y valores originales. El trigger de límite admite el proyecto
-- activo porque la cuenta Gratis (límite 1) no tendrá ninguno.
-- Al final, las filas deben dar la misma huella que la copia (931b6f7abc65a175d4da71b89478fb38).
-- Ejecutar completo, con el control MD5.
-- ============================================================

BEGIN;

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

COMMIT;
