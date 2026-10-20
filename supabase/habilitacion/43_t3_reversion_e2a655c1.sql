-- ============================================================
-- RECUPERACIÓN NO EJECUTADA (43 · inversa de T3) — no ejecutar sin aprobación explícita
-- ============================================================
-- Retira la habilitación manual de e2a655c1-700d-4ce1-86f5-25f7216761b0:
-- vuelve a free_trial + default y borra plan_granted_at y plan_note. No
-- borra la auditoría: añade un evento de retirada. Sus proyectos, líneas y
-- solicitudes no se tocan (con T4 activa quedarían en solo lectura).
-- Nota: R1 (inversa de T1) se niega mientras existan eventos en plan_events;
-- revertir T1 después de T3 exige decidir antes qué hacer con esa auditoría.
-- ============================================================

BEGIN;

DO $$
begin
  if current_user <> 'postgres' then
    raise exception '43-R3: ejecutar como postgres';
  end if;
  if (select count(*) from public.profiles
       where id = 'e2a655c1-700d-4ce1-86f5-25f7216761b0' and plan = 'individual_founder' and plan_source = 'manual_pilot') <> 1 then
    raise exception '43-R3: la cuenta no está habilitada como en T3';
  end if;
end $$;

update public.profiles
   set plan = 'free_trial', plan_source = 'default', plan_granted_at = null, plan_note = null
 where id = 'e2a655c1-700d-4ce1-86f5-25f7216761b0'
   and plan = 'individual_founder' and plan_source = 'manual_pilot';

insert into mobau_private.plan_events (user_id, from_plan, to_plan, from_source, to_source, note)
values ('e2a655c1-700d-4ce1-86f5-25f7216761b0', 'individual_founder', 'free_trial', 'manual_pilot', 'default',
        'Retirada de la habilitación manual del piloto (inversa de 43-T3).');

DO $$
begin
  if (select count(*) from public.profiles
       where id = 'e2a655c1-700d-4ce1-86f5-25f7216761b0' and plan = 'free_trial' and plan_source = 'default'
         and plan_granted_at is null and plan_note is null) <> 1 then
    raise exception '43-R3: la cuenta no volvió a Gratis';
  end if;
end $$;

COMMIT;
