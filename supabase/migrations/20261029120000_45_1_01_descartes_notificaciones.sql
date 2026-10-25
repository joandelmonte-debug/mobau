-- ============================================================
-- PROPUESTA NO EJECUTADA (45.1-01 · descartes de notificaciones por usuario) — no ejecutar sin aprobación explícita
-- ============================================================
-- Punto 45.1 · «Quitar» un aviso de Mobau o una decisión reciente en Mis
-- productos, solo para el usuario que lo descarta y de forma persistente.
--   * Tabla nueva public.notification_dismissals (user_id, notice_key,
--     dismissed_at). Descartar solo añade una fila: no borra auditoría,
--     propuestas, motivos ni datos del producto.
--   * notice_key: «lc:<producto>:<acción>:<fecha del evento>» o
--     «dec:<propuesta>:<estado>:<fecha de revisión>», con la fecha original
--     del servidor. Un evento nuevo tiene otra clave y vuelve a avisar.
--   * RLS: cada usuario autenticado lee, crea y borra solo sus filas; sin
--     UPDATE. Sin acceso para anon. No cambia ninguna función ni tabla existente.
-- Si se aplica, se registra como migración NUEVA tras confirmar su COMMIT.
-- Ejecutar completo.
-- ============================================================

BEGIN;

DO $$
begin
  if current_user <> 'postgres' then
    raise exception '45.1-01: ejecutar como postgres';
  end if;
  if not exists (select 1 from supabase_migrations.schema_migrations where version = '20261028120000')
     or exists (select 1 from supabase_migrations.schema_migrations where version = '20261029120000') then
    raise exception '45.1-01: el registro de migraciones no es el esperado (45-04 registrada y 45.1-01 sin registrar)';
  end if;
  if to_regclass('public.notification_dismissals') is not null then
    raise exception '45.1-01: la tabla public.notification_dismissals ya existe';
  end if;
end $$;

create table public.notification_dismissals (
  user_id      uuid not null default auth.uid() references auth.users (id) on delete cascade,
  notice_key   text not null,
  dismissed_at timestamptz not null default now(),
  primary key (user_id, notice_key),
  constraint notification_dismissals_key check (
    char_length(notice_key) between 4 and 300 and (notice_key like 'lc:%' or notice_key like 'dec:%'))
);
comment on table public.notification_dismissals is
  'Punto 45.1: avisos de Mis productos que cada usuario ha quitado. Solo oculta la notificación; no borra el hecho que la originó.';

alter table public.notification_dismissals enable row level security;

create policy notification_dismissals_select_own on public.notification_dismissals
  for select to authenticated using (user_id = (select auth.uid()));
create policy notification_dismissals_insert_own on public.notification_dismissals
  for insert to authenticated with check (user_id = (select auth.uid()));
create policy notification_dismissals_delete_own on public.notification_dismissals
  for delete to authenticated using (user_id = (select auth.uid()));

revoke all on table public.notification_dismissals from public, anon, authenticated;
grant select, insert, delete on table public.notification_dismissals to authenticated;

DO $$
begin
  if not (select relrowsecurity from pg_class where oid = 'public.notification_dismissals'::regclass)
     or (select count(*) from pg_policies where schemaname = 'public' and tablename = 'notification_dismissals') <> 3
     or has_table_privilege('anon', 'public.notification_dismissals', 'SELECT')
     or has_table_privilege('anon', 'public.notification_dismissals', 'INSERT')
     or not has_table_privilege('authenticated', 'public.notification_dismissals', 'SELECT')
     or not has_table_privilege('authenticated', 'public.notification_dismissals', 'INSERT')
     or not has_table_privilege('authenticated', 'public.notification_dismissals', 'DELETE')
     or has_table_privilege('authenticated', 'public.notification_dismissals', 'UPDATE')
     or has_table_privilege('authenticated', 'public.notification_dismissals', 'TRUNCATE')
     or has_table_privilege('authenticated', 'public.notification_dismissals', 'REFERENCES')
     or has_table_privilege('authenticated', 'public.notification_dismissals', 'TRIGGER') then
    raise exception '45.1-01: RLS o permisos no quedaron como se esperaba';
  end if;
end $$;

COMMIT;
