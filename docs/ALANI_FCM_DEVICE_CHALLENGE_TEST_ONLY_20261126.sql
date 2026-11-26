-- TEST ONLY. Challenge registration; no automatic sends without an isolated worker.
DO $$ BEGIN IF to_regclass('private_checkout.alani_fcm_test_devices') IS NULL OR to_regclass('private_checkout.alani_fcm_gate') IS NOT NULL THEN RAISE EXCEPTION 'TEST_ONLY_REQUIRED'; END IF; END $$;
CREATE TABLE private_checkout.alani_fcm_device_challenges_test(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
 session_id uuid NOT NULL REFERENCES auth.sessions(id) ON DELETE CASCADE,
 app_kind text NOT NULL CHECK(app_kind IN ('customer','merchant','admin')),
 token text NOT NULL CHECK(length(token) BETWEEN 20 AND 4096 AND token !~ '[[:space:]]'),
 nonce text NOT NULL DEFAULT encode(extensions.gen_random_bytes(32),'hex') CHECK(nonce ~ '^[a-f0-9]{64}$'),
 created_at timestamptz NOT NULL DEFAULT now(),
 expires_at timestamptz NOT NULL DEFAULT (now()+interval '10 minutes'),
 sent_at timestamptz,
 completed_at timestamptz,
 UNIQUE(user_id,session_id,app_kind)
);
ALTER TABLE private_checkout.alani_fcm_device_challenges_test ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private_checkout.alani_fcm_device_challenges_test FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION private_checkout.alani_fcm_registration_session_test(p_kind text)
RETURNS uuid LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE uid uuid:=auth.uid(); sid uuid; rawsid text:=auth.jwt()->>'session_id';
BEGIN
 IF uid IS NULL OR rawsid IS NULL THEN RAISE EXCEPTION 'LOGIN_REQUIRED'; END IF;
 SELECT s.id INTO sid FROM auth.sessions s WHERE s.id::text=rawsid AND s.user_id=uid AND (s.not_after IS NULL OR s.not_after>now());
 IF sid IS NULL THEN RAISE EXCEPTION 'LOGIN_REQUIRED'; END IF;
 IF p_kind IS NULL OR p_kind NOT IN ('customer','merchant','admin') THEN RAISE EXCEPTION 'INVALID_APP'; END IF;
 IF NOT EXISTS(SELECT 1 FROM private_checkout.alani_fcm_test_allowlist a WHERE a.user_id=uid AND a.app_kind=p_kind) THEN RAISE EXCEPTION 'TEST_DEVICE_NOT_ALLOWED'; END IF;
 IF p_kind='admin' AND NOT private_checkout.alani_fcm_admin_recipient_test(uid,'support_update') THEN RAISE EXCEPTION 'PERMISSION_DENIED'; END IF;
 IF p_kind='merchant' AND NOT (EXISTS(SELECT 1 FROM public.stores s WHERE s.id='25091ca2-c0da-416c-b634-81b188ee66be'::uuid AND s.owner_id=uid AND s.status='approved') OR EXISTS(SELECT 1 FROM public.alani_delivery_couriers c WHERE c.store_id='25091ca2-c0da-416c-b634-81b188ee66be'::uuid AND c.courier_id=uid AND c.enabled)) THEN RAISE EXCEPTION 'PERMISSION_DENIED'; END IF;
 RETURN sid;
END $$;
CREATE FUNCTION private_checkout.alani_fcm_request_device_test(p_kind text,p_token text)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE uid uuid:=auth.uid(); sid uuid; c private_checkout.alani_fcm_device_challenges_test%ROWTYPE; out_id uuid;
BEGIN
 sid:=private_checkout.alani_fcm_registration_session_test(p_kind);
 IF p_token IS NULL OR length(p_token) NOT BETWEEN 20 AND 4096 OR p_token ~ '[[:space:]]' THEN RAISE EXCEPTION 'INVALID_TOKEN'; END IF;
 PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('fcm-register:'||uid::text,0));
 SELECT * INTO c FROM private_checkout.alani_fcm_device_challenges_test WHERE user_id=uid AND session_id=sid AND app_kind=p_kind;
 IF FOUND AND c.created_at>now()-interval '1 minute' THEN RAISE EXCEPTION 'RETRY_LATER'; END IF;
 INSERT INTO private_checkout.alani_fcm_device_challenges_test(user_id,session_id,app_kind,token)
 VALUES(uid,sid,p_kind,p_token)
 ON CONFLICT(user_id,session_id,app_kind) DO UPDATE SET id=gen_random_uuid(),token=EXCLUDED.token,nonce=encode(extensions.gen_random_bytes(32),'hex'),created_at=now(),expires_at=now()+interval '10 minutes',sent_at=NULL,completed_at=NULL
 RETURNING id INTO out_id;
 RETURN out_id;
END $$;
CREATE FUNCTION private_checkout.alani_fcm_confirm_device_test(p_id uuid,p_nonce text)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE c private_checkout.alani_fcm_device_challenges_test%ROWTYPE; sid uuid; uid uuid:=auth.uid();
BEGIN
 IF uid IS NULL OR p_nonce IS NULL OR p_nonce !~ '^[a-f0-9]{64}$' THEN RETURN false; END IF;
 SELECT * INTO c FROM private_checkout.alani_fcm_device_challenges_test WHERE id=p_id AND user_id=uid FOR UPDATE;
 IF NOT FOUND THEN RETURN false; END IF;
 sid:=private_checkout.alani_fcm_registration_session_test(c.app_kind);
 IF c.session_id<>sid OR c.sent_at IS NULL OR c.completed_at IS NOT NULL OR c.expires_at<=now() OR c.nonce<>p_nonce THEN RETURN false; END IF;
 INSERT INTO private_checkout.alani_fcm_test_devices(user_id,session_id,app_kind,token,consent_at,verified_at)
 VALUES(uid,sid,c.app_kind,c.token,c.created_at,now())
 ON CONFLICT(token) DO UPDATE SET session_id=EXCLUDED.session_id,consent_at=EXCLUDED.consent_at,verified_at=EXCLUDED.verified_at,revoked_at=NULL
 WHERE private_checkout.alani_fcm_test_devices.user_id=uid AND private_checkout.alani_fcm_test_devices.app_kind=c.app_kind;
 IF NOT FOUND THEN RETURN false; END IF;
 UPDATE private_checkout.alani_fcm_device_challenges_test SET completed_at=now(),nonce=encode(extensions.gen_random_bytes(32),'hex') WHERE id=c.id;
 RETURN true;
END $$;
REVOKE ALL ON FUNCTION private_checkout.alani_fcm_registration_session_test(text),private_checkout.alani_fcm_request_device_test(text,text),private_checkout.alani_fcm_confirm_device_test(uuid,text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION private_checkout.alani_fcm_request_device_test(text,text),private_checkout.alani_fcm_confirm_device_test(uuid,text) TO authenticated;
CREATE FUNCTION public.alani_fcm_request_device_test(p_kind text,p_token text) RETURNS uuid LANGUAGE sql SECURITY INVOKER SET search_path='' RETURN private_checkout.alani_fcm_request_device_test(p_kind,p_token);
CREATE FUNCTION public.alani_fcm_confirm_device_test(p_id uuid,p_nonce text) RETURNS boolean LANGUAGE sql SECURITY INVOKER SET search_path='' RETURN private_checkout.alani_fcm_confirm_device_test(p_id,p_nonce);
REVOKE ALL ON FUNCTION public.alani_fcm_request_device_test(text,text),public.alani_fcm_confirm_device_test(uuid,text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.alani_fcm_request_device_test(text,text),public.alani_fcm_confirm_device_test(uuid,text) TO authenticated;
