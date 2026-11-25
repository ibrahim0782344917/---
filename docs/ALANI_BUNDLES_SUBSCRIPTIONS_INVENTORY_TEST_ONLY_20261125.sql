-- TEST ONLY: offers are previews, not checkout authorizations.
CREATE TABLE private_checkout.alani_bundle_test(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 title text NOT NULL CHECK(char_length(title) BETWEEN 2 AND 120),
 items jsonb NOT NULL CHECK(jsonb_typeof(items)='array' AND jsonb_array_length(items) BETWEEN 2 AND 20),
 price_iqd bigint NOT NULL CHECK(price_iqd>0),
 free_delivery boolean NOT NULL DEFAULT false,
 starts_at timestamptz NOT NULL,
 ends_at timestamptz NOT NULL CHECK(ends_at>starts_at),
 enabled boolean NOT NULL DEFAULT true
);
CREATE TABLE private_checkout.alani_subscription_test(
 user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
 product_id uuid NOT NULL REFERENCES public.products(id) ON DELETE CASCADE,
 quantity integer NOT NULL CHECK(quantity BETWEEN 1 AND 20),
 active boolean NOT NULL DEFAULT true,
 next_review_at timestamptz NOT NULL,
 PRIMARY KEY(user_id,product_id)
);
CREATE TABLE private_checkout.alani_inventory_settings_test(
 product_id uuid PRIMARY KEY REFERENCES public.products(id) ON DELETE CASCADE,
 barcode text UNIQUE CHECK(barcode IS NULL OR barcode ~ '^[0-9]{8,14}$'),
 low_stock_threshold integer NOT NULL CHECK(low_stock_threshold BETWEEN 0 AND 100000),
 updated_by uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
 updated_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE private_checkout.alani_bundle_test ENABLE ROW LEVEL SECURITY;
ALTER TABLE private_checkout.alani_subscription_test ENABLE ROW LEVEL SECURITY;
ALTER TABLE private_checkout.alani_inventory_settings_test ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private_checkout.alani_bundle_test,private_checkout.alani_subscription_test,private_checkout.alani_inventory_settings_test FROM PUBLIC,anon,authenticated;
CREATE FUNCTION private_checkout.alani_offer_staff_test()
RETURNS boolean LANGUAGE sql STABLE SECURITY INVOKER SET search_path='' AS $$
 SELECT auth.uid() IS NOT NULL AND EXISTS(SELECT 1 FROM public.stores s WHERE s.id='25091ca2-c0da-416c-b634-81b188ee66be'::uuid AND (s.owner_id=auth.uid() OR public.shitreed_is_admin()))
$$;
REVOKE ALL ON FUNCTION private_checkout.alani_offer_staff_test() FROM PUBLIC,anon,authenticated;
CREATE FUNCTION public.alani_save_bundle_test(p_title text,p_items jsonb,p_price_iqd bigint,p_free_delivery boolean,p_starts_at timestamptz,p_ends_at timestamptz)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE q jsonb; b uuid;
BEGIN
 IF NOT private_checkout.alani_offer_staff_test() THEN RAISE EXCEPTION 'PERMISSION_DENIED'; END IF;
 IF p_title IS NULL OR char_length(btrim(p_title)) NOT BETWEEN 2 AND 120 OR p_items IS NULL OR jsonb_typeof(p_items)<>'array' OR jsonb_array_length(p_items) NOT BETWEEN 2 AND 20 OR p_price_iqd IS NULL OR p_price_iqd<=0 OR p_free_delivery IS NULL OR p_starts_at IS NULL OR p_ends_at IS NULL OR p_ends_at<=p_starts_at THEN RAISE EXCEPTION 'INVALID_BUNDLE'; END IF;
 q:=public.alani_discount_quote(p_items);
 IF p_price_iqd>(q->>'subtotal_iqd')::bigint THEN RAISE EXCEPTION 'BUNDLE_PRICE_TOO_HIGH'; END IF;
 INSERT INTO private_checkout.alani_bundle_test(title,items,price_iqd,free_delivery,starts_at,ends_at) VALUES(btrim(p_title),p_items,p_price_iqd,p_free_delivery,p_starts_at,p_ends_at) RETURNING id INTO b;
 RETURN b;
END $$;
CREATE FUNCTION public.alani_bundle_quote_test(p_bundle_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE b private_checkout.alani_bundle_test%ROWTYPE; q jsonb; fee bigint;
BEGIN
 IF auth.uid() IS NULL THEN RAISE EXCEPTION 'LOGIN_REQUIRED'; END IF;
 SELECT * INTO b FROM private_checkout.alani_bundle_test WHERE id=p_bundle_id AND enabled AND starts_at<=now() AND ends_at>now();
 IF NOT FOUND THEN RAISE EXCEPTION 'BUNDLE_UNAVAILABLE'; END IF;
 q:=public.alani_discount_quote(b.items);
 IF b.price_iqd>(q->>'subtotal_iqd')::bigint THEN RAISE EXCEPTION 'BUNDLE_PRICE_TOO_HIGH'; END IF;
 fee:=CASE WHEN b.free_delivery THEN 0 ELSE 5000 END;
 RETURN jsonb_build_object('bundle_id',b.id,'title',b.title,'items',q->'lines','regular_subtotal_iqd',q->'subtotal_iqd','bundle_subtotal_iqd',b.price_iqd,'delivery_fee_iqd',fee,'total_iqd',b.price_iqd+fee,'checkout_enabled',false);
END $$;
CREATE FUNCTION public.alani_set_subscription_test(p_product_id uuid,p_quantity integer,p_active boolean)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE a uuid:=auth.uid();
BEGIN
 IF a IS NULL THEN RAISE EXCEPTION 'LOGIN_REQUIRED'; END IF;
 IF p_active IS NULL OR p_quantity IS NULL OR p_quantity NOT BETWEEN 1 AND 20 THEN RAISE EXCEPTION 'INVALID_SUBSCRIPTION'; END IF;
 IF NOT p_active THEN
  UPDATE private_checkout.alani_subscription_test SET active=false WHERE user_id=a AND product_id=p_product_id;
  RETURN false;
 END IF;
 IF NOT EXISTS(SELECT 1 FROM public.products p JOIN public.stores s ON s.id=p.store_id WHERE p.id=p_product_id AND p.is_active AND p.store_id='25091ca2-c0da-416c-b634-81b188ee66be'::uuid AND s.status='approved') THEN RAISE EXCEPTION 'PRODUCT_UNAVAILABLE'; END IF;
 INSERT INTO private_checkout.alani_subscription_test(user_id,product_id,quantity,next_review_at) VALUES(a,p_product_id,p_quantity,now()+interval '1 month')
 ON CONFLICT(user_id,product_id) DO UPDATE SET quantity=excluded.quantity,active=true,next_review_at=CASE WHEN alani_subscription_test.active THEN alani_subscription_test.next_review_at ELSE excluded.next_review_at END;
 RETURN true;
END $$;
CREATE FUNCTION public.alani_my_subscriptions_test()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE a uuid:=auth.uid(); result jsonb;
BEGIN
 IF a IS NULL THEN RAISE EXCEPTION 'LOGIN_REQUIRED'; END IF;
 SELECT coalesce(jsonb_agg(jsonb_build_object('product_id',s.product_id,'name',p.name,'quantity',s.quantity,'active',s.active,'next_review_at',s.next_review_at,'available',p.is_active AND p.stock_quantity>=s.quantity,'auto_order',false) ORDER BY s.next_review_at),'[]'::jsonb) INTO result FROM private_checkout.alani_subscription_test s JOIN public.products p ON p.id=s.product_id WHERE s.user_id=a;
 RETURN result;
END $$;
CREATE FUNCTION public.alani_set_inventory_settings_test(p_product_id uuid,p_barcode text,p_threshold integer)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN
 IF NOT private_checkout.alani_offer_staff_test() THEN RAISE EXCEPTION 'PERMISSION_DENIED'; END IF;
 IF p_threshold IS NULL OR p_threshold NOT BETWEEN 0 AND 100000 OR (p_barcode IS NOT NULL AND p_barcode !~ '^[0-9]{8,14}$') THEN RAISE EXCEPTION 'INVALID_INVENTORY_SETTINGS'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.products WHERE id=p_product_id AND store_id='25091ca2-c0da-416c-b634-81b188ee66be'::uuid) THEN RAISE EXCEPTION 'PRODUCT_UNAVAILABLE'; END IF;
 INSERT INTO private_checkout.alani_inventory_settings_test(product_id,barcode,low_stock_threshold,updated_by) VALUES(p_product_id,p_barcode,p_threshold,auth.uid())
 ON CONFLICT(product_id) DO UPDATE SET barcode=excluded.barcode,low_stock_threshold=excluded.low_stock_threshold,updated_by=auth.uid(),updated_at=now();
 RETURN true;
END $$;
CREATE FUNCTION public.alani_inventory_report_test(p_barcode text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE result jsonb;
BEGIN
 IF NOT private_checkout.alani_offer_staff_test() THEN RAISE EXCEPTION 'PERMISSION_DENIED'; END IF;
 IF p_barcode IS NOT NULL AND p_barcode !~ '^[0-9]{8,14}$' THEN RAISE EXCEPTION 'INVALID_BARCODE'; END IF;
 WITH demand AS (
 SELECT i.product_id,sum(i.quantity)::bigint AS sold FROM public.order_items i JOIN public.orders o ON o.id=i.order_id
 WHERE o.store_id='25091ca2-c0da-416c-b634-81b188ee66be'::uuid AND o.status='delivered' AND o.delivered_at>=now()-interval '30 days'
 GROUP BY i.product_id
 )
 SELECT coalesce(jsonb_agg(to_jsonb(t) ORDER BY t.low_stock DESC,t.name),'[]'::jsonb) INTO result FROM (
 SELECT p.id,p.name,p.stock_quantity,s.barcode,coalesce(s.low_stock_threshold,5) AS low_stock_threshold,
 p.stock_quantity<=coalesce(s.low_stock_threshold,5) AS low_stock,coalesce(d.sold,0) AS sold_30d,
 CASE WHEN d.sold>0 THEN round(30.0*p.stock_quantity/d.sold,1) END AS estimated_days_remaining,
 '30d_delivered_sales_heuristic' AS method
 FROM public.products p LEFT JOIN private_checkout.alani_inventory_settings_test s ON s.product_id=p.id LEFT JOIN demand d ON d.product_id=p.id
 WHERE p.store_id='25091ca2-c0da-416c-b634-81b188ee66be'::uuid AND p.is_active AND (p_barcode IS NULL OR s.barcode=p_barcode)
 ORDER BY low_stock DESC,p.name,p.id LIMIT 200
 ) t;
 RETURN result;
END $$;
REVOKE ALL ON FUNCTION public.alani_save_bundle_test(text,jsonb,bigint,boolean,timestamptz,timestamptz),public.alani_bundle_quote_test(uuid),public.alani_set_subscription_test(uuid,integer,boolean),public.alani_my_subscriptions_test(),public.alani_set_inventory_settings_test(uuid,text,integer),public.alani_inventory_report_test(text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.alani_save_bundle_test(text,jsonb,bigint,boolean,timestamptz,timestamptz),public.alani_bundle_quote_test(uuid),public.alani_set_subscription_test(uuid,integer,boolean),public.alani_my_subscriptions_test(),public.alani_set_inventory_settings_test(uuid,text,integer),public.alani_inventory_report_test(text) TO authenticated;
