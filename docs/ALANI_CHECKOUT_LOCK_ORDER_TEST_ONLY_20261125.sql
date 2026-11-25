-- TEST ONLY: lock cart product rows in canonical UUID order; payload hashing unchanged.
CREATE OR REPLACE FUNCTION public.place_alani_cash_order(p_items jsonb, p_delivery_address text, p_phone text, p_notes text, p_request_key uuid, p_expected_total_iqd bigint)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_user uuid := (select auth.uid());
  v_store constant uuid := '25091ca2-c0da-416c-b634-81b188ee66be'::uuid;
  v_fee constant bigint := 5000;
  v_order uuid;
  v_existing_hash text;
  v_hash text;
  v_item jsonb;
  v_product public.products%rowtype;
  v_id uuid;
  v_qty integer;
  v_effective_price integer;
  v_total bigint := 5000;
  v_seen uuid[] := array[]::uuid[];
begin
  if v_user is null then raise exception 'LOGIN_REQUIRED'; end if;
  if p_request_key is null then raise exception 'MISSING_REQUEST_KEY'; end if;
  if p_expected_total_iqd is null or
     p_expected_total_iqd < v_fee or p_expected_total_iqd > 100000000000
  then raise exception 'INVALID_TOTAL'; end if;
  if not exists (
    select 1 from public.stores where id = v_store and status = 'approved'
  ) then raise exception 'STORE_NOT_AVAILABLE'; end if;
  if p_delivery_address is null or
     char_length(pg_catalog.btrim(p_delivery_address)) not between 8 and 300
     or p_phone is null or
     char_length(pg_catalog.btrim(p_phone)) not between 8 and 25
     or p_notes is null or char_length(p_notes) > 400
  then raise exception 'INVALID_DELIVERY_DETAILS'; end if;
  if p_items is null or pg_catalog.jsonb_typeof(p_items) <> 'array'
     or pg_catalog.jsonb_array_length(p_items) not between 1 and 20
  then raise exception 'INVALID_ITEMS'; end if;

  v_hash := pg_catalog.md5(v_store::text || '|' || p_items::text ||
    '|' || pg_catalog.btrim(p_delivery_address) ||
    '|' || pg_catalog.btrim(p_phone) || '|' || p_notes ||
    '|' || p_expected_total_iqd::text || '|alani-cod-v1');

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(v_user::text || ':' || p_request_key::text,0)
  );
  select order_id,payload_hash into v_order,v_existing_hash
    from private_checkout.web_checkout_requests
    where buyer_id = v_user and request_key = p_request_key;
  if v_order is not null then
    if v_existing_hash <> v_hash then
      raise exception 'IDEMPOTENCY_PAYLOAD_MISMATCH';
    end if;
    return v_order;
  end if;

  -- Keep the price, inventory, shipping fee, and idempotency record
  -- in ONE database transaction. Any error rolls them all back.
  insert into public.orders(
    buyer_id,store_id,delivery_address,phone,notes,total_iqd,delivery_fee_iqd
  ) values (
    v_user,v_store,pg_catalog.btrim(p_delivery_address),
    pg_catalog.btrim(p_phone),pg_catalog.btrim(p_notes),0,v_fee
  ) returning id into v_order;

  for v_item in select value from pg_catalog.jsonb_array_elements(p_items) order by (value->>'product_id')::uuid loop
    if pg_catalog.jsonb_typeof(v_item) <> 'object' then
      raise exception 'INVALID_ITEM'; end if;
    v_id := (v_item->>'product_id')::uuid;
    v_qty := (v_item->>'quantity')::integer;
    if v_id is null or v_qty is null or
       v_qty not between 1 and 20 or v_id = any(v_seen)
    then raise exception 'INVALID_OR_DUPLICATE_ITEM'; end if;
    v_seen := pg_catalog.array_append(v_seen,v_id);
    select * into v_product from public.products
      where id=v_id and store_id=v_store and is_active=true
      for update;
    if not found then raise exception 'PRODUCT_UNAVAILABLE'; end if;
    if v_product.stock_quantity < v_qty then
      raise exception 'OUT_OF_STOCK'; end if;
    v_effective_price := public.alani_active_campaign_price(v_id,v_product.price_iqd);
    update public.products
      set stock_quantity=stock_quantity-v_qty where id=v_id;
    insert into public.order_items(
      order_id,product_id,product_name,unit_price_iqd,
      quantity,line_total_iqd
    ) values (
      v_order,v_id,v_product.name,v_effective_price,
      v_qty,v_effective_price::bigint*v_qty
    );
    v_total := v_total + v_effective_price::bigint*v_qty;
  end loop;

  if v_total <> p_expected_total_iqd then
    raise exception 'ORDER_TOTAL_CHANGED'; end if;
  update public.orders set total_iqd=v_total where id=v_order;
  insert into private_checkout.web_checkout_requests(
    buyer_id,request_key,payload_hash,order_id
  ) values (v_user,p_request_key,v_hash,v_order);
  return v_order;
end;
$function$;
