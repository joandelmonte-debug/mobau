-- ============================================================
-- PROPUESTA NO EJECUTADA (44-04 · recuperación) — no ejecutar sin aprobación explícita
-- ============================================================
-- Devuelve exactamente REFERENCES y TRIGGER en products a anon y
-- authenticated (concesión directa de postgres, como estaba). Si se aplica,
-- se registra como migración NUEVA tras confirmar su COMMIT.
-- ============================================================

BEGIN;

DO $$
begin
  if current_user <> 'postgres' then
    raise exception '44-04 R: ejecutar como postgres';
  end if;
  if (select relacl::text from pg_class where oid = 'public.products'::regclass)
     <> '{postgres=arwdDxtm/postgres,service_role=arwdDxtm/postgres}' then
    raise exception '44-04 R: los permisos de tabla de products no son los que deja 44-04';
  end if;
end $$;

grant references, trigger on table public.products to anon, authenticated;

DO $$
begin
  if (select relacl::text from pg_class where oid = 'public.products'::regclass)
     <> '{postgres=arwdDxtm/postgres,service_role=arwdDxtm/postgres,anon=xt/postgres,authenticated=xt/postgres}'
     and (select relacl::text from pg_class where oid = 'public.products'::regclass)
     <> '{postgres=arwdDxtm/postgres,anon=xt/postgres,authenticated=xt/postgres,service_role=arwdDxtm/postgres}' then
    raise exception '44-04 R: los permisos no volvieron a su estado';
  end if;
end $$;

COMMIT;
