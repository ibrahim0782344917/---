-- STAGING ONLY. Internal noncash store credit, NOT a bank wallet.
-- Requires separately authenticated server-side role authorization,
-- signed audit records, legal/tax review and owner approval before activation.
-- Do NOT expose this schema in the Supabase Data API.
begin;
create schema if not exists private_finance;
revoke all on schema private_finance from public,anon,authenticated;
grant usage on schema private_finance to service_role;

create table if not exists private_finance.store_credit_balances(
  store_id uuid not null references public.stores(id) on delete restrict,
  user_id uuid not null references auth.users(id) on delete restrict,
  balance_iqd bigint not null default 0 check(balance_iqd>=0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key(store_id,user_id)
);

create table if not exists private_finance.store_credit_movements(
  id uuid primary key default gen_random_uuid(),
  store_id uuid not null references public.stores(id) on delete restrict,
  user_id uuid not null references auth.users(id) on delete restrict,
  actor_id uuid not null references auth.users(id) on delete restrict,
  request_key uuid not null,
  direction text not null check(direction in ('credit','debit')),
  amount_iqd bigint not null check(amount_iqd between 1 and 1000000000),
  before_iqd bigint not null check(before_iqd>=0),
  after_iqd bigint not null check(after_iqd>=0),
  reason text not null check(char_length(btrim(reason)) between 8 and 500),
  created_at timestamptz not null default now(),
  unique(store_id,user_id,request_key)
);
create index if not exists credit_movements_owner_time
  on private_finance.store_credit_movements(store_id,user_id,created_at desc);

alter table private_finance.store_credit_balances enable row level security;
alter table private_finance.store_credit_movements enable row level security;
revoke all on private_finance.store_credit_balances from public,anon,authenticated;
revoke all on private_finance.store_credit_movements from public,anon,authenticated;

create or replace function private_finance.reject_ledger_mutation()
returns trigger language plpgsql set search_path=''
as $body$
begin
  raise exception 'IMMUTABLE_LEDGER';
end;
$body$;
drop trigger if exists credit_movements_immutable
  on private_finance.store_credit_movements;
create trigger credit_movements_immutable before update or delete
  on private_finance.store_credit_movements
  for each row execute function private_finance.reject_ledger_mutation();

create or replace function private_finance.apply_store_credit(
  p_store_id uuid,
  p_user_id uuid,
  p_actor_id uuid,
  p_amount_iqd bigint,
  p_direction text,
  p_request_key uuid,
  p_reason text
) returns bigint
language plpgsql security definer set search_path=''
as $body$
declare
  v_before bigint;
  v_after bigint;
  v_previous private_finance.store_credit_movements%rowtype;
begin
  if p_store_id is null or p_user_id is null or p_actor_id is null or
     p_request_key is null or
     p_amount_iqd not between 1 and 1000000000 or
     p_direction not in ('credit','debit') or
     p_reason is null or char_length(btrim(p_reason)) not between 8 and 500
  then raise exception 'INVALID_STORE_CREDIT_REQUEST'; end if;

  -- Checks for seller/owner/staff authorization MUST be completed by a
  -- trusted server process before calling this private function.
  if not exists(select 1 from public.stores where id=p_store_id) then
    raise exception 'STORE_NOT_FOUND';
  end if;
  if not exists(select 1 from auth.users where id=p_user_id) then
    raise exception 'CUSTOMER_NOT_FOUND';
  end if;
  if not exists(select 1 from auth.users where id=p_actor_id) then
    raise exception 'ACTOR_NOT_FOUND';
  end if;

  insert into private_finance.store_credit_balances(store_id,user_id)
    values(p_store_id,p_user_id) on conflict do nothing;
  select balance_iqd into v_before
    from private_finance.store_credit_balances
    where store_id=p_store_id and user_id=p_user_id for update;
  select * into v_previous
    from private_finance.store_credit_movements
    where store_id=p_store_id and user_id=p_user_id
      and request_key=p_request_key;
  if found then
    if v_previous.direction<>p_direction or
       v_previous.amount_iqd<>p_amount_iqd or
       v_previous.actor_id<>p_actor_id or
       v_previous.reason<>p_reason then
      raise exception 'CREDIT_IDEMPOTENCY_MISMATCH';
    end if;
    return v_previous.after_iqd;
  end if;

  if p_direction='debit' then
    if v_before<p_amount_iqd then
      raise exception 'INSUFFICIENT_STORE_CREDIT';
    end if;
    v_after:=v_before-p_amount_iqd;
  else
    v_after:=v_before+p_amount_iqd;
  end if;

  update private_finance.store_credit_balances
    set balance_iqd=v_after,updated_at=now()
    where store_id=p_store_id and user_id=p_user_id;
  insert into private_finance.store_credit_movements(
    store_id,user_id,actor_id,request_key,direction,amount_iqd,
    before_iqd,after_iqd,reason
  ) values (
    p_store_id,p_user_id,p_actor_id,p_request_key,p_direction,p_amount_iqd,
    v_before,v_after,p_reason
  );
  return v_after;
end;
$body$;

revoke all on function private_finance.apply_store_credit(
  uuid,uuid,uuid,bigint,text,uuid,text
) from public,anon,authenticated;
grant execute on function private_finance.apply_store_credit(
  uuid,uuid,uuid,bigint,text,uuid,text
) to service_role;
commit;

-- SCOPE / ACCEPTANCE:
-- no direct debit/credit from Flutter/Admin
-- never delete or edit a movement, corrections are reversing entries
-- unique idempotency key per store+customer
-- no negative balances, no cash withdrawals or transfers
-- trusted backend validates store ownership & actor permissions
-- no access to private_finance via public REST schema
-- do not activate before full staging security, consumer and legal review.
