-- Production port of order-history inbox and read acknowledgments.
-- Does not change order status, send push notifications or import TEST data.
BEGIN;
SET LOCAL lock_timeout='3s';
SET LOCAL statement_timeout='30s';
DO $guard$ BEGIN
 IF NOT public.shitreed_alani_checkout_schema_ready()
 OR to_regclass('private_checkout.alani_order_notification_reads') IS NOT NULL
 OR to_regprocedure('public.alani_order_notifications()') IS NOT NULL
 OR to_regprocedure('public.alani_read_notification(uuid)') IS NOT NULL
 THEN RAISE EXCEPTION 'ORDER_INBOX_PREFLIGHT_FAILED'; END IF;
END $guard$;
CREATE TABLE private_checkout.alani_order_notification_reads (
 user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
 event_id uuid NOT NULL REFERENCES public.order_status_history(id) ON DELETE CASCADE,
 read_at timestamptz NOT NULL DEFAULT now(),
 PRIMARY KEY(user_id,event_id)
);
ALTER TABLE private_checkout.alani_order_notification_reads ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private_checkout.alani_order_notification_reads FROM PUBLIC,anon,authenticated;
CREATE FUNCTION public.alani_order_notifications()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE a uuid:=auth.uid(); result jsonb;
BEGIN
 IF a IS NULL THEN RAISE EXCEPTION 'LOGIN_REQUIRED'; END IF;
 SELECT coalesce(jsonb_agg(to_jsonb(t) ORDER BY t.changed_at DESC,t.event_id),'[]'::jsonb) INTO result FROM (
 SELECT h.id AS event_id,h.order_id,h.new_status,h.changed_at,r.read_at IS NOT NULL AS is_read
 FROM public.order_status_history h JOIN public.orders o ON o.id=h.order_id
 LEFT JOIN private_checkout.alani_order_notification_reads r ON r.event_id=h.id AND r.user_id=a
 WHERE o.buyer_id=a AND o.store_id='25091ca2-c0da-416c-b634-81b188ee66be'::uuid ORDER BY h.changed_at DESC,h.id LIMIT 100
 ) t;
 RETURN result;
END $$;
CREATE FUNCTION public.alani_read_notification(p_event_id uuid)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE a uuid:=auth.uid();
BEGIN
 IF a IS NULL THEN RAISE EXCEPTION 'LOGIN_REQUIRED'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.order_status_history h JOIN public.orders o ON o.id=h.order_id WHERE h.id=p_event_id AND o.buyer_id=a AND o.store_id='25091ca2-c0da-416c-b634-81b188ee66be'::uuid) THEN RAISE EXCEPTION 'NOTIFICATION_NOT_AVAILABLE'; END IF;
 INSERT INTO private_checkout.alani_order_notification_reads(user_id,event_id) VALUES(a,p_event_id) ON CONFLICT DO NOTHING;
 RETURN true;
END $$;

REVOKE ALL ON FUNCTION public.alani_order_notifications(),public.alani_read_notification(uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.alani_order_notifications(),public.alani_read_notification(uuid) TO authenticated;
DO $verify$ BEGIN
 IF NOT (SELECT relrowsecurity FROM pg_class WHERE oid='private_checkout.alani_order_notification_reads'::regclass)
 OR has_table_privilege('authenticated','private_checkout.alani_order_notification_reads','SELECT,INSERT,UPDATE,DELETE')
 OR has_table_privilege('anon','private_checkout.alani_order_notification_reads','SELECT,INSERT,UPDATE,DELETE')
 OR has_function_privilege('anon','public.alani_order_notifications()','EXECUTE')
 OR has_function_privilege('anon','public.alani_read_notification(uuid)','EXECUTE')
 OR NOT has_function_privilege('authenticated','public.alani_order_notifications()','EXECUTE')
 OR NOT has_function_privilege('authenticated','public.alani_read_notification(uuid)','EXECUTE')
 OR NOT public.shitreed_alani_checkout_schema_ready()
 THEN RAISE EXCEPTION 'ORDER_INBOX_POSTCHECK_FAILED'; END IF;
END $verify$;
COMMIT;
