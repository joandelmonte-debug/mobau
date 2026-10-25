-- ============================================================
-- PROPUESTA NO EJECUTADA (recuperación de 46-02) — no ejecutar sin aprobación explícita
-- ============================================================
-- Devuelve component_structure_check() al texto exacto de 46-01 (con su
-- defecto). Solo tiene sentido junto con la recuperación de 46-01.
-- Si se aplica, se registra como migración NUEVA tras confirmar su COMMIT.
-- Ejecutar completo.
-- ============================================================

BEGIN;

DO $x$
begin
  if current_user <> 'postgres' then
    raise exception 'recuperación 46-02: ejecutar como postgres';
  end if;
  if strpos((select prosrc from pg_proc where oid = 'mobau_private.component_structure_check()'::regprocedure), '46-02: solo en filas de opciones') = 0 then
    raise exception 'recuperación 46-02: la función no es la de 46-02; no se toca nada';
  end if;
end $x$;

create or replace function mobau_private.component_structure_check() returns trigger
  language plpgsql security definer set search_path = '' as $$
declare
  v text;
begin
  -- El acabado elegido se comprueba al escribir la opción (después puede
  -- retirarse del componente: eso se informa al mostrar, no bloquea).
  if tg_table_name = 'product_component_options' and tg_op <> 'DELETE'
     and new.kind = 'componente' and new.status = 'activo' and new.component_finish_code is not null
     and not exists (select 1 from public.product_finishes f
                      where f.product_id = new.component_product_id and f.code = new.component_finish_code) then
    raise exception 'Componentes: el acabado % no existe en el artículo %.', new.component_finish_code, new.component_product_id
      using errcode = '23514';
  end if;
  v := mobau_private.component_structure_violations();
  if v is not null then
    raise exception 'Componentes: %.', v using errcode = '23514';
  end if;
  return null;
end $$;
revoke all on function mobau_private.component_structure_check() from public, anon, authenticated;

DO $x$
begin
  if (select md5(prosrc) from pg_proc where oid = 'mobau_private.component_structure_check()'::regprocedure) <> 'e56da07decc27e41c9efbeccdab28b55' then
    raise exception 'recuperación 46-02: la función no volvió al texto de 46-01';
  end if;
end $x$;

COMMIT;
