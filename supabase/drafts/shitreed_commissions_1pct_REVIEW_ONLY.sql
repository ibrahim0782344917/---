-- DRAFT / REVIEW ONLY — NOT EXECUTED ON PRODUCTION
-- Default 1% commission on completed product subtotal, IQD only.
-- Do not confuse commission DUE with commission COLLECTED.
-- Existing orders are NOT backfilled or changed by this file.

create table if not exists public.shitreed_commission_policies (
  id uuid primary key default gen_random_uuid(),
  scope text not null check (scope in ('global','merchant','category')),
  store_id uuid references public.stores(id),
  category text,
  rate_bps integer not null check (rate_bps between 0 and 10000),
  effective_from timestamptz not null,
  effective_until timestamptz,
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  notice_sent_at timestamptz,
  note text not null check (char_length(note) between 12 and 1000),
  check(effective_until is null or effective_until>effective_from),
  check((scope='global' and store_id is null and category is null)
     or (scope='merchant' and store_id is not null and category is null)
     or (scope='category' and store_id is null and category is not null))
);
create index if not exists shitreed_commission_policy_effective_idx
  on public.shitreed_commission_policies(scope, effective_from desc);

-- Snapshot the applicable policy AT ORDER CREATION, but only
-- CREATE an accrual event when the order is actually completed and paid.
-- For multi-category carts each order item should later have its own
-- rate snapshot. This table is one policy snapshot per existing one-store COD order.
create table if not exists public.shitreed_order_commission_snapshots (
  order_id uuid primary key references public.orders(id),
  policy_id uuid references public.shitreed_commission_policies(id),
  rate_bps integer not null default 100
    check(rate_bps between 0 and 10000),
  products_subtotal_iqd bigint not null check(products_subtotal_iqd>=0),
  commission_iqd bigint not null check(commission_iqd>=0),
  snapshot_at timestamptz not null default now(),
  -- No shipping and no taxes in commission basis unless formal policy changes.
  currency text not null default 'IQD' check(currency='IQD')
);
create index if not exists shitreed_order_commission_snapshots_policy_idx
  on public.shitreed_order_commission_snapshots(policy_id);

-- Append-only financial events for due, correction, reversal and receipt.
-- Neither a paid-on-delivery order nor a displayed total proves commission
-- was collected. Collections need proof and reconciliation IDs.
create table if not exists public.shitreed_commission_ledger (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders(id),
  store_id uuid not null references public.stores(id),
  kind text not null
    check(kind in ('accrued','refund_reversal','adjustment','collected')),
  signed_amount_iqd bigint not null,
  idempotency_key text not null unique
    check(char_length(idempotency_key) between 12 and 250),
  evidence_ref text,
  actor_id uuid references auth.users(id),
  created_at timestamptz not null default now(),
  check (
    (kind='accrued' and signed_amount_iqd>=0) or
    (kind='refund_reversal' and signed_amount_iqd<=0) or
    kind in ('adjustment','collected')
  )
);
create index if not exists shitreed_commission_ledger_store_idx
  on public.shitreed_commission_ledger(store_id,created_at desc);
create index if not exists shitreed_commission_ledger_order_idx
  on public.shitreed_commission_ledger(order_id);

-- Financial tables default to denied: server-only, RLS and no public grants.
alter table public.shitreed_commission_policies enable row level security;
alter table public.shitreed_order_commission_snapshots enable row level security;
alter table public.shitreed_commission_ledger enable row level security;
revoke all on public.shitreed_commission_policies
  from public, anon, authenticated;
revoke all on public.shitreed_order_commission_snapshots
  from public, anon, authenticated;
revoke all on public.shitreed_commission_ledger
  from public, anon, authenticated;

-- No client-facing RLS policies intentionally; privileged server APIs
-- must enforce merchant ownership, authorized Admin rate changes,
-- append-only ledger, invoice/refund reconciliation, effective-date notice,
-- and unique payout idempotency. Commission tables stay INACTIVE until
-- checkout, delivery confirmation, returns, COD settlement and tests exist.
