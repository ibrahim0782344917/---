-- TEST ONLY: operational records, no payment movement or full accounting.
CREATE TABLE private_checkout.alani_suppliers_test(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), name text NOT NULL CHECK(char_length(name) BETWEEN 2 AND 120), active boolean NOT NULL DEFAULT true, created_by uuid NOT NULL REFERENCES auth.users(id), created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE private_checkout.alani_purchase_test(
 request_key uuid PRIMARY KEY, supplier_id uuid NOT NULL REFERENCES private_checkout.alani_suppliers_test(id), product_id uuid NOT NULL REFERENCES public.products(id), quantity integer NOT NULL CHECK(quantity BETWEEN 1 AND 10000), unit_cost_iqd bigint NOT NULL CHECK(unit_cost_iqd BETWEEN 1 AND 100000000), on_credit boolean NOT NULL, actor uuid NOT NULL REFERENCES auth.users(id), created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE private_checkout.alani_pos_test(
 request_key uuid PRIMARY KEY, product_id uuid NOT NULL REFERENCES public.products(id), quantity integer NOT NULL CHECK(quantity BETWEEN 1 AND 20), unit_price_iqd bigint NOT NULL CHECK(unit_price_iqd>=0), actor uuid NOT NULL REFERENCES auth.users(id), created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE private_checkout.alani_expenses_test(
 request_key uuid PRIMARY KEY, description text NOT NULL CHECK(char_length(description) BETWEEN 2 AND 200), amount_iqd bigint NOT NULL CHECK(amount_iqd BETWEEN 1 AND 1000000000), actor uuid NOT NULL REFERENCES auth.users(id), created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE private_checkout.alani_suppliers_test ENABLE ROW LEVEL SECURITY;
ALTER TABLE private_checkout.alani_purchase_test ENABLE ROW LEVEL SECURITY;
ALTER TABLE private_checkout.alani_pos_test ENABLE ROW LEVEL SECURITY;
ALTER TABLE private_checkout.alani_expenses_test ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private_checkout.alani_suppliers_test,private_checkout.alani_purchase_test,private_checkout.alani_pos_test,private_checkout.alani_expenses_test FROM PUBLIC,anon,authenticated;
CREATE FUNCTION public.alani_create_supplier_test(p_name text)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE result uuid;
BEGIN
 IF NOT private_checkout.alani_offer_staff_test() THEN RAISE EXCEPTION 'PERMISSION_DENIED'; END IF;
 IF p_name IS NULL OR char_length(btrim(p_name)) NOT BETWEEN 2 AND 120 THEN RAISE EXCEPTION 'INVALID_SUPPLIER'; END IF;
 INSERT INTO private_checkout.alani_suppliers_test(name,created_by) VALUES(btrim(p_name),auth.uid()) RETURNING id INTO result;
 RETURN result;
END $$;
CREATE FUNCTION public.alani_receive_purchase_test(p_key uuid,p_supplier uuid,p_product uuid,p_qty integer,p_cost bigint,p_credit boolean)
RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE r private_checkout.alani_purchase_test%ROWTYPE;
BEGIN
 IF NOT private_checkout.alani_offer_staff_test() THEN RAISE EXCEPTION 'PERMISSION_DENIED'; END IF;
 IF p_key IS NULL OR p_qty IS NULL OR p_qty NOT BETWEEN 1 AND 10000 OR p_cost IS NULL OR p_cost NOT BETWEEN 1 AND 100000000 OR p_credit IS NULL THEN RAISE EXCEPTION 'INVALID_PURCHASE'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('purchase:'||p_key::text,0));
 SELECT * INTO r FROM private_checkout.alani_purchase_test WHERE request_key=p_key;
 IF FOUND THEN
  IF (r.supplier_id,r.product_id,r.quantity,r.unit_cost_iqd,r.on_credit) IS DISTINCT FROM (p_supplier,p_product,p_qty,p_cost,p_credit) THEN RAISE EXCEPTION 'IDEMPOTENCY_PAYLOAD_MISMATCH'; END IF;
  RETURN 'received';
 END IF;
 IF NOT EXISTS(SELECT 1 FROM private_checkout.alani_suppliers_test WHERE id=p_supplier AND active) THEN RAISE EXCEPTION 'SUPPLIER_UNAVAILABLE'; END IF;
 UPDATE public.products SET stock_quantity=stock_quantity+p_qty WHERE id=p_product AND store_id='25091ca2-c0da-416c-b634-81b188ee66be'::uuid AND stock_quantity<=2147483647-p_qty;
 IF NOT FOUND THEN RAISE EXCEPTION 'PRODUCT_UNAVAILABLE'; END IF;
 INSERT INTO private_checkout.alani_purchase_test VALUES(p_key,p_supplier,p_product,p_qty,p_cost,p_credit,auth.uid(),now());
 RETURN 'received';
END $$;
CREATE FUNCTION public.alani_pos_sale_test(p_key uuid,p_barcode text,p_qty integer,p_expected_total bigint)
RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE r private_checkout.alani_pos_test%ROWTYPE; p public.products%ROWTYPE; price integer; pid uuid;
BEGIN
 IF NOT private_checkout.alani_offer_staff_test() THEN RAISE EXCEPTION 'PERMISSION_DENIED'; END IF;
 IF p_key IS NULL OR p_barcode IS NULL OR p_barcode !~ '^[0-9]{8,14}$' OR p_qty IS NULL OR p_qty NOT BETWEEN 1 AND 20 OR p_expected_total IS NULL OR p_expected_total<0 THEN RAISE EXCEPTION 'INVALID_POS'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('pos:'||p_key::text,0));
 SELECT product_id INTO pid FROM private_checkout.alani_inventory_settings_test WHERE barcode=p_barcode;
 SELECT * INTO r FROM private_checkout.alani_pos_test WHERE request_key=p_key;
 IF FOUND THEN
  IF r.product_id IS DISTINCT FROM pid OR r.quantity<>p_qty OR r.unit_price_iqd*r.quantity<>p_expected_total THEN RAISE EXCEPTION 'IDEMPOTENCY_PAYLOAD_MISMATCH'; END IF;
  RETURN 'recorded';
 END IF;
 SELECT * INTO p FROM public.products WHERE id=pid AND store_id='25091ca2-c0da-416c-b634-81b188ee66be'::uuid AND is_active FOR UPDATE;
 IF NOT FOUND OR p.stock_quantity<p_qty THEN RAISE EXCEPTION 'PRODUCT_UNAVAILABLE'; END IF;
 price:=public.alani_active_campaign_price(p.id,p.price_iqd);
 IF price::bigint*p_qty<>p_expected_total THEN RAISE EXCEPTION 'ORDER_TOTAL_CHANGED'; END IF;
 UPDATE public.products SET stock_quantity=stock_quantity-p_qty WHERE id=p.id;
 INSERT INTO private_checkout.alani_pos_test VALUES(p_key,p.id,p_qty,price,auth.uid(),now());
 RETURN 'recorded';
END $$;
CREATE FUNCTION public.alani_record_expense_test(p_key uuid,p_description text,p_amount bigint)
RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE r private_checkout.alani_expenses_test%ROWTYPE;
BEGIN
 IF NOT private_checkout.alani_offer_staff_test() THEN RAISE EXCEPTION 'PERMISSION_DENIED'; END IF;
 IF p_key IS NULL OR p_description IS NULL OR char_length(btrim(p_description)) NOT BETWEEN 2 AND 200 OR p_amount IS NULL OR p_amount NOT BETWEEN 1 AND 1000000000 THEN RAISE EXCEPTION 'INVALID_EXPENSE'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('expense:'||p_key::text,0));
 SELECT * INTO r FROM private_checkout.alani_expenses_test WHERE request_key=p_key;
 IF FOUND THEN
  IF r.description<>btrim(p_description) OR r.amount_iqd<>p_amount THEN RAISE EXCEPTION 'IDEMPOTENCY_PAYLOAD_MISMATCH'; END IF;
  RETURN 'recorded';
 END IF;
 INSERT INTO private_checkout.alani_expenses_test VALUES(p_key,btrim(p_description),p_amount,auth.uid(),now());
 RETURN 'recorded';
END $$;
CREATE FUNCTION public.alani_business_report_test()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
BEGIN
 IF NOT private_checkout.alani_offer_staff_test() THEN RAISE EXCEPTION 'PERMISSION_DENIED'; END IF;
 RETURN jsonb_build_object(
 'supplier_count',(SELECT count(*) FROM private_checkout.alani_suppliers_test),
 'purchases_iqd',(SELECT coalesce(sum(quantity*unit_cost_iqd),0) FROM private_checkout.alani_purchase_test),
 'credit_purchases_iqd',(SELECT coalesce(sum(quantity*unit_cost_iqd),0) FROM private_checkout.alani_purchase_test WHERE on_credit),
 'pos_sales_iqd',(SELECT coalesce(sum(quantity*unit_price_iqd),0) FROM private_checkout.alani_pos_test),
 'expenses_iqd',(SELECT coalesce(sum(amount_iqd),0) FROM private_checkout.alani_expenses_test),
 'suppliers',coalesce((SELECT jsonb_agg(to_jsonb(t)) FROM (SELECT id,name,active FROM private_checkout.alani_suppliers_test ORDER BY name LIMIT 200) t),'[]'::jsonb),
 'is_accounting_settlement',false);
END $$;
REVOKE ALL ON FUNCTION public.alani_create_supplier_test(text),public.alani_receive_purchase_test(uuid,uuid,uuid,integer,bigint,boolean),public.alani_pos_sale_test(uuid,text,integer,bigint),public.alani_record_expense_test(uuid,text,bigint),public.alani_business_report_test() FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.alani_create_supplier_test(text),public.alani_receive_purchase_test(uuid,uuid,uuid,integer,bigint,boolean),public.alani_pos_sale_test(uuid,text,integer,bigint),public.alani_record_expense_test(uuid,text,bigint),public.alani_business_report_test() TO authenticated;
