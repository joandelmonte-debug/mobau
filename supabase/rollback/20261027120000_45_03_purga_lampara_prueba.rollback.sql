-- ============================================================
-- PROPUESTA NO EJECUTADA (respaldo y recuperación de 45-03) — no ejecutar sin aprobación explícita
-- ============================================================
-- Reinserta spectro-a7a2cfba y su precio tal como estaban antes de 45-03
-- (copia literal de las filas leídas el 2026-10-22).
--   * Se detiene si el producto o el precio ya existen, o si la fila
--     restaurada no coincide exactamente (MD5) con la original.
--   * Límite conocido: el trigger de product_prices fija updated_at a la
--     hora de la restauración; todos los demás campos del precio se
--     comprueban uno a uno.
--   * No borra el evento de purga de la auditoría (es de solo inserción):
--     el historial seguirá mostrando la purga.
-- Si se aplica, se registra como migración NUEVA tras confirmar su COMMIT.
-- Ejecutar completo.
-- ============================================================

BEGIN;

DO $$
begin
  if current_user <> 'postgres' then
    raise exception 'recuperación 45-03: ejecutar como postgres';
  end if;
  if exists (select 1 from public.products where id = 'spectro-a7a2cfba')
     or exists (select 1 from public.product_prices where product_id = 'spectro-a7a2cfba' or id = '95a8edea-b1f7-4dbd-8f60-2ecc3c2cf78d') then
    raise exception 'recuperación 45-03: el producto o su precio ya existen; no se toca nada';
  end if;
end $$;

insert into public.products select * from jsonb_populate_record(null::public.products, $b${"id": "spectro-a7a2cfba", "icon": null, "name": "lampara de pie", "brand": null, "space": "dormitorio", "status": "archived", "finishes": null, "image_url": "https://www.igan-iluminacion.com/60863-zoom_producto/lampara-pie-circular-1l-e27-extensible-mdc.jpg", "lead_time": null, "materials": null, "created_at": "2026-09-21T12:23:16.699463+00:00", "retired_at": null, "retired_by": null, "trash_from": null, "trashed_at": null, "trashed_by": null, "updated_at": "2026-09-21T12:53:44.513421+00:00", "category_id": "iluminacion", "description": null, "environment": null, "purge_after": null, "subcategory": "Decorativa", "use_context": "residencial", "availability": "bajo-pedido", "light_source": null, "measurements": null, "cad_bim_3d_url": null, "cover_asset_id": null, "distributor_id": "spectro", "reference_code": null, "retired_reason": null, "color_temperature": null, "publication_status": "archived", "technical_sheet_url": null, "electrical_connection": null}$b$::jsonb);
insert into public.product_prices select * from jsonb_populate_record(null::public.product_prices, $b${"id": "95a8edea-b1f7-4dbd-8f60-2ecc3c2cf78d", "currency": "USD", "created_at": "2026-09-21T12:23:16.893405+00:00", "itbis_rate": null, "price_note": null, "product_id": "spectro-a7a2cfba", "updated_at": "2026-09-21T12:23:16.893405+00:00", "price_amount": 100, "price_source": "distributor", "price_status": "published", "includes_itbis": true, "price_reference": null, "price_reference_date": null}$b$::jsonb);

DO $$
declare
  o jsonb := $b${"id": "95a8edea-b1f7-4dbd-8f60-2ecc3c2cf78d", "currency": "USD", "created_at": "2026-09-21T12:23:16.893405+00:00", "itbis_rate": null, "price_note": null, "product_id": "spectro-a7a2cfba", "updated_at": "2026-09-21T12:23:16.893405+00:00", "price_amount": 100, "price_source": "distributor", "price_status": "published", "includes_itbis": true, "price_reference": null, "price_reference_date": null}$b$::jsonb;
  n jsonb;
begin
  if (select md5(to_jsonb(p)::text) from public.products p where p.id = 'spectro-a7a2cfba') is distinct from '184760509b245183353d9150b03cd0fa' then
    raise exception 'recuperación 45-03: el producto restaurado no coincide con el original';
  end if;
  select to_jsonb(pp) into n from public.product_prices pp where pp.product_id = 'spectro-a7a2cfba';
  if (n - 'updated_at') is distinct from (o - 'updated_at') then
    raise exception 'recuperación 45-03: el precio restaurado no coincide con el original';
  end if;
end $$;

COMMIT;
