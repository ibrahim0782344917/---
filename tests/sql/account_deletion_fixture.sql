-- Disposable test schema to mirror current Supabase deletion request policy.
create table public.customer_deletion_requests(
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id),
  reason text not null default '',
  status text not null default 'pending',
  requested_at timestamptz not null default now(),
  processed_at timestamptz
);
alter table public.customer_deletion_requests enable row level security;
create policy delete_request_owner_select on public.customer_deletion_requests
  for select to authenticated
  using(user_id=(select auth.uid()));
create policy delete_request_owner_insert on public.customer_deletion_requests
  for insert to authenticated
  with check(
    user_id=(select auth.uid()) and status='pending'
    and requested_at between now()-interval '2 minutes'
      and now()+interval '2 minutes'
  );
