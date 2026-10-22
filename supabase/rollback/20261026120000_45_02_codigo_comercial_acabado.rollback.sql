-- ============================================================
-- PROPUESTA NO EJECUTADA (recuperación de 45-02) — no ejecutar sin aprobación explícita
-- ============================================================
-- Deshace SOLO lo que copió 45-02: reference_code → null en los mismos 22
-- acabados, y únicamente si siguen con reference_code = code. Si alguno se
-- ha eliminado o su código comercial ha cambiado después, se detiene sin
-- tocar nada (no sobrescribe cambios posteriores).
-- Sin cambios de esquema, funciones ni permisos. Con la interfaz del punto
-- 45 publicada, esos acabados se mostrarían solo con su nombre: revertir
-- también la interfaz.
-- Si se aplica, se registra como migración NUEVA tras confirmar su COMMIT.
-- Ejecutar completo.
-- ============================================================

BEGIN;

create temporary table p4502_set (product_id text, code text, primary key (product_id, code)) on commit drop;
insert into p4502_set (product_id, code) values
    ('spectro-16e21399', '93'),
    ('spectro-16e21399', '18'),
    ('spectro-16e21399', '58'),
    ('spectro-21cdc5fd', '25'),
    ('spectro-21cdc5fd', '11'),
    ('spectro-2e12589a', '07'),
    ('spectro-2e12589a', '08'),
    ('spectro-3470d67d', '08'),
    ('spectro-3470d67d', '07'),
    ('spectro-5add2cfd', '38'),
    ('spectro-5add2cfd', '56'),
    ('spectro-5add2cfd', '24'),
    ('spectro-8ae12824', '03'),
    ('spectro-8ae12824', '24'),
    ('spectro-8ae12824', '36'),
    ('spectro-b029fd1b', '93'),
    ('spectro-b029fd1b', '36'),
    ('spectro-b029fd1b', '24'),
    ('spectro-cb1cc62f', '11'),
    ('spectro-cb1cc62f', '25'),
    ('spectro-d3016bf1', '25'),
    ('spectro-d3016bf1', '11');

DO $$
declare
  faltan text;
  cambiados text;
begin
  if current_user <> 'postgres' then
    raise exception 'recuperación 45-02: ejecutar como postgres';
  end if;
  select string_agg(s.product_id || '/' || s.code, ', ') into faltan
    from p4502_set s where not exists (select 1 from public.product_finishes f where f.product_id = s.product_id and f.code = s.code);
  select string_agg(f.product_id || '/' || f.code, ', ') into cambiados
    from public.product_finishes f join p4502_set s using (product_id, code)
   where f.reference_code is distinct from f.code;
  if faltan is not null or cambiados is not null then
    raise exception 'recuperación 45-02: cambios posteriores, no se toca nada. Eliminados: %. Con otro código comercial: %',
      coalesce(faltan, 'ninguno'), coalesce(cambiados, 'ninguno');
  end if;
  perform set_config('mobau.p4502_otros', md5(
    coalesce((select string_agg(product_id || ':' || code || ':' || name || ':' || is_default || ':' || sort_order || ':' || coalesce(image_asset_id::text, '-'), '|' order by product_id, code) from public.product_finishes), '') || '#' ||
    coalesce((select string_agg(id::text || ':' || coalesce(finish_code, '-'), '|' order by id) from public.product_assets), '') || '#' ||
    coalesce((select string_agg(id::text || ':' || product_id || ':' || coalesce(finish_code, '-') || ':' || quantity || ':' || unit, '|' order by id) from public.project_products), '') || '#' ||
    coalesce((select string_agg(id || ':' || updated_at::text, '|' order by id) from public.products), '') || '#' ||
    coalesce((select string_agg(id::text || ':' || updated_at::text, '|' order by id) from public.product_proposals), '')), true);
end $$;

DO $$
declare
  n int;
begin
  update public.product_finishes f
     set reference_code = null
    from p4502_set s
   where f.product_id = s.product_id and f.code = s.code and f.reference_code = f.code;
  get diagnostics n = row_count;
  if n <> 22 then
    raise exception 'recuperación 45-02: se esperaban 22 acabados y se actualizaron %', n;
  end if;
end $$;

DO $$
begin
  if exists (select 1 from public.product_finishes f join p4502_set s using (product_id, code) where f.reference_code is not null) then
    raise exception 'recuperación 45-02: reference_code no quedó como se esperaba';
  end if;
  if md5(
    coalesce((select string_agg(product_id || ':' || code || ':' || name || ':' || is_default || ':' || sort_order || ':' || coalesce(image_asset_id::text, '-'), '|' order by product_id, code) from public.product_finishes), '') || '#' ||
    coalesce((select string_agg(id::text || ':' || coalesce(finish_code, '-'), '|' order by id) from public.product_assets), '') || '#' ||
    coalesce((select string_agg(id::text || ':' || product_id || ':' || coalesce(finish_code, '-') || ':' || quantity || ':' || unit, '|' order by id) from public.project_products), '') || '#' ||
    coalesce((select string_agg(id || ':' || updated_at::text, '|' order by id) from public.products), '') || '#' ||
    coalesce((select string_agg(id::text || ':' || updated_at::text, '|' order by id) from public.product_proposals), ''))
     <> current_setting('mobau.p4502_otros') then
    raise exception '%: ha cambiado algo distinto de reference_code (claves, fotos, líneas, productos o propuestas)', 'recuperación 45-02';
  end if;
end $$;

COMMIT;
