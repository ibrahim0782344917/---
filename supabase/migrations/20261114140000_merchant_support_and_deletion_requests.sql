-- Shitreed Merchant: real help tickets and account-deletion requests.
-- Non-destructive: no accounts, stores, products or orders are deleted here.
create table if not exists public.shitreed_merchant_support_tickets (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete restrict,
  subject text not null check (char_length(subject) between 5 and 120),
  body text not null check (char_length(body) between 15 and 2000),
  status text not null default 'open'
    check (status in ('open','reviewing','resolved','closed')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists merchant_tickets_user_date
  on public.shitreed_merchant_support_tickets(user_id,created_at desc);
alter table public.shitreed_merchant_support_tickets enable row level security;
revoke all on public.shitreed_merchant_support_tickets
  from public,anon,authenticated;
grant select on public.shitreed_merchant_support_tickets to authenticated;
create policy "merchant can view own support tickets"
  on public.shitreed_merchant_support_tickets for select to authenticated
  using (user_id = (select auth.uid()));

create table if not exists public.shitreed_merchant_deletion_requests (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete restrict,
  note text not null default ''
    check (char_length(note) <= 1000),
  status text not null default 'requested'
    check (status in ('requested','under_review','completed','declined')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  resolved_at timestamptz
);
create index if not exists merchant_deletion_user_date
  on public.shitreed_merchant_deletion_requests(user_id,created_at desc);
create unique index if not exists merchant_one_active_deletion_request
  on public.shitreed_merchant_deletion_requests(user_id)
  where status in ('requested','under_review');
alter table public.shitreed_merchant_deletion_requests enable row level security;
revoke all on public.shitreed_merchant_deletion_requests
  from public,anon,authenticated;
grant select on public.shitreed_merchant_deletion_requests to authenticated;
create policy "merchant can view own account deletion requests"
  on public.shitreed_merchant_deletion_requests for select to authenticated
  using (user_id = (select auth.uid()));

-- Clients cannot directly modify ticket status, approve deletion, or
-- pretend that an account has been deleted. Requests go through RPC.
create or replace function public.shitreed_merchant_open_ticket(
  p_subject text, p_body text
) returns uuid
language plpgsql security definer set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
  v_id uuid;
begin
  if v_user is null then raise exception 'LOGIN_REQUIRED'; end if;
  if p_subject is null or char_length(btrim(p_subject)) not between 5 and 120
     or p_body is null or char_length(btrim(p_body)) not between 15 and 2000
  then raise exception 'INVALID_SUPPORT_DETAILS'; end if;
  if (select count(*) from public.shitreed_merchant_support_tickets
      where user_id = v_user and created_at >= now()-interval '1 day') >= 5
  then raise exception 'SUPPORT_RATE_LIMIT'; end if;
  insert into public.shitreed_merchant_support_tickets
    (user_id,subject,body)
  values (v_user,btrim(p_subject),btrim(p_body))
  returning id into v_id;
  return v_id;
end;
$$;
revoke all on function public.shitreed_merchant_open_ticket(text,text)
  from public,anon,authenticated;
grant execute on function public.shitreed_merchant_open_ticket(text,text)
  to authenticated;

-- User-submitted deletion request, NOT instant deletion. The business
-- must verify identity, retention obligations and fulfill the request.
create or replace function public.shitreed_merchant_request_deletion(
  p_note text default ''
) returns uuid
language plpgsql security definer set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
  v_id uuid;
begin
  if v_user is null then raise exception 'LOGIN_REQUIRED'; end if;
  if p_note is null or char_length(p_note) > 1000
  then raise exception 'INVALID_REQUEST'; end if;
  select id into v_id
    from public.shitreed_merchant_deletion_requests
    where user_id = v_user and status in ('requested','under_review')
    order by created_at desc limit 1;
  if v_id is not null then return v_id; end if;

  insert into public.shitreed_merchant_deletion_requests (user_id,note)
  values (v_user,btrim(p_note))
  returning id into v_id;
  return v_id;
end;
$$;
revoke all on function public.shitreed_merchant_request_deletion(text)
  from public,anon,authenticated;
grant execute on function public.shitreed_merchant_request_deletion(text)
  to authenticated;
