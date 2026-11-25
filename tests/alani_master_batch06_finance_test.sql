-- TEST ONLY: verified shitreed-test tgvdwotbrnhcoykuxdpr. No external sends.
-- Synthetic rows, rollback required; never run on production. Direct fixture order bypasses checkout.
BEGIN;
SELECT set_config('alani.qa.owner',(SELECT owner_id::text FROM public.stores WHERE id='25091ca2-c0da-416c-b634-81b188ee66be' AND status='approved'),true) IS NOT NULL;
INSERT INTO auth.users(id,aud,role,email,raw_app_meta_data,raw_user_meta_data)
VALUES
('00000000-0000-4000-8000-000000003301','authenticated','authenticated','alani-batch3-buyer@example.invalid','{}','{}'),
('00000000-0000-4000-8000-000000003302','authenticated','authenticated','alani-batch3-other@example.invalid','{}','{}'),
('00000000-0000-4000-8000-000000003303','authenticated','authenticated','alani-batch3-courier@example.invalid','{}','{}');
INSERT INTO public.orders(id,buyer_id,store_id,status,delivery_address,phone,total_iqd,delivery_fee_iqd)
VALUES('00000000-0000-4000-8000-000000003310','00000000-0000-4000-8000-000000003301','25091ca2-c0da-416c-b634-81b188ee66be','ready','Synthetic test address only','00000000000',25000,5000);
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000003301',true) IS NOT NULL;
SELECT set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('request.jwt.claim.sub'),'role','authenticated')::text,true) IS NOT NULL;

DO $$ BEGIN
 PERFORM set_config('alani.qa.thread',public.alani_open_support_thread()::text,true);
 PERFORM set_config('alani.qa.message',public.alani_send_support_message(current_setting('alani.qa.thread')::uuid,'Synthetic test message')::text,true);
 IF NOT COALESCE((EXISTS(SELECT 1 FROM public.alani_support_messages WHERE id=current_setting('alani.qa.message')::uuid)),false) THEN RAISE EXCEPTION 'FAIL buyer sees own message'; END IF;
 BEGIN PERFORM public.alani_request_return('00000000-0000-4000-8000-000000003310','damaged','Synthetic damaged item request'); RAISE EXCEPTION 'FAIL premature return'; EXCEPTION WHEN OTHERS THEN IF SQLERRM <> 'RETURN_REQUIRES_DELIVERY' THEN RAISE; END IF; END;
END $$;

SELECT set_config('request.jwt.claim.sub',current_setting('alani.qa.owner'),true) IS NOT NULL;
SELECT set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('request.jwt.claim.sub'),'role','authenticated')::text,true) IS NOT NULL;

DO $$ BEGIN
 IF NOT COALESCE((public.alani_set_delivery_courier('00000000-0000-4000-8000-000000003303',true)),false) THEN RAISE EXCEPTION 'FAIL owner approves courier'; END IF;
 IF NOT COALESCE((public.alani_dispatch_delivery('00000000-0000-4000-8000-000000003310','00000000-0000-4000-8000-000000003303')='out_for_delivery'),false) THEN RAISE EXCEPTION 'FAIL owner dispatch'; END IF;
 IF NOT COALESCE((EXISTS(SELECT 1 FROM public.alani_support_unread_counts() WHERE thread_id=current_setting('alani.qa.thread')::uuid AND unread_count=1)),false) THEN RAISE EXCEPTION 'FAIL owner sees unread'; END IF;
 PERFORM public.alani_mark_support_read(current_setting('alani.qa.thread')::uuid,current_setting('alani.qa.message')::uuid);
 IF NOT COALESCE((EXISTS(SELECT 1 FROM public.alani_support_unread_counts() WHERE thread_id=current_setting('alani.qa.thread')::uuid AND unread_count=0)),false) THEN RAISE EXCEPTION 'FAIL owner read receipt'; END IF;
END $$;

SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000003302',true) IS NOT NULL;
SELECT set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('request.jwt.claim.sub'),'role','authenticated')::text,true) IS NOT NULL;

DO $$ BEGIN
 IF NOT COALESCE((NOT EXISTS(SELECT 1 FROM public.alani_support_threads WHERE id=current_setting('alani.qa.thread')::uuid)),false) THEN RAISE EXCEPTION 'FAIL other thread hidden'; END IF;
 IF NOT COALESCE((NOT EXISTS(SELECT 1 FROM public.alani_support_messages WHERE id=current_setting('alani.qa.message')::uuid)),false) THEN RAISE EXCEPTION 'FAIL other message hidden'; END IF;
 IF NOT COALESCE((NOT EXISTS(SELECT 1 FROM public.alani_support_unread_counts() WHERE thread_id=current_setting('alani.qa.thread')::uuid)),false) THEN RAISE EXCEPTION 'FAIL other unread hidden'; END IF;
 BEGIN PERFORM public.alani_send_support_message(current_setting('alani.qa.thread')::uuid,'Unauthorized synthetic test'); RAISE EXCEPTION 'FAIL other cannot send'; EXCEPTION WHEN OTHERS THEN IF SQLERRM <> 'PERMISSION_DENIED' THEN RAISE; END IF; END;
 BEGIN PERFORM public.alani_mark_support_read(current_setting('alani.qa.thread')::uuid,current_setting('alani.qa.message')::uuid); RAISE EXCEPTION 'FAIL other cannot mark read'; EXCEPTION WHEN OTHERS THEN IF SQLERRM <> 'PERMISSION_DENIED' THEN RAISE; END IF; END;
 IF NOT COALESCE((NOT EXISTS(SELECT 1 FROM public.alani_my_delivery_tasks() WHERE order_id='00000000-0000-4000-8000-000000003310')),false) THEN RAISE EXCEPTION 'FAIL other delivery hidden'; END IF;
 BEGIN PERFORM public.alani_order_delivery_status('00000000-0000-4000-8000-000000003310'); RAISE EXCEPTION 'FAIL other delivery status denied'; EXCEPTION WHEN OTHERS THEN IF SQLERRM <> 'PERMISSION_DENIED' THEN RAISE; END IF; END;
 BEGIN PERFORM public.alani_request_return('00000000-0000-4000-8000-000000003310','damaged','Synthetic damaged item request'); RAISE EXCEPTION 'FAIL other return denied'; EXCEPTION WHEN OTHERS THEN IF SQLERRM <> 'PERMISSION_DENIED' THEN RAISE; END IF; END;
END $$;

SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000003303',true) IS NOT NULL;
SELECT set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('request.jwt.claim.sub'),'role','authenticated')::text,true) IS NOT NULL;

DO $$ BEGIN
 IF NOT COALESCE((EXISTS(SELECT 1 FROM public.alani_my_delivery_tasks() WHERE order_id='00000000-0000-4000-8000-000000003310' AND delivery_fee_iqd=5000 AND total_iqd=25000)),false) THEN RAISE EXCEPTION 'FAIL courier sees assigned order and fee'; END IF;
 IF NOT COALESCE((public.alani_courier_pickup('00000000-0000-4000-8000-000000003310') IS NOT NULL),false) THEN RAISE EXCEPTION 'FAIL courier pickup'; END IF;
END $$;

DO $$ BEGIN
BEGIN PERFORM public.alani_record_cod_test('00000000-0000-4000-8000-000000003310',25000); RAISE EXCEPTION 'FAIL expected DELIVERY_REQUIRED'; EXCEPTION WHEN OTHERS THEN IF SQLERRM <> 'DELIVERY_REQUIRED' THEN RAISE; END IF; END;
END $$;
SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000003301',true) IS NOT NULL;
SELECT set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('request.jwt.claim.sub'),'role','authenticated')::text,true) IS NOT NULL;

DO $$ BEGIN
 PERFORM set_config('alani.qa.pin',public.alani_issue_delivery_pin('00000000-0000-4000-8000-000000003310')->>'code',true);
 IF NOT COALESCE((current_setting('alani.qa.pin') ~ '^[0-9]{6}$'),false) THEN RAISE EXCEPTION 'FAIL buyer gets PIN'; END IF;
END $$;

SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000003303',true) IS NOT NULL;
SELECT set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('request.jwt.claim.sub'),'role','authenticated')::text,true) IS NOT NULL;

DO $$ BEGIN
 IF NOT COALESCE((public.alani_courier_complete_delivery('00000000-0000-4000-8000-000000003310',CASE WHEN current_setting('alani.qa.pin')='000000' THEN '000001' ELSE '000000' END,'Synthetic wrong code')='WRONG_CODE'),false) THEN RAISE EXCEPTION 'FAIL wrong PIN rejected'; END IF;
 IF NOT COALESCE((public.alani_courier_complete_delivery('00000000-0000-4000-8000-000000003310',current_setting('alani.qa.pin'),'Synthetic received')='delivered'),false) THEN RAISE EXCEPTION 'FAIL correct PIN delivers'; END IF;
END $$;

SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000003301',true) IS NOT NULL;
SELECT set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('request.jwt.claim.sub'),'role','authenticated')::text,true) IS NOT NULL;

DO $$ BEGIN
 PERFORM set_config('alani.qa.return',public.alani_request_return('00000000-0000-4000-8000-000000003310','damaged','Synthetic damaged item request')::text,true);
 IF NOT COALESCE((public.alani_request_return('00000000-0000-4000-8000-000000003310','damaged','Synthetic damaged item request')::text=current_setting('alani.qa.return')),false) THEN RAISE EXCEPTION 'FAIL duplicate return idempotent'; END IF;
END $$;

SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000003302',true) IS NOT NULL;
SELECT set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('request.jwt.claim.sub'),'role','authenticated')::text,true) IS NOT NULL;

DO $$ BEGIN
 BEGIN PERFORM public.alani_review_return(current_setting('alani.qa.return')::uuid,'reviewing','Synthetic review note'); RAISE EXCEPTION 'FAIL other cannot review return'; EXCEPTION WHEN OTHERS THEN IF SQLERRM <> 'PERMISSION_DENIED' THEN RAISE; END IF; END;
END $$;

SELECT set_config('request.jwt.claim.sub',current_setting('alani.qa.owner'),true) IS NOT NULL;
SELECT set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('request.jwt.claim.sub'),'role','authenticated')::text,true) IS NOT NULL;

DO $$ BEGIN
 IF NOT COALESCE((public.alani_review_return(current_setting('alani.qa.return')::uuid,'reviewing','Synthetic review note')='reviewing'),false) THEN RAISE EXCEPTION 'FAIL owner reviews return'; END IF;
 IF NOT COALESCE((public.alani_review_return(current_setting('alani.qa.return')::uuid,'approved','Synthetic approval note')='approved'),false) THEN RAISE EXCEPTION 'FAIL owner approves return'; END IF;
END $$;

RESET ROLE;
DO $$ BEGIN
 IF NOT COALESCE((EXISTS(SELECT 1 FROM public.alani_delivery_jobs WHERE order_id='00000000-0000-4000-8000-000000003310' AND proof_method='buyer_one_time_pin' AND pin_hash IS NULL AND failed_attempts=1)),false) THEN RAISE EXCEPTION 'FAIL PIN hash cleared and wrong guess audited'; END IF;
 IF NOT COALESCE((EXISTS(SELECT 1 FROM public.alani_return_requests WHERE id=current_setting('alani.qa.return')::uuid AND status='approved')),false) THEN RAISE EXCEPTION 'FAIL return persisted in transaction'; END IF;
END $$;

SELECT 'PASS: 25 assertions, synthetic nonempty delivery/chat/return fixtures' AS result;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000003301',true) IS NOT NULL;
SELECT set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('request.jwt.claim.sub'),'role','authenticated')::text,true) IS NOT NULL;
DO $$ BEGIN
BEGIN PERFORM public.alani_record_cod_test('00000000-0000-4000-8000-000000003310',25000); RAISE EXCEPTION 'FAIL expected PERMISSION_DENIED'; EXCEPTION WHEN OTHERS THEN IF SQLERRM <> 'PERMISSION_DENIED' THEN RAISE; END IF; END;
END $$;

SELECT set_config('request.jwt.claim.sub',current_setting('alani.qa.owner'),true) IS NOT NULL;
SELECT set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('request.jwt.claim.sub'),'role','authenticated')::text,true) IS NOT NULL;
DO $$ BEGIN
BEGIN PERFORM public.alani_confirm_cod_test('00000000-0000-4000-8000-000000003310'); RAISE EXCEPTION 'FAIL expected COD_NOT_RECORDED'; EXCEPTION WHEN OTHERS THEN IF SQLERRM <> 'COD_NOT_RECORDED' THEN RAISE; END IF; END;
END $$;

SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000003303',true) IS NOT NULL;
SELECT set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('request.jwt.claim.sub'),'role','authenticated')::text,true) IS NOT NULL;
DO $$ BEGIN
BEGIN PERFORM public.alani_record_cod_test('00000000-0000-4000-8000-000000003310',24999); RAISE EXCEPTION 'FAIL expected COD_AMOUNT_MISMATCH'; EXCEPTION WHEN OTHERS THEN IF SQLERRM <> 'COD_AMOUNT_MISMATCH' THEN RAISE; END IF; END;
IF NOT COALESCE((public.alani_record_cod_test('00000000-0000-4000-8000-000000003310',25000)='recorded'),false) THEN RAISE EXCEPTION 'FAIL record COD'; END IF;
IF NOT COALESCE((public.alani_record_cod_test('00000000-0000-4000-8000-000000003310',25000)='recorded'),false) THEN RAISE EXCEPTION 'FAIL retry COD'; END IF;
BEGIN PERFORM public.alani_confirm_cod_test('00000000-0000-4000-8000-000000003310'); RAISE EXCEPTION 'FAIL expected PERMISSION_DENIED'; EXCEPTION WHEN OTHERS THEN IF SQLERRM <> 'PERMISSION_DENIED' THEN RAISE; END IF; END;
END $$;

SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000003302',true) IS NOT NULL;
SELECT set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('request.jwt.claim.sub'),'role','authenticated')::text,true) IS NOT NULL;
DO $$ BEGIN
BEGIN PERFORM public.alani_record_cod_test('00000000-0000-4000-8000-000000003310',25000); RAISE EXCEPTION 'FAIL expected PERMISSION_DENIED'; EXCEPTION WHEN OTHERS THEN IF SQLERRM <> 'PERMISSION_DENIED' THEN RAISE; END IF; END;
BEGIN PERFORM public.alani_confirm_cod_test('00000000-0000-4000-8000-000000003310'); RAISE EXCEPTION 'FAIL expected PERMISSION_DENIED'; EXCEPTION WHEN OTHERS THEN IF SQLERRM <> 'PERMISSION_DENIED' THEN RAISE; END IF; END;
END $$;

SELECT set_config('request.jwt.claim.sub',current_setting('alani.qa.owner'),true) IS NOT NULL;
SELECT set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('request.jwt.claim.sub'),'role','authenticated')::text,true) IS NOT NULL;
DO $$ BEGIN
IF NOT COALESCE((public.alani_confirm_cod_test('00000000-0000-4000-8000-000000003310')='confirmed'),false) THEN RAISE EXCEPTION 'FAIL owner confirms'; END IF;
IF NOT COALESCE((public.alani_confirm_cod_test('00000000-0000-4000-8000-000000003310')='confirmed'),false) THEN RAISE EXCEPTION 'FAIL confirmation retry'; END IF;
END $$;

RESET ROLE;
DO $$ BEGIN
IF NOT COALESCE(((SELECT count(*) FROM private_checkout.alani_cod_receipts_test WHERE order_id='00000000-0000-4000-8000-000000003310' AND amount_iqd=25000 AND confirmed_by<>courier_id AND confirmed_at IS NOT NULL)=1),false) THEN RAISE EXCEPTION 'FAIL single confirmed receipt'; END IF;
IF NOT COALESCE((NOT has_table_privilege('authenticated','private_checkout.alani_cod_receipts_test','SELECT,INSERT,UPDATE,DELETE') AND NOT has_function_privilege('anon','public.alani_record_cod_test(uuid,bigint)','EXECUTE') AND NOT has_function_privilege('anon','public.alani_confirm_cod_test(uuid)','EXECUTE')),false) THEN RAISE EXCEPTION 'FAIL privileges'; END IF;
END $$;

SELECT 'PASS: 13 new COD assertions' AS result;
SELECT set_config('alani.qa.admin',(SELECT id::text FROM auth.users WHERE raw_app_meta_data->>'shitreed_role'='admin' LIMIT 1),true) IS NOT NULL;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000003301',true) IS NOT NULL;
SELECT set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('request.jwt.claim.sub'),'role','authenticated')::text,true) IS NOT NULL;
DO $$ BEGIN
BEGIN PERFORM public.alani_post_cod_settlement_test('00000000-0000-4000-8000-000000003310'); RAISE EXCEPTION 'FAIL unauthorized'; EXCEPTION WHEN OTHERS THEN IF SQLERRM <> 'ADMIN_ACCESS_REQUIRED' THEN RAISE; END IF; END;
IF NOT COALESCE(((public.alani_my_points_test()->>'points')::bigint=0),false) THEN RAISE EXCEPTION 'FAIL initial points zero'; END IF;
BEGIN PERFORM public.alani_post_full_refund_test(current_setting('alani.qa.return')::uuid); RAISE EXCEPTION 'FAIL unauthorized'; EXCEPTION WHEN OTHERS THEN IF SQLERRM <> 'ADMIN_ACCESS_REQUIRED' THEN RAISE; END IF; END;
END $$;

SELECT set_config('request.jwt.claim.sub',current_setting('alani.qa.admin'),true) IS NOT NULL;
SELECT set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('request.jwt.claim.sub'),'role','authenticated')::text,true) IS NOT NULL;
DO $$ BEGIN
IF NOT COALESCE((public.alani_post_cod_settlement_test('00000000-0000-4000-8000-000000003310')='posted'),false) THEN RAISE EXCEPTION 'FAIL settlement'; END IF;
IF NOT COALESCE((public.alani_post_cod_settlement_test('00000000-0000-4000-8000-000000003310')='posted'),false) THEN RAISE EXCEPTION 'FAIL idempotent settlement'; END IF;
END $$;

SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000003301',true) IS NOT NULL;
SELECT set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('request.jwt.claim.sub'),'role','authenticated')::text,true) IS NOT NULL;
DO $$ BEGIN
IF NOT COALESCE(((public.alani_my_points_test()->>'points')::bigint=20),false) THEN RAISE EXCEPTION 'FAIL earned points exclude delivery'; END IF;
IF NOT COALESCE(((public.alani_my_points_test()->>'cash_balance_available')::boolean=false),false) THEN RAISE EXCEPTION 'FAIL not cash'; END IF;
END $$;

SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000003302',true) IS NOT NULL;
SELECT set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('request.jwt.claim.sub'),'role','authenticated')::text,true) IS NOT NULL;
DO $$ BEGIN
IF NOT COALESCE(((public.alani_my_points_test()->>'points')::bigint=0),false) THEN RAISE EXCEPTION 'FAIL other points isolated'; END IF;
END $$;

SELECT set_config('request.jwt.claim.sub',current_setting('alani.qa.admin'),true) IS NOT NULL;
SELECT set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('request.jwt.claim.sub'),'role','authenticated')::text,true) IS NOT NULL;
DO $$ BEGIN
IF NOT COALESCE((public.alani_post_full_refund_test(current_setting('alani.qa.return')::uuid)='posted'),false) THEN RAISE EXCEPTION 'FAIL refund simulation'; END IF;
IF NOT COALESCE((public.alani_post_full_refund_test(current_setting('alani.qa.return')::uuid)='posted'),false) THEN RAISE EXCEPTION 'FAIL idempotent refund'; END IF;
END $$;

SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000003301',true) IS NOT NULL;
SELECT set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('request.jwt.claim.sub'),'role','authenticated')::text,true) IS NOT NULL;
DO $$ BEGIN
IF NOT COALESCE(((public.alani_my_points_test()->>'points')::bigint=0),false) THEN RAISE EXCEPTION 'FAIL points reversed'; END IF;
END $$;

RESET ROLE;
DO $$ BEGIN
IF NOT COALESCE(((SELECT count(*) FROM private_checkout.alani_journal_test WHERE order_id='00000000-0000-4000-8000-000000003310')=2),false) THEN RAISE EXCEPTION 'FAIL exactly two journal pairs'; END IF;
IF NOT COALESCE(((SELECT sum(CASE WHEN debit_account='cash_simulated' THEN amount_iqd ELSE -amount_iqd END) FROM private_checkout.alani_journal_test WHERE order_id='00000000-0000-4000-8000-000000003310')=0),false) THEN RAISE EXCEPTION 'FAIL net cash zero after refund'; END IF;
IF NOT COALESCE(((SELECT count(*) FROM private_checkout.alani_points_test WHERE order_id='00000000-0000-4000-8000-000000003310')=2),false) THEN RAISE EXCEPTION 'FAIL two point entries'; END IF;
IF NOT COALESCE((NOT has_table_privilege('authenticated','private_checkout.alani_journal_test','SELECT,INSERT,UPDATE,DELETE') AND NOT has_table_privilege('authenticated','private_checkout.alani_points_test','SELECT,INSERT,UPDATE,DELETE') AND NOT has_function_privilege('anon','public.alani_my_points_test()','EXECUTE')),false) THEN RAISE EXCEPTION 'FAIL direct client access denied'; END IF;
END $$;

SELECT 'PASS: 15 finance and loyalty assertions' AS result;
ROLLBACK;
