-- TEST ONLY. Reset lease and validation state on explicit new registration.
DO $$ BEGIN IF to_regclass('private_checkout.alani_fcm_device_challenges_test') IS NULL OR to_regclass('private_checkout.alani_fcm_gate') IS NOT NULL THEN RAISE EXCEPTION 'TEST_ONLY_REQUIRED'; END IF; END $$;
CREATE OR REPLACE FUNCTION private_checkout.alani_fcm_request_device_test(p_kind text, p_token text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE uid uuid:=auth.uid(); sid uuid; c private_checkout.alani_fcm_device_challenges_test%ROWTYPE; out_id uuid;
BEGIN
 sid:=private_checkout.alani_fcm_registration_session_test(p_kind);
 IF p_token IS NULL OR length(p_token) NOT BETWEEN 20 AND 4096 OR p_token ~ '[[:space:]]' THEN RAISE EXCEPTION 'INVALID_TOKEN'; END IF;
 PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('fcm-register:'||uid::text,0));
 SELECT * INTO c FROM private_checkout.alani_fcm_device_challenges_test WHERE user_id=uid AND session_id=sid AND app_kind=p_kind;
 IF FOUND AND c.created_at>now()-interval '1 minute' THEN RAISE EXCEPTION 'RETRY_LATER'; END IF;
 INSERT INTO private_checkout.alani_fcm_device_challenges_test(user_id,session_id,app_kind,token)
 VALUES(uid,sid,p_kind,p_token)
 ON CONFLICT(user_id,session_id,app_kind) DO UPDATE SET id=gen_random_uuid(),token=EXCLUDED.token,nonce=encode(extensions.gen_random_bytes(32),'hex'),created_at=now(),expires_at=now()+interval '10 minutes',sent_at=NULL,completed_at=NULL,claim_key=NULL,claimed_at=NULL,attempts=0,validated_at=NULL
 RETURNING id INTO out_id;
 RETURN out_id;
END $function$
;
