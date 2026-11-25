-- TEST ONLY; synthetic fixtures, rolled back.
BEGIN;
INSERT INTO auth.users(id,aud,role,email,raw_app_meta_data,raw_user_meta_data) VALUES('00000000-0000-4000-8000-000000004401','authenticated','authenticated','alani-batch4-buyer@example.invalid','{}','{}');
INSERT INTO public.products(id,store_id,name,price_iqd,is_active,stock_quantity) VALUES('00000000-0000-4000-8000-000000004410','25091ca2-c0da-416c-b634-81b188ee66be','Synthetic A',20000,true,3),('00000000-0000-4000-8000-000000004411','25091ca2-c0da-416c-b634-81b188ee66be','Synthetic B',10000,true,2);
SELECT set_config('request.jwt.claim.sub',(SELECT owner_id::text FROM public.stores WHERE id='25091ca2-c0da-416c-b634-81b188ee66be'),true) IS NOT NULL;
SET LOCAL ROLE authenticated;
DO $$ BEGIN
PERFORM public.alani_save_campaign(NULL,'25091ca2-c0da-416c-b634-81b188ee66be','Synthetic active','Test only',NULL,now()-interval '1 hour',now()+interval '1 hour',true,'[{"product_id":"00000000-0000-4000-8000-000000004410","sale_price_iqd":15000}]');
PERFORM public.alani_save_campaign(NULL,'25091ca2-c0da-416c-b634-81b188ee66be','Synthetic expired','Test only',NULL,now()-interval '2 hours',now()-interval '1 hour',true,'[{"product_id":"00000000-0000-4000-8000-000000004411","sale_price_iqd":1000}]');
PERFORM public.alani_save_campaign(NULL,'25091ca2-c0da-416c-b634-81b188ee66be','Synthetic unpublished','Test only',NULL,now()-interval '1 hour',now()+interval '1 hour',false,'[{"product_id":"00000000-0000-4000-8000-000000004411","sale_price_iqd":2000}]');
END $$;
SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000004401',true) IS NOT NULL;
DO $$ DECLARE o uuid; BEGIN
BEGIN PERFORM public.place_alani_cash_order('[{"product_id":"00000000-0000-4000-8000-000000004410","quantity":2},{"product_id":"00000000-0000-4000-8000-000000004411","quantity":1}]'::jsonb,'Synthetic test address','00000000000','batch04','00000000-0000-4000-8000-000000004421',10000); RAISE EXCEPTION 'FAIL expected ORDER_TOTAL_CHANGED'; EXCEPTION WHEN OTHERS THEN IF SQLERRM <> 'ORDER_TOTAL_CHANGED' THEN RAISE; END IF; END;
BEGIN PERFORM public.place_alani_cash_order('[{"product_id":"00000000-0000-4000-8000-000000004410","quantity":4}]','Synthetic test address','00000000000','batch04','00000000-0000-4000-8000-000000004422',45000); RAISE EXCEPTION 'FAIL expected OUT_OF_STOCK'; EXCEPTION WHEN OTHERS THEN IF SQLERRM <> 'OUT_OF_STOCK' THEN RAISE; END IF; END;
BEGIN PERFORM public.place_alani_cash_order('[{"product_id":"00000000-0000-4000-8000-000000004410","quantity":1},{"product_id":"00000000-0000-4000-8000-000000004410","quantity":1}]','Synthetic test address','00000000000','batch04','00000000-0000-4000-8000-000000004423',45000); RAISE EXCEPTION 'FAIL expected INVALID_OR_DUPLICATE_ITEM'; EXCEPTION WHEN OTHERS THEN IF SQLERRM <> 'INVALID_OR_DUPLICATE_ITEM' THEN RAISE; END IF; END;
o:=public.place_alani_cash_order('[{"product_id":"00000000-0000-4000-8000-000000004410","quantity":2},{"product_id":"00000000-0000-4000-8000-000000004411","quantity":1}]'::jsonb,'Synthetic test address','00000000000','batch04','00000000-0000-4000-8000-000000004424',45000);
PERFORM set_config('alani.qa.order',o::text,true);
IF NOT COALESCE((public.place_alani_cash_order('[{"product_id":"00000000-0000-4000-8000-000000004410","quantity":2},{"product_id":"00000000-0000-4000-8000-000000004411","quantity":1}]'::jsonb,'Synthetic test address','00000000000','batch04','00000000-0000-4000-8000-000000004424',45000)=o),false) THEN RAISE EXCEPTION 'FAIL idempotent retry'; END IF;
BEGIN PERFORM public.place_alani_cash_order('[{"product_id":"00000000-0000-4000-8000-000000004410","quantity":2},{"product_id":"00000000-0000-4000-8000-000000004411","quantity":1}]'::jsonb,'Synthetic test address','00000000000','batch04','00000000-0000-4000-8000-000000004424',45001); RAISE EXCEPTION 'FAIL expected IDEMPOTENCY_PAYLOAD_MISMATCH'; EXCEPTION WHEN OTHERS THEN IF SQLERRM <> 'IDEMPOTENCY_PAYLOAD_MISMATCH' THEN RAISE; END IF; END;
IF NOT COALESCE((EXISTS(SELECT 1 FROM public.orders WHERE id=o AND total_iqd=45000 AND delivery_fee_iqd=5000)),false) THEN RAISE EXCEPTION 'FAIL total and fee'; END IF;
IF NOT COALESCE((EXISTS(SELECT 1 FROM public.order_items WHERE order_id=o AND product_id='00000000-0000-4000-8000-000000004410' AND unit_price_iqd=15000 AND quantity=2 AND line_total_iqd=30000)),false) THEN RAISE EXCEPTION 'FAIL active discount'; END IF;
IF NOT COALESCE((EXISTS(SELECT 1 FROM public.order_items WHERE order_id=o AND product_id='00000000-0000-4000-8000-000000004411' AND unit_price_iqd=10000 AND quantity=1)),false) THEN RAISE EXCEPTION 'FAIL expired and unpublished ignored'; END IF;
IF NOT COALESCE(((SELECT stock_quantity FROM public.products WHERE id='00000000-0000-4000-8000-000000004410')=1 AND (SELECT stock_quantity FROM public.products WHERE id='00000000-0000-4000-8000-000000004411')=1),false) THEN RAISE EXCEPTION 'FAIL stock decremented once'; END IF;
BEGIN PERFORM public.place_alani_cash_order('[{"product_id":"00000000-0000-4000-8000-000000004410","quantity":2},{"product_id":"00000000-0000-4000-8000-000000004411","quantity":1}]'::jsonb,'Synthetic test address','00000000000','batch04','00000000-0000-4000-8000-000000004425',45000); RAISE EXCEPTION 'FAIL expected OUT_OF_STOCK'; EXCEPTION WHEN OTHERS THEN IF SQLERRM <> 'OUT_OF_STOCK' THEN RAISE; END IF; END;
IF NOT COALESCE((public.change_cash_order_status(o,'cancelled')='cancelled'),false) THEN RAISE EXCEPTION 'FAIL buyer cancel'; END IF;
IF NOT COALESCE(((SELECT stock_quantity FROM public.products WHERE id='00000000-0000-4000-8000-000000004410')=3 AND (SELECT stock_quantity FROM public.products WHERE id='00000000-0000-4000-8000-000000004411')=2),false) THEN RAISE EXCEPTION 'FAIL stock restored'; END IF;
BEGIN PERFORM public.change_cash_order_status(o,'cancelled'); RAISE EXCEPTION 'FAIL expected INVALID_BUYER_TRANSITION'; EXCEPTION WHEN OTHERS THEN IF SQLERRM <> 'INVALID_BUYER_TRANSITION' THEN RAISE; END IF; END;
END $$;
RESET ROLE;
DO $$ BEGIN
IF NOT COALESCE(((SELECT count(*) FROM public.orders WHERE buyer_id='00000000-0000-4000-8000-000000004401')=1),false) THEN RAISE EXCEPTION 'FAIL one order only'; END IF;
IF NOT COALESCE(((SELECT count(*) FROM public.order_items WHERE order_id=current_setting('alani.qa.order')::uuid)=2),false) THEN RAISE EXCEPTION 'FAIL two lines only'; END IF;
END $$;
SELECT 'PASS checkout 15 assertions' AS result;
ROLLBACK;