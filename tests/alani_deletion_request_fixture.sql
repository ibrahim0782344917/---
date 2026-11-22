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

-- Synthetic identity relations used by the read-only preflight.
create table public.orders(id uuid primary key,buyer_id uuid not null,status text not null);
create table public.stores(id uuid primary key,owner_id uuid not null);
insert into public.orders(id,buyer_id,status) values
  ('f0000000-0000-4000-8000-000000000001','cccccccc-cccc-4ccc-8ccc-cccccccccccc','placed'),
  ('f0000000-0000-4000-8000-000000000002','cccccccc-cccc-4ccc-8ccc-cccccccccccc','cancelled'),
  ('f0000000-0000-4000-8000-000000000003','dddddddd-dddd-4ddd-8ddd-dddddddddddd','ready');
insert into public.stores(id,owner_id) values
  ('f1000000-0000-4000-8000-000000000001','dddddddd-dddd-4ddd-8ddd-dddddddddddd');
alter table public.orders enable row level security;
alter table public.stores enable row level security;
grant select on public.orders,public.stores to authenticated;
create policy synthetic_buyer_orders on public.orders for select to authenticated
  using (buyer_id=(select auth.uid()));
create policy synthetic_owned_stores on public.stores for select to authenticated
  using (owner_id=(select auth.uid()));
