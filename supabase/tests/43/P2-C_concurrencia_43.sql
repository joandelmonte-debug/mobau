-- ============================================================
-- PROPUESTA NO EJECUTADA (43 · P2-C concurrencia R1, protocolo) — no ejecutar sin aprobación explícita
-- ============================================================
-- Se lanzan DOS ejecuciones simultáneas de este mismo texto. Cada una toma,
-- como hará el trigger de T4, el bloqueo FOR UPDATE de la fila del perfil
-- de la cuenta Individual de prueba (e2a655c1), cuenta sus proyectos
-- activos, espera 5 s y termina con MB990 (rollback): no escribe nada.
-- Éxito: la que llega segunda obtiene el bloqueo después del «fin» de la
-- primera (espera ≈ 5 s). Aquí no se puede usar el trigger real: T4 no está
-- aplicada y aplicarla en dos transacciones a la vez las serializaría por
-- los bloqueos de la DDL. La comprobación con el trigger real queda para
-- después de aplicar T4 (C2-R1), también revertida.
-- ============================================================

DO $P2CC$
declare
  v_i uuid; t0 timestamptz; t_lock timestamptz; t_end timestamptz; n int; lim int;
begin
  select id into v_i from public.profiles where id::text like 'e2a655c1%';
  if v_i is null then
    raise exception 'MB998: no está la cuenta de prueba' using errcode = 'MB998';
  end if;
  t0 := clock_timestamp();
  select pl.max_active_projects into lim
    from public.profiles pr join public.plans pl on pl.id = pr.plan
   where pr.id = v_i
     for update of pr;
  t_lock := clock_timestamp();
  select count(*) into n from public.projects where owner_user_id = v_i and studio_id is null and status = 'active';
  perform pg_sleep(5);
  t_end := clock_timestamp();
  raise exception 'MOBAU_43_P2C pid=% inicio=% bloqueo=% fin=% espera_ms=% activos=% limite=%',
    pg_backend_pid(), t0, t_lock, t_end, round(extract(epoch from (t_lock - t0)) * 1000), n, lim
    using errcode = 'MB990';
end $P2CC$;
