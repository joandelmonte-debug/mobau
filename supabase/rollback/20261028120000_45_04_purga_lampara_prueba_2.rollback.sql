-- ============================================================
-- PROPUESTA NO EJECUTADA (respaldo y recuperación de 45-04) — no ejecutar sin aprobación explícita
-- ============================================================
-- Reinserta spectro-02988ada y su precio (no la línea de proyecto quitada antes) tal como estaban antes de 45-04
-- (copia literal de las filas leídas el 2026-10-23).
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
    raise exception 'recuperación 45-04: ejecutar como postgres';
  end if;
  if exists (select 1 from public.products where id = 'spectro-02988ada')
     or exists (select 1 from public.product_prices where product_id = 'spectro-02988ada' or id = 'f9792725-c763-4981-a1ce-e306b0eecb2a') then
    raise exception 'recuperación 45-04: el producto o su precio ya existen; no se toca nada';
  end if;
end $$;

insert into public.products select * from jsonb_populate_record(null::public.products, $b${"id": "spectro-02988ada", "icon": null, "name": "lampara de pie", "brand": null, "space": null, "status": "archived", "finishes": null, "image_url": "https://www.igan-iluminacion.com/60863-zoom_producto/lampara-pie-circular-1l-e27-extensible-mdc.jpg", "lead_time": null, "materials": null, "created_at": "2026-09-21T14:09:26.915251+00:00", "retired_at": null, "retired_by": null, "trash_from": null, "trashed_at": null, "trashed_by": null, "updated_at": "2026-09-21T15:32:37.491221+00:00", "category_id": "iluminacion", "description": null, "environment": null, "purge_after": null, "subcategory": "Decorativa", "use_context": null, "availability": "en-stock", "light_source": null, "measurements": null, "cad_bim_3d_url": null, "cover_asset_id": null, "distributor_id": "spectro", "reference_code": null, "retired_reason": null, "color_temperature": null, "publication_status": "archived", "technical_sheet_url": null, "electrical_connection": null}$b$::jsonb);
insert into public.product_prices select * from jsonb_populate_record(null::public.product_prices, $b${"id": "f9792725-c763-4981-a1ce-e306b0eecb2a", "currency": "USD", "created_at": "2026-09-21T14:09:27.12534+00:00", "itbis_rate": null, "price_note": null, "product_id": "spectro-02988ada", "updated_at": "2026-09-21T14:09:27.12534+00:00", "price_amount": 100, "price_source": "distributor", "price_status": "quote_required", "includes_itbis": true, "price_reference": null, "price_reference_date": null}$b$::jsonb);

DO $$
declare
  o jsonb := $b${"id": "f9792725-c763-4981-a1ce-e306b0eecb2a", "currency": "USD", "created_at": "2026-09-21T14:09:27.12534+00:00", "itbis_rate": null, "price_note": null, "product_id": "spectro-02988ada", "updated_at": "2026-09-21T14:09:27.12534+00:00", "price_amount": 100, "price_source": "distributor", "price_status": "quote_required", "includes_itbis": true, "price_reference": null, "price_reference_date": null}$b$::jsonb;
  n jsonb;
begin
  if (select md5(to_jsonb(p)::text) from public.products p where p.id = 'spectro-02988ada') is distinct from 'a9250da55d459ce0eda96cc3a0233b5c' then
    raise exception 'recuperación 45-04: el producto restaurado no coincide con el original';
  end if;
  select to_jsonb(pp) into n from public.product_prices pp where pp.product_id = 'spectro-02988ada';
  if (n - 'updated_at') is distinct from (o - 'updated_at') then
    raise exception 'recuperación 45-04: el precio restaurado no coincide con el original';
  end if;
end $$;

COMMIT;
