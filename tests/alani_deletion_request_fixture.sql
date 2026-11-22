-- synthetic-only account deletion request fixture
create role anon nologin;
create role authenticated nologin;
create schema auth;
create function auth.uid() returns uuid language sql stable
 as $uid$ select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid $uid$;
grant usage on schema auth to anon,authenticated;
grant execute on function auth.uid() to anon,authenticated;
create table public.customer_deletion_requests (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid(),
  reason text not null default '',
  status text not null default 'pending'
    check(status in ('pending','processing','completed','rejected')),
  requested_at timestamptz not null default now(),
  processed_at timestamptz
);
create unique index active_customer_delete_one
 on public.customer_deletion_requests(user_id)
 where status in ('pending','processing');
alter table public.customer_deletion_requests enable row level security;
create policy customer_only_read on public.customer_deletion_requests
 for select to authenticated using (user_id=(select auth.uid()));
create policy customer_only_insert on public.customer_deletion_requests
 for insert to authenticated with check
 (user_id=(select auth.uid()) and status='pending');
