-- STAGING ONLY: private customer-to-store SUPPORT thread; NOT full social DMs.
-- No staff account may read unrelated private threads by being an Admin.
-- Requires per-user rate limits, reporting, notifications and privacy tests
-- before the feature is enabled in client apps.
begin;

create table if not exists public.alani_support_threads (
  id uuid primary key default gen_random_uuid(),
  store_id uuid not null references public.stores(id) on delete restrict,
  buyer_id uuid not null references auth.users(id) on delete restrict,
  merchant_id uuid not null references auth.users(id) on delete restrict,
  status text not null default 'open' check(status in ('open','closed')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(store_id,buyer_id),
  check(buyer_id<>merchant_id)
);
create index if not exists alani_support_merchant_idx
  on public.alani_support_threads(merchant_id,status,updated_at desc);
alter table public.alani_support_threads enable row level security;
revoke all on public.alani_support_threads from public,anon,authenticated;
grant select,insert on public.alani_support_threads to authenticated;
grant update(status,updated_at) on public.alani_support_threads to authenticated;

drop policy if exists alani_support_members_select on public.alani_support_threads;
create policy alani_support_members_select on public.alani_support_threads
  for select to authenticated
  using(buyer_id=(select auth.uid()) or merchant_id=(select auth.uid()));

drop policy if exists alani_support_buyer_create on public.alani_support_threads;
create policy alani_support_buyer_create on public.alani_support_threads
  for insert to authenticated
  with check(
    buyer_id=(select auth.uid()) and status='open'
    and exists(select 1 from public.stores s where
      s.id=store_id and s.owner_id=merchant_id and s.status='approved')
  );

drop policy if exists alani_support_merchant_close on public.alani_support_threads;
create policy alani_support_merchant_close on public.alani_support_threads
  for update to authenticated
  using(merchant_id=(select auth.uid()))
  with check(merchant_id=(select auth.uid()));

create table if not exists public.alani_support_messages(
  id uuid primary key default gen_random_uuid(),
  thread_id uuid not null references public.alani_support_threads(id) on delete restrict,
  sender_id uuid not null references auth.users(id) on delete restrict,
  body text not null check(char_length(btrim(body)) between 1 and 2000),
  created_at timestamptz not null default now()
);
create index if not exists alani_support_messages_latest_idx
  on public.alani_support_messages(thread_id,created_at desc);
alter table public.alani_support_messages enable row level security;
revoke all on public.alani_support_messages from public,anon,authenticated;
grant select,insert on public.alani_support_messages to authenticated;
-- Never grant update or delete directly: keep reported content auditable.

drop policy if exists alani_support_message_members_select
  on public.alani_support_messages;
create policy alani_support_message_members_select
  on public.alani_support_messages for select to authenticated
  using(exists(
    select 1 from public.alani_support_threads t
    where t.id=thread_id and
      (t.buyer_id=(select auth.uid()) or t.merchant_id=(select auth.uid()))
  ));

drop policy if exists alani_support_message_sender_insert
  on public.alani_support_messages;
create policy alani_support_message_sender_insert
  on public.alani_support_messages for insert to authenticated
  with check(
    sender_id=(select auth.uid()) and
    exists(select 1 from public.alani_support_threads t
      where t.id=thread_id and t.status='open'
        and (t.buyer_id=(select auth.uid())
          or t.merchant_id=(select auth.uid())))
  );

commit;
-- This is customer-to-store support only. Personal DMs, voice messages,
-- moderation cases, blocked users, push notifications, and attachments
-- require additional models/verification; do not advertise them as live.
