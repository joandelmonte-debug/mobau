-- ============================================================
-- PROPUESTA NO EJECUTADA (43-D5 · endurecimiento mínimo de moodboards) — no ejecutar sin aprobación explícita
-- ============================================================
-- 43 · CC1 · Permisos de public.moodboards (0 filas). Hoy anon y
-- authenticated tienen todos los privilegios de tabla (los da el privilegio
-- por defecto del esquema public), incluido TRUNCATE, que no está sujeto a
-- RLS. Rutas comprobadas el 2026-10-20: ninguna función, vista, publicación
-- de tiempo real ni GraphQL usa la tabla; la web no la usa; sus 3 políticas
-- (INSERT, SELECT y UPDATE) exigen ser dueño del proyecto (auth.uid()).
--   * anon: sin ningún privilegio (no tiene uso legítimo: sin sesión las
--     políticas no dejan ver ni escribir nada).
--   * authenticated: solo SELECT, INSERT y UPDATE, los que cubren sus
--     políticas. Fuera DELETE (no hay política), TRUNCATE, REFERENCES y
--     TRIGGER.
--   * service_role y postgres no cambian.
-- No cambia políticas, columnas ni datos, ni el diseño futuro del moodboard
-- (Gratis independiente; Individual y Estudio, uno por proyecto): ese punto
-- concederá lo que necesite cuando exista.
-- Ejecutar completo.
-- ============================================================

BEGIN;

DO $$
begin
  if current_user <> 'postgres' then
    raise exception '43-D5: ejecutar como postgres';
  end if;
  if (select relacl::text from pg_class where oid = 'public.moodboards'::regclass)
     <> '{postgres=arwdDxtm/postgres,anon=arwdDxtm/postgres,authenticated=arwdDxtm/postgres,service_role=arwdDxtm/postgres}' then
    raise exception '43-D5: los permisos de partida de moodboards no son los leídos';
  end if;
end $$;

revoke all on table public.moodboards from anon;
revoke delete, truncate, references, trigger on table public.moodboards from authenticated;

DO $$
declare
  p text;
begin
  foreach p in array array['SELECT', 'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER'] loop
    if has_table_privilege('anon', 'public.moodboards', p) then
      raise exception '43-D5: anon conserva %', p;
    end if;
    if has_table_privilege('authenticated', 'public.moodboards', p) <> (p in ('SELECT', 'INSERT', 'UPDATE')) then
      raise exception '43-D5: authenticated no tiene exactamente SELECT, INSERT y UPDATE (falla en %)', p;
    end if;
    if not has_table_privilege('service_role', 'public.moodboards', p) then
      raise exception '43-D5: service_role ha perdido %', p;
    end if;
  end loop;
end $$;

COMMIT;
