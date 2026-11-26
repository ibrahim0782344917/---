-- TEST ONLY, isolated fixtures; no network sends or real payment.
BEGIN;
INSERT INTO auth.users(id,aud,role,email,raw_app_meta_data,raw_user_meta_data) VALUES
('00000000-0000-4000-8000-000000007701','authenticated','authenticated','alani-batch7-a@example.invalid','{}','{}'),
('00000000-0000-4000-8000-000000007702','authenticated','authenticated','alani-batch7-b@example.invalid','{}','{}'),
('00000000-0000-4000-8000-000000007703','authenticated','authenticated','alani-batch7-c@example.invalid','{}','{}');
INSERT INTO public.products(id,store_id,name,price_iqd,is_active,stock_quantity) VALUES('00000000-0000-4000-8000-000000007710','25091ca2-c0da-416c-b634-81b188ee66be','Synthetic loyalty item',20000,true,0);
INSERT INTO public.orders(id,buyer_id,store_id,status,delivery_address,phone,total_iqd,delivery_fee_iqd,delivered_at) VALUES('00000000-0000-4000-8000-000000007711','00000000-0000-4000-8000-000000007701','25091ca2-c0da-416c-b634-81b188ee66be','delivered','Synthetic test address','00000000000',45000,5000,now());
INSERT INTO public.order_items(order_id,product_id,product_name,unit_price_iqd,quantity,line_total_iqd) VALUES('00000000-0000-4000-8000-000000007711','00000000-0000-4000-8000-000000007710','Synthetic loyalty item',20000,2,40000);
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000007701',true) IS NOT NULL;
SELECT set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('request.jwt.claim.sub'),'role','authenticated')::text,true) IS NOT NULL;
DO $$ BEGIN
PERFORM public.alani_set_favorite_test('00000000-0000-4000-8000-000000007710',true);
PERFORM public.alani_set_subscription_test('00000000-0000-4000-8000-000000007710',1,true);
IF NOT COALESCE((jsonb_array_length(public.alani_customer_alerts_test())=0),false) THEN RAISE EXCEPTION 'FAIL no initial alerts'; END IF;
END $$;
RESET ROLE;
UPDATE public.products SET stock_quantity=3,price_iqd=15000 WHERE id='00000000-0000-4000-8000-000000007710';
UPDATE private_checkout.alani_subscription_test SET next_review_at=now()-interval '1 day' WHERE user_id='00000000-0000-4000-8000-000000007701' AND product_id='00000000-0000-4000-8000-000000007710';
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000007701',true) IS NOT NULL;
SELECT set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('request.jwt.claim.sub'),'role','authenticated')::text,true) IS NOT NULL;
DO $$ BEGIN
IF NOT COALESCE((EXISTS(SELECT 1 FROM jsonb_array_elements(public.alani_customer_alerts_test()) a WHERE a->>'kind'='price_drop' AND a->>'product_id'='00000000-0000-4000-8000-000000007710')),false) THEN RAISE EXCEPTION 'FAIL price alert'; END IF;
IF NOT COALESCE((EXISTS(SELECT 1 FROM jsonb_array_elements(public.alani_customer_alerts_test()) a WHERE a->>'kind'='restocked' AND a->>'product_id'='00000000-0000-4000-8000-000000007710')),false) THEN RAISE EXCEPTION 'FAIL restock alert'; END IF;
IF NOT COALESCE((EXISTS(SELECT 1 FROM jsonb_array_elements(public.alani_customer_alerts_test()) a WHERE a->>'kind'='monthly_review' AND a->>'product_id'='00000000-0000-4000-8000-000000007710')),false) THEN RAISE EXCEPTION 'FAIL monthly review'; END IF;
IF NOT COALESCE((jsonb_array_length(public.alani_customer_alerts_test())=3),false) THEN RAISE EXCEPTION 'FAIL three distinct alerts'; END IF;
END $$;
SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000007702',true) IS NOT NULL;
SELECT set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('request.jwt.claim.sub'),'role','authenticated')::text,true) IS NOT NULL;
DO $$ BEGIN
IF NOT COALESCE((jsonb_array_length(public.alani_customer_alerts_test())=0),false) THEN RAISE EXCEPTION 'FAIL account isolated'; END IF;
END $$;
SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000007701',true) IS NOT NULL;
SELECT set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('request.jwt.claim.sub'),'role','authenticated')::text,true) IS NOT NULL;
DO $$ BEGIN
PERFORM public.alani_set_favorite_test('00000000-0000-4000-8000-000000007710',false);
PERFORM public.alani_set_subscription_test('00000000-0000-4000-8000-000000007710',1,false);
IF NOT COALESCE((jsonb_array_length(public.alani_customer_alerts_test())=0),false) THEN RAISE EXCEPTION 'FAIL cancel removes alerts'; END IF;
END $$;
RESET ROLE;
DO $$ BEGIN
IF NOT COALESCE((NOT has_function_privilege('anon','public.alani_customer_alerts_test()','EXECUTE')),false) THEN RAISE EXCEPTION 'FAIL anon blocked'; END IF;
END $$;
SELECT 'PASS: 8 batch13 alerts assertions' AS result;
ROLLBACK;