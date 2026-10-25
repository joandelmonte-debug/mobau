-- ============================================================
-- PROPUESTA NO EJECUTADA (46-02 · corrige la comprobación de componentes) — no ejecutar sin aprobación explícita
-- ============================================================
-- Defecto de 46-01 detectado por su ensayo: mobau_private.component_structure_check()
-- leía new.kind en filas de grupos y de products («record "new" has no field
-- "kind"»), así que cualquier alta de grupo fallaba al confirmar la transacción.
-- Corrección: la comprobación del acabado solo se evalúa en filas de opciones
-- (IF anidado). Mismo comportamiento en todo lo demás; sin cambios de datos,
-- tablas, permisos ni políticas.
-- Requiere 46-01 aplicada (registrada o no) y la función con su texto de 46-01.
-- Si se aplica, se registra como migración NUEVA tras confirmar su COMMIT.
-- Ejecutar completo.
-- ============================================================

BEGIN;

DO $$
begin
  if current_user <> 'postgres' then
    raise exception '46-02: ejecutar como postgres';
  end if;
  if exists (select 1 from supabase_migrations.schema_migrations where version = '20261030130000') then
    raise exception '46-02: ya está registrada';
  end if;
  if (select md5(prosrc) from pg_proc where oid = 'mobau_private.component_structure_check()'::regprocedure) <> 'e56da07decc27e41c9efbeccdab28b55' then
    raise exception '46-02: la función no es la de 46-01';
  end if;
end $$;

create or replace function mobau_private.component_structure_check() returns trigger
  language plpgsql security definer set search_path = '' as $$
declare
  v text;
begin
  -- El acabado elegido se comprueba al escribir la opción (después puede
  -- retirarse del componente: eso se informa al mostrar, no bloquea).
  -- 46-02: solo en filas de opciones (NEW de grupos o products no tiene kind).
  if tg_table_name = 'product_component_options' and tg_op <> 'DELETE' then
    if new.kind = 'componente' and new.status = 'activo' and new.component_finish_code is not null
       and not exists (select 1 from public.product_finishes f
                        where f.product_id = new.component_product_id and f.code = new.component_finish_code) then
      raise exception 'Componentes: el acabado % no existe en el artículo %.', new.component_finish_code, new.component_product_id
        using errcode = '23514';
    end if;
  end if;
  v := mobau_private.component_structure_violations();
  if v is not null then
    raise exception 'Componentes: %.', v using errcode = '23514';
  end if;
  return null;
end $$;
revoke all on function mobau_private.component_structure_check() from public, anon, authenticated;

DO $$
begin
  if strpos((select prosrc from pg_proc where oid = 'mobau_private.component_structure_check()'::regprocedure), '46-02: solo en filas de opciones') = 0
     or not (select prosecdef from pg_proc where oid = 'mobau_private.component_structure_check()'::regprocedure)
     or has_function_privilege('anon', 'mobau_private.component_structure_check()', 'EXECUTE')
     or has_function_privilege('authenticated', 'mobau_private.component_structure_check()', 'EXECUTE')
     or (select count(*) from pg_trigger where not tgisinternal and tgdeferrable and tgfoid = 'mobau_private.component_structure_check()'::regprocedure) <> 3 then
    raise exception '46-02: la función no quedó como se esperaba';
  end if;
end $$;

COMMIT;
