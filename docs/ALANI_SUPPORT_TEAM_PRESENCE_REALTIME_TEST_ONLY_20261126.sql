-- TEST ONLY: team support, private per-thread presence and realtime.
-- No production or external notification activation.
BEGIN;
SET LOCAL lock_timeout='3s';
SET LOCAL statement_timeout='30s';
ALTER POLICY alani_support_thread_participants ON public.alani_support_threads USING (
 customer_id=(SELECT auth.uid()) OR EXISTS(SELECT 1 FROM public.stores s WHERE s.id=store_id AND s.owner_id=(SELECT auth.uid()))
 OR COALESCE((SELECT public.shitreed_admin_role()) IN ('super_admin','operations','support'),false)
);
CREATE OR REPLACE FUNCTION public.alani_mark_support_read(p_thread_id uuid, p_last_seen_message_id uuid)
 RETURNS timestamp with time zone
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_actor uuid := (SELECT auth.uid());
  v_customer uuid;
  v_store uuid;
  v_message_time timestamptz;
  v_saved_at timestamptz;
BEGIN
  IF v_actor IS NULL THEN RAISE EXCEPTION 'LOGIN_REQUIRED'; END IF;
  IF p_thread_id IS NULL OR p_last_seen_message_id IS NULL
  THEN RAISE EXCEPTION 'INVALID_READ_ACK'; END IF;
  SELECT customer_id,store_id INTO v_customer,v_store
    FROM public.alani_support_threads WHERE id=p_thread_id;
  IF v_customer IS NULL THEN RAISE EXCEPTION 'THREAD_NOT_FOUND'; END IF;
  IF v_customer<>v_actor AND NOT EXISTS (
      SELECT 1 FROM public.stores s
      WHERE s.id=v_store AND s.owner_id=v_actor
    ) AND NOT COALESCE(public.shitreed_admin_role() IN ('super_admin','operations','support'),false)
  THEN RAISE EXCEPTION 'PERMISSION_DENIED'; END IF;
  SELECT m.created_at INTO v_message_time
    FROM public.alani_support_messages m
    WHERE m.id=p_last_seen_message_id AND m.thread_id=p_thread_id;
  IF v_message_time IS NULL THEN RAISE EXCEPTION 'MESSAGE_NOT_IN_THREAD'; END IF;

  INSERT INTO public.alani_support_read_receipts (
    thread_id,user_id,last_read_at
  ) VALUES (p_thread_id,v_actor,v_message_time)
  ON CONFLICT (thread_id,user_id) DO UPDATE SET
    last_read_at=GREATEST(
      public.alani_support_read_receipts.last_read_at,
      EXCLUDED.last_read_at),
    updated_at=now()
  RETURNING last_read_at INTO v_saved_at;
  RETURN v_saved_at;
END $function$;

CREATE OR REPLACE FUNCTION public.alani_open_support_thread()
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
 v_actor uuid:=(SELECT auth.uid());
 v_store constant uuid:='25091ca2-c0da-416c-b634-81b188ee66be'::uuid;
 v_id uuid;
BEGIN
 IF v_actor IS NULL THEN RAISE EXCEPTION 'LOGIN_REQUIRED'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.stores s
   WHERE s.id=v_store AND s.status='approved') THEN
  RAISE EXCEPTION 'STORE_UNAVAILABLE'; END IF;
 IF EXISTS(SELECT 1 FROM public.stores s WHERE s.id=v_store AND s.owner_id=v_actor)
   OR COALESCE(public.shitreed_admin_role() IN ('super_admin','operations','support'),false) THEN
  RAISE EXCEPTION 'USE_STAFF_INBOX'; END IF;
 INSERT INTO public.alani_support_threads(store_id,customer_id)
 VALUES(v_store,v_actor) ON CONFLICT(store_id,customer_id)
 DO UPDATE SET updated_at=public.alani_support_threads.updated_at
 RETURNING id INTO v_id;
 RETURN v_id;
END $function$;

CREATE OR REPLACE FUNCTION public.alani_send_support_message(p_thread_id uuid, p_body text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
 v_actor uuid:=(SELECT auth.uid());
 v_thread public.alani_support_threads%ROWTYPE;
 v_id uuid;
BEGIN
 IF v_actor IS NULL THEN RAISE EXCEPTION 'LOGIN_REQUIRED'; END IF;
 IF p_thread_id IS NULL OR p_body IS NULL
  OR char_length(btrim(p_body)) NOT BETWEEN 1 AND 1500
 THEN RAISE EXCEPTION 'INVALID_MESSAGE'; END IF;
 SELECT * INTO v_thread FROM public.alani_support_threads
 WHERE id=p_thread_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'THREAD_NOT_FOUND'; END IF;
 IF v_thread.customer_id<>v_actor AND
  NOT EXISTS(SELECT 1 FROM public.stores s
    WHERE s.id=v_thread.store_id AND s.owner_id=v_actor)
  AND NOT COALESCE(public.shitreed_admin_role() IN ('super_admin','operations','support'),false)
 THEN RAISE EXCEPTION 'PERMISSION_DENIED'; END IF;
 IF (SELECT count(*) FROM public.alani_support_messages
      WHERE thread_id=p_thread_id AND sender_id=v_actor
        AND created_at>now()-interval '1 minute')>=12
 THEN RAISE EXCEPTION 'RATE_LIMIT'; END IF;
 INSERT INTO public.alani_support_messages(thread_id,sender_id,body)
 VALUES(p_thread_id,v_actor,btrim(p_body)) RETURNING id INTO v_id;
 UPDATE public.alani_support_threads SET updated_at=now() WHERE id=p_thread_id;
 RETURN v_id;
END $function$;

CREATE OR REPLACE FUNCTION public.alani_support_unread_counts()
 RETURNS TABLE(thread_id uuid, unread_count bigint)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE v_actor uuid := (SELECT auth.uid());
BEGIN
  IF v_actor IS NULL THEN RAISE EXCEPTION 'LOGIN_REQUIRED'; END IF;
  RETURN QUERY
    SELECT t.id,(
      SELECT count(*)
      FROM public.alani_support_messages m
      WHERE m.thread_id=t.id AND m.sender_id<>v_actor
        AND m.created_at>COALESCE(r.last_read_at,'-infinity'::timestamptz)
    )
    FROM public.alani_support_threads t
    LEFT JOIN public.alani_support_read_receipts r
      ON r.thread_id=t.id AND r.user_id=v_actor
    WHERE t.customer_id=v_actor
      OR EXISTS (
        SELECT 1 FROM public.stores s
        WHERE s.id=t.store_id AND s.owner_id=v_actor
      )
      OR COALESCE(public.shitreed_admin_role() IN ('super_admin','operations','support'),false)
    ORDER BY t.updated_at DESC
    LIMIT 100;
END $function$;

CREATE TABLE private_checkout.alani_support_presence_test (
 thread_id uuid NOT NULL REFERENCES public.alani_support_threads(id) ON DELETE CASCADE,
 user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
 last_seen_at timestamptz NOT NULL,
 typing_until timestamptz,
 PRIMARY KEY(thread_id,user_id)
);
ALTER TABLE private_checkout.alani_support_presence_test ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private_checkout.alani_support_presence_test FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION public.alani_support_presence_ping_test(p_thread_id uuid,p_typing boolean)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $f$
DECLARE v_actor uuid:=(SELECT auth.uid()); v_now timestamptz:=clock_timestamp();
BEGIN
 IF v_actor IS NULL OR p_typing IS NULL THEN RAISE EXCEPTION 'LOGIN_REQUIRED'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.alani_support_threads t JOIN public.stores s ON s.id=t.store_id WHERE t.id=p_thread_id AND s.status='approved' AND
 (t.customer_id=v_actor OR s.owner_id=v_actor OR COALESCE(public.shitreed_admin_role() IN ('super_admin','operations','support'),false))) THEN RAISE EXCEPTION 'PERMISSION_DENIED'; END IF;
 INSERT INTO private_checkout.alani_support_presence_test(thread_id,user_id,last_seen_at,typing_until)
 VALUES(p_thread_id,v_actor,v_now,CASE WHEN p_typing THEN v_now+interval '12 seconds' END)
 ON CONFLICT(thread_id,user_id) DO UPDATE SET last_seen_at=excluded.last_seen_at,typing_until=excluded.typing_until
 WHERE private_checkout.alani_support_presence_test.last_seen_at<=v_now-interval '2 seconds';
 RETURN true;
END $f$;
REVOKE ALL ON FUNCTION public.alani_support_presence_ping_test(uuid,boolean) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.alani_support_presence_ping_test(uuid,boolean) TO authenticated;

CREATE OR REPLACE FUNCTION public.alani_support_presence_read_test(p_thread_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO '' AS $f$
DECLARE v_actor uuid:=(SELECT auth.uid()); v_customer uuid; v_owner uuid; v_seen timestamptz; v_typing boolean; v_read timestamptz;
BEGIN
 IF v_actor IS NULL THEN RAISE EXCEPTION 'LOGIN_REQUIRED'; END IF;
 SELECT t.customer_id,s.owner_id INTO v_customer,v_owner FROM public.alani_support_threads t JOIN public.stores s ON s.id=t.store_id WHERE t.id=p_thread_id AND s.status='approved';
 IF v_customer IS NULL OR (v_customer<>v_actor AND v_owner IS DISTINCT FROM v_actor AND NOT COALESCE(public.shitreed_admin_role() IN ('super_admin','operations','support'),false)) THEN RAISE EXCEPTION 'PERMISSION_DENIED'; END IF;
 -- Customer sees only aggregate authorized team activity; staff see only the customer.
 SELECT max(p.last_seen_at),coalesce(bool_or(p.typing_until>now()),false) INTO v_seen,v_typing
 FROM private_checkout.alani_support_presence_test p
 WHERE p.thread_id=p_thread_id AND
 ((v_actor<>v_customer AND p.user_id=v_customer) OR
 (v_actor=v_customer AND p.user_id<>v_customer AND (p.user_id=v_owner OR EXISTS(SELECT 1 FROM auth.users u WHERE u.id=p.user_id AND u.raw_app_meta_data->>'shitreed_role'='admin') OR EXISTS(SELECT 1 FROM public.shitreed_admin_staff a WHERE a.user_id=p.user_id AND a.enabled AND a.staff_role IN ('operations','support')))));
 SELECT max(r.last_read_at) INTO v_read FROM public.alani_support_read_receipts r
 WHERE r.thread_id=p_thread_id AND
 ((v_actor<>v_customer AND r.user_id=v_customer) OR
 (v_actor=v_customer AND r.user_id<>v_customer AND (r.user_id=v_owner OR EXISTS(SELECT 1 FROM auth.users u WHERE u.id=r.user_id AND u.raw_app_meta_data->>'shitreed_role'='admin') OR EXISTS(SELECT 1 FROM public.shitreed_admin_staff a WHERE a.user_id=r.user_id AND a.enabled AND a.staff_role IN ('operations','support')))));
 RETURN jsonb_build_object('online',COALESCE(v_seen>now()-interval '45 seconds',false),'typing',v_typing,'last_seen_at',CASE WHEN v_seen>now()-interval '7 days' THEN date_trunc('minute',v_seen) END,'peer_read_at',v_read);
END $f$;
REVOKE ALL ON FUNCTION public.alani_support_presence_read_test(uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.alani_support_presence_read_test(uuid) TO authenticated;
ALTER PUBLICATION supabase_realtime ADD TABLE public.alani_support_messages,public.alani_support_threads;
COMMIT;
