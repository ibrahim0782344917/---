-- TEST ONLY, synthetic rows, no payments and no committed fixtures.
BEGIN;
SELECT set_config('alani.qa.owner',(SELECT owner_id::text FROM public.stores WHERE id='25091ca2-c0da-416c-b634-81b188ee66be'),true) IS NOT NULL;
INSERT INTO auth.users(id,aud,role,email,raw_app_meta_data,raw_user_meta_data) VALUES
('00000000-0000-4000-8000-000000009901','authenticated','authenticated','alani-batch9-a@example.invalid','{}','{}'),
('00000000-0000-4000-8000-000000009902','authenticated','authenticated','alani-batch9-b@example.invalid','{}','{}');
INSERT INTO public.products(id,store_id,name,price_iqd,is_active,stock_quantity) VALUES
('00000000-0000-4000-8000-000000009910','25091ca2-c0da-416c-b634-81b188ee66be','Synthetic A',20000,true,4),('00000000-0000-4000-8000-000000009911','25091ca2-c0da-416c-b634-81b188ee66be','Synthetic B',10000,true,10);
INSERT INTO public.orders(id,buyer_id,store_id,status,delivery_address,phone,total_iqd,delivery_fee_iqd,delivered_at) VALUES('00000000-0000-4000-8000-000000009912','00000000-0000-4000-8000-000000009901','25091ca2-c0da-416c-b634-81b188ee66be','delivered','Synthetic test address','00000000000',45000,5000,now());
INSERT INTO public.order_items(order_id,product_id,product_name,unit_price_iqd,quantity,line_total_iqd) VALUES('00000000-0000-4000-8000-000000009912','00000000-0000-4000-8000-000000009910','Synthetic A',20000,2,40000);
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub',current_setting('alani.qa.owner'),true) IS NOT NULL;
SELECT set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('request.jwt.claim.sub'),'role','authenticated')::text,true) IS NOT NULL;
DO $$ BEGIN
BEGIN PERFORM public.alani_save_bundle_test('Synthetic bundle','[{"product_id":"00000000-0000-4000-8000-000000009910","quantity":2},{"product_id":"00000000-0000-4000-8000-000000009911","quantity":1}]'::jsonb,60000,true,now()-interval '1 hour',now()+interval '1 hour'); RAISE EXCEPTION 'FAIL expected BUNDLE_PRICE_TOO_HIGH'; EXCEPTION WHEN OTHERS THEN IF SQLERRM <> 'BUNDLE_PRICE_TOO_HIGH' THEN RAISE; END IF; END;
PERFORM set_config('alani.qa.bundle',public.alani_save_bundle_test('Synthetic bundle','[{"product_id":"00000000-0000-4000-8000-000000009910","quantity":2},{"product_id":"00000000-0000-4000-8000-000000009911","quantity":1}]'::jsonb,40000,true,now()-interval '1 hour',now()+interval '1 hour')::text,true);
PERFORM set_config('alani.qa.expired',public.alani_save_bundle_test('Synthetic bundle','[{"product_id":"00000000-0000-4000-8000-000000009910","quantity":2},{"product_id":"00000000-0000-4000-8000-000000009911","quantity":1}]'::jsonb,40000,false,now()-interval '2 hours',now()-interval '1 hour')::text,true);
IF NOT COALESCE((public.alani_set_inventory_settings_test('00000000-0000-4000-8000-000000009910','999999990001',5)),false) THEN RAISE EXCEPTION 'FAIL set barcode'; END IF;
BEGIN PERFORM public.alani_set_inventory_settings_test('00000000-0000-4000-8000-000000009910','abc',5); RAISE EXCEPTION 'FAIL expected INVALID_INVENTORY_SETTINGS'; EXCEPTION WHEN OTHERS THEN IF SQLERRM <> 'INVALID_INVENTORY_SETTINGS' THEN RAISE; END IF; END;
IF NOT COALESCE((jsonb_array_length(public.alani_inventory_report_test('999999990001'))=1),false) THEN RAISE EXCEPTION 'FAIL barcode finds one'; END IF;
IF NOT COALESCE(((public.alani_inventory_report_test('999999990001')->0->>'low_stock')::boolean),false) THEN RAISE EXCEPTION 'FAIL low stock'; END IF;
IF NOT COALESCE(((public.alani_inventory_report_test('999999990001')->0->>'sold_30d')::bigint=2),false) THEN RAISE EXCEPTION 'FAIL sales demand'; END IF;
IF NOT COALESCE(((public.alani_inventory_report_test('999999990001')->0->>'estimated_days_remaining')::numeric=60),false) THEN RAISE EXCEPTION 'FAIL forecast estimate'; END IF;
END $$;

SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000009901',true) IS NOT NULL;
SELECT set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('request.jwt.claim.sub'),'role','authenticated')::text,true) IS NOT NULL;
DO $$ BEGIN
IF NOT COALESCE(((public.alani_bundle_quote_test(current_setting('alani.qa.bundle')::uuid)->>'total_iqd')::bigint=40000),false) THEN RAISE EXCEPTION 'FAIL bundle total'; END IF;
IF NOT COALESCE(((public.alani_bundle_quote_test(current_setting('alani.qa.bundle')::uuid)->>'delivery_fee_iqd')::int=0),false) THEN RAISE EXCEPTION 'FAIL free delivery preview'; END IF;
IF NOT COALESCE(((public.alani_bundle_quote_test(current_setting('alani.qa.bundle')::uuid)->>'checkout_enabled')::boolean=false),false) THEN RAISE EXCEPTION 'FAIL checkout disabled'; END IF;
BEGIN PERFORM public.alani_bundle_quote_test(current_setting('alani.qa.expired')::uuid); RAISE EXCEPTION 'FAIL expected BUNDLE_UNAVAILABLE'; EXCEPTION WHEN OTHERS THEN IF SQLERRM <> 'BUNDLE_UNAVAILABLE' THEN RAISE; END IF; END;
BEGIN PERFORM public.alani_save_bundle_test('Synthetic bundle','[{"product_id":"00000000-0000-4000-8000-000000009910","quantity":2},{"product_id":"00000000-0000-4000-8000-000000009911","quantity":1}]'::jsonb,40000,true,now()-interval '1 hour',now()+interval '1 hour'); RAISE EXCEPTION 'FAIL expected PERMISSION_DENIED'; EXCEPTION WHEN OTHERS THEN IF SQLERRM <> 'PERMISSION_DENIED' THEN RAISE; END IF; END;
BEGIN PERFORM public.alani_inventory_report_test('999999990001'); RAISE EXCEPTION 'FAIL expected PERMISSION_DENIED'; EXCEPTION WHEN OTHERS THEN IF SQLERRM <> 'PERMISSION_DENIED' THEN RAISE; END IF; END;
IF NOT COALESCE((public.alani_set_subscription_test('00000000-0000-4000-8000-000000009910',2,true)),false) THEN RAISE EXCEPTION 'FAIL subscribe'; END IF;
IF NOT COALESCE((public.alani_set_subscription_test('00000000-0000-4000-8000-000000009910',3,true)),false) THEN RAISE EXCEPTION 'FAIL update subscription'; END IF;
IF NOT COALESCE((jsonb_array_length(public.alani_my_subscriptions_test())=1 AND (public.alani_my_subscriptions_test()->0->>'quantity')::int=3),false) THEN RAISE EXCEPTION 'FAIL unique subscription'; END IF;
IF NOT COALESCE(((public.alani_my_subscriptions_test()->0->>'auto_order')::boolean=false),false) THEN RAISE EXCEPTION 'FAIL no auto order'; END IF;
BEGIN PERFORM public.alani_set_subscription_test('00000000-0000-4000-8000-000000009910',21,true); RAISE EXCEPTION 'FAIL expected INVALID_SUBSCRIPTION'; EXCEPTION WHEN OTHERS THEN IF SQLERRM <> 'INVALID_SUBSCRIPTION' THEN RAISE; END IF; END;
END $$;

SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000009902',true) IS NOT NULL;
SELECT set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('request.jwt.claim.sub'),'role','authenticated')::text,true) IS NOT NULL;
DO $$ BEGIN
IF NOT COALESCE((jsonb_array_length(public.alani_my_subscriptions_test())=0),false) THEN RAISE EXCEPTION 'FAIL isolation'; END IF;
BEGIN PERFORM public.alani_set_inventory_settings_test('00000000-0000-4000-8000-000000009910','999999990002',5); RAISE EXCEPTION 'FAIL expected PERMISSION_DENIED'; EXCEPTION WHEN OTHERS THEN IF SQLERRM <> 'PERMISSION_DENIED' THEN RAISE; END IF; END;
END $$;

SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000009901',true) IS NOT NULL;
SELECT set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('request.jwt.claim.sub'),'role','authenticated')::text,true) IS NOT NULL;
DO $$ BEGIN
IF NOT COALESCE((NOT public.alani_set_subscription_test('00000000-0000-4000-8000-000000009910',3,false)),false) THEN RAISE EXCEPTION 'FAIL cancel'; END IF;
IF NOT COALESCE(((public.alani_my_subscriptions_test()->0->>'active')::boolean=false),false) THEN RAISE EXCEPTION 'FAIL cancel persisted'; END IF;
END $$;

RESET ROLE;
UPDATE public.products SET stock_quantity=1 WHERE id='00000000-0000-4000-8000-000000009910';
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000009901',true) IS NOT NULL;
SELECT set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('request.jwt.claim.sub'),'role','authenticated')::text,true) IS NOT NULL;
DO $$ BEGIN
BEGIN PERFORM public.alani_bundle_quote_test(current_setting('alani.qa.bundle')::uuid); RAISE EXCEPTION 'FAIL expected PRODUCT_UNAVAILABLE'; EXCEPTION WHEN OTHERS THEN IF SQLERRM <> 'PRODUCT_UNAVAILABLE' THEN RAISE; END IF; END;
END $$;

RESET ROLE;
DO $$ BEGIN
IF NOT COALESCE(((SELECT count(*) FROM public.orders WHERE buyer_id='00000000-0000-4000-8000-000000009901')=1),false) THEN RAISE EXCEPTION 'FAIL no new order'; END IF;
IF NOT COALESCE((NOT has_table_privilege('authenticated','private_checkout.alani_subscription_test','SELECT,INSERT,UPDATE,DELETE') AND NOT has_function_privilege('anon','public.alani_bundle_quote_test(uuid)','EXECUTE')),false) THEN RAISE EXCEPTION 'FAIL access denied'; END IF;
END $$;

SELECT 'PASS: 25 batch09 assertions' AS result;
ROLLBACK;
