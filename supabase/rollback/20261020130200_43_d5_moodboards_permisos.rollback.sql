-- ============================================================
-- RECUPERACIÓN NO EJECUTADA (43 · R-D5, inversa de D5) — no ejecutar sin aprobación explícita
-- ============================================================
-- Devuelve a public.moodboards exactamente los permisos de partida (todos
-- los privilegios para anon y authenticated, concedidos por postgres).
-- Ejecutar completo.
-- ============================================================

BEGIN;

DO $$
begin
  if current_user <> 'postgres' then
    raise exception '43-RD5: ejecutar como postgres';
  end if;
  if has_table_privilege('anon', 'public.moodboards', 'SELECT')
     or has_table_privilege('authenticated', 'public.moodboards', 'TRUNCATE') then
    raise exception '43-RD5: D5 no está aplicada';
  end if;
end $$;

grant all on table public.moodboards to anon;
grant delete, truncate, references, trigger on table public.moodboards to authenticated;

DO $$
declare
  p text;
begin
  -- Se comparan privilegios efectivos, no el texto del ACL (el orden de las
  -- entradas puede variar al volver a concederlas).
  foreach p in array array['SELECT', 'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER'] loop
    if not has_table_privilege('anon', 'public.moodboards', p)
       or not has_table_privilege('authenticated', 'public.moodboards', p)
       or not has_table_privilege('service_role', 'public.moodboards', p) then
      raise exception '43-RD5: falta % tras la recuperación', p;
    end if;
  end loop;
end $$;

COMMIT;
