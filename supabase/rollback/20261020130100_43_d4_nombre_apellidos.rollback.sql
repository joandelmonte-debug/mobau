-- ============================================================
-- RECUPERACIÓN NO EJECUTADA (43 · R-D4 conservadora, inversa de D4) — no ejecutar sin aprobación explícita
-- ============================================================
-- Como R-D4, pero antes de quitar las columnas copia los nombres y apellidos
-- ya separados a mobau_private.professional_name_parts_backup (sin acceso de
-- clientes), para no perder los datos de identidad guardados después de
-- publicar. professional_name ya contiene «Nombre Apellidos», así que ningún
-- nombre visible cambia. Si D4 se vuelve a aplicar, las partes se pueden
-- restaurar desde esa copia con un SQL aparte y autorizado.
-- ANTES: la web debe volver a una versión que no escriba first_name ni
-- last_name, y la edición de perfiles queda en pausa hasta el COMMIT.
-- Dentro de la transacción, el bloqueo SHARE ROW EXCLUSIVE impide escribir
-- en professional_profiles (las lecturas siguen) desde la copia hasta quitar
-- las columnas; si no lo obtiene en 10 s, se detiene sin cambiar nada.
-- Registro: tras confirmar el COMMIT, se registra como migración nueva con
-- versión y nombre propios; la fila de D4 en schema_migrations no se borra.
-- Ejecutar completo.
-- ============================================================

BEGIN;

set local lock_timeout = '10s';
lock table public.professional_profiles in share row exclusive mode;

DO $$
begin
  if current_user <> 'postgres' then
    raise exception '43-RD4C: ejecutar como postgres';
  end if;
  if (select count(*) from information_schema.columns where table_schema = 'public' and table_name = 'professional_profiles'
      and column_name in ('first_name', 'last_name')) <> 2
     or to_regprocedure('public.professional_profiles_sync_name()') is null then
    raise exception '43-RD4C: D4 no está aplicada';
  end if;
  if to_regclass('mobau_private.professional_name_parts_backup') is not null then
    raise exception '43-RD4C: ya existe la copia de nombres y apellidos; revísala antes de continuar';
  end if;
  perform set_config('mobau.rd4c_nombres',
    coalesce((select md5(string_agg(user_id::text || ':' || professional_name, '|' order by user_id)) from public.professional_profiles), '-'),
    true);
  perform set_config('mobau.rd4c_partes',
    (select count(*)::text from public.professional_profiles where first_name is not null), true);
end $$;

create table mobau_private.professional_name_parts_backup (
  user_id uuid primary key,
  first_name text not null,
  last_name text not null,
  professional_name text not null,
  saved_at timestamptz not null default now()
);
alter table mobau_private.professional_name_parts_backup enable row level security;
revoke all on table mobau_private.professional_name_parts_backup from public, anon, authenticated;

insert into mobau_private.professional_name_parts_backup (user_id, first_name, last_name, professional_name)
select user_id, first_name, last_name, professional_name
  from public.professional_profiles
 where first_name is not null;

drop trigger trg_professional_profiles_sync_name on public.professional_profiles;
drop function public.professional_profiles_sync_name();
alter table public.professional_profiles drop constraint professional_profiles_name_parts_check;
alter table public.professional_profiles drop column first_name, drop column last_name;

DO $$
begin
  if exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'professional_profiles'
             and column_name in ('first_name', 'last_name'))
     or to_regprocedure('public.professional_profiles_sync_name()') is not null then
    raise exception '43-RD4C: quedan objetos de D4';
  end if;
  if (select count(*)::text from mobau_private.professional_name_parts_backup) <> current_setting('mobau.rd4c_partes') then
    raise exception '43-RD4C: la copia no tiene todos los nombres y apellidos separados';
  end if;
  if coalesce((select md5(string_agg(user_id::text || ':' || professional_name, '|' order by user_id)) from public.professional_profiles), '-')
     <> current_setting('mobau.rd4c_nombres') then
    raise exception '43-RD4C: ha cambiado algún nombre visible';
  end if;
  if exists (select 1 from unnest(array['anon', 'authenticated']) r,
                           unnest(array['SELECT', 'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER']) p
             where has_table_privilege(r, 'mobau_private.professional_name_parts_backup', p))
     or not (select relrowsecurity from pg_class where oid = 'mobau_private.professional_name_parts_backup'::regclass) then
    raise exception '43-RD4C: la copia tiene permisos de cliente o no tiene RLS';
  end if;
end $$;

COMMIT;
