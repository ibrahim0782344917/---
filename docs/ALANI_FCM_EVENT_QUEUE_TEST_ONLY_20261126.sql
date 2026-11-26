-- TEST ONLY. No FCM network requests, credentials, registration or delivery.
-- Apply exclusively to tgvdwotbrnhcoykuxdpr.
DO $guard$ BEGIN
 IF to_regclass('public.alani_notification_preferences_test') IS NULL
 OR to_regclass('private_checkout.alani_fcm_test_events') IS NOT NULL
 THEN RAISE EXCEPTION 'FCM_TEST_PREFLIGHT_FAILED'; END IF;
END $guard$;
CREATE TABLE private_checkout.alani_fcm_test_allowlist (
 user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
 app_kind text NOT NULL CHECK(app_kind IN ('customer','merchant','admin')),
 event_kind text NOT NULL CHECK(event_kind IN ('order_created','order_update','support_update','delivery_update')),
 PRIMARY KEY(user_id,app_kind,event_kind)
);
CREATE TABLE private_checkout.alani_fcm_test_events (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 event_kind text NOT NULL CHECK(event_kind IN ('order_created','order_update','support_update','delivery_update')),
 event_id uuid NOT NULL,
 recipient_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
 app_kind text NOT NULL CHECK(app_kind IN ('customer','merchant','admin')),
 created_at timestamptz NOT NULL DEFAULT now(),
 expires_at timestamptz NOT NULL DEFAULT (now()+interval '5 minutes'),
 UNIQUE(event_kind,event_id,recipient_id,app_kind)
);
ALTER TABLE private_checkout.alani_fcm_test_allowlist ENABLE ROW LEVEL SECURITY;
ALTER TABLE private_checkout.alani_fcm_test_events ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private_checkout.alani_fcm_test_allowlist,private_checkout.alani_fcm_test_events FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION private_checkout.alani_capture_fcm_test_event()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
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
   OR (a.app_kind='admin' AND EXISTS(
      SELECT 1 FROM public.shitreed_admin_staff st WHERE st.user_id=a.user_id AND st.enabled
      AND (st.staff_role IN ('super_admin','operations') OR (k='support_update' AND st.staff_role='support'))))
 )
 ON CONFLICT DO NOTHING;
 RETURN NEW;
END $$;
REVOKE ALL ON FUNCTION private_checkout.alani_capture_fcm_test_event() FROM PUBLIC,anon,authenticated,service_role;
CREATE TRIGGER alani_fcm_test_order_created AFTER INSERT ON public.orders FOR EACH ROW EXECUTE FUNCTION private_checkout.alani_capture_fcm_test_event();
CREATE TRIGGER alani_fcm_test_order_status AFTER INSERT ON public.order_status_history FOR EACH ROW EXECUTE FUNCTION private_checkout.alani_capture_fcm_test_event();
CREATE TRIGGER alani_fcm_test_support AFTER INSERT ON public.alani_support_messages FOR EACH ROW EXECUTE FUNCTION private_checkout.alani_capture_fcm_test_event();
CREATE TRIGGER alani_fcm_test_delivery AFTER INSERT ON public.alani_delivery_jobs FOR EACH ROW EXECUTE FUNCTION private_checkout.alani_capture_fcm_test_event();
-- Empty allowlist by design. No network worker or registration API.
