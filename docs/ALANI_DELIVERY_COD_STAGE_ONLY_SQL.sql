-- STAGING REVIEW ONLY. NEVER APPLY TO PRODUCTION WITHOUT DB BACKUP,
-- restore rehearsal, isolated test data, role testing, and owner approval.
-- This keeps all other Shitreed stores at their existing delivery rules.
-- Existing historical orders are NOT retroactively modified.

begin;

alter table public.orders
  add column if not exists delivery_fee_iqd bigint not null default 0
  check (delivery_fee_iqd >= 0 and delivery_fee_iqd <= 1000000);

-- IMPORTANT: exact replacement of the EXISTING place_cash_order function
-- as inspected on November 18, 2026. The web idempotency wrapper
-- place_cash_order_web already invokes this function transactionally.
create or replace function public.place_cash_order(
  p_store_id uuid, p_items jsonb, p_delivery_address text,
  p_phone text, p_notes text default ''
) returns uuid
language plpgsql security definer set search_path to ''
as $function$
declare
  v_user uuid := (select auth.uid());
  v_order uuid;
  v_item jsonb;
  v_product public.products%rowtype;
  v_id uuid;
  v_quantity integer;
  v_total bigint := 0;
  v_fee bigint := 0;
  v_seen uuid[] := array[]::uuid[];
begin
  if v_user is null then raise exception 'LOGIN_REQUIRED'; end if;
  if not exists (
    select 1 from public.stores
    where id=p_store_id and status='approved'
  ) then raise exception 'STORE_NOT_AVAILABLE'; end if;
  if p_delivery_address is null or
     char_length(trim(p_delivery_address)) not between 8 and 300 or
     p_phone is null or char_length(trim(p_phone)) not between 8 and 25 or
     p_notes is null or char_length(p_notes)>400
  then raise exception 'INVALID_DELIVERY_DETAILS'; end if;
  if p_items is null or jsonb_typeof(p_items)<>'array' or
     jsonb_array_length(p_items) not between 1 and 20
  then raise exception 'INVALID_ITEMS'; end if;

  -- Fixed 5,000 IQD delivery charge ONLY for the Al-Ani approved store.
  -- Fees are calculated on the server, never accepted from client JSON.
  if p_store_id='25091ca2-c0da-416c-b634-81b188ee66be'::uuid then
    v_fee:=5000;
  end if;

  insert into public.orders(
    buyer_id,store_id,delivery_address,phone,notes,total_iqd,delivery_fee_iqd
  ) values (
    v_user,p_store_id,trim(p_delivery_address),trim(p_phone),
    trim(p_notes),0,v_fee
  ) returning id into v_order;

  for v_item in select value from jsonb_array_elements(p_items) loop
    if jsonb_typeof(v_item)<>'object' then
      raise exception 'INVALID_ITEM';
    end if;
    v_id:=(v_item->>'product_id')::uuid;
    v_quantity:=(v_item->>'quantity')::integer;
    if v_id is null or v_quantity is null or
       v_quantity not between 1 and 20 or v_id=any(v_seen)
    then raise exception 'INVALID_OR_DUPLICATE_ITEM'; end if;

    v_seen:=array_append(v_seen,v_id);
    select * into v_product from public.products
    where id=v_id and store_id=p_store_id and is_active=true
    for update;
    if not found then raise exception 'PRODUCT_UNAVAILABLE'; end if;
    if v_product.stock_quantity<v_quantity then
      raise exception 'OUT_OF_STOCK';
    end if;

    update public.products
      set stock_quantity=stock_quantity-v_quantity where id=v_id;
    insert into public.order_items(
      order_id,product_id,product_name,unit_price_iqd,
      quantity,line_total_iqd
    ) values (
      v_order,v_id,v_product.name,v_product.price_iqd,v_quantity,
      v_product.price_iqd::bigint*v_quantity
    );
    v_total:=v_total+v_product.price_iqd::bigint*v_quantity;
  end loop;

  update public.orders
    set total_iqd=v_total+v_fee
    where id=v_order and buyer_id=v_user and store_id=p_store_id;
  return v_order;
end;
$function$;

-- Maintain authenticated use, deny anonymous invocations.
revoke all on function public.place_cash_order(
  uuid,jsonb,text,text,text
) from public,anon;
grant execute on function public.place_cash_order(
  uuid,jsonb,text,text,text
) to authenticated;

commit;

-- REQUIRED STAGING SQL CHECKS:
-- 1. Anonymous RPC invocation fails.
-- 2. Buyer A places 2 products: sum(order_items.line_total_iqd)
--    + 5000 == orders.total_iqd, delivery_fee_iqd==5000.
-- 3. Buyer B on another approved store gets delivery_fee_iqd=0,
--    no change in that store's existing checkout behavior.
-- 4. Out-of-stock order atomically rolls back order, order_items,
--    stock quantity and idempotency record.
-- 5. Calling place_cash_order_web twice with identical requestKey
--    returns the same order with exactly ONE 5000 delivery fee.
-- 6. Same requestKey with modified items yields PAYLOAD_MISMATCH,
--    no extra stock decrement or order.
-- 7. Order status cancellation restores inventory exactly once.
-- 8. Admin owner only sees store orders; buyer sees own orders only.
-- 9. Historically-created orders preserve existing total_iqd.
-- 10. API and Flutter display product subtotal, fee and final total.

-- NO EXECUTION ON LIVE SUPABASE IS AUTHORIZED BY THIS REVIEW FILE.
