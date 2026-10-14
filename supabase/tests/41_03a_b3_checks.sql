-- ============================================================
-- PROPUESTA NO EJECUTADA (41-03a · B3) — no ejecutar sin aprobación explícita
-- ============================================================
-- 41 · 03a · Regla única de distribuidor verificado (B3-EQ), en una
-- transacción revertida. Ejecutar después de 41-03a. Rol postgres; JWT
-- simulado como en 39 (rol con SET LOCAL ROLE; claims con set_config).
--
-- Identidades (todas existen; no se crea ninguna cuenta):
--   A   distribuidor verificado real (supplier)
--   B   2.º perfil 'individual', vinculado SOLO dentro de cada caso a
--       'rls41v3-dist-b' (verificado); según el caso, con role = 'supplier'
--       también solo dentro del caso
--   P   3.er perfil 'individual' (sin empresa)
-- Formato de expect en 'exec': SQLSTATE (5) o SQLSTATE[hint] exactos.
-- NADA queda guardado: cada caso es una subtransacción (MB001) y el final
-- es MB999 con el resumen.
-- ============================================================

BEGIN;

DO $$
declare
  v_sup uuid; v_sup_dist text; v_pro2 uuid; v_pro3 uuid; v_cat1 text;
  s_dist_b text; s_dp_b text; s_dp_b_pending text; s_dp_b_rejected text; s_role_b text; s_prod_b text;
  r jsonb := '[]'::jsonb; t record; i int;
  v_got text; v_n bigint; v_ok boolean; v_stmt text; v_hint text;
  n_total int := 0; n_ok int := 0;
  dp_cols constant text := 'insert into public.distributor_profiles (user_id, nombre_comercial, razon_social, rnc, direccion_fiscal, telefono, email_contacto, nombre_contacto, cargo_contacto, verification_status, verified_at, distributor_id%s)'
                           || ' values (%L, %L, %L, %L, %L, %L, %L, %L, %L, %L, %s, %L%s)';
begin
  select dp.user_id, dp.distributor_id into v_sup, v_sup_dist
    from public.distributor_profiles dp join public.profiles p on p.id = dp.user_id
   where p.role = 'supplier' and dp.verification_status = 'verified' and dp.distributor_id is not null
   order by dp.created_at limit 1;
  select p.id into v_pro2 from public.profiles p
   where p.role = 'individual' and not exists (select 1 from public.mobau_admins a where a.user_id = p.id)
     and not exists (select 1 from public.distributor_profiles dp where dp.user_id = p.id)
   order by p.created_at offset 1 limit 1;
  select p.id into v_pro3 from public.profiles p
   where p.role = 'individual' and p.id <> v_pro2 and not exists (select 1 from public.mobau_admins a where a.user_id = p.id)
     and not exists (select 1 from public.distributor_profiles dp where dp.user_id = p.id)
   order by p.created_at offset 2 limit 1;
  select c.id into v_cat1 from public.categories c order by c.id limit 1;
  if v_sup is null or v_pro2 is null or v_pro3 is null or v_cat1 is null then
    raise exception 'MOBAU_41_03A: faltan datos de partida' using errcode = 'MB998';
  end if;
  if to_regprocedure('mobau_private.resolve_verified_distributor(uuid)') is null then
    raise exception 'MOBAU_41_03A: falta 41-03a' using errcode = 'MB998';
  end if;

  s_dist_b := format('insert into public.distributors (id, name) values (%L, %L)', 'rls41v3-dist-b', 'Distribuidor B (prueba 41 V3)');
  s_dp_b := format(dp_cols, '', v_pro2, 'Prueba 41 V3 B', 'Prueba 41 V3 B SRL', '999999943', 'Calle de prueba 41', '0000000043',
                   'prueba41v3@example.invalid', 'Contacto prueba 41', 'Prueba', 'verified', 'now()', 'rls41v3-dist-b', '');
  s_dp_b_pending := format(dp_cols, '', v_pro2, 'Prueba 41 V3 B', 'Prueba 41 V3 B SRL', '999999943', 'Calle de prueba 41', '0000000043',
                   'prueba41v3@example.invalid', 'Contacto prueba 41', 'Prueba', 'pending_verification', 'null', 'rls41v3-dist-b', '');
  s_dp_b_rejected := format(dp_cols, ', rejection_reason', v_pro2, 'Prueba 41 V3 B', 'Prueba 41 V3 B SRL', '999999943', 'Calle de prueba 41', '0000000043',
                   'prueba41v3@example.invalid', 'Contacto prueba 41', 'Prueba', 'rejected', 'null', 'rls41v3-dist-b', ', ''Motivo de prueba 41''');
  s_role_b := format('update public.profiles set role = %L where id = %L', 'supplier', v_pro2);
  s_prod_b := format('insert into public.products (id, name, distributor_id, category_id, publication_status) values (%L, %L, %L, %L, %L)',
                     'rls41v3-b-draft', 'B borrador 41 V3', 'rls41v3-dist-b', v_cat1, 'draft');

  for t in
    select * from (values
      -- ---------- la regla ----------
      ('B01 A (supplier verificado real): my_verified_distributor_id() = su empresa', 'authenticated', v_sup::text, 'aal1', null::text[],
         array[format('select count(*) where public.my_verified_distributor_id() = %L', v_sup_dist)]::text[], 'count', '1'),
      ('B02 auxiliar como postgres para A = su empresa', '-', null, null, null::text[],
         array[format('select count(*) where mobau_private.resolve_verified_distributor(%L::uuid) = %L', v_sup, v_sup_dist)], 'count', '1'),
      ('B03 B verificado SIN role supplier → null (cierra el hueco de B3)', 'authenticated', v_pro2::text, 'aal1', array[s_dist_b, s_dp_b],
         array['select count(*) where public.my_verified_distributor_id() is null'], 'count', '1'),
      ('B04 B verificado CON role supplier (solo en el caso) → rls41v3-dist-b', 'authenticated', v_pro2::text, 'aal1', array[s_dist_b, s_dp_b, s_role_b],
         array['select count(*) where public.my_verified_distributor_id() = ''rls41v3-dist-b'''], 'count', '1'),
      ('B05 B supplier con empresa pendiente → null', 'authenticated', v_pro2::text, 'aal1', array[s_dist_b, s_dp_b_pending, s_role_b],
         array['select count(*) where public.my_verified_distributor_id() is null'], 'count', '1'),
      ('B06 B supplier con empresa rechazada → null', 'authenticated', v_pro2::text, 'aal1', array[s_dist_b, s_dp_b_rejected, s_role_b],
         array['select count(*) where public.my_verified_distributor_id() is null'], 'count', '1'),
      ('B07 profesional sin empresa → null', 'authenticated', v_pro3::text, 'aal1', null::text[],
         array['select count(*) where public.my_verified_distributor_id() is null'], 'count', '1'),
      ('B08 authenticated con JWT sin sub → null', 'authenticated', 'nosub', 'aal1', null::text[],
         array['select count(*) where public.my_verified_distributor_id() is null'], 'count', '1'),
      ('B09 auxiliar con uid nulo → null', '-', null, null, null::text[],
         array['select count(*) where mobau_private.resolve_verified_distributor(null) is null'], 'count', '1'),
      -- ---------- efectos en 38–40 (RLS y triggers usan la regla) ----------
      ('B10 B verificado sin supplier NO ve su producto (products_select_own)', 'authenticated', v_pro2::text, 'aal1', array[s_dist_b, s_dp_b, s_prod_b],
         array['select count(*) from public.products where id = ''rls41v3-b-draft'''], 'count', '0'),
      ('B11 B verificado supplier SÍ ve su borrador', 'authenticated', v_pro2::text, 'aal1', array[s_dist_b, s_dp_b, s_role_b, s_prod_b],
         array['select count(*) from public.products where id = ''rls41v3-b-draft'''], 'count', '1'),
      ('B12 B verificado sin supplier NO crea propuestas (42501)', 'authenticated', v_pro2::text, 'aal1', array[s_dist_b, s_dp_b, s_prod_b],
         array[format('insert into public.product_proposals (proposal_kind, product_id, proposed_changes) values (%L, %L, %L)', 'update', 'rls41v3-b-draft', '{"name": "Cambio 41 V3"}')], 'exec', '42501'),
      ('B13 B verificado supplier SÍ crea su borrador de propuesta', 'authenticated', v_pro2::text, 'aal1', array[s_dist_b, s_dp_b, s_role_b, s_prod_b],
         array[format('insert into public.product_proposals (proposal_kind, product_id, proposed_changes) values (%L, %L, %L)', 'update', 'rls41v3-b-draft', '{"name": "Cambio 41 V3"}')], 'exec', 'ok'),
      ('B14 A sigue creando borradores de propuesta como hoy', 'authenticated', v_sup::text, 'aal1', null::text[],
         array[format('insert into public.product_proposals (proposal_kind, proposed_changes) values (%L, %L)', 'create', '{"name": "Nuevo 41 V3 B3"}')], 'exec', 'ok'),
      -- ---------- permisos ----------
      ('B15 anon no ejecuta my_verified_distributor_id() (como antes)', 'anon', null, null, null::text[],
         array['select public.my_verified_distributor_id()'], 'exec', '42501'),
      ('B16 authenticated no puede llamar al auxiliar (sin USAGE de mobau_private)', 'authenticated', v_sup::text, 'aal1', null::text[],
         array[format('select mobau_private.resolve_verified_distributor(%L::uuid)', v_sup)], 'exec', '42501'),
      ('B17 auxiliar: ACL {postgres=X/postgres}, sin EXECUTE de anon/authenticated/service_role, invoker, STABLE', '-', null, null, null::text[],
         array['select count(*) from pg_proc p where p.oid = ''mobau_private.resolve_verified_distributor(uuid)''::regprocedure'
               || ' and p.proacl::text = ''{postgres=X/postgres}'' and not p.prosecdef and p.provolatile = ''s'''
               || ' and not has_function_privilege(''anon'', p.oid, ''EXECUTE'') and not has_function_privilege(''authenticated'', p.oid, ''EXECUTE'')'
               || ' and not has_function_privilege(''service_role'', p.oid, ''EXECUTE'')'], 'count', '1'),
      ('B18 my_verified_distributor_id(): cuerpo de 41-03a, definer, STABLE, search_path vacío, postgres; authenticated sí, anon no', '-', null, null, null::text[],
         array['select count(*) from pg_proc p where p.oid = ''public.my_verified_distributor_id()''::regprocedure'
               || ' and md5(p.prosrc) = ''c4c85af9dc9fde6d93f9fb25a56d1b87'''
               || ' and p.prosecdef and p.provolatile = ''s'' and p.proconfig @> array[''search_path=""''] and p.proowner = ''postgres''::regrole'
               || ' and has_function_privilege(''authenticated'', p.oid, ''EXECUTE'') and not has_function_privilege(''anon'', p.oid, ''EXECUTE'')'], 'count', '1'),
      -- ---------- datos reales ----------
      ('B19 PUERTA B3 con datos reales: 0 verificados cuyo rol no es supplier', '-', null, null, null::text[],
         array['select count(*) from public.distributor_profiles dp left join public.profiles pr on pr.id = dp.user_id'
               || ' where dp.verification_status = ''verified'' and dp.distributor_id is not null and pr.role is distinct from ''supplier'''], 'count', '0'),
      ('B20 regla nueva = regla anterior para todas las cuentas reales', '-', null, null, null::text[],
         array['select count(*) from (select p.id as uid from public.profiles p union select dp.user_id from public.distributor_profiles dp) u'
               || ' where mobau_private.resolve_verified_distributor(u.uid) is distinct from (select dp.distributor_id from public.distributor_profiles dp'
               || ' where dp.user_id = u.uid and dp.verification_status = ''verified'' and dp.distributor_id is not null)'], 'count', '0'),
      ('B21 sin restos: rls41v3 en products, distributors y perfiles', '-', null, null, null::text[],
         array['select (select count(*) from public.products where id like ''rls41v3%'') + (select count(*) from public.distributors where id like ''rls41v3%'')'
               || ' + (select count(*) from public.distributor_profiles where distributor_id like ''rls41v3%'')'], 'count', '0'),
      ('B22 B sigue siendo individual fuera de los casos', '-', null, null, null::text[],
         array[format('select count(*) from public.profiles where id = %L and role = %L', v_pro2, 'individual')], 'count', '1')
    ) as c(name, role, sub, aal, setup, sql, kind, expect)
  loop
    v_got := null;
    begin
      if t.setup is not null then
        foreach v_stmt in array t.setup loop execute v_stmt; end loop;
      end if;
      if t.role <> '-' then execute format('set local role %I', t.role); end if;
      perform set_config('request.jwt.claim.sub', case when t.sub is null or t.sub = 'nosub' then '' else t.sub end, true);
      perform set_config('request.jwt.claim.role', '', true);
      perform set_config('request.jwt.claims',
        case when t.sub is null then ''
             when t.sub = 'nosub' then json_build_object('role', 'authenticated', 'aud', 'authenticated', 'aal', 'aal1')::text
             else json_build_object('sub', t.sub, 'role', t.role, 'aal', t.aal)::text end, true);
      for i in 1 .. array_length(t.sql, 1) loop
        if i < array_length(t.sql, 1) then
          execute t.sql[i];
        elsif t.kind = 'count' then
          execute t.sql[i] into v_n; v_got := v_n::text;
        elsif t.kind = 'text' then
          execute t.sql[i] into v_got;
        else
          execute t.sql[i]; get diagnostics v_n = row_count; v_got := 'ok rows=' || v_n;
        end if;
      end loop;
      raise exception using errcode = 'MB001';
    exception
      when sqlstate 'MB001' then null;
      when others then
        get stacked diagnostics v_hint = pg_exception_hint;
        v_got := sqlstate || ' [' || coalesce(v_hint, '') || '] ' || left(sqlerrm, 160);
    end;
    v_ok := case
      when t.kind = 'exec' and t.expect ~ '^[0-9A-Z]{5}\[' then left(v_got, length(t.expect) + 1) = substr(t.expect, 1, 5) || ' ' || substr(t.expect, 6)
      when t.kind = 'exec' and t.expect ~ '^[0-9A-Z]{5}$' then left(v_got, 6) = t.expect || ' '
      when t.expect = 'ok' then v_got like 'ok rows=%' and v_got <> 'ok rows=0'
      else v_got = t.expect
    end;
    n_total := n_total + 1;
    if v_ok then n_ok := n_ok + 1; end if;
    r := r || jsonb_build_object('prueba', t.name, 'esperado', t.expect, 'obtenido', v_got, 'ok', coalesce(v_ok, false));
  end loop;

  raise exception 'MOBAU_41_03A_B3 total=% ok=% fallos=% :: %', n_total, n_ok, n_total - n_ok, r::text
    using errcode = 'MB999';
end $$;

ROLLBACK;
