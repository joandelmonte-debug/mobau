-- ============================================================
-- PROPUESTA NO EJECUTADA (39-06) — no ejecutar sin aprobación explícita
-- ============================================================
-- 39 · 06 · ROLLBACK · Privacidad de product_prices
-- ------------------------------------------------------------
-- ADVERTENCIA: este rollback REABRE la exposición de precios (R1 y R2):
-- cualquier usuario autenticado vuelve a leer todas las columnas del
-- precio de cualquier producto publicado, incluidos importes con estado no
-- publicado y campos internos, y anon recupera SELECT sobre la tabla
-- (aunque sin política siga viendo 0 filas).
--
-- Por eso se niega salvo confirmación explícita en la misma transacción:
-- descomentar la línea marcada «CONFIRMACIÓN» antes de ejecutar, y solo
-- con autorización. Restaura exactamente la definición y los permisos
-- previos a 39-06 y comprueba el MD5 de las 47 políticas
-- (77e501e24bdd8b4af3dd2cc025d23c5f). No toca catalog_published_prices
-- (39-05), que puede quedarse: solo devuelve importes publicados.
-- Ejecutar completo.
-- ============================================================

BEGIN;

-- CONFIRMACIÓN (descomentar solo con autorización expresa):
-- select set_config('mobau.reabrir_exposicion_precios', 'confirmo', true);

DO $$
begin
  if coalesce(current_setting('mobau.reabrir_exposicion_precios', true), '') <> 'confirmo' then
    raise exception '39-06 rollback: reabre la exposición de precios R1/R2; falta la confirmación explícita';
  end if;
  if (select string_agg(policyname, ',' order by policyname) from pg_policies
       where schemaname = 'public' and tablename = 'product_prices')
     <> 'product_prices_insert_own,product_prices_select_mobau,product_prices_select_own,product_prices_update_own' then
    raise exception '39-06 rollback: 39-06 no está aplicada tal como se aprobó';
  end if;
  if (select count(*) from pg_policies where schemaname = 'public') <> 48 then
    raise exception '39-06 rollback: se esperaban 48 políticas';
  end if;
end $$;

drop policy product_prices_select_mobau on public.product_prices;
drop policy product_prices_select_own on public.product_prices;

create policy product_prices_select_authenticated
  on public.product_prices
  for select
  to authenticated
  using (exists (select 1 from public.products p where p.id = product_prices.product_id));

grant select, references, trigger on table public.product_prices to anon;
grant references, trigger on table public.product_prices to authenticated;

DO $$
begin
  if (select count(*) from pg_policies where schemaname = 'public') <> 47
     or (select md5(string_agg(concat_ws('#', tablename, policyname, permissive, roles::text, cmd, qual, with_check), '|' order by tablename, policyname))
           from pg_policies where schemaname = 'public') <> '77e501e24bdd8b4af3dd2cc025d23c5f' then
    raise exception '39-06 rollback: las políticas no quedaron idénticas a las previas a 39-06';
  end if;
  if not has_table_privilege('anon', 'public.product_prices', 'SELECT')
     or not has_table_privilege('authenticated', 'public.product_prices', 'SELECT,REFERENCES,TRIGGER') then
    raise exception '39-06 rollback: no se restauraron los permisos previos';
  end if;
  raise notice '39-06 rollback OK: estado previo restaurado (exposición R1/R2 reabierta).';
end $$;

COMMIT;
