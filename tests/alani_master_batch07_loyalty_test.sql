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
IF NOT COALESCE((public.alani_set_favorite_test('00000000-0000-4000-8000-000000007710',true)),false) THEN RAISE EXCEPTION 'FAIL save favorite'; END IF;
IF NOT COALESCE((public.alani_set_favorite_test('00000000-0000-4000-8000-000000007710',true)),false) THEN RAISE EXCEPTION 'FAIL repeat save'; END IF;
IF NOT COALESCE((jsonb_array_length(public.alani_my_favorites_test())=1),false) THEN RAISE EXCEPTION 'FAIL no duplicate'; END IF;
IF NOT COALESCE(((public.alani_reorder_quote_test('00000000-0000-4000-8000-000000007711')->>'all_available')::boolean=false),false) THEN RAISE EXCEPTION 'FAIL out of stock reorder blocked'; END IF;
PERFORM set_config('alani.qa.invite',public.alani_my_invite_test()->>'code',true);
BEGIN PERFORM public.alani_claim_invite_test(current_setting('alani.qa.invite')::uuid); RAISE EXCEPTION 'FAIL expected INVALID_INVITE'; EXCEPTION WHEN OTHERS THEN IF SQLERRM <> 'INVALID_INVITE' THEN RAISE; END IF; END;
END $$;

SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000007702',true) IS NOT NULL;
SELECT set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('request.jwt.claim.sub'),'role','authenticated')::text,true) IS NOT NULL;
DO $$ BEGIN
IF NOT COALESCE((jsonb_array_length(public.alani_my_favorites_test())=0),false) THEN RAISE EXCEPTION 'FAIL favorite isolation'; END IF;
BEGIN PERFORM public.alani_reorder_quote_test('00000000-0000-4000-8000-000000007711'); RAISE EXCEPTION 'FAIL expected ORDER_NOT_AVAILABLE'; EXCEPTION WHEN OTHERS THEN IF SQLERRM <> 'ORDER_NOT_AVAILABLE' THEN RAISE; END IF; END;
IF NOT COALESCE((public.alani_claim_invite_test(current_setting('alani.qa.invite')::uuid)='registered'),false) THEN RAISE EXCEPTION 'FAIL claim invite'; END IF;
IF NOT COALESCE((public.alani_claim_invite_test(current_setting('alani.qa.invite')::uuid)='registered'),false) THEN RAISE EXCEPTION 'FAIL repeat claim'; END IF;
PERFORM set_config('alani.qa.invite_x',public.alani_my_invite_test()->>'code',true);
END $$;

SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000007703',true) IS NOT NULL;
SELECT set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('request.jwt.claim.sub'),'role','authenticated')::text,true) IS NOT NULL;
DO $$ BEGIN
IF NOT COALESCE((public.alani_claim_invite_test(current_setting('alani.qa.invite_x')::uuid)='registered'),false) THEN RAISE EXCEPTION 'FAIL second invite'; END IF;
BEGIN PERFORM public.alani_claim_invite_test(current_setting('alani.qa.invite')::uuid); RAISE EXCEPTION 'FAIL expected INVITE_ALREADY_CLAIMED'; EXCEPTION WHEN OTHERS THEN IF SQLERRM <> 'INVITE_ALREADY_CLAIMED' THEN RAISE; END IF; END;
END $$;

SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000007701',true) IS NOT NULL;
SELECT set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('request.jwt.claim.sub'),'role','authenticated')::text,true) IS NOT NULL;
DO $$ BEGIN
BEGIN PERFORM public.alani_claim_invite_test(current_setting('alani.qa.invite_x')::uuid); RAISE EXCEPTION 'FAIL expected INVITE_BEFORE_FIRST_ORDER'; EXCEPTION WHEN OTHERS THEN IF SQLERRM <> 'INVITE_BEFORE_FIRST_ORDER' THEN RAISE; END IF; END;
IF NOT COALESCE(((public.alani_my_invite_test()->>'invite_count')::int=1),false) THEN RAISE EXCEPTION 'FAIL invite count'; END IF;
IF NOT COALESCE(((public.alani_my_invite_test()->>'reward_enabled')::boolean=false),false) THEN RAISE EXCEPTION 'FAIL rewards disabled'; END IF;
END $$;

RESET ROLE;
UPDATE public.products SET stock_quantity=3,price_iqd=15000 WHERE id='00000000-0000-4000-8000-000000007710';
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000007701',true) IS NOT NULL;
SELECT set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('request.jwt.claim.sub'),'role','authenticated')::text,true) IS NOT NULL;
DO $$ BEGIN
IF NOT COALESCE((EXISTS(SELECT 1 FROM jsonb_array_elements(public.alani_my_favorites_test()) e WHERE e->>'id'='00000000-0000-4000-8000-000000007710' AND (e->>'price_dropped')::boolean AND (e->>'restocked')::boolean)),false) THEN RAISE EXCEPTION 'FAIL price and stock changes'; END IF;
IF NOT COALESCE(((public.alani_reorder_quote_test('00000000-0000-4000-8000-000000007711')->>'all_available')::boolean),false) THEN RAISE EXCEPTION 'FAIL reorder available'; END IF;
IF NOT COALESCE(((public.alani_reorder_quote_test('00000000-0000-4000-8000-000000007711')->>'total_iqd')::bigint=35000),false) THEN RAISE EXCEPTION 'FAIL current price and fee'; END IF;
IF NOT COALESCE((NOT public.alani_set_favorite_test('00000000-0000-4000-8000-000000007710',false)),false) THEN RAISE EXCEPTION 'FAIL remove favorite'; END IF;
IF NOT COALESCE((jsonb_array_length(public.alani_my_favorites_test())=0),false) THEN RAISE EXCEPTION 'FAIL favorite removed'; END IF;
END $$;

RESET ROLE;
DO $$ BEGIN
IF NOT COALESCE(((SELECT count(*) FROM public.orders WHERE buyer_id='00000000-0000-4000-8000-000000007701')=1),false) THEN RAISE EXCEPTION 'FAIL quote did not place order'; END IF;
IF NOT COALESCE(((SELECT stock_quantity FROM public.products WHERE id='00000000-0000-4000-8000-000000007710')=3),false) THEN RAISE EXCEPTION 'FAIL quote did not reserve stock'; END IF;
IF NOT COALESCE((NOT has_function_privilege('anon','public.alani_my_favorites_test()','EXECUTE') AND NOT has_table_privilege('authenticated','private_checkout.alani_favorites_test','SELECT,INSERT,UPDATE,DELETE')),false) THEN RAISE EXCEPTION 'FAIL client access denied'; END IF;
END $$;

SELECT 'PASS: 23 loyalty assertions' AS result;
ROLLBACK;
