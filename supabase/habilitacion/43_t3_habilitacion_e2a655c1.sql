-- ============================================================
-- PROPUESTA NO EJECUTADA (43 · T3 habilitación manual) — no ejecutar sin aprobación explícita
-- ============================================================
-- 43 · T3 · Habilitación manual del piloto (E2) de la cuenta Individual de
-- prueba del creador: e2a655c1-700d-4ce1-86f5-25f7216761b0.
--   * profiles: plan = individual_founder, plan_source = manual_pilot,
--     plan_granted_at = now(), plan_note (motivo). NO toca role,
--     subscription_status (sigue 'trialing', que no autoriza nada),
--     requested_plan ni ningún otro dato. No registra pago ni suscripción.
--   * mobau_private.plan_events: una fila de auditoría.
-- Requiere T1 aplicada y registrada (20261020120000). Es una escritura de
-- datos, no una migración: no se registra en schema_migrations.
-- No toca ninguna otra cuenta, proyecto, línea ni solicitud.
-- Ejecutar completo.
-- ============================================================

BEGIN;

DO $$
declare
  v_id constant uuid := 'e2a655c1-700d-4ce1-86f5-25f7216761b0';
begin
  if current_user <> 'postgres' then
    raise exception '43-T3: ejecutar como postgres';
  end if;
  if not exists (select 1 from supabase_migrations.schema_migrations where version = '20261020120000')
     or to_regprocedure('public.my_professional_access()') is null
     or to_regclass('mobau_private.plan_events') is null then
    raise exception '43-T3: T1 no está aplicada y registrada';
  end if;
  if not exists (select 1 from public.plans where id = 'individual_founder' and includes_professional_tools) then
    raise exception '43-T3: individual_founder no incluye las herramientas profesionales';
  end if;
  if (select count(*) from public.profiles
       where id = v_id and role = 'individual' and plan = 'free_trial' and plan_source = 'default'
         and plan_granted_at is null and plan_note is null) <> 1 then
    raise exception '43-T3: la cuenta no está en el estado de partida esperado (individual, free_trial, default)';
  end if;
  if exists (select 1 from public.distributor_profiles where user_id = v_id)
     or exists (select 1 from public.mobau_admins where user_id = v_id) then
    raise exception '43-T3: la cuenta es distribuidor o Mobau';
  end if;
  if exists (select 1 from mobau_private.plan_events where user_id = v_id) then
    raise exception '43-T3: la cuenta ya tiene eventos de habilitación';
  end if;
  if exists (select 1 from public.profiles where plan_source <> 'default') then
    raise exception '43-T3: hay otras habilitaciones inesperadas';
  end if;
end $$;

update public.profiles
   set plan = 'individual_founder',
       plan_source = 'manual_pilot',
       plan_granted_at = now(),
       plan_note = 'Habilitación manual del piloto (43-T3): cuenta Individual de prueba del creador. Sin cobro ni suscripción.'
 where id = 'e2a655c1-700d-4ce1-86f5-25f7216761b0'
   and plan = 'free_trial' and plan_source = 'default';

insert into mobau_private.plan_events (user_id, from_plan, to_plan, from_source, to_source, note)
values ('e2a655c1-700d-4ce1-86f5-25f7216761b0', 'free_trial', 'individual_founder', 'default', 'manual_pilot',
        'Habilitación manual del piloto (43-T3): cuenta Individual de prueba del creador. Sin cobro ni suscripción.');

DO $$
declare
  v_id constant uuid := 'e2a655c1-700d-4ce1-86f5-25f7216761b0';
  v_ok boolean;
begin
  if (select count(*) from public.profiles
       where id = v_id and role = 'individual' and plan = 'individual_founder' and plan_source = 'manual_pilot'
         and plan_granted_at is not null and subscription_status = 'trialing') <> 1 then
    raise exception '43-T3: la cuenta no quedó habilitada como se esperaba';
  end if;
  if (select count(*) from public.profiles where plan_source <> 'default') <> 1 then
    raise exception '43-T3: más de una cuenta habilitada';
  end if;
  if (select count(*) from mobau_private.plan_events) <> 1
     or (select count(*) from mobau_private.plan_events where user_id = v_id and to_source = 'manual_pilot') <> 1 then
    raise exception '43-T3: auditoría inesperada';
  end if;
  -- Comprobación funcional dentro de la misma transacción: la regla del
  -- servidor concede las herramientas a esta cuenta (JWT simulado, local).
  perform set_config('request.jwt.claim.sub', v_id::text, true);
  perform set_config('request.jwt.claims', json_build_object('sub', v_id, 'role', 'authenticated')::text, true);
  v_ok := public.my_professional_access();
  perform set_config('request.jwt.claims', '', true);
  perform set_config('request.jwt.claim.sub', '', true);
  if not v_ok then
    raise exception '43-T3: my_professional_access() no concede acceso a la cuenta';
  end if;
end $$;

COMMIT;
