-- ============================================================
-- PROPUESTA NO EJECUTADA (41-06) — no ejecutar sin aprobación explícita
-- ============================================================
-- 41 · 06 · Primera activación del ciclo de vida (ventana V4)
-- ------------------------------------------------------------
-- Requiere V3 instalada y apagada (41-03a, 41-03, 41-04, 41-05) y SIN uso:
-- es SOLO para la primera activación. Transacción única. Ejecutar como postgres.
--
--   1. GRANT EXECUTE a authenticated (y a nadie más) sobre las 9 funciones de
--      entrada, con sus firmas exactas de 41-03 y 41-05.
--   2. Interruptor del servidor: enabled = true (fila id = 1).
--
-- NO cambia: cuerpos de funciones, RLS, políticas, tablas, datos de negocio,
-- auxiliares de mobau_private (siguen sin EXECUTE ni USAGE de cliente) ni
-- otras migraciones. NO concede nada a anon, PUBLIC ni service_role.
--
-- Precondiciones que NO se pueden comprobar aquí (las exige el guion de la
-- ventana antes de ejecutar este archivo): piloto sin uso confirmado y A2 de
-- D1 y D2 superada en la misma ventana.
--
-- Registro: SOLO después de confirmar el COMMIT sin error de este archivo,
-- con V4-2_registro_41_06.sql (nunca en la misma tanda).
-- Parada (inverso operativo): parada/41_06_parada.sql. No desregistra.
-- ============================================================

BEGIN;

-- Solo cambia ACL de 9 funciones y una fila de mobau_private.
set local lock_timeout = '5s';

-- ---------- 0. precondiciones (primera activación) ----------
DO $pre41_06$
declare
  f record;
  v_base text;
begin
  if current_user <> 'postgres' then
    raise exception '41-06: ejecutar como postgres';
  end if;

  -- V3 registrada; 41-06 no registrada
  if (select count(*) from supabase_migrations.schema_migrations
       where (version, name) in (('20261014120000', '41_03a_verified_distributor'), ('20261014120100', '41_03_distributor_lifecycle'),
                                 ('20261014120200', '41_04_republish'), ('20261014120300', '41_05_mobau_lifecycle'))) <> 4 then
    raise exception '41-06: V3 no está registrada completa';
  end if;
  if exists (select 1 from supabase_migrations.schema_migrations where version = '20261015120000' or name like '41_06%') then
    raise exception '41-06: ya hay un registro de 41-06 (no es una primera activación)';
  end if;

  -- interruptor apagado, una fila
  if (select count(*) from mobau_private.product_lifecycle_settings) <> 1
     or (select enabled from mobau_private.product_lifecycle_settings where id = 1)
     or mobau_private.product_lifecycle_enabled() then
    raise exception '41-06: el interruptor debe estar apagado (una fila)';
  end if;

  -- las 9 funciones de entrada: cuerpo, propiedades y ACL exacta de V3
  for f in
    select * from (values
      ('public.my_products_lifecycle()', '238308a02c5d2a4f956424c00b953aa2'),
      ('public.my_product_lifecycle_events(text)', '9f4f092494d29521d0159f29c9c94b40'),
      ('public.distributor_retire_product(text, text, timestamp with time zone)', '616219991f4be91055dc4f83124d3998'),
      ('public.distributor_trash_product(text, timestamp with time zone)', 'cb687302bb76e5c56f39c9998efb4b3e'),
      ('public.distributor_restore_product(text, timestamp with time zone)', 'fb3cbc10d5dc5ac5a8b89d6d1ee94372'),
      ('public.mobau_product_lifecycle(text, text, text, timestamp with time zone)', 'b0f0225f53ad326a35e5c3faf00ec566'),
      ('public.mobau_purge_product(text, text, text, boolean, timestamp with time zone)', '3421e8c5dec7015db2888c1d685d0f8c'),
      ('public.mobau_product_references(text)', '5ac9822c1abcc9c5949df5029e3e0686'),
      ('public.mobau_product_lifecycle_view(text)', '79d9aec3f54087bef4f3f9e38a9bc47f')
    ) as x(sig, body_md5)
  loop
    if to_regprocedure(f.sig) is null then
      raise exception '41-06: falta %', f.sig;
    end if;
    if (select md5(prosrc) from pg_proc where oid = to_regprocedure(f.sig)) is distinct from f.body_md5
       or not (select prosecdef from pg_proc where oid = to_regprocedure(f.sig))
       or not (select proconfig @> array['search_path=""'] from pg_proc where oid = to_regprocedure(f.sig))
       or (select proowner from pg_proc where oid = to_regprocedure(f.sig)) <> 'postgres'::regrole
       or (select proacl::text from pg_proc where oid = to_regprocedure(f.sig)) is distinct from '{postgres=X/postgres}'
       or has_function_privilege('anon', to_regprocedure(f.sig), 'EXECUTE')
       or has_function_privilege('authenticated', to_regprocedure(f.sig), 'EXECUTE')
       or has_function_privilege('service_role', to_regprocedure(f.sig), 'EXECUTE') then
      raise exception '41-06: % no está como la dejó V3 (cuerpo, propiedades o permisos)', f.sig;
    end if;
  end loop;

  -- privilegios EFECTIVOS de partida (roles no superusuario con EXECUTE, por
  -- concesión directa o por herencia). Deben ser iguales en las 9 funciones,
  -- incluir al propietario y no incluir ningún rol cliente. Se guardan para
  -- exigir en la validación final exactamente «partida + authenticated».
  select string_agg(distinct x.roles, ' | ') into v_base
    from (select (select string_agg(r.rolname, ',' order by r.rolname) from pg_roles r
                   where not r.rolsuper and has_function_privilege(r.oid, p.oid, 'EXECUTE')) as roles
            from pg_proc p
           where p.oid in ('public.my_products_lifecycle()'::regprocedure, 'public.my_product_lifecycle_events(text)'::regprocedure,
                           'public.distributor_retire_product(text, text, timestamp with time zone)'::regprocedure,
                           'public.distributor_trash_product(text, timestamp with time zone)'::regprocedure,
                           'public.distributor_restore_product(text, timestamp with time zone)'::regprocedure,
                           'public.mobau_product_lifecycle(text, text, text, timestamp with time zone)'::regprocedure,
                           'public.mobau_purge_product(text, text, text, boolean, timestamp with time zone)'::regprocedure,
                           'public.mobau_product_references(text)'::regprocedure,
                           'public.mobau_product_lifecycle_view(text)'::regprocedure)) x;
  if v_base is null or v_base like '% | %'
     or not ('postgres' = any (string_to_array(v_base, ',')))
     or string_to_array(v_base, ',') && array['anon', 'authenticated', 'service_role', 'authenticator'] then
    raise exception '41-06: privilegios efectivos de partida inesperados: %', v_base;
  end if;
  perform set_config('mobau.v4_exec_base', v_base, true);
  -- ningún rol cliente hereda de authenticated (si no, recibiría EXECUTE)
  if pg_has_role('anon', 'authenticated', 'USAGE') or pg_has_role('service_role', 'authenticated', 'USAGE') then
    raise exception '41-06: anon o service_role heredan de authenticated';
  end if;

  -- auxiliares y esquema privado intactos
  if (select count(*) from pg_proc where pronamespace = 'mobau_private'::regnamespace) <> 9
     or exists (select 1 from pg_proc p where p.pronamespace = 'mobau_private'::regnamespace
                 and (p.proacl is null or p.proacl::text <> '{postgres=X/postgres}'))
     or has_schema_privilege('anon', 'mobau_private', 'USAGE') or has_schema_privilege('authenticated', 'mobau_private', 'USAGE')
     or has_schema_privilege('service_role', 'mobau_private', 'USAGE') then
    raise exception '41-06: mobau_private no está como lo dejó V3';
  end if;

  -- puerta republish y moderación de V3
  if (select md5(prosrc) from pg_proc where oid = 'mobau_private.product_proposals_lifecycle_gate()'::regprocedure)
       is distinct from 'b4a6d365255e8498a8838be5e6d5fd27'
     or (select md5(prosrc) from pg_proc where oid = 'public.moderate_product_proposal(uuid, text, text, integer)'::regprocedure)
       is distinct from 'aa4fac4c25f4634499532824782ee908'
     or (select string_agg(t.tgname || ':' || t.tgtype || ':' || n.nspname || '.' || fn.proname, ',' order by t.tgname collate "C")
           from pg_trigger t join pg_proc fn on fn.oid = t.tgfoid join pg_namespace n on n.oid = fn.pronamespace
          where t.tgrelid = 'public.product_proposals'::regclass and not t.tgisinternal)
       is distinct from 'trg_product_proposals_05_lifecycle_gate:23:mobau_private.product_proposals_lifecycle_gate,trg_product_proposals_10_author:7:public.fix_proposal_author,trg_product_proposals_20_transition:19:public.transition_proposal_status,trg_product_proposals_30_validate:23:public.validate_proposal_changes,trg_product_proposals_40_snapshot:19:public.snapshot_product_on_submit,trg_product_proposals_50_updated_at:19:public.set_updated_at,trg_product_proposals_90_event_insert:5:public.log_proposal_event,trg_product_proposals_91_event_status:17:public.log_proposal_event' then
    raise exception '41-06: la puerta republish o la moderación no son las de V3';
  end if;

  -- sin uso: 0 eventos, 0 republish, 0 productos con datos de ciclo de vida, sin restos
  if exists (select 1 from mobau_private.product_lifecycle_events) then
    raise exception '41-06: la auditoría de ciclo de vida no está vacía (no es una primera activación)';
  end if;
  if exists (select 1 from public.product_proposals where proposal_kind = 'republish') then
    raise exception '41-06: ya hay propuestas republish';
  end if;
  if exists (select 1 from public.products
              where retired_at is not null or trashed_at is not null or retired_by is not null or trashed_by is not null
                 or trash_from is not null or purge_after is not null) then
    raise exception '41-06: hay productos con datos de ciclo de vida';
  end if;
  if exists (select 1 from public.products where id like 'rls41%')
     or exists (select 1 from public.distributors where id like 'rls41%') then
    raise exception '41-06: hay restos de pruebas rls41';
  end if;
  if (select count(*) from pg_policies where schemaname = 'public') <> 48 then
    raise exception '41-06: se esperaban 48 políticas';
  end if;
end $pre41_06$;

-- ---------- 1. EXECUTE solo para authenticated (firmas exactas) ----------
grant execute on function public.my_products_lifecycle() to authenticated;
grant execute on function public.my_product_lifecycle_events(text) to authenticated;
grant execute on function public.distributor_retire_product(text, text, timestamptz) to authenticated;
grant execute on function public.distributor_trash_product(text, timestamptz) to authenticated;
grant execute on function public.distributor_restore_product(text, timestamptz) to authenticated;
grant execute on function public.mobau_product_lifecycle(text, text, text, timestamptz) to authenticated;
grant execute on function public.mobau_purge_product(text, text, text, boolean, timestamptz) to authenticated;
grant execute on function public.mobau_product_references(text) to authenticated;
grant execute on function public.mobau_product_lifecycle_view(text) to authenticated;

-- ---------- 2. interruptor del servidor ----------
update mobau_private.product_lifecycle_settings
   set enabled = true, changed_at = now(), changed_by = null,
       note = '41-06: primera activación (ventana V4)'
 where id = 1 and enabled = false;

-- ---------- 3. validación final (privilegios efectivos, no solo ACL) ----------
DO $post41_06$
declare
  f record;
  v_roles text;
  v_expected text;
begin
  select string_agg(x, ',' order by x) into v_expected
    from unnest(string_to_array(current_setting('mobau.v4_exec_base'), ',') || 'authenticated'::text) x;
  if (select count(*) from mobau_private.product_lifecycle_settings) <> 1
     or not (select enabled from mobau_private.product_lifecycle_settings where id = 1)
     or not mobau_private.product_lifecycle_enabled() then
    raise exception '41-06: el interruptor no quedó encendido';
  end if;
  for f in
    select * from (values
      ('public.my_products_lifecycle()'),
      ('public.my_product_lifecycle_events(text)'),
      ('public.distributor_retire_product(text, text, timestamp with time zone)'),
      ('public.distributor_trash_product(text, timestamp with time zone)'),
      ('public.distributor_restore_product(text, timestamp with time zone)'),
      ('public.mobau_product_lifecycle(text, text, text, timestamp with time zone)'),
      ('public.mobau_purge_product(text, text, text, boolean, timestamp with time zone)'),
      ('public.mobau_product_references(text)'),
      ('public.mobau_product_lifecycle_view(text)')
    ) as x(sig)
  loop
    -- ACL exacta
    if (select proacl::text from pg_proc where oid = to_regprocedure(f.sig))
       is distinct from '{postgres=X/postgres,authenticated=X/postgres}' then
      raise exception '41-06: ACL inesperada en %: %', f.sig, (select proacl::text from pg_proc where oid = to_regprocedure(f.sig));
    end if;
    -- PUBLIC sin entrada (grantee 0)
    if exists (select 1 from pg_proc p, aclexplode(p.proacl) a where p.oid = to_regprocedure(f.sig) and a.grantee = 0) then
      raise exception '41-06: PUBLIC tiene EXECUTE en %', f.sig;
    end if;
    -- privilegios efectivos: exactamente los de partida + authenticated
    -- (si otro rol heredara de authenticated, aparecería aquí y se aborta)
    select string_agg(r.rolname, ',' order by r.rolname) into v_roles
      from pg_roles r where not r.rolsuper and has_function_privilege(r.oid, to_regprocedure(f.sig), 'EXECUTE');
    if v_roles is distinct from v_expected then
      raise exception '41-06: privilegios efectivos inesperados en %: % (esperado %)', f.sig, v_roles, v_expected;
    end if;
    if has_function_privilege('anon', to_regprocedure(f.sig), 'EXECUTE')
       or has_function_privilege('service_role', to_regprocedure(f.sig), 'EXECUTE')
       or not has_function_privilege('authenticated', to_regprocedure(f.sig), 'EXECUTE') then
      raise exception '41-06: EXECUTE efectivo incorrecto en %', f.sig;
    end if;
  end loop;
  -- nada más ha cambiado
  if (select count(*) from pg_proc where pronamespace = 'mobau_private'::regnamespace) <> 9
     or exists (select 1 from pg_proc p where p.pronamespace = 'mobau_private'::regnamespace
                 and (p.proacl is null or p.proacl::text <> '{postgres=X/postgres}'))
     or has_schema_privilege('anon', 'mobau_private', 'USAGE') or has_schema_privilege('authenticated', 'mobau_private', 'USAGE')
     or has_schema_privilege('service_role', 'mobau_private', 'USAGE') then
    raise exception '41-06: mobau_private cambió';
  end if;
  if exists (select 1 from mobau_private.product_lifecycle_events)
     or exists (select 1 from public.product_proposals where proposal_kind = 'republish')
     or (select count(*) from pg_policies where schemaname = 'public') <> 48 then
    raise exception '41-06: ha cambiado algo que no debía cambiar';
  end if;
  raise notice '41-06 OK: interruptor encendido; 9 funciones con EXECUTE solo para authenticated.';
end $post41_06$;

COMMIT;
