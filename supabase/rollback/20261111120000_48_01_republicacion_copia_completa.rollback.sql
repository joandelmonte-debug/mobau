-- ============================================================
-- RECUPERACIÓN DE 48-01 (republicación: copia completa) — NO EJECUTADA — no ejecutar sin aprobación explícita
-- ============================================================
-- Deshace las dos sustituciones de 48-01 y comprueba que cada función vuelve EXACTAMENTE al md5 original
-- (snapshot_product_on_submit c0de5fdc…, moderate_product_proposal 16b7b165…). Se detiene sin cambios si la función actual no es la de 48-01.
-- No toca datos: las copias ya creadas con la marca "schema" 2 se conservan y las anteriores a 48-01 vuelven a no incluir las 3 columnas.
-- ============================================================

BEGIN;

create function pg_temp.unpatch_fn(p_fn regprocedure, p_md5_original text, p_old text[], p_new text[]) returns boolean
  language plpgsql as $f$
declare
  v_def text := pg_get_functiondef(p_fn);
  v_n int;
  i int;
begin
  for i in 1 .. array_length(p_old, 1) loop
    v_n := (length(v_def) - length(replace(v_def, p_old[i], ''))) / length(p_old[i]);
    if v_n <> 1 then
      raise exception '48-01 recuperación: el trozo % de % aparece % veces (debe ser 1): la función no es la de 48-01', i, p_fn, v_n;
    end if;
    v_def := replace(v_def, p_old[i], p_new[i]);
  end loop;
  execute v_def;
  if (select md5(prosrc) from pg_proc where oid = p_fn) <> p_md5_original then
    raise exception '48-01 recuperación: % no quedó con el md5 original', p_fn;
  end if;
  return true;
end $f$;

DO $$
begin
  if current_user <> 'postgres' then raise exception '48-01 recuperación: ejecutar como postgres'; end if;
end $$;

select case when pg_temp.unpatch_fn('public.snapshot_product_on_submit()'::regprocedure, 'c0de5fdc0a49f8dd2ef80cb0e8959fef',
  array[
    $r$p.color_temperature,
                   p.reference_code, p.cover_asset_id, p.catalog_role
              from public.products p where p.id = new.product_id) s;$r$,
    $r$new.product_snapshot := jsonb_build_object('product', v_product, 'price', v_price, 'taken_at', now(), 'schema', 2);$r$
  ],
  array[
    $r$p.color_temperature
              from public.products p where p.id = new.product_id) s;$r$,
    $r$new.product_snapshot := jsonb_build_object('product', v_product, 'price', v_price, 'taken_at', now());$r$
  ]) then 'ok' end;

select case when pg_temp.unpatch_fn('public.moderate_product_proposal(uuid,text,text,integer)'::regprocedure, '16b7b1650b34ca486859dec098f1a67f',
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
  ],
  array[
    $r$  v_uid uuid := (select auth.uid());
$r$,
    $r$      for k in select x from pg_catalog.jsonb_object_keys(v_snap || v_cur_json) as x order by x loop
        if (v_snap -> k) is distinct from (v_cur_json -> k) then
          v_conflicts := v_conflicts || pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object(
            'field', k, 'at_submit', v_snap -> k, 'current', v_cur_json -> k, 'proposed', null));
        end if;
      end loop;$r$
  ]) then 'ok' end;

COMMIT;
