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
IF NOT COALESCE((public.alani_set_inventory_settings_test('00000000-0000-4000-8000-000000009910','999999990001',5)),false) THEN RAISE EXCEPTION 'FAIL barcode setup'; END IF;
IF NOT COALESCE((public.alani_receive_purchase_test('00000000-0000-4000-8000-000000010011',current_setting('alani.qa.supplier')::uuid,'00000000-0000-4000-8000-000000009910',5,8000,true)='received'),false) THEN RAISE EXCEPTION 'FAIL receive purchase'; END IF;
IF NOT COALESCE((public.alani_receive_purchase_test('00000000-0000-4000-8000-000000010011',current_setting('alani.qa.supplier')::uuid,'00000000-0000-4000-8000-000000009910',5,8000,true)='received'),false) THEN RAISE EXCEPTION 'FAIL purchase retry'; END IF;
BEGIN PERFORM public.alani_receive_purchase_test('00000000-0000-4000-8000-000000010011',current_setting('alani.qa.supplier')::uuid,'00000000-0000-4000-8000-000000009910',6,8000,true); RAISE EXCEPTION 'FAIL expected IDEMPOTENCY_PAYLOAD_MISMATCH'; EXCEPTION WHEN OTHERS THEN IF SQLERRM <> 'IDEMPOTENCY_PAYLOAD_MISMATCH' THEN RAISE; END IF; END;
BEGIN PERFORM public.alani_pos_sale_test('00000000-0000-4000-8000-000000010012','999999990001',2,39999); RAISE EXCEPTION 'FAIL expected ORDER_TOTAL_CHANGED'; EXCEPTION WHEN OTHERS THEN IF SQLERRM <> 'ORDER_TOTAL_CHANGED' THEN RAISE; END IF; END;
IF NOT COALESCE((public.alani_pos_sale_test('00000000-0000-4000-8000-000000010012','999999990001',2,40000)='recorded'),false) THEN RAISE EXCEPTION 'FAIL pos sale'; END IF;
IF NOT COALESCE((public.alani_pos_sale_test('00000000-0000-4000-8000-000000010012','999999990001',2,40000)='recorded'),false) THEN RAISE EXCEPTION 'FAIL pos retry'; END IF;
BEGIN PERFORM public.alani_pos_sale_test('00000000-0000-4000-8000-000000010012','999999990001',3,60000); RAISE EXCEPTION 'FAIL expected IDEMPOTENCY_PAYLOAD_MISMATCH'; EXCEPTION WHEN OTHERS THEN IF SQLERRM <> 'IDEMPOTENCY_PAYLOAD_MISMATCH' THEN RAISE; END IF; END;
IF NOT COALESCE((public.alani_record_expense_test('00000000-0000-4000-8000-000000010013','Synthetic transport expense',3000)='recorded'),false) THEN RAISE EXCEPTION 'FAIL expense'; END IF;
IF NOT COALESCE((public.alani_record_expense_test('00000000-0000-4000-8000-000000010013','Synthetic transport expense',3000)='recorded'),false) THEN RAISE EXCEPTION 'FAIL expense retry'; END IF;
BEGIN PERFORM public.alani_record_expense_test('00000000-0000-4000-8000-000000010013','Synthetic transport expense',4000); RAISE EXCEPTION 'FAIL expected IDEMPOTENCY_PAYLOAD_MISMATCH'; EXCEPTION WHEN OTHERS THEN IF SQLERRM <> 'IDEMPOTENCY_PAYLOAD_MISMATCH' THEN RAISE; END IF; END;
IF NOT COALESCE(((public.alani_business_report_test()->>'purchases_iqd')::bigint=40000),false) THEN RAISE EXCEPTION 'FAIL purchases report'; END IF;
IF NOT COALESCE(((public.alani_business_report_test()->>'credit_purchases_iqd')::bigint=40000),false) THEN RAISE EXCEPTION 'FAIL credit purchases report'; END IF;
IF NOT COALESCE(((public.alani_business_report_test()->>'pos_sales_iqd')::bigint=40000),false) THEN RAISE EXCEPTION 'FAIL POS report'; END IF;
IF NOT COALESCE(((public.alani_business_report_test()->>'expenses_iqd')::bigint=3000),false) THEN RAISE EXCEPTION 'FAIL expenses report'; END IF;
IF NOT COALESCE(((public.alani_debt_report_test()->>'balance_iqd')::bigint=40000),false) THEN RAISE EXCEPTION 'FAIL initial debt'; END IF;
IF NOT COALESCE((public.alani_record_debt_payment_test('00000000-0000-4000-8000-000000011001','00000000-0000-4000-8000-000000010011',15000)='recorded'),false) THEN RAISE EXCEPTION 'FAIL partial payment'; END IF;
IF NOT COALESCE((public.alani_record_debt_payment_test('00000000-0000-4000-8000-000000011001','00000000-0000-4000-8000-000000010011',15000)='recorded'),false) THEN RAISE EXCEPTION 'FAIL retry'; END IF;
BEGIN PERFORM public.alani_record_debt_payment_test('00000000-0000-4000-8000-000000011001','00000000-0000-4000-8000-000000010011',16000); RAISE EXCEPTION 'FAIL expected IDEMPOTENCY_PAYLOAD_MISMATCH'; EXCEPTION WHEN OTHERS THEN IF SQLERRM <> 'IDEMPOTENCY_PAYLOAD_MISMATCH' THEN RAISE; END IF; END;
IF NOT COALESCE(((public.alani_debt_report_test()->>'balance_iqd')::bigint=25000),false) THEN RAISE EXCEPTION 'FAIL remaining'; END IF;
BEGIN PERFORM public.alani_record_debt_payment_test('00000000-0000-4000-8000-000000011002','00000000-0000-4000-8000-000000010011',25001); RAISE EXCEPTION 'FAIL expected PAYMENT_EXCEEDS_BALANCE'; EXCEPTION WHEN OTHERS THEN IF SQLERRM <> 'PAYMENT_EXCEEDS_BALANCE' THEN RAISE; END IF; END;
IF NOT COALESCE((public.alani_record_debt_payment_test('00000000-0000-4000-8000-000000011002','00000000-0000-4000-8000-000000010011',25000)='recorded'),false) THEN RAISE EXCEPTION 'FAIL full payment'; END IF;
IF NOT COALESCE(((public.alani_debt_report_test()->>'balance_iqd')::bigint=0 AND (public.alani_debt_report_test()->>'paid_iqd')::bigint=40000),false) THEN RAISE EXCEPTION 'FAIL closed debt'; END IF;
IF NOT COALESCE(((public.alani_pos_quote_test('999999990001',2)->>'total_iqd')::bigint=40000),false) THEN RAISE EXCEPTION 'FAIL POS quote'; END IF;
BEGIN PERFORM public.alani_pos_quote_test('999999990001',20); RAISE EXCEPTION 'FAIL expected PRODUCT_UNAVAILABLE'; EXCEPTION WHEN OTHERS THEN IF SQLERRM <> 'PRODUCT_UNAVAILABLE' THEN RAISE; END IF; END;
IF NOT COALESCE((public.alani_save_supplier_key_test('00000000-0000-4000-8000-000000011003','Synthetic keyed supplier')='00000000-0000-4000-8000-000000011003'::uuid),false) THEN RAISE EXCEPTION 'FAIL supplier keyed'; END IF;
IF NOT COALESCE((public.alani_save_supplier_key_test('00000000-0000-4000-8000-000000011003','Synthetic keyed supplier')='00000000-0000-4000-8000-000000011003'::uuid),false) THEN RAISE EXCEPTION 'FAIL supplier retry'; END IF;
BEGIN PERFORM public.alani_save_supplier_key_test('00000000-0000-4000-8000-000000011003','Changed supplier'); RAISE EXCEPTION 'FAIL expected IDEMPOTENCY_PAYLOAD_MISMATCH'; EXCEPTION WHEN OTHERS THEN IF SQLERRM <> 'IDEMPOTENCY_PAYLOAD_MISMATCH' THEN RAISE; END IF; END;
IF NOT COALESCE((public.alani_operational_trial_balance_test()->>'balanced')::boolean,false) THEN RAISE EXCEPTION 'FAIL balanced trial balance'; END IF;
IF NOT COALESCE((public.alani_operational_trial_balance_test()->>'debit_iqd')::bigint=123000 AND (public.alani_operational_trial_balance_test()->>'credit_iqd')::bigint=123000,false) THEN RAISE EXCEPTION 'FAIL total legs'; END IF;
IF NOT EXISTS(SELECT 1 FROM jsonb_array_elements(public.alani_operational_trial_balance_test()->'accounts') x WHERE x->>'account'='supplier_payable' AND (x->>'net_debit_iqd')::bigint=0) THEN RAISE EXCEPTION 'FAIL supplier payable cleared'; END IF;
IF NOT COALESCE((public.alani_operational_trial_balance_test()->>'includes_cost_of_goods_sold')::boolean=false AND (public.alani_operational_trial_balance_test()->>'is_cash_movement')::boolean=false,false) THEN RAISE EXCEPTION 'FAIL scope'; END IF;
END $$;
SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000009901',true) IS NOT NULL;
SELECT set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('request.jwt.claim.sub'),'role','authenticated')::text,true) IS NOT NULL;
DO $$ BEGIN
BEGIN PERFORM public.alani_debt_report_test(); RAISE EXCEPTION 'FAIL expected PERMISSION_DENIED'; EXCEPTION WHEN OTHERS THEN IF SQLERRM <> 'PERMISSION_DENIED' THEN RAISE; END IF; END;
BEGIN PERFORM public.alani_record_debt_payment_test('00000000-0000-4000-8000-000000011001','00000000-0000-4000-8000-000000010011',15000); RAISE EXCEPTION 'FAIL expected PERMISSION_DENIED'; EXCEPTION WHEN OTHERS THEN IF SQLERRM <> 'PERMISSION_DENIED' THEN RAISE; END IF; END;
BEGIN PERFORM public.alani_pos_quote_test('999999990001',2); RAISE EXCEPTION 'FAIL expected PERMISSION_DENIED'; EXCEPTION WHEN OTHERS THEN IF SQLERRM <> 'PERMISSION_DENIED' THEN RAISE; END IF; END;
BEGIN PERFORM public.alani_operational_trial_balance_test(); RAISE EXCEPTION 'FAIL expected PERMISSION_DENIED'; EXCEPTION WHEN OTHERS THEN IF SQLERRM <> 'PERMISSION_DENIED' THEN RAISE; END IF; END;
BEGIN PERFORM public.alani_business_report_test(); RAISE EXCEPTION 'FAIL expected PERMISSION_DENIED'; EXCEPTION WHEN OTHERS THEN IF SQLERRM <> 'PERMISSION_DENIED' THEN RAISE; END IF; END;
BEGIN PERFORM public.alani_receive_purchase_test('00000000-0000-4000-8000-000000010011',current_setting('alani.qa.supplier')::uuid,'00000000-0000-4000-8000-000000009910',5,8000,true); RAISE EXCEPTION 'FAIL expected PERMISSION_DENIED'; EXCEPTION WHEN OTHERS THEN IF SQLERRM <> 'PERMISSION_DENIED' THEN RAISE; END IF; END;
BEGIN PERFORM public.alani_pos_sale_test('00000000-0000-4000-8000-000000010012','999999990001',2,40000); RAISE EXCEPTION 'FAIL expected PERMISSION_DENIED'; EXCEPTION WHEN OTHERS THEN IF SQLERRM <> 'PERMISSION_DENIED' THEN RAISE; END IF; END;
BEGIN PERFORM public.alani_record_expense_test('00000000-0000-4000-8000-000000010013','Synthetic transport expense',3000); RAISE EXCEPTION 'FAIL expected PERMISSION_DENIED'; EXCEPTION WHEN OTHERS THEN IF SQLERRM <> 'PERMISSION_DENIED' THEN RAISE; END IF; END;
BEGIN PERFORM public.alani_create_supplier_test('Synthetic outsider'); RAISE EXCEPTION 'FAIL expected PERMISSION_DENIED'; EXCEPTION WHEN OTHERS THEN IF SQLERRM <> 'PERMISSION_DENIED' THEN RAISE; END IF; END;
END $$;
RESET ROLE;
DO $$ BEGIN
IF NOT COALESCE(((SELECT stock_quantity FROM public.products WHERE id='00000000-0000-4000-8000-000000009910')=7),false) THEN RAISE EXCEPTION 'FAIL stock +5 -2'; END IF;
IF NOT COALESCE(((SELECT count(*) FROM private_checkout.alani_purchase_test WHERE request_key='00000000-0000-4000-8000-000000010011')=1 AND (SELECT count(*) FROM private_checkout.alani_pos_test WHERE request_key='00000000-0000-4000-8000-000000010012')=1 AND (SELECT count(*) FROM private_checkout.alani_expenses_test WHERE request_key='00000000-0000-4000-8000-000000010013')=1),false) THEN RAISE EXCEPTION 'FAIL single records'; END IF;
IF NOT COALESCE((NOT has_table_privilege('authenticated','private_checkout.alani_purchase_test','SELECT,INSERT,UPDATE,DELETE') AND NOT has_function_privilege('anon','public.alani_business_report_test()','EXECUTE')),false) THEN RAISE EXCEPTION 'FAIL private data restricted'; END IF;
END $$;

DO $$ BEGIN
IF NOT COALESCE(((SELECT count(*) FROM private_checkout.alani_debt_payments_test WHERE purchase_key='00000000-0000-4000-8000-000000010011')=2),false) THEN RAISE EXCEPTION 'FAIL two payments only'; END IF;
IF NOT COALESCE((NOT has_table_privilege('authenticated','private_checkout.alani_debt_payments_test','SELECT,INSERT,UPDATE,DELETE') AND NOT has_function_privilege('anon','public.alani_debt_report_test()','EXECUTE')),false) THEN RAISE EXCEPTION 'FAIL private debt'; END IF;
END $$;
SELECT 'PASS: 5 additional trial balance assertions' AS result;
ROLLBACK;