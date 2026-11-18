-- REVIEW-ONLY proposal. DO NOT execute on Production without an isolated
-- staging database, verified backup/restore, two-account RLS tests and approval.
-- Campaigns control informational banners, NOT order prices or discounts.

begin;
create table if not exists public.shitreed_store_campaigns (
  id uuid primary key default gen_random_uuid(),
  store_id uuid not null references public.stores(id) on delete restrict,
  created_by uuid not null references auth.users(id) on delete restrict,
  title text not null check (char_length(title) between 3 and 100),
  description text not null default '' check (char_length(description)<=600),
  image_url text check (
    image_url is null or (
      left(image_url,8)='https://' and char_length(image_url)<=1000
    )
  ),
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  priority smallint not null default 0 check (priority between 0 and 20),
  is_published boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint campaign_dates_valid check (
    ends_at > starts_at
    and ends_at <= starts_at + interval '90 days'
  )
);
create index if not exists idx_campaign_public_window
  on public.shitreed_store_campaigns
  (store_id, is_published, starts_at, ends_at, priority desc);
alter table public.shitreed_store_campaigns enable row level security;

revoke all on public.shitreed_store_campaigns from anon, authenticated;
grant select on public.shitreed_store_campaigns to anon, authenticated;
grant insert on public.shitreed_store_campaigns to authenticated;
grant update(title,description,image_url,starts_at,ends_at,
  priority,is_published,updated_at)
  on public.shitreed_store_campaigns to authenticated;

drop policy if exists campaign_public_active
  on public.shitreed_store_campaigns;
create policy campaign_public_active
on public.shitreed_store_campaigns for select to anon,authenticated
using (
  is_published and starts_at <= now() and ends_at > now()
  and exists (select 1 from public.stores s
    where s.id=store_id and s.status='approved')
);

drop policy if exists campaign_owner_read
  on public.shitreed_store_campaigns;
create policy campaign_owner_read
on public.shitreed_store_campaigns for select to authenticated
using (exists(select 1 from public.stores s
  where s.id=store_id and s.owner_id=(select auth.uid())));

drop policy if exists campaign_owner_insert
  on public.shitreed_store_campaigns;
create policy campaign_owner_insert
on public.shitreed_store_campaigns for insert to authenticated
with check (
  created_by=(select auth.uid())
  and exists (select 1 from public.stores s
    where s.id=store_id and s.owner_id=(select auth.uid())
      and s.status='approved')
);

drop policy if exists campaign_owner_update
  on public.shitreed_store_campaigns;
create policy campaign_owner_update
on public.shitreed_store_campaigns for update to authenticated
using (exists(select 1 from public.stores s
  where s.id=store_id and s.owner_id=(select auth.uid())
    and s.status='approved'))
with check (exists(select 1 from public.stores s
  where s.id=store_id and s.owner_id=(select auth.uid())
    and s.status='approved'));
commit;

-- SECURITY & FUNCTIONAL ACCEPTANCE (run on isolated staging):
-- A. anon only sees approved-store, published, within UTC time window.
-- B. seller A cannot read drafts or change campaign of seller B.
-- C. seller A cannot modify store_id, created_by, created_at via REST.
-- D. expired campaigns become invisible without an app redeploy.
-- E. unapproved store cannot create/publish a campaign.
-- F. checkout ignores the campaign text until a server-validated price
--    promotion engine and separate payment acceptance tests exist.
-- G. mobile + web banners read this table only when feature flag is approved.

-- WALLET / CREDIT DESIGN REQUIREMENTS (not executed):
-- Create immutable credit_ledger with idempotency unique constraints,
-- integer amount_iqd, debit/credit signs, unique request_key,
-- order_id / compensation_id, actor_id, reason, created_at,
-- authorization by narrow server-side operations with mandatory audit.
-- Customer sees ONLY their own ledger; a platform manager cannot edit
-- entries in place. Corrections are new reversing entries.
-- Credit is STORE-ONLY, non-transferable, non-withdrawable, until
-- legal/regulatory and accounting review. Do not create top-up endpoints
-- or a payment gateway without explicit service approval.
