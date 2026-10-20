-- ============================================================
-- PROPUESTA NO EJECUTADA (43 · C2-R1 · sesión S1, la lanzas TÚ en el editor SQL de Supabase)
-- ============================================================
-- Concurrencia R1 con el trigger REAL (requiere T4 aplicada y registrada).
-- S1 inserta un proyecto de e2a655c1 como esa cuenta (RLS y trigger reales),
-- mantiene el bloqueo de la fila del perfil 30 s y termina SIEMPRE con MB990:
-- nada persiste. Mientras S1 duerme, lanzo S2 (C2-R1_S2.sql), que debe
-- esperar a que S1 termine para poder contar.
-- Pega el bloque completo y ejecútalo una sola vez. El resultado viaja en el
-- mensaje de error (MB990): cópialo tal cual en el chat.
-- ============================================================
DO $S1$
declare
  v_i uuid;
  v_pid int := pg_backend_pid();
  t0 timestamptz; t_ins timestamptz; t_end timestamptz;
  n_activos int;
begin
  select id into v_i from public.profiles where id::text like 'e2a655c1%';
  if v_i is null
     or not exists (select 1 from supabase_migrations.schema_migrations where version = '20261020120100')
     or not exists (select 1 from public.profiles where id = v_i and plan = 'individual_founder' and plan_source = 'manual_pilot')
     or (select max_active_projects from public.plans where id = 'individual_founder') <> 2
     or (select prosrc from pg_proc where oid = 'public.enforce_active_project_limit()'::regprocedure) !~ 'for update of pr'
     or (select count(*) from public.projects where owner_user_id = v_i and status = 'active') <> 1
     or exists (select 1 from public.projects where name like 'C2-R1%') then
    raise exception 'MOBAU_43_C2R1 S1: estado de partida inesperado' using errcode = 'MB998';
  end if;

  perform set_config('request.jwt.claim.sub', v_i::text, true);
  perform set_config('request.jwt.claims', json_build_object('sub', v_i, 'role', 'authenticated', 'aal', 'aal1')::text, true);
  execute 'set local role authenticated';
  t0 := clock_timestamp();
  insert into public.projects (owner_user_id, name) values (v_i, 'C2-R1 S1 (revertido)');
  t_ins := clock_timestamp();
  execute 'reset role';
  select count(*) into n_activos from public.projects where owner_user_id = v_i and status = 'active';

  -- Mantiene el bloqueo FOR UPDATE de la fila del perfil (tomado por el trigger) hasta el final.
  perform pg_sleep(30);
  t_end := clock_timestamp();

  raise exception 'MOBAU_43_C2R1 S1 pid=% inicio=% insertado=% fin=% activos_en_su_transaccion=%',
    v_pid, t0, t_ins, t_end, n_activos
    using errcode = 'MB990';
end $S1$;
