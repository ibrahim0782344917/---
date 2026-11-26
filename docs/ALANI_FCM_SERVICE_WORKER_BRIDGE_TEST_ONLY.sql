-- TEST ONLY. Worker delivery receipts and service-only bridge.
DO $$ BEGIN IF to_regclass('private_checkout.alani_fcm_device_challenges_test') IS NULL OR to_regclass('private_checkout.alani_fcm_gate') IS NOT NULL THEN RAISE EXCEPTION 'TEST_ONLY_REQUIRED'; END IF; END $$;
CREATE TABLE private_checkout.alani_fcm_event_delivery_test(
 event_id uuid NOT NULL REFERENCES private_checkout.alani_fcm_test_events(id) ON DELETE CASCADE,
 device_id uuid NOT NULL REFERENCES private_checkout.alani_fcm_test_devices(id) ON DELETE CASCADE,
 claim_key uuid, claimed_at timestamptz, attempts integer NOT NULL DEFAULT 0 CHECK(attempts BETWEEN 0 AND 3),
 outcome text CHECK(outcome IN ('accepted','validated','retry','failed','suppressed')),
 finished_at timestamptz,
 PRIMARY KEY(event_id,device_id)
);
ALTER TABLE private_checkout.alani_fcm_event_delivery_test ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private_checkout.alani_fcm_event_delivery_test FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION private_checkout.alani_fcm_claim_event_test()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE c record; lease uuid;
BEGIN
 -- Serialize claims; do not send to devices not verified before the event was captured.
 PERFORM pg_catalog.pg_advisory_xact_lock(26001127);
 SELECT e.id AS eid,e.event_kind,e.expires_at,d.id AS did,a.token INTO c
 FROM private_checkout.alani_fcm_test_events e
 JOIN private_checkout.alani_fcm_test_devices d ON d.user_id=e.recipient_id AND d.app_kind=e.app_kind AND d.verified_at<=e.created_at
 CROSS JOIN LATERAL private_checkout.alani_fcm_test_authorize_device(e.id,d.id) a
 LEFT JOIN private_checkout.alani_fcm_event_delivery_test r ON r.event_id=e.id AND r.device_id=d.id
 WHERE e.expires_at>now()+interval '15 seconds'
 AND (r.event_id IS NULL OR (r.attempts<3 AND (r.outcome IS NULL OR r.outcome='retry') AND (r.claimed_at IS NULL OR r.claimed_at<now()-interval '1 minute')))
 ORDER BY e.created_at,e.id,d.id LIMIT 1;
 IF NOT FOUND THEN RETURN NULL; END IF;
 lease:=gen_random_uuid();
 INSERT INTO private_checkout.alani_fcm_event_delivery_test(event_id,device_id,claim_key,claimed_at,attempts)
 VALUES(c.eid,c.did,lease,now(),1)
 ON CONFLICT(event_id,device_id) DO UPDATE SET claim_key=lease,claimed_at=now(),attempts=private_checkout.alani_fcm_event_delivery_test.attempts+1,outcome=NULL,finished_at=NULL;
 RETURN jsonb_build_object('id',c.eid,'device_id',c.did,'claim_key',lease,'token',c.token,'event_kind',c.event_kind,'expires_at',c.expires_at);
END $$;
CREATE FUNCTION private_checkout.alani_fcm_finish_event_test(p_id uuid,p_device uuid,p_claim uuid,p_outcome text)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN
 IF p_outcome IS NULL OR p_outcome NOT IN ('accepted','validated','retry','failed','suppressed') THEN RAISE EXCEPTION 'INVALID_OUTCOME'; END IF;
 UPDATE private_checkout.alani_fcm_event_delivery_test SET outcome=p_outcome,finished_at=now(),claim_key=NULL,claimed_at=CASE WHEN p_outcome='retry' THEN now() ELSE NULL END
 WHERE event_id=p_id AND device_id=p_device AND claim_key=p_claim;
 RETURN FOUND;
END $$;
CREATE FUNCTION private_checkout.alani_fcm_worker_bridge_test(p_action text,p_args jsonb DEFAULT '{}'::jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE result jsonb; k uuid; d uuid; i uuid; o text;
BEGIN
 IF p_action='claim_challenge' THEN SELECT to_jsonb(c) INTO result FROM private_checkout.alani_fcm_claim_challenge_test() c; RETURN result;
 ELSIF p_action='claim_event' THEN RETURN private_checkout.alani_fcm_claim_event_test();
 ELSIF p_action IN ('finish_challenge','finish_event') THEN
 i:=(p_args->>'id')::uuid; k:=(p_args->>'claim_key')::uuid; o:=p_args->>'outcome';
 IF p_action='finish_challenge' THEN RETURN to_jsonb(private_checkout.alani_fcm_finish_challenge_test(i,k,o)); END IF;
 d:=(p_args->>'device_id')::uuid;
 RETURN to_jsonb(private_checkout.alani_fcm_finish_event_test(i,d,k,o));
 ELSIF p_action='check_event' THEN
 i:=(p_args->>'id')::uuid; d:=(p_args->>'device_id')::uuid; k:=(p_args->>'claim_key')::uuid;
 RETURN to_jsonb(EXISTS(SELECT 1 FROM private_checkout.alani_fcm_event_delivery_test r CROSS JOIN LATERAL private_checkout.alani_fcm_test_authorize_device(r.event_id,r.device_id) a WHERE r.event_id=i AND r.device_id=d AND r.claim_key=k AND r.claimed_at>now()-interval '1 minute'));
 ELSIF p_action='check_challenge' THEN
 i:=(p_args->>'id')::uuid; k:=(p_args->>'claim_key')::uuid;
 RETURN to_jsonb(EXISTS(SELECT 1 FROM private_checkout.alani_fcm_device_challenges_test c JOIN auth.sessions s ON s.id=c.session_id AND s.user_id=c.user_id WHERE c.id=i AND c.claim_key=k AND c.claimed_at>now()-interval '1 minute' AND c.sent_at IS NULL AND c.completed_at IS NULL AND c.expires_at>now() AND (s.not_after IS NULL OR s.not_after>now()) AND EXISTS(SELECT 1 FROM private_checkout.alani_fcm_test_allowlist a WHERE a.user_id=c.user_id AND a.app_kind=c.app_kind) AND (c.app_kind='customer' OR (c.app_kind='admin' AND private_checkout.alani_fcm_admin_recipient_test(c.user_id,'support_update')) OR (c.app_kind='merchant' AND (EXISTS(SELECT 1 FROM public.stores st WHERE st.id='25091ca2-c0da-416c-b634-81b188ee66be' AND st.owner_id=c.user_id AND st.status='approved') OR EXISTS(SELECT 1 FROM public.alani_delivery_couriers co WHERE co.store_id='25091ca2-c0da-416c-b634-81b188ee66be' AND co.courier_id=c.user_id AND co.enabled))))));
 ELSE RAISE EXCEPTION 'INVALID_ACTION'; END IF;
END $$;
REVOKE ALL ON FUNCTION private_checkout.alani_fcm_claim_event_test(),private_checkout.alani_fcm_finish_event_test(uuid,uuid,uuid,text),private_checkout.alani_fcm_worker_bridge_test(text,jsonb) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION private_checkout.alani_fcm_worker_bridge_test(text,jsonb) TO service_role;
CREATE FUNCTION public.alani_fcm_worker_bridge_test(p_action text,p_args jsonb DEFAULT '{}'::jsonb)
RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='' RETURN private_checkout.alani_fcm_worker_bridge_test(p_action,p_args);
REVOKE ALL ON FUNCTION public.alani_fcm_worker_bridge_test(text,jsonb) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.alani_fcm_worker_bridge_test(text,jsonb) TO service_role;
