-- Prevent duplicate cash orders when the Android client retries after a timeout.
-- Deliberately kept on a feature branch; deploy this migration before shipping
-- the new client. Existing clients can continue to omit p_request_id.
alter table public.orders
  add column if not exists client_request_id uuid;
alter table public.orders
  add column if not exists request_payload_digest text;

create unique index if not exists orders_buyer_request_key_unique
  on public.orders (buyer_id, client_request_id)
  where client_request_id is not null;

-- PostgreSQL functions cannot replace their argument signature in-place.
-- Migrations execute transactionally: the old RPC stays available on failure.
drop function if exists public.place_cash_order(uuid, jsonb, text, text, text);

create function public.place_cash_order(
  p_store_id uuid,
  p_items jsonb,
  p_delivery_address text,
  p_phone text,
  p_notes text default '',
  p_request_id uuid default null
) returns uuid
language plpgsql security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
  v_order uuid;
  v_item jsonb;
  v_product public.products%rowtype;
  v_id uuid;
  v_quantity integer;
  v_total bigint := 0;
  v_seen uuid[] := array[]::uuid[];
  v_request_digest text;
  v_prior public.orders%rowtype;
begin
  if v_user is null then
    raise exception 'LOGIN_REQUIRED';
  end if;

  -- Serialize same-user/same-request retries before checking stock.
  -- PostgreSQL's transaction-scoped advisory lock releases automatically.
  if p_request_id is not null then
    perform pg_catalog.pg_advisory_xact_lock(
      pg_catalog.hashtextextended(
        v_user::text || ':' || p_request_id::text, 0
      )
    );

    v_request_digest := pg_catalog.md5(
      coalesce(p_store_id::text, '') || '|' ||
      coalesce(p_items::text, '') || '|' ||
      coalesce(trim(p_delivery_address), '') || '|' ||
      coalesce(trim(p_phone), '') || '|' ||
      coalesce(trim(p_notes), '')
    );

    select * into v_prior
      from public.orders
      where buyer_id = v_user and client_request_id = p_request_id;

    if found then
      if v_prior.request_payload_digest is distinct from v_request_digest then
        raise exception 'IDEMPOTENCY_KEY_REUSED';
      end if;
      return v_prior.id;
    end if;
  end if;

  if not exists (select 1 from public.stores
      where id = p_store_id and status = 'approved') then
    raise exception 'STORE_NOT_AVAILABLE';
  end if;
  if p_delivery_address is null or
       char_length(trim(p_delivery_address)) not between 8 and 300 or
       p_phone is null or char_length(trim(p_phone)) not between 8 and 25 or
       p_notes is null or char_length(p_notes) > 400 then
    raise exception 'INVALID_DELIVERY_DETAILS';
  end if;
  if p_items is null or jsonb_typeof(p_items) <> 'array'
       or jsonb_array_length(p_items) not between 1 and 20 then
    raise exception 'INVALID_ITEMS';
  end if;

  insert into public.orders
    (buyer_id, store_id, delivery_address, phone, notes, total_iqd,
     client_request_id, request_payload_digest)
  values
    (v_user, p_store_id, trim(p_delivery_address), trim(p_phone),
     trim(p_notes), 0, p_request_id, v_request_digest)
  returning id into v_order;

  for v_item in select value from jsonb_array_elements(p_items) loop
    if jsonb_typeof(v_item) <> 'object' then
      raise exception 'INVALID_ITEM';
    end if;
    v_id := (v_item ->> 'product_id')::uuid;
    v_quantity := (v_item ->> 'quantity')::integer;
    if v_id is null or v_quantity is null or
         v_quantity not between 1 and 20 or v_id = any(v_seen) then
      raise exception 'INVALID_OR_DUPLICATE_ITEM';
    end if;
    v_seen := array_append(v_seen, v_id);
    select * into v_product from public.products
      where id = v_id and store_id = p_store_id and is_active = true
      for update;
    if not found then
      raise exception 'PRODUCT_UNAVAILABLE';
    end if;
    if v_product.stock_quantity < v_quantity then
      raise exception 'OUT_OF_STOCK';
    end if;
    update public.products
      set stock_quantity = stock_quantity - v_quantity where id = v_id;
    insert into public.order_items
      (order_id, product_id, product_name, unit_price_iqd,
       quantity, line_total_iqd)
    values
      (v_order, v_id, v_product.name, v_product.price_iqd,
       v_quantity, v_product.price_iqd::bigint * v_quantity);
    v_total := v_total + v_product.price_iqd::bigint * v_quantity;
  end loop;
  update public.orders set total_iqd = v_total where id = v_order;
  return v_order;
end;
$$;

revoke all on function public.place_cash_order(uuid,jsonb,text,text,text,uuid)
  from public, anon, authenticated;
grant execute on function public.place_cash_order(uuid,jsonb,text,text,text,uuid)
  to authenticated;

comment on column public.orders.client_request_id
  is 'Optional per-user checkout idempotency key supplied by client';
comment on column public.orders.request_payload_digest
  is 'Checkout payload checksum for safe replay matching; no card details';
notify pgrst, 'reload schema';
