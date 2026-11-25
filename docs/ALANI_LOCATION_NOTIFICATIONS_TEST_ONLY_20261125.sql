-- TEST ONLY. Latest foreground location only; no tracking history, push delivery or external calls.
CREATE TABLE private_checkout.alani_delivery_location_test (
 order_id uuid PRIMARY KEY REFERENCES public.orders(id) ON DELETE CASCADE,
 courier_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
 latitude double precision NOT NULL CHECK(latitude BETWEEN -90 AND 90),
 longitude double precision NOT NULL CHECK(longitude BETWEEN -180 AND 180),
 accuracy_m double precision NOT NULL CHECK(accuracy_m BETWEEN 0 AND 1000),
 updated_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
CREATE TABLE private_checkout.alani_order_notification_reads_test (
 user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
 event_id uuid NOT NULL REFERENCES public.order_status_history(id) ON DELETE CASCADE,
 read_at timestamptz NOT NULL DEFAULT now(),
 PRIMARY KEY(user_id,event_id)
);
ALTER TABLE private_checkout.alani_delivery_location_test ENABLE ROW LEVEL SECURITY;
ALTER TABLE private_checkout.alani_order_notification_reads_test ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private_checkout.alani_delivery_location_test,private_checkout.alani_order_notification_reads_test FROM PUBLIC,anon,authenticated;
CREATE FUNCTION public.alani_publish_location_test(p_order_id uuid,p_lat double precision,p_lon double precision,p_accuracy_m double precision,p_consent boolean)
RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE a uuid:=auth.uid(); o public.orders%ROWTYPE; j public.alani_delivery_jobs%ROWTYPE;
BEGIN
 IF a IS NULL THEN RAISE EXCEPTION 'LOGIN_REQUIRED'; END IF;
 SELECT * INTO o FROM public.orders WHERE id=p_order_id AND store_id='25091ca2-c0da-416c-b634-81b188ee66be'::uuid FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'ORDER_NOT_AVAILABLE'; END IF;
 SELECT * INTO j FROM public.alani_delivery_jobs WHERE order_id=o.id;
 IF j.courier_id IS DISTINCT FROM a THEN RAISE EXCEPTION 'PERMISSION_DENIED'; END IF;
 IF p_consent IS FALSE THEN
  DELETE FROM private_checkout.alani_delivery_location_test WHERE order_id=o.id AND courier_id=a;
  RETURN 'stopped';
 END IF;
 IF p_consent IS DISTINCT FROM true THEN RAISE EXCEPTION 'CONSENT_REQUIRED'; END IF;
 IF o.status<>'out_for_delivery' OR j.picked_up_at IS NULL OR NOT EXISTS(SELECT 1 FROM public.alani_delivery_couriers c WHERE c.store_id=o.store_id AND c.courier_id=a AND c.enabled) THEN RAISE EXCEPTION 'DELIVERY_NOT_ACTIVE'; END IF;
 IF p_lat IS NULL OR p_lon IS NULL OR p_accuracy_m IS NULL OR NOT(p_lat BETWEEN -90 AND 90 AND p_lon BETWEEN -180 AND 180 AND p_accuracy_m BETWEEN 0 AND 1000) THEN RAISE EXCEPTION 'INVALID_LOCATION'; END IF;
 IF EXISTS(SELECT 1 FROM private_checkout.alani_delivery_location_test WHERE order_id=o.id AND updated_at>clock_timestamp()-interval '10 seconds') THEN RETURN 'rate_limited'; END IF;
 INSERT INTO private_checkout.alani_delivery_location_test(order_id,courier_id,latitude,longitude,accuracy_m) VALUES(o.id,a,p_lat,p_lon,p_accuracy_m)
 ON CONFLICT(order_id) DO UPDATE SET courier_id=excluded.courier_id,latitude=excluded.latitude,longitude=excluded.longitude,accuracy_m=excluded.accuracy_m,updated_at=clock_timestamp();
 RETURN 'published';
END $$;
CREATE FUNCTION public.alani_read_location_test(p_order_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE a uuid:=auth.uid(); result jsonb;
BEGIN
 IF a IS NULL THEN RAISE EXCEPTION 'LOGIN_REQUIRED'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.orders o WHERE o.id=p_order_id AND o.buyer_id=a AND o.store_id='25091ca2-c0da-416c-b634-81b188ee66be'::uuid) THEN RAISE EXCEPTION 'ORDER_NOT_AVAILABLE'; END IF;
 SELECT jsonb_build_object('latitude',l.latitude,'longitude',l.longitude,'accuracy_m',l.accuracy_m,'updated_at',l.updated_at) INTO result
 FROM private_checkout.alani_delivery_location_test l JOIN public.orders o ON o.id=l.order_id JOIN public.alani_delivery_jobs j ON j.order_id=o.id AND j.courier_id=l.courier_id
 JOIN public.alani_delivery_couriers c ON c.store_id=o.store_id AND c.courier_id=l.courier_id AND c.enabled
 WHERE o.id=p_order_id AND o.status='out_for_delivery' AND j.picked_up_at IS NOT NULL AND l.updated_at>clock_timestamp()-interval '90 seconds';
 RETURN result;
END $$;
CREATE FUNCTION private_checkout.alani_clear_location_test()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN
 IF NEW.status<>'out_for_delivery' THEN DELETE FROM private_checkout.alani_delivery_location_test WHERE order_id=NEW.id; END IF;
 RETURN NEW;
END $$;
REVOKE ALL ON FUNCTION private_checkout.alani_clear_location_test() FROM PUBLIC,anon,authenticated;
CREATE TRIGGER alani_clear_location_test AFTER UPDATE OF status ON public.orders FOR EACH ROW EXECUTE FUNCTION private_checkout.alani_clear_location_test();
CREATE FUNCTION public.alani_order_notifications_test()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE a uuid:=auth.uid(); result jsonb;
BEGIN
 IF a IS NULL THEN RAISE EXCEPTION 'LOGIN_REQUIRED'; END IF;
 SELECT coalesce(jsonb_agg(to_jsonb(t) ORDER BY t.changed_at DESC,t.event_id),'[]'::jsonb) INTO result FROM (
 SELECT h.id AS event_id,h.order_id,h.new_status,h.changed_at,r.read_at IS NOT NULL AS is_read
 FROM public.order_status_history h JOIN public.orders o ON o.id=h.order_id
 LEFT JOIN private_checkout.alani_order_notification_reads_test r ON r.event_id=h.id AND r.user_id=a
 WHERE o.buyer_id=a AND o.store_id='25091ca2-c0da-416c-b634-81b188ee66be'::uuid ORDER BY h.changed_at DESC,h.id LIMIT 100
 ) t;
 RETURN result;
END $$;
CREATE FUNCTION public.alani_read_notification_test(p_event_id uuid)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE a uuid:=auth.uid();
BEGIN
 IF a IS NULL THEN RAISE EXCEPTION 'LOGIN_REQUIRED'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.order_status_history h JOIN public.orders o ON o.id=h.order_id WHERE h.id=p_event_id AND o.buyer_id=a AND o.store_id='25091ca2-c0da-416c-b634-81b188ee66be'::uuid) THEN RAISE EXCEPTION 'NOTIFICATION_NOT_AVAILABLE'; END IF;
 INSERT INTO private_checkout.alani_order_notification_reads_test(user_id,event_id) VALUES(a,p_event_id) ON CONFLICT DO NOTHING;
 RETURN true;
END $$;
REVOKE ALL ON FUNCTION public.alani_publish_location_test(uuid,double precision,double precision,double precision,boolean),public.alani_read_location_test(uuid),public.alani_order_notifications_test(),public.alani_read_notification_test(uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.alani_publish_location_test(uuid,double precision,double precision,double precision,boolean),public.alani_read_location_test(uuid),public.alani_order_notifications_test(),public.alani_read_notification_test(uuid) TO authenticated;
