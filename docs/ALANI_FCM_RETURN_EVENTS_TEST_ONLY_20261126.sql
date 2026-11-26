-- TEST ONLY, tgvdwotbrnhcoykuxdpr. No delivery worker, no tokens.
DO $$ BEGIN
 IF to_regclass('private_checkout.alani_fcm_test_events') IS NULL OR to_regclass('public.alani_notification_preferences_test') IS NULL OR to_regclass('private_checkout.alani_fcm_gate') IS NOT NULL THEN RAISE EXCEPTION 'TEST_ONLY_REQUIRED'; END IF;
END $$;
ALTER TABLE private_checkout.alani_fcm_test_allowlist DROP CONSTRAINT alani_fcm_test_allowlist_event_kind_check, ADD CONSTRAINT alani_fcm_test_allowlist_event_kind_check CHECK(event_kind IN ('order_created','order_update','support_update','delivery_update','return_update'));
ALTER TABLE private_checkout.alani_fcm_test_events DROP CONSTRAINT alani_fcm_test_events_event_kind_check, ADD CONSTRAINT alani_fcm_test_events_event_kind_check CHECK(event_kind IN ('order_created','order_update','support_update','delivery_update','return_update'));
CREATE FUNCTION private_checkout.alani_capture_fcm_test_return()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
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
 OR (a.app_kind='admin' AND EXISTS(SELECT 1 FROM public.shitreed_admin_staff st WHERE st.user_id=a.user_id AND st.enabled AND st.staff_role IN ('super_admin','operations'))))
 ON CONFLICT DO NOTHING;
 RETURN NEW;
END $$;
REVOKE ALL ON FUNCTION private_checkout.alani_capture_fcm_test_return() FROM PUBLIC,anon,authenticated,service_role;
CREATE TRIGGER alani_fcm_test_return_status AFTER INSERT ON public.alani_return_status_history FOR EACH ROW EXECUTE FUNCTION private_checkout.alani_capture_fcm_test_return();
