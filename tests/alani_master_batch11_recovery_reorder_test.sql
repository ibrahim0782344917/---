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
PERFORM set_config('alani.qa.bundle',public.alani_save_bundle_test('Synthetic odd-price bundle','[{"product_id":"00000000-0000-4000-8000-000000009910","quantity":2},{"product_id":"00000000-0000-4000-8000-000000009911","quantity":1}]'::jsonb,40001,true,now()-interval '1 hour',now()+interval '1 hour')::text,true);
END $$;
SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000009901',true) IS NOT NULL;
SELECT set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('request.jwt.claim.sub'),'role','authenticated')::text,true) IS NOT NULL;
DO $$ BEGIN
BEGIN PERFORM public.alani_place_bundle_test(current_setting('alani.qa.bundle')::uuid,'00000000-0000-4000-8000-000000010001',40000,'Synthetic delivery address','00000000000',''); RAISE EXCEPTION 'FAIL expected ORDER_TOTAL_CHANGED'; EXCEPTION WHEN OTHERS THEN IF SQLERRM <> 'ORDER_TOTAL_CHANGED' THEN RAISE; END IF; END;
PERFORM set_config('alani.qa.order',public.alani_place_bundle_test(current_setting('alani.qa.bundle')::uuid,'00000000-0000-4000-8000-000000010001',40001,'Synthetic delivery address','00000000000','')::text,true);
IF NOT COALESCE((public.alani_place_bundle_test(current_setting('alani.qa.bundle')::uuid,'00000000-0000-4000-8000-000000010001',40001,'Synthetic delivery address','00000000000','')=current_setting('alani.qa.order')::uuid),false) THEN RAISE EXCEPTION 'FAIL idempotent'; END IF;
BEGIN PERFORM public.alani_place_bundle_test(current_setting('alani.qa.bundle')::uuid,'00000000-0000-4000-8000-000000010001',40002,'Synthetic delivery address','00000000000',''); RAISE EXCEPTION 'FAIL expected IDEMPOTENCY_PAYLOAD_MISMATCH'; EXCEPTION WHEN OTHERS THEN IF SQLERRM <> 'IDEMPOTENCY_PAYLOAD_MISMATCH' THEN RAISE; END IF; END;
IF NOT COALESCE(((SELECT total_iqd FROM public.orders WHERE id=current_setting('alani.qa.order')::uuid)=40001),false) THEN RAISE EXCEPTION 'FAIL total'; END IF;
IF NOT COALESCE(((SELECT delivery_fee_iqd FROM public.orders WHERE id=current_setting('alani.qa.order')::uuid)=0),false) THEN RAISE EXCEPTION 'FAIL free shipping'; END IF;
IF NOT COALESCE(((SELECT sum(line_total_iqd) FROM public.order_items WHERE order_id=current_setting('alani.qa.order')::uuid)=40001),false) THEN RAISE EXCEPTION 'FAIL exact line sum'; END IF;
IF NOT COALESCE(((SELECT sum(quantity) FROM public.order_items WHERE order_id=current_setting('alani.qa.order')::uuid AND product_id='00000000-0000-4000-8000-000000009910')=2),false) THEN RAISE EXCEPTION 'FAIL quantity'; END IF;
END $$;
RESET ROLE;
DO $$ BEGIN
IF NOT COALESCE(((SELECT stock_quantity FROM public.products WHERE id='00000000-0000-4000-8000-000000009910')=2 AND (SELECT stock_quantity FROM public.products WHERE id='00000000-0000-4000-8000-000000009911')=9),false) THEN RAISE EXCEPTION 'FAIL stock deducted once'; END IF;
IF NOT COALESCE(((SELECT count(*) FROM private_checkout.alani_bundle_order_test WHERE order_id=current_setting('alani.qa.order')::uuid)=1),false) THEN RAISE EXCEPTION 'FAIL one snapshot'; END IF;
END $$;

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000009901',true) IS NOT NULL;
SELECT set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('request.jwt.claim.sub'),'role','authenticated')::text,true) IS NOT NULL;
DO $$ BEGIN
IF NOT COALESCE((public.change_cash_order_status(current_setting('alani.qa.order')::uuid,'cancelled')='cancelled'),false) THEN RAISE EXCEPTION 'FAIL cancel'; END IF;
BEGIN PERFORM public.change_cash_order_status(current_setting('alani.qa.order')::uuid,'cancelled'); RAISE EXCEPTION 'FAIL expected INVALID_BUYER_TRANSITION'; EXCEPTION WHEN OTHERS THEN IF SQLERRM <> 'INVALID_BUYER_TRANSITION' THEN RAISE; END IF; END;
END $$;
RESET ROLE;
DO $$ BEGIN
IF NOT COALESCE(((SELECT stock_quantity FROM public.products WHERE id='00000000-0000-4000-8000-000000009910')=4 AND (SELECT stock_quantity FROM public.products WHERE id='00000000-0000-4000-8000-000000009911')=10),false) THEN RAISE EXCEPTION 'FAIL restored grouped stock'; END IF;
IF NOT COALESCE((NOT has_function_privilege('anon','public.alani_place_bundle_test(uuid,uuid,bigint,text,text,text)','EXECUTE')),false) THEN RAISE EXCEPTION 'FAIL anon blocked'; END IF;
END $$;

UPDATE public.order_items SET quantity=1,line_total_iqd=20000 WHERE order_id='00000000-0000-4000-8000-000000009912';
INSERT INTO public.order_items(order_id,product_id,product_name,unit_price_iqd,quantity,line_total_iqd) VALUES('00000000-0000-4000-8000-000000009912','00000000-0000-4000-8000-000000009910','Synthetic A',20000,1,20000);
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000009901',true) IS NOT NULL;
SELECT set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('request.jwt.claim.sub'),'role','authenticated')::text,true) IS NOT NULL;
DO $$ BEGIN
IF NOT COALESCE((public.alani_bundle_order_lookup_test('00000000-0000-4000-8000-000000010001')=current_setting('alani.qa.order')::uuid),false) THEN RAISE EXCEPTION 'FAIL recover same order'; END IF;
IF NOT COALESCE((public.alani_bundle_order_lookup_test('00000000-0000-4000-8000-000000011099') IS NULL),false) THEN RAISE EXCEPTION 'FAIL unknown key'; END IF;
IF NOT COALESCE((jsonb_array_length(public.alani_reorder_quote_test('00000000-0000-4000-8000-000000009912')->'items')=1),false) THEN RAISE EXCEPTION 'FAIL reorder groups duplicate lines'; END IF;
IF NOT COALESCE(((public.alani_reorder_quote_test('00000000-0000-4000-8000-000000009912')->'items'->0->>'quantity')::int=2),false) THEN RAISE EXCEPTION 'FAIL reorder quantity'; END IF;
IF NOT COALESCE(((public.alani_reorder_quote_test('00000000-0000-4000-8000-000000009912')->>'total_iqd')::bigint=45000),false) THEN RAISE EXCEPTION 'FAIL ordinary reorder current total'; END IF;
END $$;
SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000009902',true) IS NOT NULL;
SELECT set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('request.jwt.claim.sub'),'role','authenticated')::text,true) IS NOT NULL;
DO $$ BEGIN
IF NOT COALESCE((public.alani_bundle_order_lookup_test('00000000-0000-4000-8000-000000010001') IS NULL),false) THEN RAISE EXCEPTION 'FAIL other buyer cannot recover'; END IF;
END $$;
RESET ROLE;
DO $$ BEGIN
IF NOT COALESCE((NOT has_function_privilege('anon','public.alani_bundle_order_lookup_test(uuid)','EXECUTE')),false) THEN RAISE EXCEPTION 'FAIL anonymous blocked'; END IF;
END $$;
SELECT 'PASS: 7 new recovery and reorder assertions' AS result;
ROLLBACK;