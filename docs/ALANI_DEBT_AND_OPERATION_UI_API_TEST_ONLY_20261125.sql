-- TEST ONLY: no money transfer. Supplier payment records against individual credit purchases.
CREATE TABLE private_checkout.alani_debt_payments_test(
 request_key uuid PRIMARY KEY,
 purchase_key uuid NOT NULL REFERENCES private_checkout.alani_purchase_test(request_key) ON DELETE RESTRICT,
 amount_iqd bigint NOT NULL CHECK(amount_iqd>0),
 actor uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
 created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE private_checkout.alani_debt_payments_test ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private_checkout.alani_debt_payments_test FROM PUBLIC,anon,authenticated;
CREATE INDEX alani_debt_payments_purchase_idx ON private_checkout.alani_debt_payments_test(purchase_key);
CREATE FUNCTION public.alani_record_debt_payment_test(p_key uuid,p_purchase uuid,p_amount bigint)
RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE r private_checkout.alani_debt_payments_test%ROWTYPE; p private_checkout.alani_purchase_test%ROWTYPE; paid numeric;
BEGIN
 IF NOT private_checkout.alani_offer_staff_test() THEN RAISE EXCEPTION 'PERMISSION_DENIED'; END IF;
 IF p_key IS NULL OR p_purchase IS NULL OR p_amount IS NULL OR p_amount<=0 THEN RAISE EXCEPTION 'INVALID_PAYMENT'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('debt-payment:'||p_key::text,0));
 SELECT * INTO r FROM private_checkout.alani_debt_payments_test WHERE request_key=p_key;
 IF FOUND THEN
  IF (r.purchase_key,r.amount_iqd) IS DISTINCT FROM (p_purchase,p_amount) THEN RAISE EXCEPTION 'IDEMPOTENCY_PAYLOAD_MISMATCH'; END IF;
  RETURN 'recorded';
 END IF;
 SELECT * INTO p FROM private_checkout.alani_purchase_test WHERE request_key=p_purchase FOR UPDATE;
 IF NOT FOUND OR NOT p.on_credit THEN RAISE EXCEPTION 'CREDIT_PURCHASE_REQUIRED'; END IF;
 SELECT coalesce(sum(amount_iqd),0) INTO paid FROM private_checkout.alani_debt_payments_test WHERE purchase_key=p_purchase;
 IF p_amount>p.quantity::bigint*p.unit_cost_iqd-paid THEN RAISE EXCEPTION 'PAYMENT_EXCEEDS_BALANCE'; END IF;
 INSERT INTO private_checkout.alani_debt_payments_test(request_key,purchase_key,amount_iqd,actor) VALUES(p_key,p_purchase,p_amount,auth.uid());
 RETURN 'recorded';
END $$;
CREATE FUNCTION public.alani_debt_report_test()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE result jsonb;
BEGIN
 IF NOT private_checkout.alani_offer_staff_test() THEN RAISE EXCEPTION 'PERMISSION_DENIED'; END IF;
 WITH balances AS (
 SELECT p.request_key AS purchase_key,s.name AS supplier,p.product_id,p.created_at,
 p.quantity::bigint*p.unit_cost_iqd AS original_iqd,
 coalesce((SELECT sum(d.amount_iqd) FROM private_checkout.alani_debt_payments_test d WHERE d.purchase_key=p.request_key),0) AS paid_iqd
 FROM private_checkout.alani_purchase_test p JOIN private_checkout.alani_suppliers_test s ON s.id=p.supplier_id WHERE p.on_credit
 ), rows AS (SELECT *,original_iqd-paid_iqd AS balance_iqd FROM balances)
 SELECT jsonb_build_object('original_iqd',coalesce(sum(original_iqd),0),'paid_iqd',coalesce(sum(paid_iqd),0),'balance_iqd',coalesce(sum(balance_iqd),0),
 'items',coalesce((SELECT jsonb_agg(to_jsonb(t) ORDER BY t.created_at DESC,t.purchase_key) FROM (SELECT * FROM rows ORDER BY (balance_iqd>0) DESC,created_at DESC,purchase_key LIMIT 200) t),'[]'::jsonb)) INTO result FROM rows;
 RETURN result;
END $$;
CREATE FUNCTION public.alani_pos_quote_test(p_barcode text,p_qty integer)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE p public.products%ROWTYPE; price integer;
BEGIN
 IF NOT private_checkout.alani_offer_staff_test() THEN RAISE EXCEPTION 'PERMISSION_DENIED'; END IF;
 IF p_barcode IS NULL OR p_barcode !~ '^[0-9]{8,14}$' OR p_qty IS NULL OR p_qty NOT BETWEEN 1 AND 20 THEN RAISE EXCEPTION 'INVALID_POS'; END IF;
 SELECT pr.* INTO p FROM public.products pr JOIN private_checkout.alani_inventory_settings_test s ON s.product_id=pr.id WHERE s.barcode=p_barcode AND pr.store_id='25091ca2-c0da-416c-b634-81b188ee66be'::uuid AND pr.is_active;
 IF NOT FOUND OR p.stock_quantity<p_qty THEN RAISE EXCEPTION 'PRODUCT_UNAVAILABLE'; END IF;
 price:=public.alani_active_campaign_price(p.id,p.price_iqd);
 RETURN jsonb_build_object('name',p.name,'product_id',p.id,'unit_price_iqd',price,'quantity',p_qty,'total_iqd',price::bigint*p_qty);
END $$;
CREATE FUNCTION public.alani_save_supplier_key_test(p_key uuid,p_name text)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE old_name text;
BEGIN
 IF NOT private_checkout.alani_offer_staff_test() THEN RAISE EXCEPTION 'PERMISSION_DENIED'; END IF;
 IF p_key IS NULL OR p_name IS NULL OR char_length(btrim(p_name)) NOT BETWEEN 2 AND 120 THEN RAISE EXCEPTION 'INVALID_SUPPLIER'; END IF;
 INSERT INTO private_checkout.alani_suppliers_test(id,name,created_by) VALUES(p_key,btrim(p_name),auth.uid()) ON CONFLICT(id) DO NOTHING;
 SELECT name INTO old_name FROM private_checkout.alani_suppliers_test WHERE id=p_key;
 IF old_name IS DISTINCT FROM btrim(p_name) THEN RAISE EXCEPTION 'IDEMPOTENCY_PAYLOAD_MISMATCH'; END IF;
 RETURN p_key;
END $$;
CREATE FUNCTION public.alani_bundle_order_lookup_test(p_key uuid)
RETURNS uuid LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE result uuid;
BEGIN
 IF auth.uid() IS NULL THEN RAISE EXCEPTION 'LOGIN_REQUIRED'; END IF;
 SELECT w.order_id INTO result FROM private_checkout.web_checkout_requests w JOIN private_checkout.alani_bundle_order_test b ON b.order_id=w.order_id WHERE w.buyer_id=auth.uid() AND w.request_key=p_key;
 RETURN result;
END $$;
REVOKE ALL ON FUNCTION public.alani_record_debt_payment_test(uuid,uuid,bigint),public.alani_debt_report_test(),public.alani_pos_quote_test(text,integer),public.alani_save_supplier_key_test(uuid,text),public.alani_bundle_order_lookup_test(uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.alani_record_debt_payment_test(uuid,uuid,bigint),public.alani_debt_report_test(),public.alani_pos_quote_test(text,integer),public.alani_save_supplier_key_test(uuid,text),public.alani_bundle_order_lookup_test(uuid) TO authenticated;
