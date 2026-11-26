-- TEST only. Closed database adapter for validated device consent and session binding.
DO $$ BEGIN
 IF to_regclass('private_checkout.alani_fcm_test_events') IS NULL OR to_regclass('private_checkout.alani_fcm_gate') IS NOT NULL THEN RAISE EXCEPTION 'TEST_ONLY_REQUIRED'; END IF;
END $$;
CREATE TABLE private_checkout.alani_fcm_test_devices(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
 session_id uuid NOT NULL REFERENCES auth.sessions(id) ON DELETE CASCADE,
 app_kind text NOT NULL CHECK(app_kind IN ('customer','merchant','admin')),
 token text NOT NULL UNIQUE CHECK(length(token) BETWEEN 20 AND 4096 AND token !~ '[[:space:]]'),
 consent_at timestamptz NOT NULL DEFAULT now(),
 verified_at timestamptz,
 revoked_at timestamptz,
 CHECK(verified_at IS NULL OR verified_at>=consent_at)
);
ALTER TABLE private_checkout.alani_fcm_test_devices ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private_checkout.alani_fcm_test_devices FROM PUBLIC,anon,authenticated,service_role;
-- Private operator adapter: future verified device registration must separately prove token possession.
-- No registration endpoint, no permission to set verified_at from any client.
CREATE FUNCTION private_checkout.alani_fcm_test_authorize_device(p_event uuid,p_device uuid)
RETURNS TABLE(user_id uuid, app_kind text,token text,session_active boolean,consent boolean,verified boolean,event_authorized boolean,revoked boolean)
LANGUAGE sql STABLE SECURITY INVOKER SET search_path='' AS $$
 SELECT d.user_id,d.app_kind,d.token,true,true,true,true,false
 FROM private_checkout.alani_fcm_test_events e
 JOIN private_checkout.alani_fcm_test_devices d ON d.user_id=e.recipient_id AND d.app_kind=e.app_kind
 JOIN auth.sessions sess ON sess.id=d.session_id AND sess.user_id=d.user_id
 JOIN private_checkout.alani_fcm_test_allowlist a ON a.user_id=d.user_id AND a.app_kind=d.app_kind AND a.event_kind=e.event_kind
 WHERE e.id=p_event AND d.id=p_device AND e.expires_at>now()
 AND d.verified_at IS NOT NULL AND d.revoked_at IS NULL
 AND (sess.not_after IS NULL OR sess.not_after>now())
 AND (d.app_kind='customer' OR
 (d.app_kind='merchant' AND (EXISTS(SELECT 1 FROM public.stores s WHERE s.id='25091ca2-c0da-416c-b634-81b188ee66be'::uuid AND s.owner_id=d.user_id AND s.status='approved')
 OR (e.event_kind='delivery_update' AND EXISTS(SELECT 1 FROM public.alani_delivery_jobs j JOIN public.alani_delivery_couriers c ON c.store_id=j.store_id AND c.courier_id=j.courier_id AND c.enabled WHERE j.order_id=e.event_id AND j.courier_id=d.user_id))))
 OR (d.app_kind='admin' AND EXISTS(SELECT 1 FROM public.shitreed_admin_staff st WHERE st.user_id=d.user_id AND st.enabled AND (st.staff_role IN ('super_admin','operations') OR (e.event_kind='support_update' AND st.staff_role='support')))))
 AND CASE e.event_kind
 WHEN 'order_created' THEN EXISTS(SELECT 1 FROM public.orders o WHERE o.id=e.event_id AND o.store_id='25091ca2-c0da-416c-b634-81b188ee66be'::uuid AND (d.app_kind<>'customer' OR o.buyer_id=d.user_id))
 WHEN 'order_update' THEN EXISTS(SELECT 1 FROM public.order_status_history h JOIN public.orders o ON o.id=h.order_id WHERE h.id=e.event_id AND o.store_id='25091ca2-c0da-416c-b634-81b188ee66be'::uuid AND (d.app_kind<>'customer' OR o.buyer_id=d.user_id))
 WHEN 'support_update' THEN EXISTS(SELECT 1 FROM public.alani_support_messages m JOIN public.alani_support_threads t ON t.id=m.thread_id WHERE m.id=e.event_id AND t.store_id='25091ca2-c0da-416c-b634-81b188ee66be'::uuid AND (d.app_kind<>'customer' OR t.customer_id=d.user_id))
 WHEN 'delivery_update' THEN EXISTS(SELECT 1 FROM public.alani_delivery_jobs j JOIN public.orders o ON o.id=j.order_id WHERE j.order_id=e.event_id AND o.store_id='25091ca2-c0da-416c-b634-81b188ee66be'::uuid AND (d.app_kind<>'customer' OR o.buyer_id=d.user_id))
 WHEN 'return_update' THEN EXISTS(SELECT 1 FROM public.alani_return_status_history h JOIN public.alani_return_requests r ON r.id=h.return_id WHERE h.id=e.event_id AND r.store_id='25091ca2-c0da-416c-b634-81b188ee66be'::uuid AND (d.app_kind<>'customer' OR r.customer_id=d.user_id))
 ELSE false END
$$;
REVOKE ALL ON FUNCTION private_checkout.alani_fcm_test_authorize_device(uuid,uuid) FROM PUBLIC,anon,authenticated,service_role;
