-- Tests fail with an exception if role isolation or messaging is wrong.
SELECT 1/CASE WHEN
  NOT has_table_privilege('anon','public.alani_support_messages','SELECT')
  AND NOT has_table_privilege('anon','public.alani_support_threads','SELECT')
  AND NOT has_table_privilege('authenticated','public.alani_support_messages','INSERT')
  AND NOT has_table_privilege('authenticated','public.alani_support_threads','INSERT')
 THEN 1 ELSE 0 END AS direct_access_closed;

SET ROLE anon;
DO $anon$
BEGIN
 BEGIN
  PERFORM public.alani_open_support_thread();
  RAISE EXCEPTION 'ANON_OPEN_BYPASS';
 EXCEPTION WHEN insufficient_privilege THEN NULL;
 END;
 BEGIN
  PERFORM public.alani_send_support_message(
   '11111111-1111-4111-8111-111111111111','test');
  RAISE EXCEPTION 'ANON_SEND_BYPASS';
 EXCEPTION WHEN insufficient_privilege THEN NULL;
 END;
END $anon$;
RESET ROLE;

SELECT set_config('request.jwt.claim.sub',
 'cccccccc-cccc-4ccc-8ccc-cccccccccccc',false);
SET ROLE authenticated;
SELECT set_config('test.support_thread',
  public.alani_open_support_thread()::text,false);
SELECT 1/CASE WHEN count(*)=1 THEN 1 ELSE 0 END AS customer_sees_self
 FROM public.alani_support_threads;
SELECT public.alani_send_support_message(
 current_setting('test.support_thread')::uuid,
 'Test customer asks about an order.');
SELECT 1/CASE WHEN count(*)=1 THEN 1 ELSE 0 END AS buyer_sees_message
 FROM public.alani_support_messages;
RESET ROLE;

SELECT set_config('request.jwt.claim.sub',
 'dddddddd-dddd-4ddd-8ddd-dddddddddddd',false);
SET ROLE authenticated;
SELECT 1/CASE WHEN count(*)=0 THEN 1 ELSE 0 END AS other_customer_no_threads
 FROM public.alani_support_threads;
SELECT 1/CASE WHEN count(*)=0 THEN 1 ELSE 0 END AS other_customer_no_messages
 FROM public.alani_support_messages;
DO $cross$
BEGIN
 BEGIN
  PERFORM public.alani_send_support_message(
   current_setting('test.support_thread')::uuid,'bypass attempt');
  RAISE EXCEPTION 'CROSS_CUSTOMER_SEND_BYPASS';
 EXCEPTION WHEN OTHERS THEN
  IF SQLERRM<>'PERMISSION_DENIED' THEN RAISE; END IF;
 END;
END $cross$;
RESET ROLE;

SELECT set_config('request.jwt.claim.sub',
 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',false);
SET ROLE authenticated;
SELECT 1/CASE WHEN count(*)=1 THEN 1 ELSE 0 END AS owner_sees_thread
 FROM public.alani_support_threads;
SELECT public.alani_send_support_message(
 current_setting('test.support_thread')::uuid,
 'Test store owner response.');
SELECT 1/CASE WHEN count(*)=2 THEN 1 ELSE 0 END AS owner_can_reply
 FROM public.alani_support_messages;
RESET ROLE;

SELECT set_config('request.jwt.claim.sub',
 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee',false);
SET ROLE authenticated;
SELECT 1/CASE WHEN count(*)=1 THEN 1 ELSE 0 END AS admin_inbox_access
 FROM public.alani_support_threads;
SELECT 1/CASE WHEN count(*)=2 THEN 1 ELSE 0 END AS admin_can_read
 FROM public.alani_support_messages;
RESET ROLE;

SELECT 'PASS: anon blocked; buyer private; staff reply; admin authorized' AS result;
