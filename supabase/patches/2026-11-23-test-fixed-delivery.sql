-- PRE-PUBLISH STAGING PATCH. Apply only to shitreed-test until reviewed.
-- Historical orders keep fee = 0. New COD orders receive fixed 5,000 IQD.
BEGIN;
ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS delivery_fee_iqd bigint NOT NULL DEFAULT 0;

CREATE OR REPLACE FUNCTION public.place_cash_order(
  p_store_id uuid,
  p_items jsonb,
  p_delivery_address text,
  p_phone text,
  p_notes text DEFAULT ''::text
) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE
  v_user uuid := auth.uid();
  v_order uuid;
  v_item jsonb;
  v_product public.products%ROWTYPE;
  v_id uuid;
  v_quantity integer;
  v_subtotal bigint := 0;
  v_delivery_fee bigint := 5000;
  v_seen uuid[] := ARRAY[]::uuid[];
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'LOGIN_REQUIRED';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.stores
                 WHERE id=p_store_id AND status='approved') THEN
    RAISE EXCEPTION 'STORE_NOT_AVAILABLE';
  END IF;
  IF p_delivery_address IS NULL OR
       char_length(trim(p_delivery_address)) NOT BETWEEN 8 AND 300 OR
       p_phone IS NULL OR char_length(trim(p_phone)) NOT BETWEEN 8 AND 25 OR
       p_notes IS NULL OR char_length(p_notes) > 400 THEN
    RAISE EXCEPTION 'INVALID_DELIVERY_DETAILS';
  END IF;
  IF p_items IS NULL OR jsonb_typeof(p_items)<>'array' OR
       jsonb_array_length(p_items) NOT BETWEEN 1 AND 20 THEN
    RAISE EXCEPTION 'INVALID_ITEMS';
  END IF;

  INSERT INTO public.orders
    (buyer_id,store_id,delivery_address,phone,notes,total_iqd,delivery_fee_iqd)
  VALUES
    (v_user,p_store_id,trim(p_delivery_address),trim(p_phone),trim(p_notes),0,v_delivery_fee)
  RETURNING id INTO v_order;

  FOR v_item IN SELECT value FROM jsonb_array_elements(p_items) LOOP
    IF jsonb_typeof(v_item)<>'object' THEN
      RAISE EXCEPTION 'INVALID_ITEM';
    END IF;
    v_id := (v_item->>'product_id')::uuid;
    v_quantity := (v_item->>'quantity')::integer;
    IF v_id IS NULL OR v_quantity IS NULL OR
       v_quantity NOT BETWEEN 1 AND 20 OR v_id=ANY(v_seen) THEN
      RAISE EXCEPTION 'INVALID_OR_DUPLICATE_ITEM';
    END IF;
    v_seen := array_append(v_seen,v_id);

    SELECT * INTO v_product FROM public.products
     WHERE id=v_id AND store_id=p_store_id AND is_active=true FOR UPDATE;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'PRODUCT_UNAVAILABLE';
    END IF;
    IF v_product.stock_quantity<v_quantity THEN
      RAISE EXCEPTION 'OUT_OF_STOCK';
    END IF;
    UPDATE public.products
       SET stock_quantity=stock_quantity-v_quantity WHERE id=v_id;
    INSERT INTO public.order_items
      (order_id,product_id,product_name,unit_price_iqd,quantity,line_total_iqd)
    VALUES (v_order,v_id,v_product.name,v_product.price_iqd,v_quantity,
            v_product.price_iqd::bigint*v_quantity);
    v_subtotal := v_subtotal+v_product.price_iqd::bigint*v_quantity;
  END LOOP;
  UPDATE public.orders SET total_iqd=v_subtotal+v_delivery_fee
   WHERE id=v_order;
  RETURN v_order;
END;
$function$;

REVOKE ALL ON FUNCTION public.place_cash_order(uuid,jsonb,text,text,text)
  FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.place_cash_order(uuid,jsonb,text,text,text)
  TO authenticated,service_role;
COMMIT;
