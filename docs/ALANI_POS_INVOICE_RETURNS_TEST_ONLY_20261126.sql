-- TEST ONLY. No external payment or tax invoice.
CREATE TABLE private_checkout.alani_pos_invoice_test(
 id uuid PRIMARY KEY, items jsonb NOT NULL, total_iqd bigint NOT NULL CHECK(total_iqd>=0),
 actor uuid NOT NULL REFERENCES auth.users(id), created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE private_checkout.alani_pos_invoice_line_test(
 invoice_id uuid NOT NULL REFERENCES private_checkout.alani_pos_invoice_test(id),
 product_id uuid NOT NULL REFERENCES public.products(id), name text NOT NULL,
 quantity integer NOT NULL CHECK(quantity BETWEEN 1 AND 20),
 price_iqd integer NOT NULL CHECK(price_iqd>=0), estimated_cost_iqd bigint,
 PRIMARY KEY(invoice_id,product_id)
);
CREATE TABLE private_checkout.alani_pos_return_test(
 id uuid PRIMARY KEY, invoice_id uuid NOT NULL, product_id uuid NOT NULL,
 quantity integer NOT NULL CHECK(quantity BETWEEN 1 AND 20), restock boolean NOT NULL,
 reason text NOT NULL CHECK(char_length(reason) BETWEEN 3 AND 200),
 actor uuid NOT NULL REFERENCES auth.users(id), created_at timestamptz NOT NULL DEFAULT now(),
 FOREIGN KEY(invoice_id,product_id) REFERENCES private_checkout.alani_pos_invoice_line_test(invoice_id,product_id)
);
ALTER TABLE private_checkout.alani_pos_invoice_test ENABLE ROW LEVEL SECURITY;
ALTER TABLE private_checkout.alani_pos_invoice_line_test ENABLE ROW LEVEL SECURITY;
ALTER TABLE private_checkout.alani_pos_return_test ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private_checkout.alani_pos_invoice_test,private_checkout.alani_pos_invoice_line_test,private_checkout.alani_pos_return_test FROM PUBLIC,anon,authenticated;
CREATE FUNCTION public.alani_pos_cart_quote_test(p_items jsonb)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE i jsonb; q jsonb; lines jsonb:='[]'; seen uuid[]:='{}'; pid uuid; total bigint:=0;
BEGIN
 IF NOT private_checkout.alani_offer_staff_test() THEN RAISE EXCEPTION 'PERMISSION_DENIED'; END IF;
 IF p_items IS NULL OR jsonb_typeof(p_items)<>'array' OR jsonb_array_length(p_items) NOT BETWEEN 1 AND 20 THEN RAISE EXCEPTION 'INVALID_ITEMS'; END IF;
 FOR i IN SELECT value FROM jsonb_array_elements(p_items) LOOP
  IF jsonb_typeof(i)<>'object' OR coalesce(i->>'quantity','') !~ '^[0-9]{1,2}$' THEN RAISE EXCEPTION 'INVALID_ITEM'; END IF;
  q:=public.alani_pos_quote_test(i->>'barcode',(i->>'quantity')::integer);
  pid:=(q->>'product_id')::uuid;
  IF pid=ANY(seen) THEN RAISE EXCEPTION 'DUPLICATE_PRODUCT'; END IF;
  seen:=array_append(seen,pid);total:=total+(q->>'total_iqd')::bigint;
  lines:=lines||jsonb_build_array(q);
 END LOOP;
 RETURN jsonb_build_object('lines',lines,'total_iqd',total);
END $$;
CREATE FUNCTION public.alani_pos_invoice_sale_test(p_key uuid,p_items jsonb,p_expected_total bigint)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE old private_checkout.alani_pos_invoice_test%ROWTYPE; q jsonb; l jsonb; pid uuid; qty integer; cost bigint;
BEGIN
 IF NOT private_checkout.alani_offer_staff_test() THEN RAISE EXCEPTION 'PERMISSION_DENIED'; END IF;
 IF p_key IS NULL OR p_expected_total IS NULL OR p_expected_total<0 THEN RAISE EXCEPTION 'INVALID_INPUT'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('pos-invoice:'||p_key::text,0));
 SELECT * INTO old FROM private_checkout.alani_pos_invoice_test WHERE id=p_key;
 IF FOUND THEN
  IF (old.items,old.total_iqd) IS DISTINCT FROM (p_items,p_expected_total) THEN RAISE EXCEPTION 'IDEMPOTENCY_PAYLOAD_MISMATCH'; END IF;
  RETURN old.id;
 END IF;
 q:=public.alani_pos_cart_quote_test(p_items);
 PERFORM p.id FROM public.products p WHERE p.id IN (SELECT (v->>'product_id')::uuid FROM jsonb_array_elements(q->'lines') v) ORDER BY p.id FOR UPDATE;
 q:=public.alani_pos_cart_quote_test(p_items);
 IF (q->>'total_iqd')::bigint<>p_expected_total THEN RAISE EXCEPTION 'ORDER_TOTAL_CHANGED'; END IF;
 INSERT INTO private_checkout.alani_pos_invoice_test(id,items,total_iqd,actor) VALUES(p_key,p_items,p_expected_total,auth.uid());
 FOR l IN SELECT value FROM jsonb_array_elements(q->'lines') ORDER BY (value->>'product_id')::uuid LOOP
  pid:=(l->>'product_id')::uuid;qty:=(l->>'quantity')::integer;
  SELECT unit_cost_iqd INTO cost FROM private_checkout.alani_purchase_test WHERE product_id=pid ORDER BY created_at DESC,request_key DESC LIMIT 1;
  UPDATE public.products SET stock_quantity=stock_quantity-qty WHERE id=pid AND store_id='25091ca2-c0da-416c-b634-81b188ee66be'::uuid AND stock_quantity>=qty;
  IF NOT FOUND THEN RAISE EXCEPTION 'PRODUCT_UNAVAILABLE'; END IF;
  INSERT INTO private_checkout.alani_pos_invoice_line_test VALUES(p_key,pid,l->>'name',qty,(l->>'unit_price_iqd')::integer,cost);
 END LOOP;
 RETURN p_key;
END $$;
CREATE FUNCTION public.alani_pos_return_line_test(p_key uuid,p_invoice uuid,p_product uuid,p_qty integer,p_restock boolean,p_reason text)
RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE old private_checkout.alani_pos_return_test%ROWTYPE; l private_checkout.alani_pos_invoice_line_test%ROWTYPE; returned bigint;
BEGIN
 IF NOT private_checkout.alani_offer_staff_test() THEN RAISE EXCEPTION 'PERMISSION_DENIED'; END IF;
 IF p_key IS NULL OR p_qty IS NULL OR p_qty NOT BETWEEN 1 AND 20 OR p_restock IS NULL OR p_reason IS NULL OR char_length(btrim(p_reason)) NOT BETWEEN 3 AND 200 THEN RAISE EXCEPTION 'INVALID_RETURN'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('pos-return:'||p_key::text,0));
 SELECT * INTO old FROM private_checkout.alani_pos_return_test WHERE id=p_key;
 IF FOUND THEN
  IF (old.invoice_id,old.product_id,old.quantity,old.restock,old.reason) IS DISTINCT FROM (p_invoice,p_product,p_qty,p_restock,btrim(p_reason)) THEN RAISE EXCEPTION 'IDEMPOTENCY_PAYLOAD_MISMATCH'; END IF;
  RETURN 'recorded';
 END IF;
 SELECT * INTO l FROM private_checkout.alani_pos_invoice_line_test WHERE invoice_id=p_invoice AND product_id=p_product FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'INVOICE_LINE_NOT_FOUND'; END IF;
 SELECT coalesce(sum(quantity),0) INTO returned FROM private_checkout.alani_pos_return_test WHERE invoice_id=p_invoice AND product_id=p_product;
 IF returned+p_qty>l.quantity THEN RAISE EXCEPTION 'RETURN_EXCEEDS_SALE'; END IF;
 IF p_restock THEN
  UPDATE public.products SET stock_quantity=stock_quantity+p_qty WHERE id=p_product AND store_id='25091ca2-c0da-416c-b634-81b188ee66be'::uuid AND stock_quantity<=2147483647-p_qty;
  IF NOT FOUND THEN RAISE EXCEPTION 'PRODUCT_UNAVAILABLE'; END IF;
 END IF;
 INSERT INTO private_checkout.alani_pos_return_test VALUES(p_key,p_invoice,p_product,p_qty,p_restock,btrim(p_reason),auth.uid(),now());
 RETURN 'recorded';
END $$;
CREATE FUNCTION public.alani_pos_invoice_list_test()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE result jsonb;
BEGIN
 IF NOT private_checkout.alani_offer_staff_test() THEN RAISE EXCEPTION 'PERMISSION_DENIED'; END IF;
 SELECT coalesce(jsonb_agg(to_jsonb(t) ORDER BY t.created_at DESC,t.id),'[]') INTO result FROM (
 SELECT i.id,i.total_iqd,i.created_at,(SELECT jsonb_agg(jsonb_build_object('product_id',l.product_id,'name',l.name,'quantity',l.quantity,'unit_price_iqd',l.price_iqd,'returned_qty',coalesce((SELECT sum(r.quantity) FROM private_checkout.alani_pos_return_test r WHERE r.invoice_id=l.invoice_id AND r.product_id=l.product_id),0))) FROM private_checkout.alani_pos_invoice_line_test l WHERE l.invoice_id=i.id) AS lines
 FROM private_checkout.alani_pos_invoice_test i ORDER BY i.created_at DESC,i.id LIMIT 100) t;
 RETURN result;
END $$;
CREATE FUNCTION public.alani_pos_margin_test()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE result jsonb;
BEGIN
 IF NOT private_checkout.alani_offer_staff_test() THEN RAISE EXCEPTION 'PERMISSION_DENIED'; END IF;
 WITH lines AS (
 SELECT l.*,coalesce((SELECT sum(r.quantity) FROM private_checkout.alani_pos_return_test r WHERE r.invoice_id=l.invoice_id AND r.product_id=l.product_id),0) AS returned,
 coalesce((SELECT sum(r.quantity) FROM private_checkout.alani_pos_return_test r WHERE r.invoice_id=l.invoice_id AND r.product_id=l.product_id AND r.restock),0) AS restocked FROM private_checkout.alani_pos_invoice_line_test l
 ), totals AS (SELECT coalesce(sum(quantity::numeric*price_iqd),0) AS gross,coalesce(sum(returned::numeric*price_iqd),0) AS refunds,coalesce(sum((quantity-restocked)::numeric*estimated_cost_iqd),0) AS cost,count(*) FILTER(WHERE estimated_cost_iqd IS NULL AND quantity>restocked) AS missing FROM lines)
 SELECT jsonb_build_object('sales_iqd',gross,'returns_iqd',refunds,'net_sales_iqd',gross-refunds,'estimated_cost_iqd',CASE WHEN missing=0 THEN cost END,'estimated_gross_margin_iqd',CASE WHEN missing=0 THEN gross-refunds-cost END,'missing_cost_lines',missing,'method','latest_purchase_snapshot_not_fifo','includes_legacy_pos',false,'includes_online_orders',false,'includes_expenses',false) INTO result FROM totals;
 RETURN result;
END $$;
REVOKE ALL ON FUNCTION public.alani_pos_cart_quote_test(jsonb),public.alani_pos_invoice_sale_test(uuid,jsonb,bigint),public.alani_pos_return_line_test(uuid,uuid,uuid,integer,boolean,text),public.alani_pos_invoice_list_test(),public.alani_pos_margin_test() FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.alani_pos_cart_quote_test(jsonb),public.alani_pos_invoice_sale_test(uuid,jsonb,bigint),public.alani_pos_return_line_test(uuid,uuid,uuid,integer,boolean,text),public.alani_pos_invoice_list_test(),public.alani_pos_margin_test() TO authenticated;
