-- ============================================================
-- PROPUESTA NO EJECUTADA (41-06 · parada) — no ejecutar sin aprobación explícita
-- ============================================================
-- 41 · 06 · PARADA del ciclo de vida (inverso operativo de 41-06, A5)
-- ------------------------------------------------------------
-- Una transacción, como postgres:
--   1. Interruptor del servidor: enabled = false (fila id = 1).
--   2. REVOKE de EXECUTE de las 9 funciones de entrada a PUBLIC, anon,
--      authenticated y service_role: vuelve la ACL exacta de V3
--      {postgres=X/postgres} (misma sentencia que dejó V3).
--
-- NO borra datos, auditoría ni propuestas; NO revierte V3; NO toca la
-- moderación ordinaria (create/update), RLS, políticas ni cuerpos.
-- NO termina sesiones ni cancela peticiones: una llamada que ya pasó la
-- comprobación del interruptor o que ya empezó a ejecutarse puede terminar
-- (ver V4-W y la comparación S0/S1/S2 en el guion §4).
-- NO toca supabase_migrations: el registro de 41-06 se queda como está; su
-- tratamiento es una decisión aparte (guion §7).
--
-- No añade validaciones propias que la aborten, para no sumar motivos de
-- fallo. Eso NO garantiza que se confirme: es una transacción todo o nada.
-- Si falla el UPDATE o un REVOKE, vence lock_timeout o el COMMIT devuelve
-- error, no se aplica nada. Si la respuesta es ambigua o se pierde la
-- conexión, el estado es DESCONOCIDO. En ningún caso se afirma «servidor
-- parado» ni «servidor activo» sin la lectura V4-P_verificacion_parada.sql
-- (P1–P7 ok). Sin reintentos automáticos ni parada alternativa sin revisión.
-- Idempotente: repetirla sobre un servidor ya parado solo cambia changed_at.
-- ============================================================

BEGIN;

set local lock_timeout = '5s';

-- 1. interruptor (primero: corta las nuevas llamadas en su primera comprobación)
update mobau_private.product_lifecycle_settings
   set enabled = false, changed_at = now(), changed_by = null,
       note = '41-06 parada: interruptor apagado y EXECUTE revocado (ventana V4)'
 where id = 1;

-- 2. EXECUTE: ACL exacta de V3
revoke all on function public.my_products_lifecycle() from public, anon, authenticated, service_role;
revoke all on function public.my_product_lifecycle_events(text) from public, anon, authenticated, service_role;
revoke all on function public.distributor_retire_product(text, text, timestamptz) from public, anon, authenticated, service_role;
revoke all on function public.distributor_trash_product(text, timestamptz) from public, anon, authenticated, service_role;
revoke all on function public.distributor_restore_product(text, timestamptz) from public, anon, authenticated, service_role;
revoke all on function public.mobau_product_lifecycle(text, text, text, timestamptz) from public, anon, authenticated, service_role;
revoke all on function public.mobau_purge_product(text, text, text, boolean, timestamptz) from public, anon, authenticated, service_role;
revoke all on function public.mobau_product_references(text) from public, anon, authenticated, service_role;
revoke all on function public.mobau_product_lifecycle_view(text) from public, anon, authenticated, service_role;

COMMIT;
