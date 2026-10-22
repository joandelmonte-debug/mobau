-- ============================================================
-- PROPUESTA NO EJECUTADA (45-02 · código comercial del acabado) — no ejecutar sin aprobación explícita
-- ============================================================
-- Punto 45 · acabados sin código comercial.
--   product_finishes.code pasa a ser solo la clave técnica (oculta, estable;
--   la usan fotos, predeterminado, selección, líneas de proyecto y
--   cotización). El código comercial del acabado, opcional, es
--   product_finishes.reference_code (columna ya existente, validada y
--   aplicada por las funciones actuales).
--   Esta migración copia code → reference_code SOLO en los 22 acabados
--   aprobados verificados (códigos que ya se mostraban como «código ·
--   nombre»), sin tocar claves, fotos, líneas, productos ni propuestas.
--   No toca borradores ni propuestas (proposed_media).
-- Precondición: ninguna propuesta de cambio abierta con proposed_media, para
-- que ninguna propuesta anterior borre al aprobarse los códigos copiados.
-- Sin cambios de esquema, funciones ni permisos.
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
begin
  if current_user <> 'postgres' then
    raise exception '45-02: ejecutar como postgres';
  end if;
  if not exists (select 1 from supabase_migrations.schema_migrations where version = '20261025120000')
     or exists (select 1 from supabase_migrations.schema_migrations where version = '20261026120000') then
    raise exception '45-02: el registro de migraciones no es el esperado (45-01 registrada y 45-02 sin registrar)';
  end if;
  if (select count(*) from public.product_finishes) <> 22
     or exists (select 1 from public.product_finishes where reference_code is not null)
     or (select md5(string_agg(product_id || ':' || code || ':' || name || ':' || is_default || ':' || sort_order || ':' || coalesce(image_asset_id::text, '-'), '|' order by product_id, code)) from public.product_finishes) <> 'eae240b0e045ae1b10736442462cac3f'
     or (select count(*) from public.product_finishes f join p4502_set s using (product_id, code)) <> 22 then
    raise exception '45-02: los acabados no son el conjunto verificado (22, sin código comercial)';
  end if;
  if exists (select 1 from public.product_proposals
              where proposal_kind = 'update' and status in ('draft', 'submitted', 'changes_requested') and proposed_media is not null) then
    raise exception '45-02: hay propuestas de cambio abiertas con acabados o archivos; revisarlas antes de aplicar';
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
     set reference_code = f.code
    from p4502_set s
   where f.product_id = s.product_id and f.code = s.code and f.reference_code is null;
  get diagnostics n = row_count;
  if n <> 22 then
    raise exception '45-02: se esperaban 22 acabados y se actualizaron %', n;
  end if;
end $$;

DO $$
begin
  if (select count(*) from public.product_finishes f join p4502_set s using (product_id, code) where f.reference_code = f.code) <> 22
     or exists (select 1 from public.product_finishes f where not exists (select 1 from p4502_set s where s.product_id = f.product_id and s.code = f.code)) then
    raise exception '45-02: reference_code no quedó como se esperaba';
  end if;
  if md5(
    coalesce((select string_agg(product_id || ':' || code || ':' || name || ':' || is_default || ':' || sort_order || ':' || coalesce(image_asset_id::text, '-'), '|' order by product_id, code) from public.product_finishes), '') || '#' ||
    coalesce((select string_agg(id::text || ':' || coalesce(finish_code, '-'), '|' order by id) from public.product_assets), '') || '#' ||
    coalesce((select string_agg(id::text || ':' || product_id || ':' || coalesce(finish_code, '-') || ':' || quantity || ':' || unit, '|' order by id) from public.project_products), '') || '#' ||
    coalesce((select string_agg(id || ':' || updated_at::text, '|' order by id) from public.products), '') || '#' ||
    coalesce((select string_agg(id::text || ':' || updated_at::text, '|' order by id) from public.product_proposals), ''))
     <> current_setting('mobau.p4502_otros') then
    raise exception '%: ha cambiado algo distinto de reference_code (claves, fotos, líneas, productos o propuestas)', '45-02';
  end if;
end $$;

COMMIT;
