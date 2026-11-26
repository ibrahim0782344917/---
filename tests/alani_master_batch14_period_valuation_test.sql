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
PERFORM set_config('alani.qa.supplier',public.alani_create_supplier_test('Synthetic supplier')::text,true);
PERFORM public.alani_receive_purchase_test('00000000-0000-4000-8000-000000012010',current_setting('alani.qa.supplier')::uuid,'00000000-0000-4000-8000-000000009910',5,8000,false);
PERFORM public.alani_receive_purchase_test('00000000-0000-4000-8000-000000012011',current_setting('alani.qa.supplier')::uuid,'00000000-0000-4000-8000-000000009911',2,4000,false);
PERFORM public.alani_set_inventory_settings_test('00000000-0000-4000-8000-000000009910','999999990001',5);
PERFORM public.alani_set_inventory_settings_test('00000000-0000-4000-8000-000000009911','999999990002',5);
IF NOT COALESCE(((public.alani_pos_cart_quote_test('[{"barcode":"999999990001","quantity":2},{"barcode":"999999990002","quantity":1}]'::jsonb)->>'total_iqd')::bigint=50000),false) THEN RAISE EXCEPTION 'FAIL quote'; END IF;
BEGIN PERFORM public.alani_pos_invoice_sale_test('00000000-0000-4000-8000-000000012001','[{"barcode":"999999990001","quantity":2},{"barcode":"999999990002","quantity":1}]'::jsonb,49999); RAISE EXCEPTION 'FAIL expected ORDER_TOTAL_CHANGED'; EXCEPTION WHEN OTHERS THEN IF SQLERRM <> 'ORDER_TOTAL_CHANGED' THEN RAISE; END IF; END;
IF NOT COALESCE((public.alani_pos_invoice_sale_test('00000000-0000-4000-8000-000000012001','[{"barcode":"999999990001","quantity":2},{"barcode":"999999990002","quantity":1}]'::jsonb,50000)='00000000-0000-4000-8000-000000012001'::uuid),false) THEN RAISE EXCEPTION 'FAIL sale'; END IF;
IF NOT COALESCE((public.alani_pos_invoice_sale_test('00000000-0000-4000-8000-000000012001','[{"barcode":"999999990001","quantity":2},{"barcode":"999999990002","quantity":1}]'::jsonb,50000)='00000000-0000-4000-8000-000000012001'::uuid),false) THEN RAISE EXCEPTION 'FAIL retry'; END IF;
BEGIN PERFORM public.alani_pos_invoice_sale_test('00000000-0000-4000-8000-000000012001','[{"barcode":"999999990001","quantity":2},{"barcode":"999999990002","quantity":1}]'::jsonb,50001); RAISE EXCEPTION 'FAIL expected IDEMPOTENCY_PAYLOAD_MISMATCH'; EXCEPTION WHEN OTHERS THEN IF SQLERRM <> 'IDEMPOTENCY_PAYLOAD_MISMATCH' THEN RAISE; END IF; END;
IF NOT COALESCE(((public.alani_pos_margin_test()->>'estimated_gross_margin_iqd')::bigint=30000),false) THEN RAISE EXCEPTION 'FAIL gross margin'; END IF;
IF NOT COALESCE((public.alani_pos_return_line_test('00000000-0000-4000-8000-000000012002','00000000-0000-4000-8000-000000012001','00000000-0000-4000-8000-000000009910',1,true,'Synthetic return')='recorded'),false) THEN RAISE EXCEPTION 'FAIL return'; END IF;
IF NOT COALESCE((public.alani_pos_return_line_test('00000000-0000-4000-8000-000000012002','00000000-0000-4000-8000-000000012001','00000000-0000-4000-8000-000000009910',1,true,'Synthetic return')='recorded'),false) THEN RAISE EXCEPTION 'FAIL return retry'; END IF;
BEGIN PERFORM public.alani_pos_return_line_test('00000000-0000-4000-8000-000000012003','00000000-0000-4000-8000-000000012001','00000000-0000-4000-8000-000000009910',2,true,'Synthetic return'); RAISE EXCEPTION 'FAIL expected RETURN_EXCEEDS_SALE'; EXCEPTION WHEN OTHERS THEN IF SQLERRM <> 'RETURN_EXCEEDS_SALE' THEN RAISE; END IF; END;
IF NOT COALESCE(((public.alani_pos_margin_test()->>'net_sales_iqd')::bigint=30000),false) THEN RAISE EXCEPTION 'FAIL net sales'; END IF;
IF NOT COALESCE(((public.alani_pos_margin_test()->>'estimated_cost_iqd')::bigint=12000),false) THEN RAISE EXCEPTION 'FAIL restock cost reversal'; END IF;
IF NOT COALESCE(((public.alani_pos_margin_test()->>'estimated_gross_margin_iqd')::bigint=18000),false) THEN RAISE EXCEPTION 'FAIL margin after return'; END IF;
IF NOT COALESCE((jsonb_array_length(public.alani_pos_invoice_list_test())=1),false) THEN RAISE EXCEPTION 'FAIL one invoice'; END IF;
END $$;
SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000009901',true) IS NOT NULL;
SELECT set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('request.jwt.claim.sub'),'role','authenticated')::text,true) IS NOT NULL;
DO $$ BEGIN
BEGIN PERFORM public.alani_pos_invoice_sale_test('00000000-0000-4000-8000-000000012001','[{"barcode":"999999990001","quantity":2},{"barcode":"999999990002","quantity":1}]'::jsonb,50000); RAISE EXCEPTION 'FAIL expected PERMISSION_DENIED'; EXCEPTION WHEN OTHERS THEN IF SQLERRM <> 'PERMISSION_DENIED' THEN RAISE; END IF; END;
BEGIN PERFORM public.alani_pos_margin_test(); RAISE EXCEPTION 'FAIL expected PERMISSION_DENIED'; EXCEPTION WHEN OTHERS THEN IF SQLERRM <> 'PERMISSION_DENIED' THEN RAISE; END IF; END;
BEGIN PERFORM public.alani_pos_return_line_test('00000000-0000-4000-8000-000000012002','00000000-0000-4000-8000-000000012001','00000000-0000-4000-8000-000000009910',1,true,'Synthetic return'); RAISE EXCEPTION 'FAIL expected PERMISSION_DENIED'; EXCEPTION WHEN OTHERS THEN IF SQLERRM <> 'PERMISSION_DENIED' THEN RAISE; END IF; END;
END $$;
RESET ROLE;
DO $$ BEGIN
IF NOT COALESCE(((SELECT stock_quantity FROM public.products WHERE id='00000000-0000-4000-8000-000000009910')=8 AND (SELECT stock_quantity FROM public.products WHERE id='00000000-0000-4000-8000-000000009911')=11),false) THEN RAISE EXCEPTION 'FAIL stock exact'; END IF;
IF NOT COALESCE(((SELECT count(*) FROM private_checkout.alani_pos_invoice_line_test WHERE invoice_id='00000000-0000-4000-8000-000000012001')=2),false) THEN RAISE EXCEPTION 'FAIL two lines'; END IF;
IF NOT COALESCE(((SELECT count(*) FROM private_checkout.alani_pos_return_test WHERE invoice_id='00000000-0000-4000-8000-000000012001')=1),false) THEN RAISE EXCEPTION 'FAIL single return'; END IF;
IF NOT COALESCE((NOT has_table_privilege('authenticated','private_checkout.alani_pos_invoice_test','SELECT,INSERT,UPDATE,DELETE') AND NOT has_function_privilege('anon','public.alani_pos_margin_test()','EXECUTE')),false) THEN RAISE EXCEPTION 'FAIL direct access denied'; END IF;
END $$;
UPDATE private_checkout.alani_pos_invoice_test SET created_at='2026-11-25 21:00:00+00' WHERE id='00000000-0000-4000-8000-000000012001';
UPDATE private_checkout.alani_pos_return_test SET created_at='2026-11-26 20:59:59+00' WHERE invoice_id='00000000-0000-4000-8000-000000012001';
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub',current_setting('alani.qa.owner'),true) IS NOT NULL;
SELECT set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('request.jwt.claim.sub'),'role','authenticated')::text,true) IS NOT NULL;
DO $$ BEGIN
IF NOT COALESCE(((public.alani_period_report_test('day','2026-11-26'::date)->>'pos_sales_iqd')::bigint=50000),false) THEN RAISE EXCEPTION 'FAIL Baghdad day start inclusive'; END IF;
IF NOT COALESCE(((public.alani_period_report_test('day','2026-11-26'::date)->>'pos_returns_iqd')::bigint=20000),false) THEN RAISE EXCEPTION 'FAIL Baghdad day end inclusive'; END IF;
IF NOT COALESCE(((public.alani_period_report_test('day','2026-11-26'::date)->>'pos_estimated_cost_iqd')::bigint=12000),false) THEN RAISE EXCEPTION 'FAIL cost after return'; END IF;
IF NOT COALESCE(((public.alani_period_report_test('day','2026-11-25'::date)->>'pos_sales_iqd')::bigint=0),false) THEN RAISE EXCEPTION 'FAIL previous day excludes sale'; END IF;
IF NOT COALESCE(((public.alani_period_report_test('day','2026-11-27'::date)->>'pos_returns_iqd')::bigint=0),false) THEN RAISE EXCEPTION 'FAIL next day excludes return'; END IF;
IF NOT COALESCE(((public.alani_period_report_test('month','2026-11-01'::date)->>'pos_net_sales_iqd')::bigint=30000),false) THEN RAISE EXCEPTION 'FAIL month'; END IF;
IF NOT COALESCE(((public.alani_period_report_test('year','2026-01-01'::date)->>'pos_net_sales_iqd')::bigint=30000),false) THEN RAISE EXCEPTION 'FAIL year'; END IF;
IF NOT COALESCE((public.alani_period_report_test('month','2026-11-01'::date)->>'end_day_exclusive'='2026-12-01'),false) THEN RAISE EXCEPTION 'FAIL month boundary'; END IF;
IF NOT COALESCE((public.alani_period_report_test('year','2026-01-01'::date)->>'end_day_exclusive'='2027-01-01'),false) THEN RAISE EXCEPTION 'FAIL year boundary'; END IF;
IF NOT COALESCE((EXISTS(SELECT 1 FROM jsonb_array_elements(public.alani_stock_valuation_test()->'items') r WHERE r->>'id'='00000000-0000-4000-8000-000000009910' AND (r->>'estimated_value_iqd')::bigint=64000)),false) THEN RAISE EXCEPTION 'FAIL stock cost estimate'; END IF;
IF NOT COALESCE((NOT (public.alani_stock_valuation_test()->>'is_final_valuation')::boolean),false) THEN RAISE EXCEPTION 'FAIL not certified'; END IF;
BEGIN PERFORM public.alani_period_report_test('week','2026-11-26'::date); RAISE EXCEPTION 'FAIL expected INVALID_PERIOD'; EXCEPTION WHEN OTHERS THEN IF SQLERRM <> 'INVALID_PERIOD' THEN RAISE; END IF; END;
END $$;
SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000009901',true) IS NOT NULL;
SELECT set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('request.jwt.claim.sub'),'role','authenticated')::text,true) IS NOT NULL;
DO $$ BEGIN
BEGIN PERFORM public.alani_period_report_test('day','2026-11-26'::date); RAISE EXCEPTION 'FAIL expected PERMISSION_DENIED'; EXCEPTION WHEN OTHERS THEN IF SQLERRM <> 'PERMISSION_DENIED' THEN RAISE; END IF; END;
BEGIN PERFORM public.alani_stock_valuation_test(); RAISE EXCEPTION 'FAIL expected PERMISSION_DENIED'; EXCEPTION WHEN OTHERS THEN IF SQLERRM <> 'PERMISSION_DENIED' THEN RAISE; END IF; END;
END $$;
RESET ROLE;
DO $$ BEGIN
IF NOT COALESCE((NOT has_function_privilege('anon','public.alani_period_report_test(text,date)','EXECUTE')),false) THEN RAISE EXCEPTION 'FAIL anon blocked'; END IF;
END $$;
SELECT 'PASS: 15 batch14 assertions' AS result;
ROLLBACK;