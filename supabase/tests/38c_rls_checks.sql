-- ============================================================
-- PROPUESTA NO EJECUTADA (38-C) — no ejecutar sin aprobación explícita
-- ============================================================
-- 38-C · Pruebas de RLS, permisos y triggers de propuestas, más una
-- regresión breve de 38-B, en una transacción revertida.
-- ------------------------------------------------------------
-- Ejecutar SOLO después de aplicar 38-C 01–04. Pensado para el editor
-- SQL de Supabase (rol postgres, miembro de anon y authenticated).
-- Mismo patrón que supabase/tests/38b_rls_checks.sql.
--
-- Identidades (sin crear ni modificar cuentas ni roles):
--   * Distribuidor A: el distribuidor verificado real (solo lectura de
--     sus datos; sus productos reales no se tocan).
--   * Distribuidor B: distribuidor AUXILIAR sin usuario ('rls38c-dist-b'),
--     creado como postgres dentro de cada prueba. Sirve para comprobar
--     que A no ve ni toca lo de B.
--   * Profesional real (role 'individual'): para él
--     my_verified_distributor_id() es null, el mismo camino que un
--     distribuidor sin verificar (que, por decisión, se probará más
--     adelante con una cuenta real).
--   * anon.
--
-- Datos auxiliares (solo dentro de la subtransacción de cada prueba):
--   producto 'rls38c-a' (de A, borrador), distribuidor 'rls38c-dist-b',
--   producto 'rls38c-b' (de B) y propuestas con ids fijos de prueba.
--   38-C 04: producto 'rls38c-a2' (de A, con categoría y subcategoría
--   reales tomadas de categories) y propuestas create de A y de B.
--   Casos K01–K34: tipos create/update, D1 (duplicados), D2 (obligatorios
--   al enviar), D3 (subcategoría nueva), D5 (clasificación en update) y
--   precio en create (K30–K34; K34 vuelve a postgres con RESET ROLE para
--   comparar la huella completa de product_prices).
--   La advertencia de la web por nombre ya existente es solo UX: no se
--   prueba aquí porque no es una restricción de base de datos.
--
-- NADA queda guardado: BEGIN … ROLLBACK, cada prueba en su propia
-- subtransacción deshecha (MB001) y error final MB999 con los
-- resultados en JSON (aborta la transacción aunque se hiciera COMMIT).
-- Sin IDs reales, correos ni secretos en el archivo.
-- Recomendado además: volver a ejecutar supabase/tests/38b_rls_checks.sql.
-- ============================================================

BEGIN;

DO $$
declare
  v_sup uuid; v_sup_dist text; v_pro uuid; n_pub int;
  a1 constant text := '00000000-0000-4000-8000-0000000c0a01';
  b1 constant text := '00000000-0000-4000-8000-0000000c0b01';
  v_prod_a text; v_dist_b text; v_prod_b text;
  v_prop_a_draft text; v_prop_a_empty text; v_prop_a_submitted text; v_prop_a_changes text; v_prop_b text;
  -- 38-C 04
  a2 constant text := '00000000-0000-4000-8000-0000000c0a02';
  b2 constant text := '00000000-0000-4000-8000-0000000c0b02';
  v_name constant text := 'Lámpara RLS 38-C';
  v_new_sub constant text := 'Subcategoría nueva RLS 38-C';
  v_cat1 text; v_sub1 text; v_cat2 text; v_sub2 text;
  v_full jsonb;
  v_prod_a2 text; v_create_a text; v_create_b text; v_withdraw_a text;
  v_prices_fp text;
  r jsonb := '[]'::jsonb;
  t record;
  i int;
  v_got text; v_n bigint; v_ok boolean; v_stmt text;
  n_total int := 0; n_ok int := 0;
begin
  -- ---------- datos de partida (lectura como postgres) ----------
  select dp.user_id, dp.distributor_id into v_sup, v_sup_dist
    from public.distributor_profiles dp join public.profiles p on p.id = dp.user_id
   where p.role = 'supplier' and dp.verification_status = 'verified' and dp.distributor_id is not null
   order by dp.created_at limit 1;
  select p.id into v_pro from public.profiles p where p.role = 'individual' order by p.created_at limit 1;
  select count(*) into n_pub from public.products where publication_status = 'published';
  if v_sup is null or v_pro is null then
    raise exception 'MOBAU_38C: faltan datos de partida (distribuidor verificado o profesional)' using errcode = 'MB998';
  end if;
  -- 38-C 04: dos categorías reales con al menos una subcategoría.
  select c.id, c.subcategories[1] into v_cat1, v_sub1
    from public.categories c where cardinality(c.subcategories) >= 1 order by c.id limit 1;
  select c.id, c.subcategories[1] into v_cat2, v_sub2
    from public.categories c where cardinality(c.subcategories) >= 1 and c.id <> v_cat1 order by c.id limit 1;
  if v_cat1 is null or v_cat2 is null then
    raise exception 'MOBAU_38C: faltan dos categorías con subcategorías' using errcode = 'MB998';
  end if;
  -- Huella de product_prices antes de las pruebas (K34).
  select count(*)::text || ':' || coalesce(md5(string_agg(pp::text, '|' order by pp::text)), '')
    into v_prices_fp from public.product_prices pp;

  -- ---------- SQL auxiliar (como postgres, dentro de cada prueba) ----------
  v_prod_a := format('insert into public.products (id, name, distributor_id, category_id, publication_status) values (%L, %L, %L, %L, %L)',
                     'rls38c-a', 'Producto A (prueba RLS 38-C)', v_sup_dist, 'iluminacion', 'draft');
  v_dist_b := format('insert into public.distributors (id, name) values (%L, %L)', 'rls38c-dist-b', 'Distribuidor B (prueba RLS 38-C)');
  v_prod_b := format('insert into public.products (id, name, distributor_id, category_id, publication_status) values (%L, %L, %L, %L, %L)',
                     'rls38c-b', 'Producto B (prueba RLS 38-C)', 'rls38c-dist-b', 'iluminacion', 'draft');
  v_prop_a_draft := format('insert into public.product_proposals (id, product_id, distributor_id, status, proposed_changes) values (%L, %L, %L, %L, %L)',
                           a1, 'rls38c-a', v_sup_dist, 'draft', '{"name": "Nombre propuesto"}');
  v_prop_a_empty := format('insert into public.product_proposals (id, product_id, distributor_id, status, proposed_changes) values (%L, %L, %L, %L, %L)',
                           a1, 'rls38c-a', v_sup_dist, 'draft', '{}');
  v_prop_a_submitted := format('insert into public.product_proposals (id, product_id, distributor_id, status, proposed_changes) values (%L, %L, %L, %L, %L)',
                               a1, 'rls38c-a', v_sup_dist, 'submitted', '{"name": "Nombre propuesto"}');
  v_prop_a_changes := format('insert into public.product_proposals (id, product_id, distributor_id, status, proposed_changes) values (%L, %L, %L, %L, %L)',
                             a1, 'rls38c-a', v_sup_dist, 'changes_requested', '{"name": "Nombre propuesto"}');
  v_prop_b := format('insert into public.product_proposals (id, product_id, distributor_id, status, proposed_changes) values (%L, %L, %L, %L, %L)',
                     b1, 'rls38c-b', 'rls38c-dist-b', 'draft', '{"name": "Propuesta de B"}');
  -- 38-C 04
  v_full := jsonb_build_object('name', v_name, 'description', 'Descripción de prueba RLS 38-C',
                               'category_id', v_cat1, 'subcategory', v_sub1, 'availability', 'por-confirmar');
  v_prod_a2 := format('insert into public.products (id, name, distributor_id, category_id, subcategory, publication_status) values (%L, %L, %L, %L, %L, %L)',
                      'rls38c-a2', 'Producto A2 (prueba RLS 38-C 04)', v_sup_dist, v_cat1, v_sub1, 'draft');
  v_create_a := format('insert into public.product_proposals (id, proposal_kind, distributor_id, status, proposed_changes) values (%L, %L, %L, %L, %L)',
                       a2, 'create', v_sup_dist, 'draft', jsonb_build_object('name', v_name)::text);
  v_create_b := format('insert into public.product_proposals (id, proposal_kind, distributor_id, status, proposed_changes) values (%L, %L, %L, %L, %L)',
                       b2, 'create', 'rls38c-dist-b', 'draft', jsonb_build_object('name', v_name)::text);
  v_withdraw_a := format('update public.product_proposals set status = %L where id = %L', 'withdrawn', a2);

  -- kind: 'count' (la última sentencia devuelve un número) | 'exec' (se mide row_count de la última)
  -- expect: número exacto | 'ok' (al menos 1 fila) | 'rows=0' | código SQLSTATE (42501, 23514, 23505)
  -- role '-' = postgres sin cambio de rol. setup: como postgres, antes del cambio de rol.
  for t in
    select * from (values
      -- Crear
      ('P01 A crea una propuesta en borrador',               'authenticated', v_sup::text, array[v_prod_a]::text[],
         array[format('insert into public.product_proposals (product_id, proposed_changes) values (%L, %L)', 'rls38c-a', '{"name": "Nombre propuesto"}')]::text[], 'exec', 'ok'),
      ('P02 A no puede fijar distributor_id',                 'authenticated', v_sup::text, array[v_prod_a, v_dist_b],
         array[format('insert into public.product_proposals (product_id, distributor_id, proposed_changes) values (%L, %L, %L)', 'rls38c-a', 'rls38c-dist-b', '{"name": "x"}')], 'exec', '42501'),
      ('P03 A no puede crear ya enviada (status)',            'authenticated', v_sup::text, array[v_prod_a],
         array[format('insert into public.product_proposals (product_id, status, proposed_changes) values (%L, %L, %L)', 'rls38c-a', 'submitted', '{"name": "x"}')], 'exec', '42501'),
      ('P04 A no propone sobre un producto de B',             'authenticated', v_sup::text, array[v_dist_b, v_prod_b],
         array[format('insert into public.product_proposals (product_id, proposed_changes) values (%L, %L)', 'rls38c-b', '{"name": "x"}')], 'exec', '42501'),
      ('P05 campo fuera de la lista cerrada',                 'authenticated', v_sup::text, array[v_prod_a],
         array[format('insert into public.product_proposals (product_id, proposed_changes) values (%L, %L)', 'rls38c-a', '{"price": 10}')], 'exec', '23514'),
      ('P06 URL de imagen inválida',                          'authenticated', v_sup::text, array[v_prod_a],
         array[format('insert into public.product_proposals (product_id, proposed_changes) values (%L, %L)', 'rls38c-a', '{"image_url": "ftp://x"}')], 'exec', '23514'),
      ('P07 categoría inexistente',                           'authenticated', v_sup::text, array[v_prod_a],
         array[format('insert into public.product_proposals (product_id, proposed_changes) values (%L, %L)', 'rls38c-a', '{"category_id": "no-existe"}')], 'exec', '23514'),
      ('P08 precio publicado sin importe',                    'authenticated', v_sup::text, array[v_prod_a],
         array[format('insert into public.product_proposals (product_id, proposed_price_status) values (%L, %L)', 'rls38c-a', 'published')], 'exec', '23514'),
      ('P09 segunda propuesta abierta sobre el mismo producto', 'authenticated', v_sup::text, array[v_prod_a, v_prop_a_draft],
         array[format('insert into public.product_proposals (product_id, proposed_changes) values (%L, %L)', 'rls38c-a', '{"name": "y"}')], 'exec', '23505'),
      -- Ver
      ('P10 A ve su propuesta',                               'authenticated', v_sup::text, array[v_prod_a, v_prop_a_draft],
         array[format('select count(*) from public.product_proposals where id = %L', a1)], 'count', '1'),
      ('P11 A NO ve la propuesta de B',                       'authenticated', v_sup::text, array[v_dist_b, v_prod_b, v_prop_b],
         array[format('select count(*) from public.product_proposals where id = %L', b1)], 'count', '0'),
      ('P12 A ve el historial de su propuesta',               'authenticated', v_sup::text, array[v_prod_a, v_prop_a_draft],
         array[format('select count(*) from public.proposal_events where proposal_id = %L', a1)], 'count', '1'),
      ('P13 A NO ve el historial de B',                       'authenticated', v_sup::text, array[v_dist_b, v_prod_b, v_prop_b],
         array[format('select count(*) from public.proposal_events where proposal_id = %L', b1)], 'count', '0'),
      -- Editar
      ('P14 A edita proposed_changes en borrador',            'authenticated', v_sup::text, array[v_prod_a, v_prop_a_draft],
         array[format('update public.product_proposals set proposed_changes = %L where id = %L', '{"name": "Otro nombre"}', a1)], 'exec', 'ok'),
      ('P15 A NO puede escribir rejection_reason',            'authenticated', v_sup::text, array[v_prod_a, v_prop_a_draft],
         array[format('update public.product_proposals set rejection_reason = %L where id = %L', 'x', a1)], 'exec', '42501'),
      ('P16 A NO puede cambiar product_id',                   'authenticated', v_sup::text, array[v_prod_a, v_prop_a_draft],
         array[format('update public.product_proposals set product_id = %L where id = %L', 'rls38c-a', a1)], 'exec', '42501'),
      ('P17 A NO edita una propuesta enviada',                'authenticated', v_sup::text, array[v_prod_a, v_prop_a_submitted],
         array[format('update public.product_proposals set proposed_changes = %L where id = %L', '{"name": "z"}', a1)], 'exec', '42501'),
      ('P18 A NO toca una propuesta de B (0 filas)',          'authenticated', v_sup::text, array[v_dist_b, v_prod_b, v_prop_b],
         array[format('update public.product_proposals set proposed_changes = %L where id = %L', '{"name": "z"}', b1)], 'exec', 'rows=0'),
      -- Transiciones
      ('P19 A NO pasa de draft a approved',                   'authenticated', v_sup::text, array[v_prod_a, v_prop_a_draft],
         array[format('update public.product_proposals set status = %L where id = %L', 'approved', a1)], 'exec', '42501'),
      ('P20 A retira un borrador',                            'authenticated', v_sup::text, array[v_prod_a, v_prop_a_draft],
         array[format('update public.product_proposals set status = %L where id = %L', 'withdrawn', a1)], 'exec', 'ok'),
      ('P21 A envía: se guardan copia y fecha de envío',      'authenticated', v_sup::text, array[v_prod_a, v_prop_a_draft],
         array[format('with u as (update public.product_proposals set status = %L where id = %L returning (product_snapshot is not null and submitted_at is not null) as ok) select count(*) from u where ok', 'submitted', a1)], 'count', '1'),
      ('P22 enviar deja dos eventos en el historial',         'authenticated', v_sup::text, array[v_prod_a, v_prop_a_draft],
         array[format('update public.product_proposals set status = %L where id = %L', 'submitted', a1),
               format('select count(*) from public.proposal_events where proposal_id = %L', a1)], 'count', '2'),
      ('P23 A NO envía una propuesta vacía',                  'authenticated', v_sup::text, array[v_prod_a, v_prop_a_empty],
         array[format('update public.product_proposals set status = %L where id = %L', 'submitted', a1)], 'exec', '23514'),
      ('P24 A retira una propuesta enviada',                  'authenticated', v_sup::text, array[v_prod_a, v_prop_a_submitted],
         array[format('update public.product_proposals set status = %L where id = %L', 'withdrawn', a1)], 'exec', 'ok'),
      ('P25 reenviar tras cambios solicitados sube la versión', 'authenticated', v_sup::text, array[v_prod_a, v_prop_a_changes],
         array[format('with u as (update public.product_proposals set status = %L where id = %L returning version) select max(version) from u', 'submitted', a1)], 'count', '2'),
      ('P26 A retira con cambios solicitados',                'authenticated', v_sup::text, array[v_prod_a, v_prop_a_changes],
         array[format('update public.product_proposals set status = %L where id = %L', 'withdrawn', a1)], 'exec', 'ok'),
      -- Borrar y escribir historial
      ('P27 A NO borra su propuesta',                         'authenticated', v_sup::text, array[v_prod_a, v_prop_a_draft],
         array[format('delete from public.product_proposals where id = %L', a1)], 'exec', '42501'),
      ('P28 A NO escribe en el historial',                    'authenticated', v_sup::text, array[v_prod_a, v_prop_a_draft],
         array[format('insert into public.proposal_events (proposal_id, actor_kind, to_status, version) values (%L, %L, %L, 1)', a1, 'distributor', 'draft')], 'exec', '42501'),
      -- Otras cuentas
      ('P29 profesional (sin empresa verificada) NO crea propuestas', 'authenticated', v_pro::text, array[v_prod_a],
         array[format('insert into public.product_proposals (product_id, proposed_changes) values (%L, %L)', 'rls38c-a', '{"name": "x"}')], 'exec', '42501'),
      ('P30 profesional NO ve propuestas',                    'authenticated', v_pro::text, array[v_prod_a, v_prop_a_draft],
         array['select count(*) from public.product_proposals'], 'count', '0'),
      ('P31 anon NO lee propuestas',                          'anon', null, array[v_prod_a, v_prop_a_draft],
         array['select count(*) from public.product_proposals'], 'count', '42501'),
      ('P32 anon NO crea propuestas',                         'anon', null, array[v_prod_a],
         array[format('insert into public.product_proposals (product_id, proposed_changes) values (%L, %L)', 'rls38c-a', '{"name": "x"}')], 'exec', '42501'),
      ('P33 anon NO lee el historial',                        'anon', null, array[v_prod_a, v_prop_a_draft],
         array['select count(*) from public.proposal_events'], 'count', '42501'),
      -- Regresión 38-B
      ('R01 anon: total de productos = publicados',           'anon', null, array[v_prod_a],
         array['select count(*) from public.products'], 'count', n_pub::text),
      ('R02 A ve su producto en borrador',                    'authenticated', v_sup::text, array[v_prod_a],
         array[format('select count(*) from public.products where id = %L', 'rls38c-a')], 'count', '1'),
      ('R03 profesional NO ve el borrador de A',              'authenticated', v_pro::text, array[v_prod_a],
         array[format('select count(*) from public.products where id = %L', 'rls38c-a')], 'count', '0'),
      ('R04 A NO crea productos',                             'authenticated', v_sup::text, null::text[],
         array[format('insert into public.products (name, category_id) values (%L, %L)', 'RLS', 'iluminacion')], 'exec', '42501'),
      ('R05 A NO edita precios',                              'authenticated', v_sup::text, null::text[],
         array['update public.product_prices set price_status = price_status'], 'exec', '42501'),
      ('R06 anon sin permiso sobre product_prices (39-06)',   'anon', null, null::text[],
         array['select count(*) from public.product_prices'], 'exec', '42501'),
      ('R07 políticas de 38-B y 38-C vigentes = 43 (40 de 38-B + 4 de 38-C − product_prices_select_authenticated, sustituida en 39-06)', '-', null, null::text[],
         array['select count(*) from pg_policies where schemaname = ''public'' and policyname not in (''product_proposals_select_mobau'', ''proposal_events_select_mobau'', ''products_select_mobau'', ''product_prices_select_own'', ''product_prices_select_mobau'') /* 39 y 39-06: se excluyen las 5 políticas añadidas; el total real (48) lo comprueba R01 de 39_moderation_checks.sql */'], 'count', '43'),
      -- 38-C 04 · tipos
      ('K01 A crea un producto nuevo en borrador sin product_id', 'authenticated', v_sup::text, null::text[],
         array[format('insert into public.product_proposals (proposal_kind, proposed_changes) values (%L, %L)', 'create', '{"name": "Producto nuevo RLS 38-C K01"}')], 'exec', 'ok'),
      ('K02 create con product_id: rechazado',                 'authenticated', v_sup::text, array[v_prod_a],
         array[format('insert into public.product_proposals (proposal_kind, product_id, proposed_changes) values (%L, %L, %L)', 'create', 'rls38c-a', '{"name": "x"}')], 'exec', '23514'),
      ('K03 update sin product_id: rechazado',                 'authenticated', v_sup::text, null::text[],
         array[format('insert into public.product_proposals (proposal_kind, proposed_changes) values (%L, %L)', 'update', '{"name": "x"}')], 'exec', '23514'),
      ('K04 borrador create sin nombre: rechazado',            'authenticated', v_sup::text, null::text[],
         array[format('insert into public.product_proposals (proposal_kind, proposed_changes) values (%L, %L)', 'create', '{"description": "x"}')], 'exec', '23514'),
      -- 38-C 04 · D2 obligatorios al enviar create
      ('K05 enviar create sin nombre: rechazado',              'authenticated', v_sup::text, array[v_create_a],
         array[format('update public.product_proposals set proposed_changes = %L, status = %L where id = %L', (v_full - 'name')::text, 'submitted', a2)], 'exec', '23514'),
      ('K06 enviar create sin descripción: rechazado',         'authenticated', v_sup::text, array[v_create_a],
         array[format('update public.product_proposals set proposed_changes = %L, status = %L where id = %L', (v_full - 'description')::text, 'submitted', a2)], 'exec', '23514'),
      ('K07 enviar create sin categoría: rechazado',           'authenticated', v_sup::text, array[v_create_a],
         array[format('update public.product_proposals set proposed_changes = %L, proposed_new_subcategory = %L, status = %L where id = %L', (v_full - 'category_id' - 'subcategory')::text, v_new_sub, 'submitted', a2)], 'exec', '23514'),
      ('K08 enviar create sin subcategoría ni nueva: rechazado', 'authenticated', v_sup::text, array[v_create_a],
         array[format('update public.product_proposals set proposed_changes = %L, status = %L where id = %L', (v_full - 'subcategory')::text, 'submitted', a2)], 'exec', '23514'),
      ('K09 enviar create sin disponibilidad: rechazado',      'authenticated', v_sup::text, array[v_create_a],
         array[format('update public.product_proposals set proposed_changes = %L, status = %L where id = %L', (v_full - 'availability')::text, 'submitted', a2)], 'exec', '23514'),
      ('K10 enviar create completo: sin copia de producto y con fecha', 'authenticated', v_sup::text, array[v_create_a],
         array[format('with u as (update public.product_proposals set proposed_changes = %L, status = %L where id = %L returning (product_snapshot is null and submitted_at is not null) as ok) select count(*) from u where ok', v_full::text, 'submitted', a2)], 'count', '1'),
      ('K11 enviar create con subcategoría nueva',             'authenticated', v_sup::text, array[v_create_a],
         array[format('update public.product_proposals set proposed_changes = %L, proposed_new_subcategory = %L, status = %L where id = %L', (v_full - 'subcategory')::text, v_new_sub, 'submitted', a2)], 'exec', 'ok'),
      -- 38-C 04 · D1 duplicados
      ('K12 segundo create abierto con el mismo nombre normalizado', 'authenticated', v_sup::text, array[v_create_a],
         array[format('insert into public.product_proposals (proposal_kind, proposed_changes) values (%L, %L)', 'create', jsonb_build_object('name', '  lámpara   rls 38-c ')::text)], 'exec', '23505'),
      ('K13 mismo nombre en otra empresa: permitido',          'authenticated', v_sup::text, array[v_dist_b, v_create_b],
         array[format('insert into public.product_proposals (proposal_kind, proposed_changes) values (%L, %L)', 'create', jsonb_build_object('name', v_name)::text)], 'exec', 'ok'),
      ('K14 mismo nombre tras retirar el anterior: permitido', 'authenticated', v_sup::text, array[v_create_a, v_withdraw_a],
         array[format('insert into public.product_proposals (proposal_kind, proposed_changes) values (%L, %L)', 'create', jsonb_build_object('name', v_name)::text)], 'exec', 'ok'),
      -- 38-C 04 · D5 clasificación en update
      ('K15 update de marca y precio sin tocar clasificación', 'authenticated', v_sup::text, array[v_prod_a],
         array[format('insert into public.product_proposals (proposal_kind, product_id, proposed_changes, proposed_price_status) values (%L, %L, %L, %L)', 'update', 'rls38c-a', '{"brand": "Marca RLS"}', 'quote_required'),
               format('update public.product_proposals set status = %L where product_id = %L and status = %L', 'submitted', 'rls38c-a', 'draft')], 'exec', 'ok'),
      ('K16 update cambia categoría sin subcategoría: rechazado', 'authenticated', v_sup::text, array[v_prod_a2],
         array[format('insert into public.product_proposals (proposal_kind, product_id, proposed_changes) values (%L, %L, %L)', 'update', 'rls38c-a2', jsonb_build_object('category_id', v_cat2)::text)], 'exec', '23514'),
      ('K17 update cambia categoría con subcategoría ajena: rechazado', 'authenticated', v_sup::text, array[v_prod_a2],
         array[format('insert into public.product_proposals (proposal_kind, product_id, proposed_changes) values (%L, %L, %L)', 'update', 'rls38c-a2', jsonb_build_object('category_id', v_cat2, 'subcategory', 'no-existe-rls38c')::text)], 'exec', '23514'),
      ('K18 update cambia categoría con subcategoría válida', 'authenticated', v_sup::text, array[v_prod_a2],
         array[format('insert into public.product_proposals (proposal_kind, product_id, proposed_changes) values (%L, %L, %L)', 'update', 'rls38c-a2', jsonb_build_object('category_id', v_cat2, 'subcategory', v_sub2)::text)], 'exec', 'ok'),
      ('K19 update cambia categoría con subcategoría nueva',  'authenticated', v_sup::text, array[v_prod_a2],
         array[format('insert into public.product_proposals (proposal_kind, product_id, proposed_changes, proposed_new_subcategory) values (%L, %L, %L, %L)', 'update', 'rls38c-a2', jsonb_build_object('category_id', v_cat2)::text, v_new_sub)], 'exec', 'ok'),
      ('K20 update solo con subcategoría nueva, y se envía',  'authenticated', v_sup::text, array[v_prod_a2],
         array[format('insert into public.product_proposals (proposal_kind, product_id, proposed_new_subcategory) values (%L, %L, %L)', 'update', 'rls38c-a2', v_new_sub),
               format('update public.product_proposals set status = %L where product_id = %L and status = %L', 'submitted', 'rls38c-a2', 'draft')], 'exec', 'ok'),
      ('K21 subcategoría de la lista y nueva a la vez: rechazado', 'authenticated', v_sup::text, array[v_prod_a2],
         array[format('insert into public.product_proposals (proposal_kind, product_id, proposed_changes, proposed_new_subcategory) values (%L, %L, %L, %L)', 'update', 'rls38c-a2', jsonb_build_object('subcategory', v_sub1)::text, v_new_sub)], 'exec', '23514'),
      ('K22 subcategoría nueva que ya existe (otra caja): rechazado', 'authenticated', v_sup::text, array[v_prod_a2],
         array[format('insert into public.product_proposals (proposal_kind, product_id, proposed_new_subcategory) values (%L, %L, %L)', 'update', 'rls38c-a2', upper(v_sub1))], 'exec', '23514'),
      ('K23 subcategoría propuesta vacía: rechazado',          'authenticated', v_sup::text, array[v_prod_a2],
         array[format('insert into public.product_proposals (proposal_kind, product_id, proposed_changes) values (%L, %L, %L)', 'update', 'rls38c-a2', '{"subcategory": null}')], 'exec', '23514'),
      -- 38-C 04 · permisos, historial y otras cuentas
      ('K24 A NO cambia el tipo de una propuesta',             'authenticated', v_sup::text, array[v_prod_a, v_prop_a_draft],
         array[format('update public.product_proposals set proposal_kind = %L where id = %L', 'create', a1)], 'exec', '42501'),
      ('K25 el historial guarda el tipo create',               'authenticated', v_sup::text, null::text[],
         array[format('insert into public.product_proposals (proposal_kind, proposed_changes) values (%L, %L)', 'create', '{"name": "Producto nuevo RLS 38-C K25"}'),
               format('select count(*) from public.proposal_events e join public.product_proposals p on p.id = e.proposal_id where p.proposed_changes ->> %L = %L and e.payload ->> %L = %L', 'name', 'Producto nuevo RLS 38-C K25', 'proposal_kind', 'create')], 'count', '1'),
      ('K26 A NO ve el producto nuevo propuesto por B',        'authenticated', v_sup::text, array[v_dist_b, v_create_b],
         array[format('select count(*) from public.product_proposals where id = %L', b2)], 'count', '0'),
      ('K27 profesional NO crea un producto nuevo',            'authenticated', v_pro::text, null::text[],
         array[format('insert into public.product_proposals (proposal_kind, proposed_changes) values (%L, %L)', 'create', '{"name": "x"}')], 'exec', '42501'),
      ('K28 anon NO crea un producto nuevo',                   'anon', null, null::text[],
         array[format('insert into public.product_proposals (proposal_kind, proposed_changes) values (%L, %L)', 'create', '{"name": "x"}')], 'exec', '42501'),
      ('K29 propuestas no tocan products ni product_prices de A', 'authenticated', v_sup::text, array[v_prod_a2],
         array[format('insert into public.product_proposals (proposal_kind, product_id, proposed_changes, proposed_price_status, proposed_price_amount) values (%L, %L, %L, %L, %L)', 'update', 'rls38c-a2', '{"name": "Nombre cambiado K29"}', 'published', '99.00'),
               format('update public.product_proposals set status = %L where product_id = %L and status = %L', 'submitted', 'rls38c-a2', 'draft'),
               format('select count(*) from public.products where id = %L and name = %L', 'rls38c-a2', 'Producto A2 (prueba RLS 38-C 04)')], 'count', '1'),
      -- 38-C 04 · precio en create (restricciones de 38-C 01)
      ('K30 create con precio publicado sin importe: rechazado', 'authenticated', v_sup::text, null::text[],
         array[format('insert into public.product_proposals (proposal_kind, proposed_changes, proposed_price_status) values (%L, %L, %L)', 'create', '{"name": "Producto nuevo RLS 38-C K30"}', 'published')], 'exec', '23514'),
      ('K31 create con importe sin estado de precio: rechazado', 'authenticated', v_sup::text, null::text[],
         array[format('insert into public.product_proposals (proposal_kind, proposed_changes, proposed_price_amount) values (%L, %L, %L)', 'create', '{"name": "Producto nuevo RLS 38-C K31"}', '10.00')], 'exec', '23514'),
      ('K32 create con importe negativo: rechazado',          'authenticated', v_sup::text, null::text[],
         array[format('insert into public.product_proposals (proposal_kind, proposed_changes, proposed_price_status, proposed_price_amount) values (%L, %L, %L, %L)', 'create', '{"name": "Producto nuevo RLS 38-C K32"}', 'published', '-1.00')], 'exec', '23514'),
      ('K33 create con precio válido',                        'authenticated', v_sup::text, null::text[],
         array[format('insert into public.product_proposals (proposal_kind, proposed_changes, proposed_price_status, proposed_price_amount) values (%L, %L, %L, %L)', 'create', '{"name": "Producto nuevo RLS 38-C K33"}', 'published', '120.00')], 'exec', 'ok'),
      ('K34 enviar create con precio no toca product_prices ni products', 'authenticated', v_sup::text, array[v_create_a],
         array[format('update public.product_proposals set proposed_changes = %L, proposed_price_status = %L, proposed_price_amount = %L, status = %L where id = %L', v_full::text, 'published', '150.00', 'submitted', a2),
               'reset role',
               format('select count(*) from public.product_proposals pr where pr.id = %L and pr.status = %L and pr.proposed_price_amount = 150 and pr.product_snapshot is null'
                      || ' and (select count(*)::text || %L || coalesce(md5(string_agg(pp::text, %L order by pp::text)), %L) from public.product_prices pp) = %L'
                      || ' and not exists (select 1 from public.products p where p.name = %L)',
                      a2, 'submitted', ':', '|', '', v_prices_fp, v_name)], 'count', '1')
    ) as c(name, role, sub, setup, sql, kind, expect)
  loop
    v_got := null;
    begin
      if t.setup is not null then
        foreach v_stmt in array t.setup loop
          execute v_stmt;
        end loop;
      end if;
      if t.role <> '-' then
        execute format('set local role %I', t.role);
      end if;
      perform set_config('request.jwt.claim.sub', coalesce(t.sub, ''), true);
      perform set_config('request.jwt.claims',
        case when t.sub is null then '' else json_build_object('sub', t.sub, 'role', t.role)::text end, true);
      for i in 1 .. array_length(t.sql, 1) loop
        if i < array_length(t.sql, 1) then
          execute t.sql[i];
        elsif t.kind = 'count' then
          execute t.sql[i] into v_n;
          v_got := v_n::text;
        else
          execute t.sql[i];
          get diagnostics v_n = row_count;
          v_got := 'ok rows=' || v_n;
        end if;
      end loop;
      raise exception using errcode = 'MB001'; -- deshace la subtransacción (datos auxiliares y cambio de rol)
    exception
      when sqlstate 'MB001' then null;
      when others then v_got := sqlstate || ' ' || left(sqlerrm, 160);
    end;

    v_ok := case
      when t.expect in ('42501', '23514', '23505') then v_got like t.expect || '%'
      when t.expect = 'ok' then v_got like 'ok rows=%' and v_got <> 'ok rows=0'
      when t.expect = 'rows=0' then v_got = 'ok rows=0'
      else v_got = t.expect
    end;
    n_total := n_total + 1;
    if v_ok then n_ok := n_ok + 1; end if;
    r := r || jsonb_build_object('prueba', t.name, 'esperado', t.expect, 'obtenido', v_got, 'ok', v_ok);
  end loop;

  -- Fin: siempre se aborta la transacción completa; el resultado viaja en el mensaje
  raise exception 'MOBAU_38C_RLS total=% ok=% fallos=% :: %', n_total, n_ok, n_total - n_ok, r::text
    using errcode = 'MB999';
end $$;

ROLLBACK;
