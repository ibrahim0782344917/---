-- Run AFTER synthetic fixture, support-chat schema and support-chat RLS checks.
-- Each assertion throws on bypass or unread-count miscalculation.
SELECT 1/CASE WHEN
  NOT has_table_privilege('anon','public.alani_support_read_receipts','SELECT')
  AND NOT has_table_privilege('authenticated','public.alani_support_read_receipts','SELECT')
  AND NOT has_table_privilege('authenticated','public.alani_support_read_receipts','INSERT')
THEN 1 ELSE 0 END AS direct_receipt_access_closed;

SET ROLE anon;
DO $anon$
BEGIN
  BEGIN
    PERFORM public.alani_support_unread_counts();
    RAISE EXCEPTION 'ANON_CAN_LIST_UNREAD';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
  BEGIN
    PERFORM public.alani_mark_support_read(
      '11111111-1111-4111-8111-111111111111',
      '22222222-2222-4222-8222-222222222222');
    RAISE EXCEPTION 'ANON_CAN_ACK';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
END $anon$;
RESET ROLE;

-- Customer sees only one incoming owner reply.
SELECT set_config('request.jwt.claim.sub',
 'cccccccc-cccc-4ccc-8ccc-cccccccccccc',false);
SET ROLE authenticated;
SELECT 1/CASE WHEN
  (SELECT unread_count FROM public.alani_support_unread_counts()
   WHERE thread_id=current_setting('test.support_thread')::uuid)=1
THEN 1 ELSE 0 END AS buyer_unread_one_reply;
SELECT public.alani_mark_support_read(
 current_setting('test.support_thread')::uuid,
 (SELECT id FROM public.alani_support_messages
  WHERE thread_id=current_setting('test.support_thread')::uuid
  ORDER BY created_at DESC,id DESC LIMIT 1));
SELECT 1/CASE WHEN
  (SELECT unread_count FROM public.alani_support_unread_counts()
   WHERE thread_id=current_setting('test.support_thread')::uuid)=0
THEN 1 ELSE 0 END AS buyer_read_ack_clears_incoming;
-- Re-ack an older loaded message must never move the read pointer backwards.
SELECT public.alani_mark_support_read(
 current_setting('test.support_thread')::uuid,
 (SELECT id FROM public.alani_support_messages
  WHERE thread_id=current_setting('test.support_thread')::uuid
  ORDER BY created_at ASC,id ASC LIMIT 1));
SELECT 1/CASE WHEN
  (SELECT unread_count FROM public.alani_support_unread_counts()
   WHERE thread_id=current_setting('test.support_thread')::uuid)=0
THEN 1 ELSE 0 END AS stale_ack_does_not_unread;
RESET ROLE;

-- Unrelated customer cannot see this support thread, its count, or acknowledge it.
SELECT set_config('request.jwt.claim.sub',
 'dddddddd-dddd-4ddd-8ddd-dddddddddddd',false);
SET ROLE authenticated;
SELECT 1/CASE WHEN
 (SELECT count(*) FROM public.alani_support_unread_counts())=0
THEN 1 ELSE 0 END AS cross_customer_no_unread;
DO $cross$
BEGIN
  BEGIN
    PERFORM public.alani_mark_support_read(
      current_setting('test.support_thread')::uuid,
      '22222222-2222-4222-8222-222222222222');
    RAISE EXCEPTION 'CROSS_CUSTOMER_ACK_BYPASS';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM<>'PERMISSION_DENIED' THEN RAISE; END IF;
  END;
END $cross$;
RESET ROLE;

SELECT set_config('request.jwt.claim.sub',
 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',false);
SET ROLE authenticated;
SELECT 1/CASE WHEN
 (SELECT unread_count FROM public.alani_support_unread_counts()
  WHERE thread_id=current_setting('test.support_thread')::uuid)=1
THEN 1 ELSE 0 END AS owner_unread_customer_request;
SELECT public.alani_mark_support_read(
 current_setting('test.support_thread')::uuid,
 (SELECT id FROM public.alani_support_messages
  WHERE thread_id=current_setting('test.support_thread')::uuid
  ORDER BY created_at DESC,id DESC LIMIT 1));
SELECT 1/CASE WHEN
 (SELECT unread_count FROM public.alani_support_unread_counts()
  WHERE thread_id=current_setting('test.support_thread')::uuid)=0
THEN 1 ELSE 0 END AS owner_ack_clears_unread;
RESET ROLE;

SELECT set_config('request.jwt.claim.sub',
 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee',false);
SET ROLE authenticated;
SELECT 1/CASE WHEN
 (SELECT unread_count FROM public.alani_support_unread_counts()
  WHERE thread_id=current_setting('test.support_thread')::uuid)=2
THEN 1 ELSE 0 END AS admin_has_independent_unread;
RESET ROLE;

SELECT 'PASS: unread counts private, read positions monotonic, cross-buyer blocked' AS result;
