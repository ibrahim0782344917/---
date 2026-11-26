-- TEST ONLY, explicit user revocation even if allowlist permission has been removed.
DO $$ BEGIN IF to_regclass('private_checkout.alani_fcm_device_challenges_test') IS NULL OR to_regclass('private_checkout.alani_fcm_gate') IS NOT NULL THEN RAISE EXCEPTION 'TEST_ONLY_REQUIRED'; END IF; END $$;
CREATE FUNCTION private_checkout.alani_fcm_revoke_device_test(p_kind text)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE uid uuid:=auth.uid(); sid text:=auth.jwt()->>'session_id';
BEGIN
 IF uid IS NULL OR sid IS NULL OR p_kind IS NULL OR p_kind NOT IN ('customer','merchant','admin') THEN RAISE EXCEPTION 'LOGIN_REQUIRED'; END IF;
 IF NOT EXISTS(SELECT 1 FROM auth.sessions s WHERE s.id::text=sid AND s.user_id=uid AND (s.not_after IS NULL OR s.not_after>now())) THEN RAISE EXCEPTION 'LOGIN_REQUIRED'; END IF;
 UPDATE private_checkout.alani_fcm_test_devices SET revoked_at=now() WHERE user_id=uid AND session_id::text=sid AND app_kind=p_kind AND revoked_at IS NULL;
 DELETE FROM private_checkout.alani_fcm_device_challenges_test WHERE user_id=uid AND session_id::text=sid AND app_kind=p_kind;
 RETURN true;
END $$;
REVOKE ALL ON FUNCTION private_checkout.alani_fcm_revoke_device_test(text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION private_checkout.alani_fcm_revoke_device_test(text) TO authenticated;
CREATE FUNCTION public.alani_fcm_revoke_device_test(p_kind text) RETURNS boolean LANGUAGE sql SECURITY INVOKER SET search_path='' RETURN private_checkout.alani_fcm_revoke_device_test(p_kind);
REVOKE ALL ON FUNCTION public.alani_fcm_revoke_device_test(text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.alani_fcm_revoke_device_test(text) TO authenticated;
