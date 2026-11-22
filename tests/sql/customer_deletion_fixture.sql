-- Mirrors the EXISTING production customer_deletion_requests contract.
-- Only fake users from wallet_chat_bootstrap.sql are used here.
create table public.customer_deletion_requests (
 id uuid primary key default gen_random_uuid(),
 user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
 reason text not null default '' check (char_length(reason)<=500),
 status text not null default 'pending'
   check (status in ('pending','processing','completed','rejected')),
 requested_at timestamptz not null default now(),
 processed_at timestamptz
);
create unique index customer_deletion_one_open_request_per_user
  on public.customer_deletion_requests(user_id)
  where status in ('pending','processing');
create index customer_deletion_queue_idx
  on public.customer_deletion_requests(status,requested_at);
alter table public.customer_deletion_requests enable row level security;
revoke all on public.customer_deletion_requests from public,anon,authenticated;
create policy "Customers may read own deletion requests"
  on public.customer_deletion_requests for select to authenticated
  using(user_id=(select auth.uid()));
create policy "Customers may request deletion"
  on public.customer_deletion_requests for insert to authenticated
  with check(user_id=(select auth.uid()) and status='pending'
    and requested_at between now()-interval '2 minutes'
    and now()+interval '2 minutes');
