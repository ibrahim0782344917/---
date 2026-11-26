-- PRODUCTION additive chat foundation. No existing records modified.
-- Client privileges remain CLOSED at the end of this transaction.
BEGIN;
SET LOCAL lock_timeout='3s';
SET LOCAL statement_timeout='30s';
DO $guard$ BEGIN
 IF NOT EXISTS(SELECT 1 FROM public.stores WHERE id='25091ca2-c0da-416c-b634-81b188ee66be' AND status='approved' AND owner_id IS NOT NULL)
 OR NOT public.shitreed_alani_checkout_schema_ready()
 OR to_regclass('public.alani_support_threads') IS NOT NULL
 OR to_regclass('public.alani_support_messages') IS NOT NULL
 OR to_regclass('public.alani_support_read_receipts') IS NOT NULL
 OR to_regclass('private_checkout.alani_support_presence') IS NOT NULL
 OR EXISTS(SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname LIKE 'alani_%support%')
 THEN RAISE EXCEPTION 'PRODUCTION_CHAT_PREFLIGHT_FAILED'; END IF;
END $guard$;

CREATE TABLE public.alani_support_threads (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 store_id uuid NOT NULL REFERENCES public.stores(id) ON DELETE RESTRICT,
 customer_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
 created_at timestamptz NOT NULL DEFAULT now(),
 updated_at timestamptz NOT NULL DEFAULT now(),
 CONSTRAINT alani_support_only_approved_branch CHECK
  (store_id='25091ca2-c0da-416c-b634-81b188ee66be'::uuid),
 UNIQUE(store_id,customer_id)
);
CREATE INDEX alani_support_threads_recent_idx ON public.alani_support_threads
 (store_id,updated_at DESC);
ALTER TABLE public.alani_support_threads ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.alani_support_threads FROM PUBLIC,anon,authenticated;
GRANT SELECT ON public.alani_support_threads TO authenticated;
CREATE POLICY alani_support_thread_participants
 ON public.alani_support_threads FOR SELECT TO authenticated USING (
 customer_id=(SELECT auth.uid())
 OR EXISTS(SELECT 1 FROM public.stores s WHERE s.id=store_id
   AND s.owner_id=(SELECT auth.uid()))
 OR (SELECT public.shitreed_is_admin())
);

CREATE TABLE public.alani_support_messages (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 thread_id uuid NOT NULL REFERENCES public.alani_support_threads(id)
   ON DELETE RESTRICT,
 sender_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
 body text NOT NULL CHECK (char_length(btrim(body)) BETWEEN 1 AND 1500),
 created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX alani_support_messages_thread_time_idx
 ON public.alani_support_messages(thread_id,created_at DESC,id);
CREATE INDEX alani_support_messages_sender_time_idx
 ON public.alani_support_messages(sender_id,created_at DESC);
ALTER TABLE public.alani_support_messages ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.alani_support_messages FROM PUBLIC,anon,authenticated;
GRANT SELECT ON public.alani_support_messages TO authenticated;
CREATE POLICY alani_support_message_participants
 ON public.alani_support_messages FOR SELECT TO authenticated USING (
 EXISTS(SELECT 1 FROM public.alani_support_threads t WHERE t.id=thread_id)
);

CREATE OR REPLACE FUNCTION public.alani_open_support_thread()
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $f$
DECLARE
 v_actor uuid:=(SELECT auth.uid());
 v_store constant uuid:='25091ca2-c0da-416c-b634-81b188ee66be'::uuid;
 v_id uuid;
BEGIN
 IF v_actor IS NULL THEN RAISE EXCEPTION 'LOGIN_REQUIRED'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.stores s
   WHERE s.id=v_store AND s.status='approved')
 THEN RAISE EXCEPTION 'STORE_UNAVAILABLE'; END IF;
 IF EXISTS(SELECT 1 FROM public.stores s
   WHERE s.id=v_store AND s.owner_id=v_actor)
   OR public.shitreed_is_admin()
 THEN RAISE EXCEPTION 'USE_STAFF_INBOX'; END IF;
 INSERT INTO public.alani_support_threads(store_id,customer_id)
 VALUES(v_store,v_actor)
 ON CONFLICT(store_id,customer_id)
 DO UPDATE SET updated_at=public.alani_support_threads.updated_at
 RETURNING id INTO v_id;
 RETURN v_id;
END $f$;
REVOKE ALL ON FUNCTION public.alani_open_support_thread()
 FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.alani_open_support_thread() TO authenticated;

CREATE OR REPLACE FUNCTION public.alani_send_support_message(
 p_thread_id uuid,p_body text
) RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $f$
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
 IF v_thread.customer_id<>v_actor
  AND NOT EXISTS(SELECT 1 FROM public.stores s
    WHERE s.id=v_thread.store_id AND s.owner_id=v_actor)
  AND NOT public.shitreed_is_admin()
 THEN RAISE EXCEPTION 'PERMISSION_DENIED'; END IF;
 IF (SELECT count(*) FROM public.alani_support_messages
   WHERE thread_id=p_thread_id AND sender_id=v_actor
     AND created_at>now()-interval '1 minute')>=12
 THEN RAISE EXCEPTION 'RATE_LIMIT'; END IF;
 INSERT INTO public.alani_support_messages(thread_id,sender_id,body)
 VALUES(p_thread_id,v_actor,btrim(p_body)) RETURNING id INTO v_id;
 UPDATE public.alani_support_threads SET updated_at=now()
 WHERE id=p_thread_id;
 RETURN v_id;
END $f$;
REVOKE ALL ON FUNCTION public.alani_send_support_message(uuid,text)
 FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.alani_send_support_message(uuid,text)
 TO authenticated;
COMMENT ON TABLE public.alani_support_threads IS
 'Private store customer support threads: participant-only access.';
COMMENT ON TABLE public.alani_support_messages IS
 'Private text messages through rate-limited authenticated RPC.';


CREATE TABLE IF NOT EXISTS public.alani_support_read_receipts (
  thread_id uuid NOT NULL REFERENCES public.alani_support_threads(id)
    ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  last_read_at timestamptz NOT NULL,
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (thread_id, user_id)
);
CREATE INDEX IF NOT EXISTS alani_support_read_receipts_user_idx
  ON public.alani_support_read_receipts(user_id,updated_at DESC);
ALTER TABLE public.alani_support_read_receipts ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.alani_support_read_receipts FROM PUBLIC,anon,authenticated;
-- No direct Data API access, not even to the authenticated role.
-- Only authenticated, participant-validated SECURITY DEFINER RPCs can touch receipts.

CREATE OR REPLACE FUNCTION public.alani_mark_support_read(
  p_thread_id uuid, p_last_seen_message_id uuid
) RETURNS timestamptz LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO '' AS $read$
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
    ) AND NOT public.shitreed_is_admin()
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
END $read$;
REVOKE ALL ON FUNCTION public.alani_mark_support_read(uuid,uuid)
  FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.alani_mark_support_read(uuid,uuid)
  TO authenticated;

CREATE OR REPLACE FUNCTION public.alani_support_unread_counts()
RETURNS TABLE(thread_id uuid, unread_count bigint)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO '' AS $unread$
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
      OR public.shitreed_is_admin()
    ORDER BY t.updated_at DESC
    LIMIT 100;
END $unread$;
REVOKE ALL ON FUNCTION public.alani_support_unread_counts()
  FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.alani_support_unread_counts()
  TO authenticated;
COMMENT ON TABLE public.alani_support_read_receipts IS
  'Private chat read positions. Client cannot read or write rows directly.';
COMMENT ON FUNCTION public.alani_mark_support_read(uuid,uuid) IS
  'Mark only a participant-visible, known message as read, preventing refresh race.';
COMMENT ON FUNCTION public.alani_support_unread_counts() IS
  'Return per-actor unread totals only for the actor''s allowed support threads.';


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

CREATE TABLE private_checkout.alani_support_presence (
 thread_id uuid NOT NULL REFERENCES public.alani_support_threads(id) ON DELETE CASCADE,
 user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
 last_seen_at timestamptz NOT NULL,
 typing_until timestamptz,
 PRIMARY KEY(thread_id,user_id)
);
ALTER TABLE private_checkout.alani_support_presence ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private_checkout.alani_support_presence FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION public.alani_support_presence_ping(p_thread_id uuid,p_typing boolean)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $f$
DECLARE v_actor uuid:=(SELECT auth.uid()); v_now timestamptz:=clock_timestamp();
BEGIN
 IF v_actor IS NULL OR p_typing IS NULL THEN RAISE EXCEPTION 'LOGIN_REQUIRED'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.alani_support_threads t JOIN public.stores s ON s.id=t.store_id WHERE t.id=p_thread_id AND s.status='approved' AND
 (t.customer_id=v_actor OR s.owner_id=v_actor OR COALESCE(public.shitreed_admin_role() IN ('super_admin','operations','support'),false))) THEN RAISE EXCEPTION 'PERMISSION_DENIED'; END IF;
 INSERT INTO private_checkout.alani_support_presence(thread_id,user_id,last_seen_at,typing_until)
 VALUES(p_thread_id,v_actor,v_now,CASE WHEN p_typing THEN v_now+interval '12 seconds' END)
 ON CONFLICT(thread_id,user_id) DO UPDATE SET last_seen_at=excluded.last_seen_at,typing_until=excluded.typing_until
 WHERE private_checkout.alani_support_presence.last_seen_at<=v_now-interval '2 seconds';
 RETURN true;
END $f$;
REVOKE ALL ON FUNCTION public.alani_support_presence_ping(uuid,boolean) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.alani_support_presence_ping(uuid,boolean) TO authenticated;

CREATE OR REPLACE FUNCTION public.alani_support_presence_read(p_thread_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO '' AS $f$
DECLARE v_actor uuid:=(SELECT auth.uid()); v_customer uuid; v_owner uuid; v_seen timestamptz; v_typing boolean; v_read timestamptz;
BEGIN
 IF v_actor IS NULL THEN RAISE EXCEPTION 'LOGIN_REQUIRED'; END IF;
 SELECT t.customer_id,s.owner_id INTO v_customer,v_owner FROM public.alani_support_threads t JOIN public.stores s ON s.id=t.store_id WHERE t.id=p_thread_id AND s.status='approved';
 IF v_customer IS NULL OR (v_customer<>v_actor AND v_owner IS DISTINCT FROM v_actor AND NOT COALESCE(public.shitreed_admin_role() IN ('super_admin','operations','support'),false)) THEN RAISE EXCEPTION 'PERMISSION_DENIED'; END IF;
 -- Customer sees only aggregate authorized team activity; staff see only the customer.
 SELECT max(p.last_seen_at),coalesce(bool_or(p.typing_until>now()),false) INTO v_seen,v_typing
 FROM private_checkout.alani_support_presence p
 WHERE p.thread_id=p_thread_id AND
 ((v_actor<>v_customer AND p.user_id=v_customer) OR
 (v_actor=v_customer AND p.user_id<>v_customer AND (p.user_id=v_owner OR EXISTS(SELECT 1 FROM auth.users u WHERE u.id=p.user_id AND u.raw_app_meta_data->>'shitreed_role'='admin') OR EXISTS(SELECT 1 FROM public.shitreed_admin_staff a WHERE a.user_id=p.user_id AND a.enabled AND a.staff_role IN ('operations','support')))));
 SELECT max(r.last_read_at) INTO v_read FROM public.alani_support_read_receipts r
 WHERE r.thread_id=p_thread_id AND
 ((v_actor<>v_customer AND r.user_id=v_customer) OR
 (v_actor=v_customer AND r.user_id<>v_customer AND (r.user_id=v_owner OR EXISTS(SELECT 1 FROM auth.users u WHERE u.id=r.user_id AND u.raw_app_meta_data->>'shitreed_role'='admin') OR EXISTS(SELECT 1 FROM public.shitreed_admin_staff a WHERE a.user_id=r.user_id AND a.enabled AND a.staff_role IN ('operations','support')))));
 RETURN jsonb_build_object('online',COALESCE(v_seen>now()-interval '45 seconds',false),'typing',v_typing,'last_seen_at',CASE WHEN v_seen>now()-interval '7 days' THEN date_trunc('minute',v_seen) END,'peer_read_at',v_read);
END $f$;
REVOKE ALL ON FUNCTION public.alani_support_presence_read(uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.alani_support_presence_read(uuid) TO authenticated;
ALTER PUBLICATION supabase_realtime ADD TABLE public.alani_support_messages,public.alani_support_threads;

-- Staged activation: keep realtime publication configured, but no client privileges.
REVOKE ALL ON public.alani_support_threads,public.alani_support_messages,public.alani_support_read_receipts,private_checkout.alani_support_presence FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.alani_open_support_thread(),public.alani_send_support_message(uuid,text),public.alani_mark_support_read(uuid,uuid),public.alani_support_unread_counts(),public.alani_support_presence_ping(uuid,boolean),public.alani_support_presence_read(uuid) FROM PUBLIC,anon,authenticated;
DO $verify$ BEGIN
 IF NOT public.shitreed_alani_checkout_schema_ready()
 OR EXISTS(SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE (n.nspname,c.relname) IN (('public','alani_support_threads'),('public','alani_support_messages'),('public','alani_support_read_receipts'),('private_checkout','alani_support_presence')) AND NOT c.relrowsecurity)
 OR has_table_privilege('authenticated','public.alani_support_messages','SELECT')
 OR has_function_privilege('authenticated','public.alani_open_support_thread()','EXECUTE')
 THEN RAISE EXCEPTION 'PRODUCTION_CHAT_POSTCHECK_FAILED'; END IF;
END $verify$;
COMMIT;
