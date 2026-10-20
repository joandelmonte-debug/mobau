-- ============================================================
-- PROPUESTA NO EJECUTADA (43 · C2-R1 · sesión S2, la lanzo YO justo después de que me digas que S1 está en marcha)
-- ============================================================
-- Misma inserción que S1, como e2a655c1. Si S1 sigue abierta, el trigger de
-- S2 espera al bloqueo de la fila del perfil hasta que S1 termina (MB990) y
-- solo entonces cuenta. Registra si S1 estaba activa al empezar, cuánto
-- esperó la inserción y el recuento dentro de su transacción. Termina
-- SIEMPRE con MB990: nada persiste. Ejecutar completo, con el control MD5.
-- ============================================================

BEGIN;

DO $S2$
declare
  v_i uuid;
  v_pid int := pg_backend_pid();
  v_s1_pid int;
  t0 timestamptz; t_ins timestamptz;
  n_activos int;
begin
  -- La espera del bloqueo de S1 nunca pasa de 60 s (S1 duerme 30 s).
  perform set_config('lock_timeout', '60s', true);
  select id into v_i from public.profiles where id::text like 'e2a655c1%';
  if v_i is null
     or not exists (select 1 from supabase_migrations.schema_migrations where version = '20261020120100')
     or not exists (select 1 from public.profiles where id = v_i and plan = 'individual_founder' and plan_source = 'manual_pilot')
     or (select max_active_projects from public.plans where id = 'individual_founder') <> 2
     or (select prosrc from pg_proc where oid = 'public.enforce_active_project_limit()'::regprocedure) !~ 'for update of pr'
     or (select count(*) from public.projects where owner_user_id = v_i and status = 'active') <> 1
     or exists (select 1 from public.projects where name like 'C2-R1%') then
    raise exception 'MOBAU_43_C2R1 S2: estado de partida inesperado' using errcode = 'MB998';
  end if;

  -- ¿Está S1 en marcha? (otra sesión ejecutando su bloque; nunca esta misma)
  select pid into v_s1_pid from pg_stat_activity
   where pid <> pg_backend_pid() and state = 'active' and query like '%DO $S1$%'
   limit 1;

  perform set_config('request.jwt.claim.sub', v_i::text, true);
  perform set_config('request.jwt.claims', json_build_object('sub', v_i, 'role', 'authenticated', 'aal', 'aal1')::text, true);
  execute 'set local role authenticated';
  t0 := clock_timestamp();
  insert into public.projects (owner_user_id, name) values (v_i, 'C2-R1 S2 (revertido)');
  t_ins := clock_timestamp();
  execute 'reset role';
  select count(*) into n_activos from public.projects where owner_user_id = v_i and status = 'active';

  raise exception 'MOBAU_43_C2R1 S2 pid=% s1_pid=% inicio=% insertado=% espera_s=% activos_en_su_transaccion=%',
    v_pid, coalesce(v_s1_pid::text, 'no_detectada'), t0, t_ins, round(extract(epoch from t_ins - t0)::numeric, 2), n_activos
    using errcode = 'MB990';
end $S2$;

COMMIT;
