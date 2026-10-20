-- 43 · lectura de la limpieza Hotmail (solo SELECT). Antes y después de la
-- limpieza, del ensayo y ante cualquier respuesta ambigua. No escribe nada.
select 'cuenta' k, (select role || ' · ' || plan || ' · ' || plan_source || ' · ' || subscription_status from public.profiles where id = '46ea4397-f881-4db8-89e7-f164293a1143') v
union all select 'proyectos de la cuenta', coalesce((select string_agg(id::text || ' ' || name || ' (' || status || ')', ' | ' order by id) from public.projects where owner_user_id = '46ea4397-f881-4db8-89e7-f164293a1143'), 'ninguno')
union all select 'líneas de esos proyectos', (select count(*)::text from public.project_products where project_id = any (array['a078dbfe-939b-42e7-aa5b-abe4b50ce9ed', 'b3444724-d7aa-4bb4-8791-6b175365ebae']::uuid[]))
union all select 'solicitudes / moodboards vinculados', (select count(*)::text from public.rfqs where project_id = any (array['a078dbfe-939b-42e7-aa5b-abe4b50ce9ed', 'b3444724-d7aa-4bb4-8791-6b175365ebae']::uuid[]) or requester_user_id = '46ea4397-f881-4db8-89e7-f164293a1143')
                   || ' / ' || (select count(*)::text from public.moodboards where project_id = any (array['a078dbfe-939b-42e7-aa5b-abe4b50ce9ed', 'b3444724-d7aa-4bb4-8791-6b175365ebae']::uuid[]))
union all select 'huella de las filas de la cuenta (copia = 931b6f7abc65a175d4da71b89478fb38)', md5(coalesce((select string_agg(to_jsonb(pr)::text, '|' order by pr.id) from public.projects pr where pr.owner_user_id = '46ea4397-f881-4db8-89e7-f164293a1143'), '')
      || '#' || coalesce((select string_agg(to_jsonb(pp)::text, '|' order by pp.id) from public.project_products pp where pp.project_id = any (array['a078dbfe-939b-42e7-aa5b-abe4b50ce9ed', 'b3444724-d7aa-4bb4-8791-6b175365ebae']::uuid[])), ''))
union all select 'huella del resto', md5(coalesce((select string_agg(id::text || status || owner_user_id::text || name || updated_at::text, '|' order by id) from public.projects where not (id = any (array['a078dbfe-939b-42e7-aa5b-abe4b50ce9ed', 'b3444724-d7aa-4bb4-8791-6b175365ebae']::uuid[]))), '')
      || coalesce((select string_agg(id::text || project_id::text || quantity::text || coalesce(unit, '-'), '|' order by id) from public.project_products where not (project_id = any (array['a078dbfe-939b-42e7-aa5b-abe4b50ce9ed', 'b3444724-d7aa-4bb4-8791-6b175365ebae']::uuid[]))), '')
      || coalesce((select string_agg(id::text || status, '|' order by id) from public.rfqs), '')
      || (select count(*)::text from public.rfq_distributors)
      || (select count(*)::text from public.moodboards)
      || coalesce((select string_agg(id::text || plan || role || plan_source || subscription_status, '|' order by id) from public.profiles), ''))
union all select 'totales (proyectos / líneas / solicitudes)', (select count(*)::text from public.projects) || ' / ' || (select count(*)::text from public.project_products) || ' / ' || (select count(*)::text from public.rfqs);
