-- TEST ONLY. Bundle checkout uses existing orders and idempotency, no real payment.
CREATE TABLE private_checkout.alani_bundle_order_test(
 order_id uuid PRIMARY KEY REFERENCES public.orders(id) ON DELETE RESTRICT,
 bundle_id uuid NOT NULL REFERENCES private_checkout.alani_bundle_test(id) ON DELETE RESTRICT,
 title text NOT NULL, price_iqd bigint NOT NULL CHECK(price_iqd>0),
 delivery_fee_iqd bigint NOT NULL CHECK(delivery_fee_iqd IN (0,5000))
);
ALTER TABLE private_checkout.alani_bundle_order_test ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private_checkout.alani_bundle_order_test FROM PUBLIC,anon,authenticated;
CREATE FUNCTION public.alani_place_bundle_test(p_bundle_id uuid,p_request_key uuid,p_expected_total_iqd bigint,p_address text,p_phone text,p_notes text)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE a uuid:=auth.uid(); b private_checkout.alani_bundle_test%ROWTYPE; o uuid; old_hash text; h text;
 q jsonb; fee bigint; line jsonb; pid uuid; qty integer; pr integer; subtotal bigint; running numeric:=0; previous bigint:=0; allocated bigint; base bigint; remainder integer;
BEGIN
 IF a IS NULL THEN RAISE EXCEPTION 'LOGIN_REQUIRED'; END IF;
 IF p_bundle_id IS NULL OR p_request_key IS NULL OR p_expected_total_iqd IS NULL OR p_expected_total_iqd<=0 OR p_address IS NULL OR char_length(btrim(p_address)) NOT BETWEEN 8 AND 300 OR p_phone IS NULL OR char_length(btrim(p_phone)) NOT BETWEEN 8 AND 25 OR p_notes IS NULL OR char_length(p_notes)>400 THEN RAISE EXCEPTION 'INVALID_INPUT'; END IF;
 h:=md5(jsonb_build_array('alani-bundle-v1',p_bundle_id,p_expected_total_iqd,btrim(p_address),btrim(p_phone),p_notes)::text);
 PERFORM pg_advisory_xact_lock(hashtextextended(a::text||':'||p_request_key::text,0));
 SELECT order_id,payload_hash INTO o,old_hash FROM private_checkout.web_checkout_requests WHERE buyer_id=a AND request_key=p_request_key;
 IF FOUND THEN
  IF old_hash<>h THEN RAISE EXCEPTION 'IDEMPOTENCY_PAYLOAD_MISMATCH'; END IF;
  RETURN o;
 END IF;
 SELECT * INTO b FROM private_checkout.alani_bundle_test WHERE id=p_bundle_id AND enabled AND starts_at<=now() AND ends_at>now() FOR SHARE;
 IF NOT FOUND THEN RAISE EXCEPTION 'BUNDLE_UNAVAILABLE'; END IF;
 -- Same canonical stock-lock order as ordinary checkout.
 PERFORM p.id FROM public.products p JOIN jsonb_array_elements(b.items) i ON p.id=(i->>'product_id')::uuid ORDER BY p.id FOR UPDATE OF p;
 q:=public.alani_discount_quote(b.items);
 subtotal:=(q->>'subtotal_iqd')::bigint;
 fee:=CASE WHEN b.free_delivery THEN 0 ELSE 5000 END;
 IF b.price_iqd>subtotal OR subtotal<=0 THEN RAISE EXCEPTION 'BUNDLE_PRICE_TOO_HIGH'; END IF;
 IF b.price_iqd+fee<>p_expected_total_iqd THEN RAISE EXCEPTION 'ORDER_TOTAL_CHANGED'; END IF;
 INSERT INTO public.orders(buyer_id,store_id,delivery_address,phone,notes,total_iqd,delivery_fee_iqd)
 VALUES(a,'25091ca2-c0da-416c-b634-81b188ee66be',btrim(p_address),btrim(p_phone),p_notes,b.price_iqd+fee,fee) RETURNING id INTO o;
 FOR line IN SELECT value FROM jsonb_array_elements(q->'lines') ORDER BY (value->>'product_id')::uuid LOOP
  pid:=(line->>'product_id')::uuid;qty:=(line->>'quantity')::integer;pr:=(line->>'unit_price_iqd')::integer;
  running:=running+pr::numeric*qty;
  allocated:=floor(running*b.price_iqd/subtotal)::bigint-previous;
  previous:=previous+allocated;
  base:=allocated/qty;remainder:=(allocated%qty)::integer;
  UPDATE public.products SET stock_quantity=stock_quantity-qty WHERE id=pid AND stock_quantity>=qty;
  IF NOT FOUND THEN RAISE EXCEPTION 'OUT_OF_STOCK'; END IF;
  IF qty-remainder>0 THEN INSERT INTO public.order_items(order_id,product_id,product_name,unit_price_iqd,quantity,line_total_iqd) VALUES(o,pid,line->>'product_name',base,qty-remainder,base*(qty-remainder)); END IF;
  IF remainder>0 THEN INSERT INTO public.order_items(order_id,product_id,product_name,unit_price_iqd,quantity,line_total_iqd) VALUES(o,pid,line->>'product_name',base+1,remainder,(base+1)*remainder); END IF;
 END LOOP;
 IF previous<>b.price_iqd THEN RAISE EXCEPTION 'BUNDLE_ALLOCATION_ERROR'; END IF;
 INSERT INTO private_checkout.alani_bundle_order_test VALUES(o,b.id,b.title,b.price_iqd,fee);
 INSERT INTO private_checkout.web_checkout_requests(buyer_id,request_key,payload_hash,order_id) VALUES(a,p_request_key,h,o);
 RETURN o;
END $$;
REVOKE ALL ON FUNCTION public.alani_place_bundle_test(uuid,uuid,bigint,text,text,text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.alani_place_bundle_test(uuid,uuid,bigint,text,text,text) TO authenticated;
CREATE OR REPLACE FUNCTION public.change_cash_order_status(p_order_id uuid,p_new_status text)
RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE v_user uuid:=auth.uid(); v_order public.orders%ROWTYPE; v_owner uuid;
BEGIN
 IF v_user IS NULL THEN RAISE EXCEPTION 'LOGIN_REQUIRED'; END IF;
 SELECT * INTO v_order FROM public.orders WHERE id=p_order_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'ORDER_NOT_FOUND'; END IF;
 SELECT owner_id INTO v_owner FROM public.stores WHERE id=v_order.store_id;
 IF v_user=v_order.buyer_id THEN
  IF NOT (v_order.status='placed' AND p_new_status='cancelled') THEN RAISE EXCEPTION 'INVALID_BUYER_TRANSITION'; END IF;
 ELSIF v_user=v_owner THEN
  IF NOT ((v_order.status='placed' AND p_new_status IN ('accepted','rejected')) OR (v_order.status='accepted' AND p_new_status='preparing') OR (v_order.status='preparing' AND p_new_status='ready')) THEN RAISE EXCEPTION 'INVALID_MERCHANT_TRANSITION'; END IF;
 ELSE RAISE EXCEPTION 'PERMISSION_DENIED'; END IF;
 IF p_new_status IN ('cancelled','rejected') THEN
  PERFORM p.id FROM public.products p WHERE EXISTS(SELECT 1 FROM public.order_items i WHERE i.order_id=v_order.id AND i.product_id=p.id) ORDER BY p.id FOR UPDATE OF p;
  UPDATE public.products p SET stock_quantity=p.stock_quantity+i.qty FROM (SELECT product_id,sum(quantity)::integer AS qty FROM public.order_items WHERE order_id=v_order.id GROUP BY product_id) i WHERE p.id=i.product_id;
 END IF;
 UPDATE public.orders SET status=p_new_status,updated_at=now() WHERE id=v_order.id;
 RETURN p_new_status;
END $$;
REVOKE ALL ON FUNCTION public.change_cash_order_status(uuid,text) FROM PUBLIC,anon;
