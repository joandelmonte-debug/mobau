-- ============================================================
-- PROPUESTA NO EJECUTADA (45-01 · recuperación) — no ejecutar sin aprobación explícita
-- ============================================================
-- Deshace 45-01: la empresa vuelve a restaurar directamente al catálogo lo
-- que ella misma retiró (comportamiento de 41). No cambia datos de productos.
-- Si se aplica, se registra como migración NUEVA tras confirmar su COMMIT.
-- Ejecutar completo.
-- ============================================================

BEGIN;

create function pg_temp.r45(t text, a text, b text) returns text language plpgsql as $$
begin
  if (length(t) - length(replace(t, a, ''))) <> length(a) then
    raise exception '45-01 R: el fragmento no aparece exactamente una vez: %', left(a, 80);
  end if;
  return replace(t, a, b);
end $$;

DO $$
begin
  if current_user <> 'postgres' then
    raise exception '45-01 R: ejecutar como postgres';
  end if;
  if (select md5(prosrc) from pg_proc where oid = 'public.distributor_restore_product(text, timestamp with time zone)'::regprocedure) <> '8bf38c3de1f28a736a13e40cacc0b536'
     or (select md5(prosrc) from pg_proc where oid = 'public.my_products_lifecycle()'::regprocedure) <> '9c3685e41035a21e4f6fb3237a7211b2' then
    raise exception '45-01 R: las funciones no son las esperadas';
  end if;
  perform set_config('mobau.p45_datos', md5(coalesce((select string_agg(id || ':' || publication_status || ':' || updated_at::text || ':' || coalesce(trash_from, '-'), '|' order by id) from public.products), '')), true);
end $$;

DO $$
declare
  d text;
begin
  d := pg_get_functiondef('public.distributor_restore_product(text, timestamp with time zone)'::regprocedure);
  d := pg_temp.r45(d, $a$  -- 8. Escritura (45-01). Vuelve al estado que tenía antes de la papelera:
  --    borrador → borrador; retirado → retirado, también si lo retiró la
  --    propia empresa (no se publica: para volver al catálogo se solicita la
  --    republicación, que aprueba Mobau).
  v_to := v_p.trash_from;
  update public.products
     set trashed_at = null, trashed_by = null, trash_from = null, purge_after = null
   where id = v_p.id
  returning updated_at into v_updated;$a$,
                      $a$  -- 8. Escritura. Borrador → borrador. Retirado por la empresa sin
  --    intervención de Mobau vigente → publicado (su contenido es el último
  --    aprobado por Mobau). Con intervención vigente → sigue retirado.
  if v_p.trash_from = 'retired' and not v_hold then
    v_to := 'published';
    update public.products
       set publication_status = 'published', retired_at = null, retired_by = null, retired_reason = null,
           trashed_at = null, trashed_by = null, trash_from = null, purge_after = null
     where id = v_p.id
    returning updated_at into v_updated;
  else
    v_to := v_p.trash_from;
    update public.products
       set trashed_at = null, trashed_by = null, trash_from = null, purge_after = null
     where id = v_p.id
    returning updated_at into v_updated;
  end if;$a$);
  execute d;
  d := pg_get_functiondef('public.my_products_lifecycle()'::regprocedure);
  d := pg_temp.r45(d, $a$p.trash_from$a$, $a$case when p.trash_from = 'retired' and not f.mobau_hold then 'published' else p.trash_from end$a$);
  execute d;
end $$;

DO $$
begin
  if strpos((select prosrc from pg_proc where oid = 'public.distributor_restore_product(text, timestamp with time zone)'::regprocedure), $a$v_to := 'published';$a$) = 0
     or strpos((select prosrc from pg_proc where oid = 'public.my_products_lifecycle()'::regprocedure), $a$case when p.trash_from = 'retired' and not f.mobau_hold then 'published' else p.trash_from end$a$) = 0 then
    raise exception '45-01 R: las funciones no quedaron como se esperaba';
  end if;
  if not (select prosecdef from pg_proc where oid = 'public.distributor_restore_product(text, timestamp with time zone)'::regprocedure)
     or not has_function_privilege('authenticated', 'public.distributor_restore_product(text, timestamp with time zone)', 'EXECUTE')
     or has_function_privilege('anon', 'public.distributor_restore_product(text, timestamp with time zone)', 'EXECUTE')
     or not has_function_privilege('authenticated', 'public.my_products_lifecycle()', 'EXECUTE')
     or has_function_privilege('anon', 'public.my_products_lifecycle()', 'EXECUTE') then
    raise exception '45-01 R: permisos no esperados';
  end if;
  if md5(coalesce((select string_agg(id || ':' || publication_status || ':' || updated_at::text || ':' || coalesce(trash_from, '-'), '|' order by id) from public.products), ''))
     <> current_setting('mobau.p45_datos') then
    raise exception '45-01 R: ha cambiado algún dato de productos';
  end if;
end $$;

COMMIT;
