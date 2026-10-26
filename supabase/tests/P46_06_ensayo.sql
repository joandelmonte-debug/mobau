-- Punto 46 · 46-06 (nota técnica de línea): ensayo rollback-only (siempre termina con una excepción final), ejecutado en mobau-pruebas el 2026-10-26: OK=11 FALLO=0.
-- Datos de partida sintéticos (individual@example.test, proyecto «P46 nota técnica» archivado, dos RFQ con sus md5): se adapta a otro entorno antes de reutilizarlo.
select set_config('statement_timeout','60s',true), set_config('lock_timeout','3s',true);
DO $T$
declare
  sysid constant text := '7692130048193495360';
  snap_orig constant text := 'a71bad42f5e226f8e9a58ea1584a5a0c';
  snap_nueva constant text := 'be92152dda8c0a57881f901d49de7f39';
  i1 uuid; proj uuid; ln uuid; claims text; ctx text; ctx_esp text;
  t record; res text; n bigint; m text; h text; ok boolean; informe text := ''; n_ok int := 0; nota_antes text; len_despues int;
begin
  if current_database() <> 'postgres' or (select system_identifier::text from pg_control_system()) <> sysid then raise exception 'PARA: clúster distinto'; end if;
  select id into i1 from auth.users where email = 'individual@example.test';
  select p.id into proj from public.projects p where p.owner_user_id = i1 and p.name = 'P46 nota técnica';
  select id, notes into ln, nota_antes from public.project_products where project_id = proj;
  if proj is null or ln is null or (select status from public.projects where id = proj) <> 'archived' then raise exception 'PARA: estado de partida inesperado'; end if;
  if (select md5(lines_snapshot::text) from public.rfqs where project_id = proj) <> snap_nueva
     or (select md5(lines_snapshot::text) from public.rfqs where id = '5f284909-fc24-4215-b456-4e7858746292') <> snap_orig then raise exception 'PARA: copias de RFQ distintas de la línea base'; end if;
  claims := jsonb_build_object('sub', i1::text, 'role', 'authenticated', 'aal', 'aal1')::text;
  ctx_esp := 'authenticated|uid=' || i1::text || '|bypassrls=false';

  for t in select * from (values
    (1,'T1','ARCHIVADO · el propietario modifica notes -> rechazo 42501 line_note_archived', 'arch', format($q$update public.project_products set notes = 'cambio' where id = %L$q$, ln), 'ERROR 42501 | La nota de una línea de un proyecto archivado no se puede modificar. | hint=line_note_archived'),
    (2,'T2','ARCHIVADO · control: el propietario modifica otra columna (quantity) -> permitido (la protección solo mira notes)', 'arch', format($q$update public.project_products set quantity = quantity where id = %L$q$, ln), 'OK 1'),
    (3,'T3','ARCHIVADO · control: escribir el MISMO valor en notes -> permitido (no cambia)', 'arch', format($q$update public.project_products set notes = notes where id = %L$q$, ln), 'OK 1'),
    (4,'T4','ACTIVO · el propietario guarda una nota -> permitido', 'act', format($q$update public.project_products set notes = 'nota nueva' where id = %L$q$, ln), 'OK 1'),
    (5,'T5','ACTIVO · nota de exactamente 1000 caracteres -> permitido', 'act', format($q$update public.project_products set notes = repeat('a', 1000) where id = %L$q$, ln), 'OK 1'),
    (6,'T6','ACTIVO · nota de 1001 caracteres -> rechazo 23514 line_note_too_long', 'act', format($q$update public.project_products set notes = repeat('a', 1001) where id = %L$q$, ln), 'ERROR 23514 | La nota técnica admite como máximo 1000 caracteres. | hint=line_note_too_long'),
    (7,'T7','ACTIVO · vaciar la nota (null) -> permitido', 'act', format($q$update public.project_products set notes = null where id = %L$q$, ln), 'OK 1'),
    (8,'T8','ACTIVO · nota antigua de 1500 caracteres (simulada sin triggers): cambiar la cantidad la conserva sin truncar ni fallar', 'legado', format($q$update public.project_products set quantity = quantity + 1 where id = %L$q$, ln), 'OK 1 | len=1500'),
    (9,'T9','ACTIVO · nota antigua de 1500 caracteres: reescribir el mismo valor -> permitido; recortarla a una nueva de 1001 -> ver T10', 'legado', format($q$update public.project_products set notes = notes where id = %L$q$, ln), 'OK 1 | len=1500'),
    (10,'T10','ACTIVO · nota antigua de 1500 caracteres: cambiarla por otra de 1200 -> rechazo 23514 (un valor nuevo largo no entra)', 'legado', format($q$update public.project_products set notes = repeat('b', 1200) where id = %L$q$, ln), 'ERROR 23514 | La nota técnica admite como máximo 1000 caracteres. | hint=line_note_too_long')
  ) as v(ord, code, descr, modo, sentencia, esperado) order by ord
  loop
    begin
      perform set_config('role', 'postgres', true);
      if t.modo in ('act', 'legado') then update public.projects set status = 'active' where id = proj; end if;
      if t.modo = 'legado' then
        alter table public.project_products disable trigger trg_project_products_20_note;
        update public.project_products set notes = repeat('z', 1500) where id = ln;
        alter table public.project_products enable trigger trg_project_products_20_note;
      end if;
      perform set_config('request.jwt.claims', claims, true);
      perform set_config('role', 'authenticated', true);
      select current_user::text || '|uid=' || coalesce(auth.uid()::text, 'null') || '|bypassrls=' || (select rolbypassrls::text from pg_roles where rolname = current_user) into ctx;
      if ctx <> ctx_esp then raise exception 'PARA: contexto distinto en %: %', t.code, ctx; end if;
      begin
        execute t.sentencia; get diagnostics n = row_count;
        res := 'OK ' || n;
        if t.modo = 'legado' and t.esperado like 'OK%' then
          perform set_config('role', 'postgres', true);
          select char_length(notes) into len_despues from public.project_products where id = ln;
          res := res || ' | len=' || len_despues;
        end if;
        perform set_config('role', 'postgres', true);
        raise exception 'rb' using errcode = 'ZZ001';
      exception when sqlstate 'ZZ001' then null;
                when others then get stacked diagnostics m = message_text, h = pg_exception_hint; res := 'ERROR ' || sqlstate || ' | ' || m || ' | hint=' || coalesce(h, '(ninguna)');
      end;
      perform set_config('role', 'postgres', true);
      raise exception 'fin' using errcode = 'ZZ002';
    exception when sqlstate 'ZZ002' then null;
    end;
    ok := (res = t.esperado);
    informe := informe || E'\n' || case when ok then '[OK]    ' else '[FALLO] ' end || t.code || ' ' || t.descr || E'\n          resultado: ' || res || case when ok then '' else E'\n          esperado:  ' || t.esperado end;
    if ok then n_ok := n_ok + 1; else raise exception E'ENSAYO_DETENIDO_EN_EL_PRIMER_FALLO (todo revertido)%\nRESUMEN: OK=% FALLO=1', informe, n_ok; end if;
  end loop;

  perform set_config('role', 'postgres', true);
  if (select md5(lines_snapshot::text) from public.rfqs where project_id = proj) <> snap_nueva
     or (select md5(lines_snapshot::text) from public.rfqs where id = '5f284909-fc24-4215-b456-4e7858746292') <> snap_orig
     or (select notes from public.project_products where id = ln) is distinct from nota_antes
     or (select status from public.projects where id = proj) <> 'archived' then
    raise exception E'ENSAYO_DETENIDO: algo cambió dentro de la transacción (todo revertido)%', informe;
  end if;
  informe := informe || E'\n[OK]    I1 copias de las dos RFQ (md5), nota y estado archivado idénticos a la línea base tras los 10 casos';
  raise exception E'ENSAYO_46_06_REVERTIDO (todo OK)%\nRESUMEN: OK=% FALLO=0', informe, n_ok + 1;
end $T$;
