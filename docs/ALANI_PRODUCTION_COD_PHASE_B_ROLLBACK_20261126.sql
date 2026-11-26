-- Emergency rollback: disable new checkout and restore original legacy function. Does not delete any orders.
REVOKE ALL ON FUNCTION public.place_alani_cash_order(jsonb,text,text,text,uuid,bigint) FROM PUBLIC,anon,authenticated;
CREATE OR REPLACE FUNCTION public.place_cash_order(p_store_id uuid, p_items jsonb, p_delivery_address text, p_phone text, p_notes text DEFAULT ''::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_user uuid := auth.uid();
  v_order uuid;
  v_item jsonb;
  v_product public.products%rowtype;
  v_id uuid;
  v_quantity integer;
  v_total bigint := 0;
  v_seen uuid[] := array[]::uuid[];
begin
  if v_user is null then
    raise exception 'LOGIN_REQUIRED';
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
    (buyer_id, store_id, delivery_address, phone, notes, total_iqd)
  values
    (v_user, p_store_id, trim(p_delivery_address), trim(p_phone),
      trim(p_notes), 0)
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
$function$;
REVOKE ALL ON FUNCTION public.place_cash_order(uuid,jsonb,text,text,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.place_cash_order(uuid,jsonb,text,text,text) TO authenticated;
