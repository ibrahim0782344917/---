-- TEST ONLY. Private challenge queue. No exposed RPC and no credentials.
DO $$ BEGIN IF to_regclass('private_checkout.alani_fcm_device_challenges_test') IS NULL OR to_regclass('private_checkout.alani_fcm_gate') IS NOT NULL THEN RAISE EXCEPTION 'TEST_ONLY_REQUIRED'; END IF; END $$;
ALTER TABLE private_checkout.alani_fcm_device_challenges_test ADD COLUMN claim_key uuid, ADD COLUMN claimed_at timestamptz, ADD COLUMN attempts integer NOT NULL DEFAULT 0 CHECK(attempts BETWEEN 0 AND 3), ADD COLUMN validated_at timestamptz;
CREATE FUNCTION private_checkout.alani_fcm_claim_challenge_test()
RETURNS TABLE(id uuid,claim_key uuid,token text,nonce text,expires_at timestamptz)
LANGUAGE sql VOLATILE SECURITY INVOKER SET search_path='' AS $$
 WITH chosen AS (
 SELECT c.id FROM private_checkout.alani_fcm_device_challenges_test c JOIN auth.sessions s ON s.id=c.session_id AND s.user_id=c.user_id
 WHERE c.expires_at>now()+interval '15 seconds' AND c.sent_at IS NULL AND c.completed_at IS NULL AND c.attempts<3
 AND (c.claimed_at IS NULL OR c.claimed_at<now()-interval '1 minute')
 AND (s.not_after IS NULL OR s.not_after>now())
 AND EXISTS(SELECT 1 FROM private_checkout.alani_fcm_test_allowlist a WHERE a.user_id=c.user_id AND a.app_kind=c.app_kind)
 AND (c.app_kind='customer' OR (c.app_kind='admin' AND private_checkout.alani_fcm_admin_recipient_test(c.user_id,'support_update')) OR (c.app_kind='merchant' AND (EXISTS(SELECT 1 FROM public.stores st WHERE st.id='25091ca2-c0da-416c-b634-81b188ee66be'::uuid AND st.owner_id=c.user_id AND st.status='approved') OR EXISTS(SELECT 1 FROM public.alani_delivery_couriers co WHERE co.store_id='25091ca2-c0da-416c-b634-81b188ee66be'::uuid AND co.courier_id=c.user_id AND co.enabled))))
 ORDER BY c.created_at,c.id LIMIT 1 FOR UPDATE OF c SKIP LOCKED
 )
 UPDATE private_checkout.alani_fcm_device_challenges_test c SET claim_key=gen_random_uuid(),claimed_at=now(),attempts=c.attempts+1 FROM chosen WHERE c.id=chosen.id RETURNING c.id,c.claim_key,c.token,c.nonce,c.expires_at
$$;
CREATE FUNCTION private_checkout.alani_fcm_finish_challenge_test(p_id uuid,p_claim uuid,p_outcome text)
RETURNS boolean LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
BEGIN
 IF p_outcome IS NULL OR p_outcome NOT IN ('validated','accepted','retry','failed') THEN RAISE EXCEPTION 'INVALID_OUTCOME'; END IF;
 UPDATE private_checkout.alani_fcm_device_challenges_test c SET
 validated_at=CASE WHEN p_outcome='validated' THEN now() ELSE c.validated_at END,
 sent_at=CASE WHEN p_outcome='accepted' THEN now() ELSE c.sent_at END,
 attempts=CASE WHEN p_outcome='failed' THEN 3 ELSE c.attempts END,
 claim_key=NULL,claimed_at=CASE WHEN p_outcome='retry' THEN now() ELSE NULL END
 WHERE c.id=p_id AND c.claim_key=p_claim AND c.expires_at>now() AND c.sent_at IS NULL AND c.completed_at IS NULL;
 RETURN FOUND;
END $$;
REVOKE ALL ON FUNCTION private_checkout.alani_fcm_claim_challenge_test(),private_checkout.alani_fcm_finish_challenge_test(uuid,uuid,text) FROM PUBLIC,anon,authenticated,service_role;
