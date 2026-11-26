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
PERFORM set_config('alani.qa.bundle',public.alani_save_bundle_test('Synthetic management','[{"product_id":"00000000-0000-4000-8000-000000009910","quantity":1},{"product_id":"00000000-0000-4000-8000-000000009911","quantity":1}]'::jsonb,25000,true,now()-interval '1 hour',now()+interval '1 hour')::text,true);
IF NOT COALESCE((EXISTS(SELECT 1 FROM jsonb_array_elements(public.alani_manage_bundles_list_test()) b WHERE b->>'id'=current_setting('alani.qa.bundle')::uuid::text)),false) THEN RAISE EXCEPTION 'FAIL staff list'; END IF;
IF NOT COALESCE((NOT public.alani_bundle_enabled_test(current_setting('alani.qa.bundle')::uuid,false)),false) THEN RAISE EXCEPTION 'FAIL disable'; END IF;
IF NOT COALESCE((NOT EXISTS(SELECT 1 FROM jsonb_array_elements(public.alani_list_bundles_test()) b WHERE b->>'id'=current_setting('alani.qa.bundle')::uuid::text)),false) THEN RAISE EXCEPTION 'FAIL hidden'; END IF;
IF NOT COALESCE((public.alani_bundle_enabled_test(current_setting('alani.qa.bundle')::uuid,true)),false) THEN RAISE EXCEPTION 'FAIL enable'; END IF;
END $$;
SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000009901',true) IS NOT NULL;
SELECT set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('request.jwt.claim.sub'),'role','authenticated')::text,true) IS NOT NULL;
DO $$ BEGIN
IF NOT COALESCE((EXISTS(SELECT 1 FROM jsonb_array_elements(public.alani_list_bundles_test()) b WHERE b->>'id'=current_setting('alani.qa.bundle')::uuid::text)),false) THEN RAISE EXCEPTION 'FAIL visible'; END IF;
BEGIN PERFORM public.alani_bundle_enabled_test(current_setting('alani.qa.bundle')::uuid,false); RAISE EXCEPTION 'FAIL expected PERMISSION_DENIED'; EXCEPTION WHEN OTHERS THEN IF SQLERRM <> 'PERMISSION_DENIED' THEN RAISE; END IF; END;
BEGIN PERFORM public.alani_manage_bundles_list_test(); RAISE EXCEPTION 'FAIL expected PERMISSION_DENIED'; EXCEPTION WHEN OTHERS THEN IF SQLERRM <> 'PERMISSION_DENIED' THEN RAISE; END IF; END;
BEGIN PERFORM public.alani_admin_business_overview_test(); RAISE EXCEPTION 'FAIL expected ADMIN_ACCESS_REQUIRED'; EXCEPTION WHEN OTHERS THEN IF SQLERRM <> 'ADMIN_ACCESS_REQUIRED' THEN RAISE; END IF; END;
END $$;
RESET ROLE;
DO $$ BEGIN
IF NOT COALESCE((NOT has_function_privilege('anon','public.alani_admin_business_overview_test()','EXECUTE')),false) THEN RAISE EXCEPTION 'FAIL anonymous blocked'; END IF;
END $$;
SELECT 'PASS: 9 bundle management assertions' AS result;
ROLLBACK;