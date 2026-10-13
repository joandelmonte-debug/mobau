-- ============================================================
-- PROPUESTA NO EJECUTADA (41 · V2 · contrato de catalog_version) — no ejecutar sin aprobación explícita
-- ============================================================
-- 41 · V2 · Contrato de catalog_version(): qué cambios deben cambiar su valor
-- y cuáles no, comprobado a la vez para cuatro roles (anon, profesional,
-- distribuidor dueño A y Mobau con AAL2), en una transacción revertida.
-- ------------------------------------------------------------
-- Ejecutar después de 41-01 y 41-02. Rol postgres; JWT simulado como en 39.
--
-- Cada caso (subtransacción revertida con MB001):
--   1. auxiliares como postgres (admin temporal + los del caso);
--   2. v0 = catalog_version() como cada uno de los 4 roles;
--   3. el cambio, como postgres;
--   4. v1 = catalog_version() como cada uno de los 4 roles;
--   5. «cambia»: v0 <> v1 en los 4 roles; «igual»: v0 = v1 en los 4;
--      además, los 4 roles ven el mismo valor antes y después.
-- W20 (category_id de un producto real, con el par categoría/subcategoría de
-- otro publicado) exige además que catalog_products, como cada rol, sea igual
-- al catálogo de referencia calculado como postgres tras el cambio.
-- W19 exige que no queden restos y que los productos reales sean idénticos.
-- Los cambios de columnas de un producto (nombre, disponibilidad) se hacen
-- sobre un producto REAL publicado: su updated_at confirmado es anterior a
-- now() de esta transacción, así que el trigger de updated_at lo cambia. En
-- un auxiliar creado en la misma transacción no cambiaría (now() constante).
-- NADA queda guardado: BEGIN … ROLLBACK, MB001 por caso y MB999 final.
-- ============================================================

BEGIN;

DO $$
declare
  v_sup uuid; v_sup_dist text; v_pro uuid; v_pro2 uuid; v_pro3 uuid; v_cat1 text; v_pub_real text;
  roles constant text[] := array['anon', 'authenticated', 'authenticated', 'authenticated'];
  etiq constant text[] := array['anon', 'pro', 'own', 'm2'];
  subs text[]; aals constant text[] := array[null, 'aal1', 'aal1', 'aal2'];
  v_admin text; ins_pub text; ins_draft text; ins_rev text; ins_ret text; ins_trr text; ins_trd text; ins_price text;
  v0 text[]; v1 text[]; v_price text; v_tmp text;
  v_cat_old text; v_cat_new text; v_sub_new text; v_ref text; v_vis bigint; fpv text[]; v_real_fp text;
  q_fpv constant text := 'select count(*) || ''/'' || md5(coalesce(string_agg(to_jsonb(r)::text, ''|'' order by r.id), '''')) from (select id, name, brand, distributor_id, category_id, subcategory, use_context, space, availability, description, measurements, materials, finishes, lead_time, icon, image_url, technical_sheet_url, cad_bim_3d_url, status, created_at, updated_at from public.catalog_products) r';
  q_ref constant text := 'select count(*) || ''/'' || md5(coalesce(string_agg(to_jsonb(r)::text, ''|'' order by r.id), '''')) from (select id, name, brand, distributor_id, category_id, subcategory, use_context, space, availability, description, measurements, materials, finishes, lead_time, icon, image_url, technical_sheet_url, cad_bim_3d_url, status, created_at, updated_at from public.products where status = ''active'' and publication_status = ''published'') r';
  q_real constant text := 'select count(*) || ''/'' || md5(coalesce(string_agg(to_jsonb(r)::text, ''|'' order by r.id), '''')) from (select id, name, distributor_id, brand, category_id, subcategory, use_context, space, availability, description, measurements, materials, finishes, lead_time, icon, technical_sheet_url, cad_bim_3d_url, image_url, created_at, status, updated_at, publication_status from public.products) r';
  r jsonb := '[]'::jsonb; t record; k int; v_stmt text;
  v_got text; v_ok boolean; n_total int := 0; n_ok int := 0;
begin
  -- ---------- datos de partida (lectura como postgres) ----------
  select dp.user_id, dp.distributor_id into v_sup, v_sup_dist
    from public.distributor_profiles dp join public.profiles p on p.id = dp.user_id
   where p.role = 'supplier' and dp.verification_status = 'verified' and dp.distributor_id is not null
   order by dp.created_at limit 1;
  select p.id into v_pro from public.profiles p
   where p.role = 'individual' and not exists (select 1 from public.mobau_admins a where a.user_id = p.id)
     and not exists (select 1 from public.distributor_profiles d where d.user_id = p.id)
   order by p.created_at limit 1;
  select p.id into v_pro2 from public.profiles p
   where p.role = 'individual' and p.id <> v_pro and not exists (select 1 from public.mobau_admins a where a.user_id = p.id)
     and not exists (select 1 from public.distributor_profiles d where d.user_id = p.id)
   order by p.created_at limit 1;
  select p.id into v_pro3 from public.profiles p
   where p.role = 'individual' and p.id not in (v_pro, v_pro2) and not exists (select 1 from public.mobau_admins a where a.user_id = p.id)
     and not exists (select 1 from public.distributor_profiles d where d.user_id = p.id)
   order by p.created_at limit 1;
  select c.id into v_cat1 from public.categories c order by c.id limit 1;
  select p.id into v_pub_real from public.products p
   where p.publication_status = 'published' and p.status = 'active' and p.updated_at < now()
   order by p.id limit 1;
  if v_sup is null or v_pro is null or v_pro3 is null or v_cat1 is null or v_pub_real is null then
    raise exception 'MOBAU_41_V2_VERSION: faltan datos de partida' using errcode = 'MB998';
  end if;
  if to_regprocedure('public.catalog_version()') is null or to_regnamespace('mobau_private') is null then
    raise exception 'MOBAU_41_V2_VERSION: faltan 41-01 o 41-02' using errcode = 'MB998';
  end if;
  subs := array[null, v_pro::text, v_sup::text, v_pro3::text];
  -- W20: categoría y subcategoría válidas = el par de otro producto publicado de OTRA categoría (ya aceptado por la validación)
  select p.category_id into v_cat_old from public.products p where p.id = v_pub_real;
  select p.category_id, p.subcategory into v_cat_new, v_sub_new
    from public.products p left join public.categories c on c.id = p.category_id
   where p.publication_status = 'published' and p.status = 'active' and p.category_id is distinct from v_cat_old
   order by (p.subcategory is null), (coalesce(strpos(c.subcategories::text, p.subcategory), 0) = 0), p.id limit 1;
  execute q_real into v_real_fp;

  -- ---------- SQL auxiliar (como postgres, dentro de cada caso) ----------
  v_admin := format('insert into public.mobau_admins (user_id, granted_note) values (%L, %L)', v_pro3, 'Admin temporal de prueba 41 version');
  ins_pub := format('insert into public.products (id, name, distributor_id, category_id, publication_status) values (%L, %L, %L, %L, %L)', 'rls41v-pub', 'V publicado 41', v_sup_dist, v_cat1, 'published');
  ins_draft := format('insert into public.products (id, name, distributor_id, category_id, publication_status) values (%L, %L, %L, %L, %L)', 'rls41v-draft', 'V borrador 41', v_sup_dist, v_cat1, 'draft');
  ins_rev := format('insert into public.products (id, name, distributor_id, category_id, publication_status) values (%L, %L, %L, %L, %L)', 'rls41v-rev', 'V en revisión 41', v_sup_dist, v_cat1, 'in_review');
  ins_ret := format('insert into public.products (id, name, distributor_id, category_id, publication_status, retired_at, retired_by, retired_reason) values (%L, %L, %L, %L, %L, now(), %L, ''Motivo de prueba 41'')', 'rls41v-ret', 'V retirado 41', v_sup_dist, v_cat1, 'archived', v_pro3);
  ins_trr := format('insert into public.products (id, name, distributor_id, category_id, publication_status, retired_at, retired_by, retired_reason, trashed_at, trashed_by, trash_from, purge_after) values (%L, %L, %L, %L, %L, now(), %L, ''Motivo de prueba 41'', now(), %L, ''retired'', now() + interval ''30 days'')', 'rls41v-trr', 'V papelera (retirado) 41', v_sup_dist, v_cat1, 'archived', v_pro3, v_sup);
  ins_trd := format('insert into public.products (id, name, distributor_id, category_id, publication_status, trashed_at, trashed_by, trash_from, purge_after) values (%L, %L, %L, %L, %L, now(), %L, ''draft'', now() + interval ''30 days'')', 'rls41v-trd', 'V papelera (borrador) 41', v_sup_dist, v_cat1, 'draft', v_sup);
  ins_price := format('insert into public.product_prices (product_id, price_status, price_amount, currency, includes_itbis, price_source) values (%L, %L, 50, %L, true, %L)', 'rls41v-pub', 'published', 'USD', 'distributor');

  for t in
    select * from (values
      ('W01 publicación: alta de un producto publicado', array[]::text[],
         array[ins_pub], 'cambia', false),
      ('W02 publicación de un borrador', array[ins_draft],
         array[format('update public.products set publication_status = %L where id = %L', 'published', 'rls41v-draft')], 'cambia', false),
      ('W03 retirada de un publicado', array[ins_pub],
         array[format('update public.products set publication_status = %L, retired_at = now(), retired_by = %L, retired_reason = %L where id = %L', 'archived', v_pro3, 'Motivo de prueba 41', 'rls41v-pub')], 'cambia', false),
      ('W04 estado: despublicar (publicado → archivado; status espejo)', array[ins_pub],
         array[format('update public.products set publication_status = %L where id = %L', 'archived', 'rls41v-pub')], 'cambia', false),
      ('W05 papelera desde retirado', array[ins_ret],
         array[format('update public.products set trashed_at = now(), trashed_by = %L, trash_from = %L, purge_after = now() + interval %L where id = %L', v_sup, 'retired', '30 days', 'rls41v-ret')], 'igual', false),
      ('W06 papelera desde borrador', array[ins_draft],
         array[format('update public.products set trashed_at = now(), trashed_by = %L, trash_from = %L, purge_after = now() + interval %L where id = %L', v_sup, 'draft', '30 days', 'rls41v-draft')], 'igual', false),
      ('W07 restauración de papelera a borrador', array[ins_trd],
         array[format('update public.products set trashed_at = null, trashed_by = null, trash_from = null, purge_after = null where id = %L', 'rls41v-trd')], 'igual', false),
      ('W08 restauración de papelera a retirado', array[ins_trr],
         array[format('update public.products set trashed_at = null, trashed_by = null, trash_from = null, purge_after = null where id = %L', 'rls41v-trr')], 'igual', false),
      ('W09 republicación tras retirada', array[ins_ret],
         array[format('update public.products set publication_status = %L, retired_at = null, retired_by = null, retired_reason = null where id = %L', 'published', 'rls41v-ret')], 'cambia', false),
      ('W10 precio de un publicado: la versión no cambia y el precio se lee al momento', array[ins_pub, ins_price],
         array[format('update public.product_prices set price_amount = 55 where product_id = %L', 'rls41v-pub')], 'igual', true),
      ('W11 categoría: cambio en la tabla categories', array[]::text[],
         array[format('update public.categories set name = name || %L where id = %L', ' (prueba 41)', v_cat1)], 'cambia', false),
      ('W12 nombre de un producto real publicado', array[]::text[],
         array[format('update public.products set name = name || %L where id = %L', ' (prueba 41)', v_pub_real)], 'cambia', false),
      ('W13 disponibilidad de un producto real publicado', array[]::text[],
         array[format('update public.products set availability = case when availability = %L then %L else %L end where id = %L', 'en-stock', 'bajo-pedido', 'en-stock', v_pub_real)], 'cambia', false),
      ('W14 distribuidor real: cambio de nombre', array[]::text[],
         array[format('update public.distributors set name = name || %L where id = %L', ' (prueba 41)', v_sup_dist)], 'cambia', false),
      ('W15 perfil privado del distribuidor (no se cachea)', array[]::text[],
         array[format('update public.distributor_profiles set nombre_contacto = nombre_contacto || %L where user_id = %L', ' (prueba 41)', v_sup)], 'igual', false),
      ('W16 borrador: cambio de nombre', array[ins_draft],
         array[format('update public.products set name = name || %L where id = %L', ' (renombrado)', 'rls41v-draft')], 'igual', false),
      ('W17 en revisión: cambio de nombre', array[ins_rev],
         array[format('update public.products set name = name || %L where id = %L', ' (renombrado)', 'rls41v-rev')], 'igual', false),
      ('W18 sin cambios: dos lecturas seguidas dan el mismo valor', array[]::text[],
         array[]::text[], 'igual', false)
    ) as c(name, setup, change, expect, price_check)
  loop
    v_got := null; v0 := array[null, null, null, null]; v1 := array[null, null, null, null]; v_price := null;
    begin
      execute v_admin;
      foreach v_stmt in array t.setup loop execute v_stmt; end loop;
      for k in 1 .. 4 loop
        perform set_config('request.jwt.claim.sub', coalesce(subs[k], ''), true);
        perform set_config('request.jwt.claim.role', '', true);
        perform set_config('request.jwt.claims', case when subs[k] is null then '' else json_build_object('sub', subs[k], 'role', roles[k], 'aal', aals[k])::text end, true);
        execute format('set local role %I', roles[k]);
        execute 'select public.catalog_version()' into v_tmp; v0[k] := v_tmp;
        execute 'reset role';
      end loop;
      perform set_config('request.jwt.claims', '', true); perform set_config('request.jwt.claim.sub', '', true); perform set_config('request.jwt.claim.role', '', true);  -- identidad limpia: el cambio es administrativo (postgres, sin JWT)
      foreach v_stmt in array t.change loop execute v_stmt; end loop;
      for k in 1 .. 4 loop
        perform set_config('request.jwt.claim.sub', coalesce(subs[k], ''), true);
        perform set_config('request.jwt.claim.role', '', true);
        perform set_config('request.jwt.claims', case when subs[k] is null then '' else json_build_object('sub', subs[k], 'role', roles[k], 'aal', aals[k])::text end, true);
        execute format('set local role %I', roles[k]);
        execute 'select public.catalog_version()' into v_tmp; v1[k] := v_tmp;
        if t.price_check and k = 2 then
          execute format('select coalesce((select price_amount::text from public.catalog_published_prices(array[%L])), %L)', 'rls41v-pub', 'sin fila') into v_price;
        end if;
        execute 'reset role';
      end loop;
      perform set_config('request.jwt.claims', '', true); perform set_config('request.jwt.claim.sub', '', true); perform set_config('request.jwt.claim.role', '', true);  -- fin del caso: sin identidad heredada
      raise exception using errcode = 'MB001';
    exception
      when sqlstate 'MB001' then null;
      when others then v_got := sqlstate || ' ' || left(sqlerrm, 160);
    end;
    if v_got is null then
      v_got := (select string_agg(etiq[g.n] || ':' || case when v0[g.n] is distinct from v1[g.n] then 'cambia' else 'igual' end, ' ' order by g.n) from generate_series(1, 4) as g(n))
               || ' | mismos valores en los 4 roles antes/después: ' || coalesce((v0[1] = all (v0) and v1[1] = all (v1))::text, 'null')
               || case when t.price_check then ' | precio leído tras el cambio: ' || coalesce(v_price, 'null') else '' end;
      v_ok := coalesce((v0[1] = all (v0)) and (v1[1] = all (v1))
              and (select bool_and(case when t.expect = 'cambia' then v0[g.n] <> v1[g.n] else v0[g.n] = v1[g.n] end) from generate_series(1, 4) as g(n))
              and (not t.price_check or v_price = '55.00' or v_price = '55'), false);
    else
      v_ok := false;
    end if;
    n_total := n_total + 1;
    if v_ok then n_ok := n_ok + 1; end if;
    r := r || jsonb_build_object('prueba', t.name, 'esperado', t.expect, 'obtenido', v_got, 'ok', v_ok);
  end loop;

  -- ---------- W20: category_id de un producto REAL publicado (cambio visible) ----------
  v_got := null; v0 := array[null, null, null, null]; v1 := array[null, null, null, null]; fpv := array[null, null, null, null]; v_ref := null; v_vis := null;
  if v_cat_new is null then
    v_got := 'sin par categoría/subcategoría válido de otra categoría entre los publicados';
  else
    begin
      execute v_admin;
      for k in 1 .. 4 loop
        perform set_config('request.jwt.claim.sub', coalesce(subs[k], ''), true);
        perform set_config('request.jwt.claim.role', '', true);
        perform set_config('request.jwt.claims', case when subs[k] is null then '' else json_build_object('sub', subs[k], 'role', roles[k], 'aal', aals[k])::text end, true);
        execute format('set local role %I', roles[k]);
        execute 'select public.catalog_version()' into v_tmp; v0[k] := v_tmp;
        execute 'reset role';
      end loop;
      perform set_config('request.jwt.claims', '', true); perform set_config('request.jwt.claim.sub', '', true); perform set_config('request.jwt.claim.role', '', true);  -- identidad limpia: el cambio es administrativo (postgres, sin JWT)
      execute format('update public.products set category_id = %L, subcategory = %L where id = %L', v_cat_new, v_sub_new, v_pub_real);
      execute q_ref into v_ref;
      select count(*) into v_vis from public.catalog_products where id = v_pub_real and category_id = v_cat_new and subcategory is not distinct from v_sub_new;
      for k in 1 .. 4 loop
        perform set_config('request.jwt.claim.sub', coalesce(subs[k], ''), true);
        perform set_config('request.jwt.claim.role', '', true);
        perform set_config('request.jwt.claims', case when subs[k] is null then '' else json_build_object('sub', subs[k], 'role', roles[k], 'aal', aals[k])::text end, true);
        execute format('set local role %I', roles[k]);
        execute 'select public.catalog_version()' into v_tmp; v1[k] := v_tmp;
        execute q_fpv into v_tmp; fpv[k] := v_tmp;
        execute 'reset role';
      end loop;
      perform set_config('request.jwt.claims', '', true); perform set_config('request.jwt.claim.sub', '', true); perform set_config('request.jwt.claim.role', '', true);  -- fin del caso: sin identidad heredada
      raise exception using errcode = 'MB001';
    exception
      when sqlstate 'MB001' then null;
      when others then v_got := sqlstate || ' ' || left(sqlerrm, 160);
    end;
  end if;
  if v_got is null then
    v_got := (select string_agg(etiq[g.n] || ':' || case when v0[g.n] is distinct from v1[g.n] then 'cambia' else 'igual' end
                                || ' vista=' || case when fpv[g.n] = v_ref then 'ref' else coalesce(fpv[g.n], 'null') end, ' ' order by g.n) from generate_series(1, 4) as g(n))
             || ' | visible con la categoría nueva: ' || coalesce(v_vis::text, 'null')
             || ' | mismos valores en los 4 roles antes/después: ' || coalesce((v0[1] = all (v0) and v1[1] = all (v1))::text, 'null');
    v_ok := coalesce((v0[1] = all (v0)) and (v1[1] = all (v1)) and v_vis = 1
            and (select bool_and(v0[g.n] <> v1[g.n] and fpv[g.n] = v_ref) from generate_series(1, 4) as g(n)), false);
  else
    v_ok := false;
  end if;
  n_total := n_total + 1;
  if v_ok then n_ok := n_ok + 1; end if;
  r := r || jsonb_build_object('prueba', 'W20 category_id de un producto real publicado (categoría y subcategoría válidas): versión cambia y vista = catálogo de referencia en los 4 roles', 'esperado', 'cambia', 'obtenido', v_got, 'ok', v_ok);

  -- ---------- sin restos ----------
  perform set_config('request.jwt.claims', '', true); perform set_config('request.jwt.claim.sub', '', true); perform set_config('request.jwt.claim.role', '', true);  -- limpieza final de identidad
  n_total := n_total + 1;
  execute q_real into v_ref;
  if (select count(*) from public.products where id like 'rls41v-%') + (select count(*) from public.mobau_admins where user_id = v_pro3) = 0
     and v_ref = v_real_fp then
    n_ok := n_ok + 1;
    r := r || jsonb_build_object('prueba', 'W19 sin restos rls41v ni admin temporal; productos reales (22 columnas) iguales a los de partida', 'esperado', '0', 'obtenido', '0', 'ok', true);
  else
    r := r || jsonb_build_object('prueba', 'W19 sin restos rls41v ni admin temporal; productos reales (22 columnas) iguales a los de partida', 'esperado', '0', 'obtenido', 'quedan restos o cambios', 'ok', false);
  end if;

  raise exception 'MOBAU_41_V2_VERSION total=% ok=% fallos=% :: %', n_total, n_ok, n_total - n_ok, r::text
    using errcode = 'MB999';
end $$;

ROLLBACK;
