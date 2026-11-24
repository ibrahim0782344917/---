-- TEST ENVIRONMENT ONLY. Applied and smoke-tested on shitreed-test.
-- Production must NOT run this before verified restore and RLS review.
-- Customer and store-owner/admin support chat. No phone numbers or push.
BEGIN;
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
 'Test-only private store customer support threads: participant-only access.';
COMMENT ON TABLE public.alani_support_messages IS
 'Test-only private text messages through rate-limited authenticated RPC.';
COMMIT;
