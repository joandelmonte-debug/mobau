-- ============================================================
-- PROPUESTA NO EJECUTADA (38-C) — no ejecutar sin aprobación explícita
-- ============================================================
-- 38-C · 01 · Tablas de propuestas de producto e historial
-- ------------------------------------------------------------
-- Crea product_proposals (una propuesta de cambio de información y/o
-- precio sobre un producto existente) y proposal_events (historial de
-- estados, solo anexar). Ambas quedan CERRADAS: RLS activada sin
-- políticas y sin ningún permiso para anon ni authenticated. Nadie del
-- cliente puede leer ni escribir hasta 38-C 03.
--
-- Esta migración NO crea triggers, funciones ni políticas (02 y 03), no
-- toca products, product_prices ni ninguna tabla existente, y no incluye
-- moderación ni aplicación de propuestas (punto 39).
--
-- Notas de diseño:
--   * product_id, distributor_id: text, como products.id y distributors.id.
--   * distributor_id y author_id los fijará el servidor (02), nunca el cliente.
--   * proposed_changes: solo los campos de products que cambian (objeto
--     JSON); la lista cerrada de claves y sus validaciones llegan en 02.
--   * El precio propuesto va en columnas propias con las mismas reglas que
--     product_prices (USD, ITBIS incluido como hoy).
--   * product_snapshot: copia del producto y su precio al enviar (02).
--   * Una sola propuesta abierta (draft, submitted, changes_requested) por
--     producto: índice único parcial, garantizado por la base de datos.
--   * Sin borrado en cascada: una propuesta con historial no se puede
--     borrar, y un producto con propuestas tampoco (evidencia).
--
-- Ejecutar completo, de una vez (BEGIN … COMMIT). Si algo falla, no queda
-- nada aplicado.
-- ============================================================

BEGIN;

-- ---------- prechecks ----------
DO $$
begin
  if not exists (select 1 from supabase_migrations.schema_migrations where version = '20261002090300') then
    raise exception '38-C 01: falta 38-B 04 (20261002090300) en schema_migrations';
  end if;
  if to_regclass('public.product_proposals') is not null or to_regclass('public.proposal_events') is not null then
    raise exception '38-C 01: product_proposals o proposal_events ya existen';
  end if;
  if (select data_type from information_schema.columns
       where table_schema = 'public' and table_name = 'products' and column_name = 'id') is distinct from 'text'
     or (select data_type from information_schema.columns
       where table_schema = 'public' and table_name = 'distributors' and column_name = 'id') is distinct from 'text' then
    raise exception '38-C 01: products.id o distributors.id no son de tipo text';
  end if;
  if to_regprocedure('public.my_verified_distributor_id()') is null then
    raise exception '38-C 01: falta public.my_verified_distributor_id()';
  end if;
end $$;

-- ---------- product_proposals ----------
create table public.product_proposals (
  id                     uuid primary key default gen_random_uuid(),
  product_id             text not null references public.products (id),
  distributor_id         text not null references public.distributors (id),
  author_id              uuid references auth.users (id) on delete set null,
  status                 text not null default 'draft',
  version                integer not null default 1,
  proposed_changes       jsonb not null default '{}'::jsonb,
  proposed_price_status  text,
  proposed_price_amount  numeric(12,2),
  product_snapshot       jsonb,
  internal_note          text,
  rejection_reason       text,
  submitted_at           timestamptz,
  reviewed_at            timestamptz,
  reviewed_by            uuid references auth.users (id) on delete set null,
  created_at             timestamptz not null default now(),
  updated_at             timestamptz not null default now(),
  constraint product_proposals_status_check
    check (status in ('draft', 'submitted', 'changes_requested', 'approved', 'rejected', 'withdrawn')),
  constraint product_proposals_version_check
    check (version >= 1),
  constraint product_proposals_changes_object
    check (jsonb_typeof(proposed_changes) = 'object'),
  constraint product_proposals_changes_size
    check (pg_column_size(proposed_changes) <= 16384),
  constraint product_proposals_snapshot_object
    check (product_snapshot is null or jsonb_typeof(product_snapshot) = 'object'),
  constraint product_proposals_price_status_check
    check (proposed_price_status is null
           or proposed_price_status in ('published', 'quote_required', 'pending_confirmation', 'unavailable')),
  constraint product_proposals_price_amount_check
    check (proposed_price_amount is null or proposed_price_amount >= 0),
  constraint product_proposals_price_published_amount
    check (proposed_price_status is distinct from 'published' or proposed_price_amount is not null),
  constraint product_proposals_price_amount_needs_status
    check (proposed_price_amount is null or proposed_price_status is not null),
  constraint product_proposals_text_lengths
    check (char_length(coalesce(internal_note, '')) <= 2000
           and char_length(coalesce(rejection_reason, '')) <= 2000)
);

comment on table public.product_proposals is
  '38-C: propuesta de cambio de información y/o precio de un producto existente, hecha por su distribuidor verificado. No modifica products ni product_prices; la aplicación es del punto 39.';
comment on column public.product_proposals.internal_note is
  'Nota del distribuidor para Mobau.';
comment on column public.product_proposals.rejection_reason is
  'Motivo de Mobau al rechazar o pedir cambios (solo Mobau, punto 39).';

create index product_proposals_distributor_status_idx
  on public.product_proposals (distributor_id, status);
create index product_proposals_product_idx
  on public.product_proposals (product_id);
create unique index product_proposals_one_open_per_product
  on public.product_proposals (product_id)
  where status in ('draft', 'submitted', 'changes_requested');

-- ---------- proposal_events (historial, solo anexar) ----------
create table public.proposal_events (
  id           bigint generated always as identity primary key,
  proposal_id  uuid not null references public.product_proposals (id),
  actor_id     uuid references auth.users (id) on delete set null,
  actor_kind   text not null,
  from_status  text,
  to_status    text not null,
  version      integer not null,
  payload      jsonb,
  note         text,
  created_at   timestamptz not null default now(),
  constraint proposal_events_actor_kind_check
    check (actor_kind in ('distributor', 'mobau', 'system')),
  constraint proposal_events_from_status_check
    check (from_status is null
           or from_status in ('draft', 'submitted', 'changes_requested', 'approved', 'rejected', 'withdrawn')),
  constraint proposal_events_to_status_check
    check (to_status in ('draft', 'submitted', 'changes_requested', 'approved', 'rejected', 'withdrawn')),
  constraint proposal_events_version_check
    check (version >= 1),
  constraint proposal_events_payload_object
    check (payload is null or jsonb_typeof(payload) = 'object'),
  constraint proposal_events_note_length
    check (char_length(coalesce(note, '')) <= 2000)
);

comment on table public.proposal_events is
  '38-C: historial de estados de product_proposals. Solo anexar; lo escribirán triggers (02), nunca el cliente.';

create index proposal_events_proposal_idx
  on public.proposal_events (proposal_id, created_at);

-- ---------- cerrar: RLS sin políticas y sin permisos de cliente ----------
-- Supabase concede por defecto ALL a anon y authenticated en cada tabla y
-- secuencia nueva de public (pg_default_acl): se revoca explícitamente.
alter table public.product_proposals enable row level security;
alter table public.proposal_events enable row level security;

revoke all on table public.product_proposals from public, anon, authenticated;
revoke all on table public.proposal_events from public, anon, authenticated;

DO $$
declare
  v_seq text := pg_get_serial_sequence('public.proposal_events', 'id');
begin
  if v_seq is null then
    raise exception '38-C 01: no se encontró la secuencia de proposal_events.id';
  end if;
  execute format('revoke all on sequence %s from public, anon, authenticated', v_seq);
end $$;

-- ---------- validación final ----------
DO $$
declare
  t text;
  r text;
  v_seq text := pg_get_serial_sequence('public.proposal_events', 'id');
begin
  foreach t in array array['public.product_proposals', 'public.proposal_events'] loop
    if not (select relrowsecurity from pg_class where oid = t::regclass) then
      raise exception '38-C 01: RLS no está activada en %', t;
    end if;
    if exists (select 1 from pg_policies where schemaname = 'public' and tablename = split_part(t, '.', 2)) then
      raise exception '38-C 01: % no debería tener políticas todavía', t;
    end if;
    foreach r in array array['anon', 'authenticated'] loop
      if has_table_privilege(r, t, 'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER')
         or has_any_column_privilege(r, t, 'SELECT,INSERT,UPDATE,REFERENCES') then
        raise exception '38-C 01: % conserva algún permiso sobre %', r, t;
      end if;
    end loop;
  end loop;

  foreach r in array array['anon', 'authenticated'] loop
    if has_sequence_privilege(r, v_seq, 'USAGE,SELECT,UPDATE') then
      raise exception '38-C 01: % conserva permisos sobre la secuencia %', r, v_seq;
    end if;
  end loop;

  if to_regclass('public.product_proposals_one_open_per_product') is null then
    raise exception '38-C 01: falta el índice único de propuesta abierta por producto';
  end if;

  if (select count(*) from pg_policies where schemaname = 'public') <> 40 then
    raise exception '38-C 01: el número de políticas de public ha cambiado (esperado 40)';
  end if;

  raise notice '38-C 01 OK: tablas creadas y cerradas (RLS sin políticas, sin permisos de cliente).';
end $$;

COMMIT;
