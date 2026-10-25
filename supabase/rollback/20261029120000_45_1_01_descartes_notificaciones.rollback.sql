-- ============================================================
-- PROPUESTA NO EJECUTADA (recuperación de 45.1-01) — no ejecutar sin aprobación explícita
-- ============================================================
-- Elimina public.notification_dismissals. Los descartes guardados se
-- pierden y los avisos vuelven a mostrarse; no afecta a ningún otro dato.
-- Revertir antes la interfaz (sin la tabla, la página muestra todos los
-- avisos y «Quitar» informa del error).
-- Si se aplica, se registra como migración NUEVA tras confirmar su COMMIT.
-- Ejecutar completo.
-- ============================================================

BEGIN;

DO $$
begin
  if current_user <> 'postgres' then
    raise exception 'recuperación 45.1-01: ejecutar como postgres';
  end if;
  if to_regclass('public.notification_dismissals') is null then
    raise exception 'recuperación 45.1-01: la tabla no existe; no se toca nada';
  end if;
  if exists (select 1 from pg_constraint where confrelid = 'public.notification_dismissals'::regclass)
     or exists (select 1 from pg_depend d join pg_rewrite r on r.oid = d.objid
                 where d.refobjid = 'public.notification_dismissals'::regclass and r.ev_class <> 'public.notification_dismissals'::regclass) then
    raise exception 'recuperación 45.1-01: otros objetos dependen de la tabla; no se toca nada';
  end if;
end $$;

drop table public.notification_dismissals;

DO $$
begin
  if to_regclass('public.notification_dismissals') is not null then
    raise exception 'recuperación 45.1-01: la tabla sigue existiendo';
  end if;
end $$;

COMMIT;
