-- ============================================================
-- RECUPERACIÓN NO EJECUTADA (43 · R-D4, inversa de D4) — no ejecutar sin aprobación explícita
-- ============================================================
-- Retira nombre y apellidos separados. professional_name ya contiene
-- «Nombre Apellidos» en los perfiles que los indicaron, así que ningún nombre
-- visible se pierde; solo se pierde la separación entre nombre y apellidos.
-- ANTES: la web debe volver a una versión que no escriba first_name ni
-- last_name (la interfaz de 43-C1 fallaría al guardar el perfil).
-- Ejecutar completo.
-- ============================================================

BEGIN;

DO $$
begin
  if current_user <> 'postgres' then
    raise exception '43-RD4: ejecutar como postgres';
  end if;
  if (select count(*) from information_schema.columns where table_schema = 'public' and table_name = 'professional_profiles'
      and column_name in ('first_name', 'last_name')) <> 2
     or to_regprocedure('public.professional_profiles_sync_name()') is null then
    raise exception '43-RD4: D4 no está aplicada';
  end if;
  perform set_config('mobau.rd4_nombres',
    coalesce((select md5(string_agg(user_id::text || ':' || professional_name, '|' order by user_id)) from public.professional_profiles), '-'),
    true);
end $$;

drop trigger trg_professional_profiles_sync_name on public.professional_profiles;
drop function public.professional_profiles_sync_name();
alter table public.professional_profiles drop constraint professional_profiles_name_parts_check;
alter table public.professional_profiles drop column first_name, drop column last_name;

DO $$
begin
  if exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'professional_profiles'
             and column_name in ('first_name', 'last_name'))
     or to_regprocedure('public.professional_profiles_sync_name()') is not null then
    raise exception '43-RD4: quedan objetos de D4';
  end if;
  if coalesce((select md5(string_agg(user_id::text || ':' || professional_name, '|' order by user_id)) from public.professional_profiles), '-')
     <> current_setting('mobau.rd4_nombres') then
    raise exception '43-RD4: ha cambiado algún nombre visible';
  end if;
end $$;

COMMIT;
