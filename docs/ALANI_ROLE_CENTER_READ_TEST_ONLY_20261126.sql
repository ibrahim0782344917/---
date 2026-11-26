-- TEST ONLY. Read-only role-bound center; no financial writes or legacy PII.
DO $$ BEGIN
 IF to_regclass('private_checkout.alani_wallet_accounts_test') IS NULL OR to_regclass('private_checkout.alani_fcm_gate') IS NOT NULL THEN RAISE EXCEPTION 'TEST_ONLY_REQUIRED'; END IF;
END $$;
CREATE FUNCTION private_checkout.alani_center_read_test(p_scope text)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE uid uuid:=auth.uid(); sid text:=auth.jwt()->>'session_id'; storeid uuid:='25091ca2-c0da-416c-b634-81b188ee66be'; result jsonb;
BEGIN
 IF uid IS NULL OR sid IS NULL OR sid !~ '^[0-9a-fA-F-]{36}$' THEN RAISE EXCEPTION 'LOGIN_REQUIRED'; END IF;
 IF NOT EXISTS(SELECT 1 FROM auth.sessions s WHERE s.id::text=sid AND s.user_id=uid AND (s.not_after IS NULL OR s.not_after>now())) THEN RAISE EXCEPTION 'LOGIN_REQUIRED'; END IF;
 IF p_scope='customer' THEN
 SELECT jsonb_build_object('balance_iqd',coalesce((SELECT balance_iqd FROM private_checkout.alani_wallet_accounts_test WHERE user_id=uid),0),'transactions',coalesce((SELECT jsonb_agg(to_jsonb(x) ORDER BY x.created_at DESC) FROM (SELECT delta_iqd,balance_after_iqd,created_at FROM private_checkout.alani_wallet_ledger_test WHERE user_id=uid ORDER BY created_at DESC,request_key LIMIT 30)x),'[]'::jsonb),'payments_enabled',false) INTO result;
 ELSIF p_scope='merchant' THEN
 IF NOT EXISTS(SELECT 1 FROM public.stores WHERE id=storeid AND owner_id=uid AND status='approved') THEN RAISE EXCEPTION 'PERMISSION_DENIED'; END IF;
 SELECT jsonb_build_object('customers',(SELECT count(DISTINCT buyer_id) FROM public.orders WHERE store_id=storeid),'orders',(SELECT count(*) FROM public.orders WHERE store_id=storeid),'payments_enabled',false,'import_enabled',false) INTO result;
 ELSIF p_scope='admin' THEN
 IF NOT EXISTS(SELECT 1 FROM public.shitreed_admin_staff WHERE user_id=uid AND enabled AND staff_role='super_admin') THEN RAISE EXCEPTION 'PERMISSION_DENIED'; END IF;
 SELECT jsonb_build_object('legacy_contacts',(SELECT count(*) FROM private_legacy.contacts),'review_queue',(SELECT count(*) FROM private_legacy.review_queue),'synthetic_contacts',(SELECT count(*) FROM private_checkout.alani_legacy_contacts_test),'wallet_accounts',(SELECT count(*) FROM private_checkout.alani_wallet_accounts_test),'wallet_movements',(SELECT count(*) FROM private_checkout.alani_wallet_ledger_test),'payments_enabled',false,'import_enabled',false) INTO result;
 ELSE RAISE EXCEPTION 'INVALID_SCOPE'; END IF;
 RETURN result;
END $$;
REVOKE ALL ON FUNCTION private_checkout.alani_center_read_test(text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION private_checkout.alani_center_read_test(text) TO authenticated;
-- SQL-standard body resolves the private function at definition time; no new schema usage grant.
CREATE FUNCTION public.alani_center_read_test(p_scope text)
RETURNS jsonb LANGUAGE sql STABLE SECURITY INVOKER SET search_path=''
RETURN private_checkout.alani_center_read_test(p_scope);
REVOKE ALL ON FUNCTION public.alani_center_read_test(text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.alani_center_read_test(text) TO authenticated;
