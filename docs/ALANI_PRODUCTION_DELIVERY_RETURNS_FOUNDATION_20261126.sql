-- Additive production foundation only: do not change order statuses or open access.
BEGIN;
SET LOCAL lock_timeout='3s';
SET LOCAL statement_timeout='30s';
DO $g$ BEGIN
 IF NOT public.shitreed_alani_checkout_schema_ready() OR EXISTS(SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='public' AND c.relname IN ('alani_delivery_couriers','alani_delivery_jobs','alani_return_requests','alani_return_status_history')) THEN RAISE EXCEPTION 'DELIVERY_FOUNDATION_PREFLIGHT_FAILED'; END IF;
END $g$;
CREATE TABLE public.alani_delivery_couriers (
  store_id uuid NOT NULL REFERENCES public.stores(id) ON DELETE RESTRICT,
  courier_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
  enabled boolean NOT NULL DEFAULT true,
  added_by uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
  added_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (store_id,courier_id),
  CONSTRAINT alani_delivery_courier_store_check CHECK
    (store_id='25091ca2-c0da-416c-b634-81b188ee66be'::uuid)
);
CREATE TABLE public.alani_delivery_jobs (
  order_id uuid PRIMARY KEY REFERENCES public.orders(id) ON DELETE RESTRICT,
  store_id uuid NOT NULL REFERENCES public.stores(id) ON DELETE RESTRICT,
  courier_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
  dispatched_by uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
  dispatched_at timestamptz NOT NULL DEFAULT now(),
  picked_up_at timestamptz,
  delivered_at timestamptz,
  delivery_note text NOT NULL DEFAULT '' CHECK (char_length(delivery_note)<=300),
  proof_method text CHECK (proof_method IS NULL OR proof_method='buyer_one_time_pin'),
  pin_salt uuid,
  pin_hash text,
  pin_issued_at timestamptz,
  pin_expires_at timestamptz,
  failed_attempts integer NOT NULL DEFAULT 0 CHECK (failed_attempts BETWEEN 0 AND 5),
  CONSTRAINT alani_delivery_job_store_check CHECK
    (store_id='25091ca2-c0da-416c-b634-81b188ee66be'::uuid),
  CONSTRAINT alani_delivery_job_pin_pair CHECK (
    (pin_salt IS NULL AND pin_hash IS NULL AND pin_expires_at IS NULL)
    OR (pin_salt IS NOT NULL AND pin_hash IS NOT NULL AND pin_expires_at IS NOT NULL))
);
CREATE INDEX alani_delivery_courier_jobs_idx
  ON public.alani_delivery_jobs(courier_id,dispatched_at DESC);
ALTER TABLE public.alani_delivery_couriers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.alani_delivery_jobs ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.alani_delivery_couriers FROM PUBLIC,anon,authenticated;
REVOKE ALL ON public.alani_delivery_jobs FROM PUBLIC,anon,authenticated;
-- No direct client access to delivery jobs or customer addresses.
-- Read and write access is only through the participant-checked functions below.


create table public.alani_return_requests (
  id uuid primary key default gen_random_uuid(),
  store_id uuid not null references public.stores(id) on delete restrict,
  order_id uuid not null references public.orders(id) on delete restrict,
  customer_id uuid not null references auth.users(id) on delete restrict,
  reason text not null check (reason in ('change_mind','damaged','wrong_item','defective','delivery_issue')),
  details text not null check (char_length(details) between 15 and 2000),
  status text not null default 'submitted' check
    (status in ('submitted','reviewing','approved','declined','resolved')),
  resolution_note text not null default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create unique index alani_active_return_once_idx
  on public.alani_return_requests(customer_id,order_id)
  where status in ('submitted','reviewing','approved');
create index alani_return_store_idx on public.alani_return_requests(store_id,created_at desc);
alter table public.alani_return_requests enable row level security;
revoke all on public.alani_return_requests from public,anon,authenticated;

create policy alani_returns_read_participant on public.alani_return_requests
  for select to authenticated using (
    customer_id=(select auth.uid()) or exists (
      select 1 from public.stores s where s.id=store_id
        and s.owner_id=(select auth.uid())
    )
  );

create table public.alani_return_status_history (
  id uuid primary key default gen_random_uuid(),
  return_id uuid not null references public.alani_return_requests(id) on delete restrict,
  old_status text,
  new_status text not null,
  changed_by uuid references auth.users(id) on delete set null,
  changed_at timestamptz not null default now()
);
create index alani_return_events_idx
  on public.alani_return_status_history(return_id,changed_at);
alter table public.alani_return_status_history enable row level security;
revoke all on public.alani_return_status_history from public,anon,authenticated;

create policy alani_return_events_participant
  on public.alani_return_status_history for select to authenticated using (
    exists (select 1 from public.alani_return_requests r
      where r.id=return_id and (
        r.customer_id=(select auth.uid()) or exists (
          select 1 from public.stores s where s.id=r.store_id
            and s.owner_id=(select auth.uid())
        )
      )
    )
  );


REVOKE ALL ON public.alani_delivery_couriers,public.alani_delivery_jobs,public.alani_return_requests,public.alani_return_status_history FROM PUBLIC,anon,authenticated;
DO $v$ BEGIN
 IF (SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='public' AND c.relname IN ('alani_delivery_couriers','alani_delivery_jobs','alani_return_requests','alani_return_status_history') AND c.relrowsecurity AND NOT has_table_privilege('anon',c.oid,'SELECT,INSERT,UPDATE,DELETE') AND NOT has_table_privilege('authenticated',c.oid,'SELECT,INSERT,UPDATE,DELETE'))<>4 OR NOT public.shitreed_alani_checkout_schema_ready() THEN RAISE EXCEPTION 'DELIVERY_FOUNDATION_POSTCHECK_FAILED'; END IF;
END $v$;
COMMIT;
