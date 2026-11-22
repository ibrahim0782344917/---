-- Shitreed: wallet read model + private balanced ledger, private customer/merchant chat,
-- and admin-only aggregate oversight. Additive; ZERO initial balances; no payments enabled.
-- Apply to disposable Staging first. Real money posting requires a separate vetted
-- payment/webhook service, reconciliation, compliance, and two-person approvals.

-- FINANCIAL BOUNDARY: No client role may INSERT, UPDATE or DELETE money.
create schema if not exists shitreed_finance;
revoke all on schema shitreed_finance from public, anon, authenticated;
grant usage on schema shitreed_finance to service_role;

create table if not exists shitreed_finance.accounts (
  id uuid primary key default gen_random_uuid(),
  owner_user_id uuid references auth.users(id) on delete restrict,
  kind text not null check (kind in (
    'customer_wallet','merchant_wallet','customer_points',
    'platform_clearing','points_issuer')),
  currency text not null check (currency in ('IQD','POINT')),
  created_at timestamptz not null default now(),
  check (
    (kind in ('customer_wallet','merchant_wallet','platform_clearing') and currency='IQD') or
    (kind in ('customer_points','points_issuer') and currency='POINT')
  ),
  check (
    (owner_user_id is not null and kind in
      ('customer_wallet','merchant_wallet','customer_points')) or
    (owner_user_id is null and kind in ('platform_clearing','points_issuer'))
  ),
  unique (owner_user_id, kind, currency),
  unique (id, currency)
);
create unique index if not exists shitreed_platform_single_account_per_kind
  on shitreed_finance.accounts(kind) where owner_user_id is null;

create table if not exists shitreed_finance.journals (
  id uuid primary key default gen_random_uuid(),
  currency text not null check (currency in ('IQD','POINT')),
  reference_key text not null unique check (char_length(reference_key) between 8 and 160),
  description text not null check (char_length(description) between 4 and 300),
  created_by uuid references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  unique (id, currency)
);
create table if not exists shitreed_finance.entries (
  id bigint generated always as identity primary key,
  journal_id uuid not null,
  account_id uuid not null,
  currency text not null check (currency in ('IQD','POINT')),
  delta bigint not null check (delta <> 0),
  foreign key (journal_id, currency)
    references shitreed_finance.journals(id, currency) on delete restrict,
  foreign key (account_id, currency)
    references shitreed_finance.accounts(id, currency) on delete restrict,
  unique (journal_id, account_id)
);
create index if not exists shitreed_finance_account_entries
  on shitreed_finance.entries(account_id, id desc);

-- Every posted journal must balance to zero and contain >=2 distinct accounts.
-- Deferred constraint permits both entries to be inserted in one transaction.
create or replace function shitreed_finance.check_balanced_journal()
returns trigger language plpgsql set search_path = '' as $$
declare v_journal uuid := coalesce(new.journal_id, old.journal_id);
        v_total bigint; v_count integer;
begin
  select coalesce(sum(delta),0),count(*) into v_total,v_count
    from shitreed_finance.entries where journal_id=v_journal;
  if v_total <> 0 or v_count < 2 then
    raise exception 'UNBALANCED_FINANCIAL_JOURNAL';
  end if;
  return null;
end; $$;
drop trigger if exists shitreed_entries_balance on shitreed_finance.entries;
create constraint trigger shitreed_entries_balance
after insert or update or delete on shitreed_finance.entries
deferrable initially deferred for each row
execute function shitreed_finance.check_balanced_journal();

-- Corrections are compensating journals, never rewriting money history.
create or replace function shitreed_finance.deny_financial_mutation()
returns trigger language plpgsql set search_path = '' as $$
begin raise exception 'FINANCIAL_LEDGER_IMMUTABLE'; end; $$;
drop trigger if exists shitreed_entries_immutable on shitreed_finance.entries;
create trigger shitreed_entries_immutable before update or delete
on shitreed_finance.entries for each row
execute function shitreed_finance.deny_financial_mutation();
drop trigger if exists shitreed_journals_immutable on shitreed_finance.journals;
create trigger shitreed_journals_immutable before update or delete
on shitreed_finance.journals for each row
execute function shitreed_finance.deny_financial_mutation();

alter table shitreed_finance.accounts enable row level security;
alter table shitreed_finance.journals enable row level security;
alter table shitreed_finance.entries enable row level security;
revoke all on all tables in schema shitreed_finance from public, anon, authenticated;
revoke all on all sequences in schema shitreed_finance from public, anon, authenticated;
grant select,insert on all tables in schema shitreed_finance to service_role;
grant usage,select on all sequences in schema shitreed_finance to service_role;

-- Read only: showing zero means no money has been deposited/posted.
create or replace function public.shitreed_wallet_overview()
returns table(cash_balance_iqd bigint, merchant_balance_iqd bigint, reward_points bigint)
language sql stable security definer set search_path = '' as $$
  select
    coalesce(sum(e.delta) filter(where a.kind='customer_wallet'),0)::bigint,
    coalesce(sum(e.delta) filter(where a.kind='merchant_wallet'),0)::bigint,
    coalesce(sum(e.delta) filter(where a.kind='customer_points'),0)::bigint
  from shitreed_finance.accounts a
  left join shitreed_finance.entries e on e.account_id=a.id
  where a.owner_user_id=(select auth.uid());
$$;
revoke all on function public.shitreed_wallet_overview() from public,anon,authenticated;
grant execute on function public.shitreed_wallet_overview() to authenticated;

create or replace function public.shitreed_wallet_activity(p_limit integer default 30)
returns table(occurred_at timestamptz, currency text, amount bigint,
              description text, reference_key text)
language plpgsql stable security definer set search_path = '' as $$
begin
  if auth.uid() is null then raise exception 'LOGIN_REQUIRED'; end if;
  return query
    select j.created_at, l.currency, l.delta, j.description, j.reference_key
    from shitreed_finance.entries l
    join shitreed_finance.accounts a on a.id=l.account_id
    join shitreed_finance.journals j on j.id=l.journal_id
    where a.owner_user_id=(select auth.uid())
    order by j.created_at desc, l.id desc
    limit least(greatest(coalesce(p_limit,30),1),50);
end; $$;
revoke all on function public.shitreed_wallet_activity(integer) from public,anon,authenticated;
grant execute on function public.shitreed_wallet_activity(integer) to authenticated;

-- CUSTOMER/MERCHANT CHAT: no phone numbers exposed, no public messages.
create table if not exists public.shitreed_chat_threads (
  id uuid primary key default gen_random_uuid(),
  store_id uuid not null references public.stores(id) on delete restrict,
  customer_id uuid not null references auth.users(id) on delete restrict,
  merchant_id uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  last_message_at timestamptz not null default now(),
  closed_at timestamptz,
  unique (store_id, customer_id)
);
create index if not exists shitreed_chat_threads_customer
  on public.shitreed_chat_threads(customer_id,last_message_at desc);
create index if not exists shitreed_chat_threads_store
  on public.shitreed_chat_threads(store_id,last_message_at desc);
create table if not exists public.shitreed_chat_messages (
  id uuid primary key default gen_random_uuid(),
  thread_id uuid not null references public.shitreed_chat_threads(id) on delete restrict,
  sender_id uuid not null references auth.users(id) on delete restrict,
  body text not null check (char_length(btrim(body)) between 1 and 2000),
  created_at timestamptz not null default now()
);
create index if not exists shitreed_chat_messages_thread
  on public.shitreed_chat_messages(thread_id,created_at desc);
alter table public.shitreed_chat_threads enable row level security;
alter table public.shitreed_chat_messages enable row level security;
revoke all on public.shitreed_chat_threads from public,anon,authenticated;
revoke all on public.shitreed_chat_messages from public,anon,authenticated;
grant select on public.shitreed_chat_threads, public.shitreed_chat_messages to authenticated;

create policy "chat threads visible to participants"
on public.shitreed_chat_threads for select to authenticated
using (
  customer_id=(select auth.uid()) or (
    merchant_id=(select auth.uid()) and exists(
      select 1 from public.stores s
      where s.id=store_id and s.owner_id=(select auth.uid())
    )
  )
);
create policy "chat messages visible to participants"
on public.shitreed_chat_messages for select to authenticated
using (exists(
  select 1 from public.shitreed_chat_threads t
  join public.stores s on s.id=t.store_id
  where t.id=thread_id
  and (t.customer_id=(select auth.uid()) or
       (t.merchant_id=(select auth.uid()) and s.owner_id=(select auth.uid())))
));
-- New threads must be initiated by customer; merchants reply in existing threads.
create or replace function public.shitreed_chat_open(p_store_id uuid)
returns uuid language plpgsql security definer set search_path = '' as $$
declare v_user uuid := auth.uid(); v_thread uuid; v_store_owner uuid;
begin
  if v_user is null then raise exception 'LOGIN_REQUIRED'; end if;
  select owner_id into v_store_owner
  from public.stores where id=p_store_id and status='approved';
  if v_store_owner is null then raise exception 'STORE_NOT_AVAILABLE'; end if;
  if v_store_owner=v_user then raise exception 'CANNOT_MESSAGE_SELF'; end if;
  select id into v_thread from public.shitreed_chat_threads
  where store_id=p_store_id and customer_id=v_user;
  if v_thread is not null then return v_thread; end if;
  if (select count(*) from public.shitreed_chat_threads
    where customer_id=v_user and created_at > now()-interval '1 day') >= 10
  then raise exception 'CHAT_THREAD_DAILY_LIMIT'; end if;
  insert into public.shitreed_chat_threads(store_id,customer_id,merchant_id)
  values (p_store_id,v_user,v_store_owner)
  on conflict (store_id,customer_id) do nothing
  returning id into v_thread;
  if v_thread is null then
    select id into v_thread from public.shitreed_chat_threads
    where store_id=p_store_id and customer_id=v_user;
  end if;
  return v_thread;
end; $$;
revoke all on function public.shitreed_chat_open(uuid) from public,anon,authenticated;
grant execute on function public.shitreed_chat_open(uuid) to authenticated;

create or replace function public.shitreed_chat_send(p_thread_id uuid, p_body text)
returns uuid language plpgsql security definer set search_path = '' as $$
declare v_user uuid := auth.uid(); v_message uuid; v_customer uuid;
        v_owner uuid; v_merchant uuid; v_closed timestamptz;
begin
  if v_user is null then raise exception 'LOGIN_REQUIRED'; end if;
  if p_body is null or char_length(btrim(p_body)) not between 1 and 2000
  then raise exception 'INVALID_MESSAGE'; end if;
  -- Serialize all sends from the user to enforce the per-minute limit.
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(v_user::text, 93271));
  select t.customer_id,s.owner_id,t.merchant_id,t.closed_at
    into v_customer,v_owner,v_merchant,v_closed
    from public.shitreed_chat_threads t
    join public.stores s on s.id=t.store_id
    where t.id=p_thread_id;
  if not found or v_owner is distinct from v_merchant or
     (v_user is distinct from v_customer and
      v_user is distinct from v_merchant)
  then raise exception 'CHAT_NOT_AUTHORIZED'; end if;
  if v_closed is not null then raise exception 'CHAT_CLOSED'; end if;
  if (select count(*) from public.shitreed_chat_messages
      where sender_id=v_user and created_at > now()-interval '1 minute') >= 20
  then raise exception 'CHAT_RATE_LIMIT'; end if;
  insert into public.shitreed_chat_messages(thread_id,sender_id,body)
    values (p_thread_id,v_user,btrim(p_body)) returning id into v_message;
  update public.shitreed_chat_threads
    set last_message_at=now() where id=p_thread_id;
  return v_message;
end; $$;
revoke all on function public.shitreed_chat_send(uuid,text) from public,anon,authenticated;
grant execute on function public.shitreed_chat_send(uuid,text) to authenticated;

-- Supabase Postgres Changes sends only RLS-authorized rows to subscribers.
-- Skip when testing against plain PostgreSQL without the realtime publication.
do $
begin
  if exists(select 1 from pg_catalog.pg_publication
            where pubname='supabase_realtime')
     and not exists(
       select 1 from pg_catalog.pg_publication_tables
       where pubname='supabase_realtime'
         and schemaname='public'
         and tablename='shitreed_chat_messages'
     )
  then
    alter publication supabase_realtime add table public.shitreed_chat_messages;
  end if;
end; $;

-- Only trusted app_metadata admin receives aggregate oversight; NO chat bodies.
create or replace function public.shitreed_admin_finance_chat_summary()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  if not public.shitreed_is_admin() then
    raise exception 'ADMIN_ACCESS_REQUIRED';
  end if;
  return pg_catalog.jsonb_build_object(
    'ledger_journals', (select count(*) from shitreed_finance.journals),
    'cash_customer_iqd', (select coalesce(sum(e.delta),0)
      from shitreed_finance.entries e
      join shitreed_finance.accounts a on a.id=e.account_id
      where a.kind='customer_wallet'),
    'cash_merchants_iqd', (select coalesce(sum(e.delta),0)
      from shitreed_finance.entries e
      join shitreed_finance.accounts a on a.id=e.account_id
      where a.kind='merchant_wallet'),
    'reward_points', (select coalesce(sum(e.delta),0)
      from shitreed_finance.entries e
      join shitreed_finance.accounts a on a.id=e.account_id
      where a.kind='customer_points'),
    'chat_threads', (select count(*) from public.shitreed_chat_threads),
    'chat_messages', (select count(*) from public.shitreed_chat_messages)
  );
end; $$;
revoke all on function public.shitreed_admin_finance_chat_summary()
  from public,anon,authenticated;
grant execute on function public.shitreed_admin_finance_chat_summary()
  to authenticated;
