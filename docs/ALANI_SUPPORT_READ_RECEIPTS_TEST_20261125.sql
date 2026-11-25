-- TEST/QA ONLY: unread message counts and read acknowledgements for Al-Ani support chat.
-- Do not apply to production until a verified backup has been restored and RLS reviewed.
-- Acknowledgements refer to an actual fetched message, never to 'now()':
-- messages arriving during a refresh cannot accidentally become marked as read.
BEGIN;
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
  'Private TEST-only chat read positions. Client cannot read or write rows directly.';
COMMENT ON FUNCTION public.alani_mark_support_read(uuid,uuid) IS
  'Mark only a participant-visible, known message as read, preventing refresh race.';
COMMENT ON FUNCTION public.alani_support_unread_counts() IS
  'Return per-actor unread totals only for the actor''s allowed support threads.';
COMMIT;
