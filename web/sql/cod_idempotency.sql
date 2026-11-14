-- Website-only COD idempotency; existing mobile order RPC remains unchanged.
create schema if not exists private_checkout;
revoke all on schema private_checkout from public, anon, authenticated;
create table if not exists private_checkout.web_checkout_requests (
  buyer_id uuid not null references auth.users(id),
  request_key uuid not null,
  payload_hash text not null,
  order_id uuid not null references public.orders(id),
  created_at timestamptz not null default now(),
  primary key (buyer_id, request_key)
);
alter table private_checkout.web_checkout_requests enable row level security;
revoke all on table private_checkout.web_checkout_requests from public, anon, authenticated;

create or replace function public.place_cash_order_web(
 p_store_id uuid,
 p_items jsonb,
 p_delivery_address text,
 p_phone text,
 p_notes text,
 p_request_key uuid
) returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := (select auth.uid());
  v_current uuid;
  v_existing_hash text;
  v_hash text;
begin
  if v_user is null then raise exception 'LOGIN_REQUIRED'; end if;
  if p_request_key is null then raise exception 'MISSING_REQUEST_KEY'; end if;
  if p_store_id is null or p_items is null
     or p_delivery_address is null or p_phone is null or p_notes is null
  then raise exception 'INVALID_REQUEST'; end if;

  v_hash := pg_catalog.md5(p_store_id::text || '|' || p_items::text || '|' ||
    pg_catalog.btrim(p_delivery_address) || '|' || pg_catalog.btrim(p_phone) ||
    '|' || p_notes);

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(v_user::text || ':' || p_request_key::text, 0)
  );
  select order_id, payload_hash into v_current, v_existing_hash
    from private_checkout.web_checkout_requests
    where buyer_id = v_user and request_key = p_request_key;

  if v_current is not null then
    if v_existing_hash <> v_hash then
      raise exception 'IDEMPOTENCY_PAYLOAD_MISMATCH';
    end if;
    return v_current;
  end if;

  v_current := public.place_cash_order(
    p_store_id, p_items, p_delivery_address, p_phone, p_notes
  );
  insert into private_checkout.web_checkout_requests
    (buyer_id, request_key, payload_hash, order_id)
  values (v_user, p_request_key, v_hash, v_current);
  return v_current;
end;
$$;

revoke all on function public.place_cash_order_web(uuid,jsonb,text,text,text,uuid)
 from public, anon;
grant execute on function public.place_cash_order_web(uuid,jsonb,text,text,text,uuid)
 to authenticated;
