-- Additive account-deletion request intake for authenticated shoppers.
-- A request does not immediately erase purchase records: authorized operators must
-- process it under the retention policy and delete/anonymize eligible personal data.
create table if not exists public.customer_deletion_requests (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  reason text not null default '' check (char_length(reason) <= 500),
  status text not null default 'pending' check (status in ('pending','processing','completed','rejected')),
  requested_at timestamptz not null default now(),
  processed_at timestamptz
);
create unique index if not exists customer_deletion_one_open_request_per_user
  on public.customer_deletion_requests (user_id)
  where status in ('pending','processing');
create index if not exists customer_deletion_queue_idx
  on public.customer_deletion_requests (status, requested_at);
alter table public.customer_deletion_requests enable row level security;
revoke all on table public.customer_deletion_requests from public, anon, authenticated;
grant select (id, user_id, status, requested_at) on public.customer_deletion_requests to authenticated;
grant insert (reason) on public.customer_deletion_requests to authenticated;
drop policy if exists "Customers may read own deletion requests" on public.customer_deletion_requests;
create policy "Customers may read own deletion requests"
 on public.customer_deletion_requests for select to authenticated
 using (user_id = (select auth.uid()));
drop policy if exists "Customers may request deletion" on public.customer_deletion_requests;
create policy "Customers may request deletion"
 on public.customer_deletion_requests for insert to authenticated
 with check (
   user_id = (select auth.uid())
   and status = 'pending'
   and requested_at between now()-interval '2 minutes' and now()+interval '2 minutes'
 );
