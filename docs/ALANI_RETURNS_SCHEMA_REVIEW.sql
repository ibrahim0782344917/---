-- REVIEW ONLY. NOT applied to any production database.
-- For a separate test project after approval/backup and RLS tests.
-- Iraqi consumer rights are not overridden by delivery/return fee policy.
-- Never collect bank card data or claim a refund has been processed.

begin;
create table if not exists public.alani_return_requests (
  id uuid primary key default gen_random_uuid(),
  store_id uuid not null references public.stores(id) on delete restrict,
  order_id uuid not null references public.orders(id) on delete restrict,
  customer_id uuid not null references auth.users(id) on delete restrict,
  reason text not null check
    (reason in ('change_mind','damaged','wrong_item','defective')),
  details text not null check (char_length(details) between 15 and 2000),
  photo_url text check (
    photo_url is null or (
      photo_url like 'https://%' and char_length(photo_url) <= 1000
    )
  ),
  status text not null default 'submitted' check (
    status in ('submitted','reviewing','approved','declined','resolved')
  ),
  resolution_note text not null default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists alani_returns_customer_idx
  on public.alani_return_requests (customer_id,created_at desc);
create index if not exists alani_returns_store_idx
  on public.alani_return_requests (store_id,created_at desc);
alter table public.alani_return_requests enable row level security;

revoke all on public.alani_return_requests from anon,authenticated;
grant select,insert on public.alani_return_requests to authenticated;
grant update(status,resolution_note,updated_at)
  on public.alani_return_requests to authenticated;

drop policy if exists alani_returns_customer_owner_read
  on public.alani_return_requests;
create policy alani_returns_customer_owner_read
  on public.alani_return_requests for select to authenticated
  using (
    customer_id=(select auth.uid()) or
    exists (select 1 from public.stores s
      where s.id=store_id and s.owner_id=(select auth.uid()))
  );

drop policy if exists alani_returns_buyer_insert
  on public.alani_return_requests;
create policy alani_returns_buyer_insert
  on public.alani_return_requests for insert to authenticated
  with check (
    customer_id=(select auth.uid())
    and status='submitted'
    and resolution_note=''
    and exists (
      select 1 from public.orders o
      where o.id=order_id
        and o.store_id=store_id
        and o.buyer_id=(select auth.uid())
    )
    and exists (
      select 1 from public.stores s
      where s.id=store_id and s.status='approved'
    )
  );

drop policy if exists alani_returns_store_owner_review
  on public.alani_return_requests;
create policy alani_returns_store_owner_review
  on public.alani_return_requests for update to authenticated
  using (exists (
    select 1 from public.stores s
      where s.id=store_id and s.owner_id=(select auth.uid())
  ))
  with check (exists (
    select 1 from public.stores s
      where s.id=store_id and s.owner_id=(select auth.uid())
  ));
commit;

-- REQUIRED BEFORE ANY PRODUCTION DEPLOYMENT:
-- [ ] Test anon SELECT/INSERT denied.
-- [ ] Test customer A cannot read customer B's return requests.
-- [ ] Test customer A cannot insert for another buyer's order.
-- [ ] Test customer A cannot update status, notes, store_id or order_id.
-- [ ] Test owner can read only requests belonging to their store.
-- [ ] Test owner can update ONLY status, resolution_note, updated_at.
-- [ ] Ensure order delivery verification is manual until delivered_at is
--     supported; current orders status only indicates ready, not delivered.
-- [ ] Attach proof images via private signed storage with RLS when implemented.
-- [ ] Confirm fee deductions and exemptions follow Iraqi consumer law.
-- [ ] Implement refund accounting separately; submitting is not refunding.
