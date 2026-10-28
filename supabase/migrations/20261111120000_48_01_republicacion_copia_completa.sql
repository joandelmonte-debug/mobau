-- ============================================================
-- PROPUESTA NO EJECUTADA (48-01 · republicación: copia completa y compatibilidad acotada) — no ejecutar sin aprobación explícita
-- ============================================================
-- Incidencia (separada del Punto 47): aprobar la republicación de un producto retirado da «snapshot_conflict» por catalog_role,
-- cover_asset_id y reference_code SIN que nada haya cambiado. Causa: snapshot_product_on_submit() guarda 26 columnas explícitas
-- (44-01 y 46-01 añadieron esas 3 a products y no las añadieron a la lista) y la comparación de la rama republish de
-- moderate_product_proposal() recorre la UNIÓN de claves de la copia y de la fila actual: una clave ausente en la copia cuenta siempre
-- como diferencia. Ninguna republicación puede aprobarse hasta corregirlo.
--
-- Cambios (ambas funciones se parchean con sustituciones exactas, comprobando md5 antes y que cada trozo existe una sola vez;
-- solo cambia lo indicado, ACL y atributos se conservan):
--   1. snapshot_product_on_submit(): la copia añade reference_code, cover_asset_id y catalog_role, y lleva la marca "schema": 2
--      (copia completa de 48-01 en adelante).
--   2. moderate_product_proposal(), rama republish, comparación de la copia con la fila actual:
--      · copia con marca schema 2: una clave de la fila actual ausente en la copia es un DESFASE del sistema (columna nueva sin añadir
--        al trigger): se señala como conflicto con reason 'snapshot_incomplete'; nunca se ignora ni se presenta como cambio del producto.
--      · copia anterior (sin marca): solo las 3 columnas conocidas (catalog_role, cover_asset_id, reference_code) no son comparables
--        (no se guardó su valor al enviar). Se aceptan SOLO si la fila no se ha modificado desde el envío: updated_at de la copia idéntico
--        al actual (trg_products_updated_at lo renueva en cualquier UPDATE). Si la fila cambió, conflicto con reason 'legacy_not_comparable'.
--        Cualquier otra clave ausente (una cuarta columna) es conflicto 'snapshot_incomplete'. NO se rellena la copia con valores actuales.
--      · el resto de claves se compara exactamente como antes (clave ausente, null y cadena vacía siguen siendo distintos).
--   La rama update y la rama create no cambian. No se toca ninguna fila de datos.
-- Condiciones y límites de la compatibilidad con copias anteriores (sin la marca "schema"):
--   · La igualdad de updated_at NO demuestra en términos absolutos que el producto no cambió. Prueba solo que no hubo ningún UPDATE
--     «normal» desde el envío, porque trg_products_updated_at (BEFORE UPDATE, sin lista de columnas) fija updated_at = now() en cada UPDATE.
--     No la renuevan: una escritura con el disparador desactivado o con session_replication_role = replica (solo un rol privilegiado),
--     ni dos escrituras dentro de la MISMA transacción que el envío (now() es el inicio de la transacción: envío y modificación en una
--     misma transacción dejarían updated_at idéntico). Ninguna ruta de la aplicación hace ninguna de las dos cosas hoy: el envío es un
--     UPDATE de product_proposals en su propia sentencia y authenticated no puede escribir products.
--   · Alcance: solo catalog_role, cover_asset_id y reference_code. Las otras 26 claves y el precio se comparan siempre.
--   · Con updated_at distinto o cualquier otra clave ausente, la aprobación se bloquea y se pide solicitar cambios y reenviar (la copia
--     nueva sí es completa). Nunca se rellena la copia con valores actuales.
--   · Concurrencia: la rama republish toma FOR UPDATE sobre la fila de products (y sobre product_prices si existe) ANTES de comparar y
--     lo conserva hasta el COMMIT de la decisión, de modo que nadie puede modificar el producto entre la comparación y la publicación.
--     Límite: si el producto no tiene fila de precio no hay nada que bloquear en product_prices; el único camino que la crea es otra
--     aprobación de Mobau, que el bloqueo de la propuesta y del producto serializa.
-- Recuperación: supabase/rollback/20261111120000_48_01_republicacion_copia_completa.rollback.sql (deshace las sustituciones y comprueba el md5 original).
-- Si se aplica, se registra como migración NUEVA tras confirmar su COMMIT.
-- ============================================================

BEGIN;

create function pg_temp.patch_fn(p_fn regprocedure, p_md5_before text, p_old text[], p_new text[]) returns text
  language plpgsql as $f$
declare
  v_def text := pg_get_functiondef(p_fn);
  v_n int;
  i int;
begin
  if (select md5(prosrc) from pg_proc where oid = p_fn) is distinct from p_md5_before then
    raise exception '48-01: % no tiene el md5 esperado', p_fn;
  end if;
  for i in 1 .. array_length(p_old, 1) loop
    v_n := (length(v_def) - length(replace(v_def, p_old[i], ''))) / length(p_old[i]);
    if v_n <> 1 then
      raise exception '48-01: el trozo % de % aparece % veces (debe ser 1)', i, p_fn, v_n;
    end if;
    v_def := replace(v_def, p_old[i], p_new[i]);
  end loop;
  execute v_def;
  return (select md5(prosrc) from pg_proc where oid = p_fn);
end $f$;

DO $$
declare
  v_reg int;
begin
  if current_user <> 'postgres' then raise exception '48-01: ejecutar como postgres'; end if;
  if to_regclass('supabase_migrations.schema_migrations') is not null then
    execute $q$select count(*) from supabase_migrations.schema_migrations where version = '20261110120000'$q$ into v_reg;
    if v_reg <> 1 then raise exception '48-01: 47-01 no está registrada'; end if;
    execute $q$select count(*) from supabase_migrations.schema_migrations where version = '20261111120000'$q$ into v_reg;
    if v_reg <> 0 then raise exception '48-01: ya está registrada'; end if;
  end if;
  if (select md5(prosrc) from pg_proc where oid = 'public.snapshot_product_on_submit()'::regprocedure) <> 'c0de5fdc0a49f8dd2ef80cb0e8959fef'
     or (select md5(prosrc) from pg_proc where oid = 'public.moderate_product_proposal(uuid,text,text,integer)'::regprocedure) <> '16b7b1650b34ca486859dec098f1a67f' then
    raise exception '48-01: las funciones de partida no son las esperadas';
  end if;
end $$;

-- 1. La copia del envío incluye las tres columnas que faltaban y la marca de copia completa.
select pg_temp.patch_fn('public.snapshot_product_on_submit()'::regprocedure, 'c0de5fdc0a49f8dd2ef80cb0e8959fef',
  array[
    $r$p.color_temperature
              from public.products p where p.id = new.product_id) s;$r$,
    $r$new.product_snapshot := jsonb_build_object('product', v_product, 'price', v_price, 'taken_at', now());$r$
  ],
  array[
    $r$p.color_temperature,
                   p.reference_code, p.cover_asset_id, p.catalog_role
              from public.products p where p.id = new.product_id) s;$r$,
    $r$new.product_snapshot := jsonb_build_object('product', v_product, 'price', v_price, 'taken_at', now(), 'schema', 2);$r$
  ]);

-- 2. Comparación de la republicación: copia completa estricta; copia anterior con compatibilidad explícita y acotada.
select pg_temp.patch_fn('public.moderate_product_proposal(uuid,text,text,integer)'::regprocedure, '16b7b1650b34ca486859dec098f1a67f',
  array[
    $r$  v_uid uuid := (select auth.uid());
$r$,
    $r$      for k in select x from pg_catalog.jsonb_object_keys(v_snap || v_cur_json) as x order by x loop
        if (v_snap -> k) is distinct from (v_cur_json -> k) then
          v_conflicts := v_conflicts || pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object(
            'field', k, 'at_submit', v_snap -> k, 'current', v_cur_json -> k, 'proposed', null));
        end if;
      end loop;$r$
  ],
  array[
    $r$  -- 48-01: columnas que las copias anteriores a 48-01 (sin la marca "schema") no incluyen: no se guardó su valor al enviar.
  c_legacy_missing constant text[] := array['catalog_role', 'cover_asset_id', 'reference_code'];
  v_legacy boolean;
  v_uid uuid := (select auth.uid());
$r$,
    $r$      -- 48-01: copia con marca "schema" = completa. Una clave de la fila actual ausente de la copia es un desfase del sistema
      -- (columna nueva sin añadir al trigger de envío): se señala (snapshot_incomplete), nunca se ignora ni se llama «cambio».
      -- Copia anterior (sin marca): solo las 3 columnas conocidas son no comparables y se aceptan únicamente si la fila no se ha
      -- modificado desde el envío (updated_at idéntico); si cambió, o si falta cualquier otra clave, hay conflicto.
      v_legacy := (v_p.product_snapshot ->> 'schema') is null;
      for k in select x from pg_catalog.jsonb_object_keys(v_snap || v_cur_json) as x order by x loop
        if not (v_snap ? k) then
          if v_legacy and k = any (c_legacy_missing)
             and (v_snap -> 'updated_at') is not distinct from (v_cur_json -> 'updated_at') then
            continue;
          end if;
          v_conflicts := v_conflicts || pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object(
            'field', k, 'at_submit', null, 'current', v_cur_json -> k, 'proposed', null,
            'reason', case when v_legacy and k = any (c_legacy_missing) then 'legacy_not_comparable' else 'snapshot_incomplete' end));
        elsif (v_snap -> k) is distinct from (v_cur_json -> k) then
          v_conflicts := v_conflicts || pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object(
            'field', k, 'at_submit', v_snap -> k, 'current', v_cur_json -> k, 'proposed', null, 'reason', 'changed'));
        end if;
      end loop;$r$
  ]);

DO $$
begin
  if (select prosrc from pg_proc where oid = 'public.snapshot_product_on_submit()'::regprocedure) not like '%p.reference_code, p.cover_asset_id, p.catalog_role%'
     or (select prosrc from pg_proc where oid = 'public.snapshot_product_on_submit()'::regprocedure) not like '%''schema'', 2%'
     or (select prosrc from pg_proc where oid = 'public.moderate_product_proposal(uuid,text,text,integer)'::regprocedure) not like '%c_legacy_missing%'
     or (select md5(prosrc) from pg_proc where oid = 'public.snapshot_product_on_submit()'::regprocedure) = 'c0de5fdc0a49f8dd2ef80cb0e8959fef'
     or (select md5(prosrc) from pg_proc where oid = 'public.moderate_product_proposal(uuid,text,text,integer)'::regprocedure) = '16b7b1650b34ca486859dec098f1a67f' then
    raise exception '48-01: las funciones no quedaron como se esperaba';
  end if;
  -- Atributos y permisos conservados.
  if (select prosecdef from pg_proc where oid = 'public.moderate_product_proposal(uuid,text,text,integer)'::regprocedure) is not true
     or (select prosecdef from pg_proc where oid = 'public.snapshot_product_on_submit()'::regprocedure) is true
     or has_function_privilege('anon', 'public.moderate_product_proposal(uuid,text,text,integer)', 'EXECUTE')
     or not has_function_privilege('authenticated', 'public.moderate_product_proposal(uuid,text,text,integer)', 'EXECUTE') then
    raise exception '48-01: atributos o permisos distintos de los esperados';
  end if;
end $$;

COMMIT;
