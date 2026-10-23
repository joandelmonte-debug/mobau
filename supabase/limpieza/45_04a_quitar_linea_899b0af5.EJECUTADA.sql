-- ============================================================
-- YA EJECUTADA el 2026-10-23 · NO VOLVER A APLICAR (45-04a · quitar la línea 899b0af5 del proyecto de prueba a33bb396)
-- Se ejecutó su bloque DO una vez; lectura posterior: línea inexistente, proyecto activo con 5 líneas.
-- ============================================================
-- Autorizada por la empresa (2026-10-23): la cuenta del proyecto es de
-- prueba. Elimina SOLO la línea 899b0af5…, que referencia a
-- spectro-02988ada. No toca el proyecto, sus otras líneas ni ningún otro dato.
-- No existe auditoría propia para líneas de proyecto (los eventos de ciclo
-- de vida son solo de productos): la purga 45-04 dejará constancia en su meta.
-- Operación de datos, no migración de esquema: no se registra.
-- Ejecutar completo.
-- ============================================================

BEGIN;

DO $$
declare
  n int;
begin
  if current_user <> 'postgres' then
    raise exception '45-04a: ejecutar como postgres';
  end if;
  -- Línea exacta leída el 2026-10-22 (proyecto activo, 1 ud., sin acabado).
  if (select md5(to_jsonb(l)::text) from public.project_products l where l.id = '899b0af5-4f84-4e0f-ac9b-e0a734b606c3') is distinct from '87adc6daa76d1a4969f71479e879516f'
     or (select product_id || '|' || project_id from public.project_products where id = '899b0af5-4f84-4e0f-ac9b-e0a734b606c3')
        is distinct from 'spectro-02988ada|a33bb396-b780-4d22-86db-b66e91fd4ee8' then
    raise exception '45-04a: la línea no es la verificada';
  end if;
  if (select count(*) from public.project_products where project_id = 'a33bb396-b780-4d22-86db-b66e91fd4ee8') <> 6
     or (select count(*) from public.project_products where product_id = 'spectro-02988ada') <> 1 then
    raise exception '45-04a: el proyecto o las líneas del producto no son los esperados';
  end if;
  perform set_config('mobau.p4504a_otras', md5(coalesce((select string_agg(to_jsonb(l)::text, '|' order by l.id) from public.project_products l
                                                         where l.id <> '899b0af5-4f84-4e0f-ac9b-e0a734b606c3'), '')), true);
  perform set_config('mobau.p4504a_proyecto', (select md5(to_jsonb(pj)::text) from public.projects pj where pj.id = 'a33bb396-b780-4d22-86db-b66e91fd4ee8'), true);

  delete from public.project_products where id = '899b0af5-4f84-4e0f-ac9b-e0a734b606c3';
  get diagnostics n = row_count;
  if n <> 1 then
    raise exception '45-04a: se esperaba borrar 1 línea y se borraron %', n;
  end if;

  if (select count(*) from public.project_products where project_id = 'a33bb396-b780-4d22-86db-b66e91fd4ee8') <> 5
     or md5(coalesce((select string_agg(to_jsonb(l)::text, '|' order by l.id) from public.project_products l), '')) <> current_setting('mobau.p4504a_otras')
     or (select md5(to_jsonb(pj)::text) from public.projects pj where pj.id = 'a33bb396-b780-4d22-86db-b66e91fd4ee8') <> current_setting('mobau.p4504a_proyecto') then
    raise exception '45-04a: ha cambiado algo más que la línea';
  end if;
end $$;

COMMIT;
