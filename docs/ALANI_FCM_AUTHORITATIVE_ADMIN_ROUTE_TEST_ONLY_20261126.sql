-- TEST ONLY. No sends or real device registration.
DO $$ BEGIN IF to_regclass('private_checkout.alani_fcm_test_devices') IS NULL OR to_regclass('private_checkout.alani_fcm_gate') IS NOT NULL THEN RAISE EXCEPTION 'TEST_ONLY_REQUIRED'; END IF; END $$;
CREATE FUNCTION private_checkout.alani_fcm_admin_recipient_test(p_user uuid,p_kind text)
RETURNS boolean LANGUAGE sql STABLE SECURITY INVOKER SET search_path='' AS $$
 SELECT EXISTS(SELECT 1 FROM auth.users u WHERE u.id=p_user AND u.raw_app_meta_data->>'shitreed_role'='admin')
 OR EXISTS(SELECT 1 FROM public.shitreed_admin_staff st WHERE st.user_id=p_user AND st.enabled AND (st.staff_role='operations' OR (p_kind='support_update' AND st.staff_role='support')))
$$;
REVOKE ALL ON FUNCTION private_checkout.alani_fcm_admin_recipient_test(uuid,text) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION private_checkout.alani_capture_fcm_test_event()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
 k text; eid uuid; sid uuid; buyer uuid; ownerid uuid; actor uuid; courier uuid;
BEGIN
 -- Trigger only. Derive all identities from server rows.
 IF TG_TABLE_NAME='orders' THEN
   k:='order_created'; eid:=NEW.id; sid:=NEW.store_id; buyer:=NEW.buyer_id; actor:=NEW.buyer_id;
 ELSIF TG_TABLE_NAME='order_status_history' THEN
   IF NEW.old_status IS NOT DISTINCT FROM NEW.new_status THEN RETURN NEW; END IF;
   k:='order_update'; eid:=NEW.id; actor:=NEW.changed_by;
   SELECT o.store_id,o.buyer_id INTO sid,buyer FROM public.orders o WHERE o.id=NEW.order_id;
 ELSIF TG_TABLE_NAME='alani_support_messages' THEN
   k:='support_update'; eid:=NEW.id; actor:=NEW.sender_id;
   SELECT t.store_id,t.customer_id INTO sid,buyer FROM public.alani_support_threads t WHERE t.id=NEW.thread_id;
 ELSIF TG_TABLE_NAME='alani_delivery_jobs' THEN
   k:='delivery_update'; eid:=NEW.order_id; sid:=NEW.store_id; courier:=NEW.courier_id; actor:=NEW.dispatched_by;
   SELECT o.buyer_id INTO buyer FROM public.orders o WHERE o.id=NEW.order_id AND o.store_id=sid;
 ELSE RETURN NEW;
 END IF;
 IF sid IS DISTINCT FROM '25091ca2-c0da-416c-b634-81b188ee66be'::uuid OR buyer IS NULL THEN RETURN NEW; END IF;
 SELECT s.owner_id INTO ownerid FROM public.stores s WHERE s.id=sid;
 INSERT INTO private_checkout.alani_fcm_test_events(event_kind,event_id,recipient_id,app_kind)
 SELECT k,eid,a.user_id,a.app_kind
 FROM private_checkout.alani_fcm_test_allowlist a
 WHERE a.event_kind=k AND a.user_id IS DISTINCT FROM actor
 AND (
   (a.app_kind='customer' AND a.user_id=buyer)
   OR (a.app_kind='merchant' AND (a.user_id=ownerid OR
      (k='delivery_update' AND a.user_id=courier AND EXISTS(
       SELECT 1 FROM public.alani_delivery_couriers c WHERE c.store_id=sid AND c.courier_id=courier AND c.enabled))))
   OR (a.app_kind='admin' AND private_checkout.alani_fcm_admin_recipient_test(a.user_id,k))
 )
 ON CONFLICT DO NOTHING;
 RETURN NEW;
END $function$
;
CREATE OR REPLACE FUNCTION private_checkout.alani_capture_fcm_test_return()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE sid uuid; buyer uuid; ownerid uuid;
BEGIN
 IF NEW.old_status IS NOT DISTINCT FROM NEW.new_status THEN RETURN NEW; END IF;
 SELECT r.store_id,r.customer_id,s.owner_id INTO sid,buyer,ownerid
 FROM public.alani_return_requests r
 JOIN public.orders o ON o.id=r.order_id AND o.store_id=r.store_id AND o.buyer_id=r.customer_id
 JOIN public.stores s ON s.id=r.store_id
 WHERE r.id=NEW.return_id AND r.status=NEW.new_status;
 IF sid IS DISTINCT FROM '25091ca2-c0da-416c-b634-81b188ee66be'::uuid OR buyer IS NULL THEN RETURN NEW; END IF;
 INSERT INTO private_checkout.alani_fcm_test_events(event_kind,event_id,recipient_id,app_kind)
 SELECT 'return_update',NEW.id,a.user_id,a.app_kind FROM private_checkout.alani_fcm_test_allowlist a
 WHERE a.event_kind='return_update' AND a.user_id IS DISTINCT FROM NEW.changed_by
 AND ((a.app_kind='customer' AND a.user_id=buyer) OR (a.app_kind='merchant' AND a.user_id=ownerid)
 OR (a.app_kind='admin' AND private_checkout.alani_fcm_admin_recipient_test(a.user_id,'return_update')))
 ON CONFLICT DO NOTHING;
 RETURN NEW;
END $function$
;
CREATE OR REPLACE FUNCTION private_checkout.alani_fcm_test_authorize_device(p_event uuid, p_device uuid)
 RETURNS TABLE(user_id uuid, app_kind text, token text, session_active boolean, consent boolean, verified boolean, event_authorized boolean, revoked boolean)
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
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
 OR (d.app_kind='admin' AND private_checkout.alani_fcm_admin_recipient_test(d.user_id,e.event_kind)))
 AND CASE e.event_kind
 WHEN 'order_created' THEN EXISTS(SELECT 1 FROM public.orders o WHERE o.id=e.event_id AND o.store_id='25091ca2-c0da-416c-b634-81b188ee66be'::uuid AND (d.app_kind<>'customer' OR o.buyer_id=d.user_id))
 WHEN 'order_update' THEN EXISTS(SELECT 1 FROM public.order_status_history h JOIN public.orders o ON o.id=h.order_id WHERE h.id=e.event_id AND o.store_id='25091ca2-c0da-416c-b634-81b188ee66be'::uuid AND (d.app_kind<>'customer' OR o.buyer_id=d.user_id))
 WHEN 'support_update' THEN EXISTS(SELECT 1 FROM public.alani_support_messages m JOIN public.alani_support_threads t ON t.id=m.thread_id WHERE m.id=e.event_id AND t.store_id='25091ca2-c0da-416c-b634-81b188ee66be'::uuid AND (d.app_kind<>'customer' OR t.customer_id=d.user_id))
 WHEN 'delivery_update' THEN EXISTS(SELECT 1 FROM public.alani_delivery_jobs j JOIN public.orders o ON o.id=j.order_id WHERE j.order_id=e.event_id AND o.store_id='25091ca2-c0da-416c-b634-81b188ee66be'::uuid AND (d.app_kind<>'customer' OR o.buyer_id=d.user_id))
 WHEN 'return_update' THEN EXISTS(SELECT 1 FROM public.alani_return_status_history h JOIN public.alani_return_requests r ON r.id=h.return_id WHERE h.id=e.event_id AND r.store_id='25091ca2-c0da-416c-b634-81b188ee66be'::uuid AND (d.app_kind<>'customer' OR r.customer_id=d.user_id))
 ELSE false END
$function$
;
