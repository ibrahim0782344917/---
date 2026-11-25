-- TEST ONLY: run against confirmed shitreed-test (tgvdwotbrnhcoykuxdpr).
-- Read-only SQL role simulation, NOT a real Auth/API login. No customer rows returned.
BEGIN READ ONLY;
DO $$
DECLARE v_order uuid; v_buyer uuid; v_admin uuid;
BEGIN
 SELECT id,buyer_id INTO STRICT v_order,v_buyer FROM public.orders WHERE store_id='25091ca2-c0da-416c-b634-81b188ee66be'::uuid ORDER BY id LIMIT 1;
 SELECT id INTO STRICT v_admin FROM auth.users WHERE raw_app_meta_data->>'shitreed_role'='admin' LIMIT 1;
 PERFORM set_config('alani.test.order',v_order::text,true);
 PERFORM set_config('alani.test.buyer',v_buyer::text,true);
 PERFORM set_config('alani.test.admin',v_admin::text,true);
END $$;
SET LOCAL ROLE authenticated;
DO $$
DECLARE v_outsider uuid:='00000000-0000-4000-8000-000000000123'; v_order uuid:=current_setting('alani.test.order')::uuid; v_result jsonb;
BEGIN
 PERFORM set_config('request.jwt.claim.sub',v_outsider::text,true);
 PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',v_outsider,'role','authenticated','user_metadata',jsonb_build_object('shitreed_role','admin'))::text,true);
 IF public.shitreed_admin_role() IS NOT NULL OR public.shitreed_is_admin() THEN RAISE EXCEPTION 'FAIL outsider admin'; END IF;
 BEGIN PERFORM public.shitreed_admin_dashboard(); RAISE EXCEPTION 'FAIL dashboard allowed'; EXCEPTION WHEN OTHERS THEN IF SQLERRM <> 'ADMIN_ACCESS_REQUIRED' THEN RAISE; END IF; END;
 BEGIN PERFORM public.alani_order_delivery_status(v_order); RAISE EXCEPTION 'FAIL order allowed'; EXCEPTION WHEN OTHERS THEN IF SQLERRM <> 'PERMISSION_DENIED' THEN RAISE; END IF; END;
 IF EXISTS (SELECT 1 FROM public.alani_my_delivery_tasks()) THEN RAISE EXCEPTION 'FAIL outsider delivery tasks'; END IF;
 IF EXISTS (SELECT 1 FROM public.alani_support_unread_counts()) THEN RAISE EXCEPTION 'FAIL outsider chat'; END IF;
 IF EXISTS (SELECT 1 FROM public.orders WHERE id=v_order) THEN RAISE EXCEPTION 'FAIL direct order RLS'; END IF;
 PERFORM set_config('request.jwt.claim.sub',current_setting('alani.test.buyer'),true);
 PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('alani.test.buyer'),'role','authenticated')::text,true);
 v_result:=public.alani_order_delivery_status(v_order);
 IF v_result->>'order_id' IS DISTINCT FROM v_order::text THEN RAISE EXCEPTION 'FAIL buyer order'; END IF;
 PERFORM set_config('request.jwt.claim.sub',current_setting('alani.test.admin'),true);
 PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('alani.test.admin'),'role','authenticated')::text,true);
 IF public.shitreed_admin_role() IS DISTINCT FROM 'super_admin' THEN RAISE EXCEPTION 'FAIL admin role'; END IF;
 v_result:=public.shitreed_admin_dashboard();
 IF NOT (v_result ? 'orders') THEN RAISE EXCEPTION 'FAIL admin dashboard'; END IF;
END $$;
RESET ROLE;
SELECT 'PASS: 9 role assertions; read only, no row data returned' AS result;
ROLLBACK;
