-- ============================================================
-- PROPUESTA NO EJECUTADA (43-D4 · 43-C1 · nombre y apellidos) — no ejecutar sin aprobación explícita
-- ============================================================
-- 43 · 43-C1 · Nombre y apellidos en campos separados del perfil profesional.
--   * professional_profiles.first_name y last_name (text, NULL permitido):
--     las filas existentes quedan sin partes; no se divide ningún nombre.
--   * Fuente de verdad: cuando existen nombre y apellidos, mandan ellos y
--     professional_name se calcula siempre como «Nombre Apellidos» (trigger
--     BEFORE INSERT OR UPDATE). Así nunca hay campos contradictorios y los
--     lectores actuales de professional_name siguen funcionando.
--   * Un perfil anterior (sin partes) conserva su professional_name tal cual
--     hasta que su titular indique nombre y apellidos al editar.
--   * Una vez indicadas, las partes no pueden volver a quedar vacías.
--   * Restricción: las dos partes o ninguna, de 1 a 60 caracteres.
-- No toca Auth (ni handle_new_user ni metadatos) ni profiles.name.
-- Ejecutar completo.
-- ============================================================

BEGIN;

DO $$
begin
  if current_user <> 'postgres' then
    raise exception '43-D4: ejecutar como postgres';
  end if;
  if to_regclass('public.professional_profiles') is null
     or exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'professional_profiles'
                and column_name in ('first_name', 'last_name'))
     or to_regprocedure('public.professional_profiles_sync_name()') is not null
     or exists (select 1 from pg_constraint where conname = 'professional_profiles_name_parts_check') then
    raise exception '43-D4: el estado de partida no es el esperado (ya existen columnas, función o restricción de D4)';
  end if;
  -- Huella de los nombres actuales: la migración no debe cambiar ninguno.
  perform set_config('mobau.d4_nombres',
    coalesce((select md5(string_agg(user_id::text || ':' || professional_name, '|' order by user_id)) from public.professional_profiles), '-'),
    true);
end $$;

alter table public.professional_profiles
  add column first_name text,
  add column last_name text;

alter table public.professional_profiles
  add constraint professional_profiles_name_parts_check
  check ((first_name is null) = (last_name is null)
         and (first_name is null
              or (char_length(first_name) between 1 and 60 and char_length(last_name) between 1 and 60)));

CREATE OR REPLACE FUNCTION public.professional_profiles_sync_name()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
begin
  -- 43-C1: con nombre y apellidos, professional_name es siempre «Nombre Apellidos».
  if new.first_name is not null or new.last_name is not null then
    new.first_name := nullif(regexp_replace(btrim(coalesce(new.first_name, '')), '\s+', ' ', 'g'), '');
    new.last_name := nullif(regexp_replace(btrim(coalesce(new.last_name, '')), '\s+', ' ', 'g'), '');
    if new.first_name is null or new.last_name is null then
      raise exception 'Indica tu nombre y tus apellidos.' using errcode = '23514';
    end if;
    new.professional_name := new.first_name || ' ' || new.last_name;
  elsif tg_op = 'UPDATE' and old.first_name is not null then
    raise exception 'El nombre y los apellidos no pueden quedar vacíos.' using errcode = '23514';
  end if;
  return new;
end;
$function$;

revoke all on function public.professional_profiles_sync_name() from public, anon, authenticated;

create trigger trg_professional_profiles_sync_name
  before insert or update on public.professional_profiles
  for each row execute function public.professional_profiles_sync_name();

DO $$
begin
  if (select count(*) from information_schema.columns where table_schema = 'public' and table_name = 'professional_profiles'
      and column_name in ('first_name', 'last_name')) <> 2
     or not exists (select 1 from pg_constraint where conname = 'professional_profiles_name_parts_check')
     or not exists (select 1 from pg_trigger where tgname = 'trg_professional_profiles_sync_name' and tgrelid = 'public.professional_profiles'::regclass) then
    raise exception '43-D4: objetos no creados como se esperaba';
  end if;
  if exists (select 1 from public.professional_profiles where first_name is not null or last_name is not null) then
    raise exception '43-D4: algún perfil tiene ya nombre y apellidos (no debe dividirse ninguno)';
  end if;
  if coalesce((select md5(string_agg(user_id::text || ':' || professional_name, '|' order by user_id)) from public.professional_profiles), '-')
     <> current_setting('mobau.d4_nombres') then
    raise exception '43-D4: ha cambiado algún nombre existente';
  end if;
  if has_function_privilege('authenticated', 'public.professional_profiles_sync_name()', 'EXECUTE')
     or has_function_privilege('anon', 'public.professional_profiles_sync_name()', 'EXECUTE') then
    raise exception '43-D4: la función del trigger es ejecutable por clientes';
  end if;
end $$;

COMMIT;
