-- Fresh local database, synthetic accounts only; no live data or credentials.
SELECT 1/CASE WHEN (SELECT count(*) FROM pg_publication_tables WHERE pubname='supabase_realtime' AND tablename IN ('alani_support_messages','alani_support_threads'))=2 THEN 1 ELSE 0 END AS realtime_tables;
SELECT 1/CASE WHEN NOT has_function_privilege('anon','public.alani_support_presence_read_test(uuid)','EXECUTE') AND NOT has_function_privilege('anon','public.alani_support_presence_ping_test(uuid,boolean)','EXECUTE') AND NOT has_table_privilege('authenticated','private_checkout.alani_support_presence_test','SELECT') THEN 1 ELSE 0 END AS private_presence;
SELECT set_config('request.jwt.claim.sub','bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',false);
SET ROLE authenticated;
SELECT 1/CASE WHEN count(*)=1 THEN 1 ELSE 0 END AS support_reads_thread FROM public.alani_support_threads;
SELECT public.alani_send_support_message(current_setting('test.support_thread')::uuid,'Synthetic support reply');
SELECT public.alani_support_presence_ping_test(current_setting('test.support_thread')::uuid,true);
SELECT public.alani_mark_support_read(current_setting('test.support_thread')::uuid,(SELECT id FROM public.alani_support_messages ORDER BY created_at DESC,id DESC LIMIT 1));
RESET ROLE;
SELECT set_config('request.jwt.claim.sub','cccccccc-cccc-4ccc-8ccc-cccccccccccc',false);
SET ROLE authenticated;
SELECT 1/CASE WHEN (public.alani_support_presence_read_test(current_setting('test.support_thread')::uuid)->>'online')::boolean AND (public.alani_support_presence_read_test(current_setting('test.support_thread')::uuid)->>'typing')::boolean AND public.alani_support_presence_read_test(current_setting('test.support_thread')::uuid)->>'peer_read_at' IS NOT NULL THEN 1 ELSE 0 END AS customer_sees_team_activity;
SELECT public.alani_support_presence_ping_test(current_setting('test.support_thread')::uuid,false);
RESET ROLE;
SELECT set_config('request.jwt.claim.sub','dddddddd-dddd-4ddd-8ddd-dddddddddddd',false);
SET ROLE authenticated;
SELECT 1/CASE WHEN count(*)=0 THEN 1 ELSE 0 END AS unrelated_customer_isolated FROM public.alani_support_messages;
DO $test$ BEGIN
 BEGIN
 PERFORM public.alani_support_presence_read_test(current_setting('test.support_thread')::uuid);
 RAISE EXCEPTION 'BYPASS';
 EXCEPTION WHEN OTHERS THEN IF SQLERRM<>'PERMISSION_DENIED' THEN RAISE; END IF; END;
 BEGIN
 PERFORM public.alani_support_presence_ping_test(current_setting('test.support_thread')::uuid,true);
 RAISE EXCEPTION 'BYPASS';
 EXCEPTION WHEN OTHERS THEN IF SQLERRM<>'PERMISSION_DENIED' THEN RAISE; END IF; END;
END $test$;
RESET ROLE;
UPDATE public.shitreed_admin_staff SET enabled=false WHERE user_id='bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
SELECT set_config('request.jwt.claim.sub','bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',false);
SET ROLE authenticated;
SELECT 1/CASE WHEN count(*)=0 THEN 1 ELSE 0 END AS disabled_support_isolated FROM public.alani_support_threads;
RESET ROLE;
SELECT set_config('request.jwt.claim.sub','cccccccc-cccc-4ccc-8ccc-cccccccccccc',false);
SET ROLE authenticated;
SELECT 1/CASE WHEN NOT (public.alani_support_presence_read_test(current_setting('test.support_thread')::uuid)->>'online')::boolean THEN 1 ELSE 0 END AS revoked_staff_presence_hidden;
RESET ROLE;
UPDATE private_checkout.alani_support_presence_test SET last_seen_at=now()-interval '8 days',typing_until=now()-interval '1 minute' WHERE user_id='cccccccc-cccc-4ccc-8ccc-cccccccccccc';
SELECT set_config('request.jwt.claim.sub','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',false);
SET ROLE authenticated;
SELECT 1/CASE WHEN NOT (public.alani_support_presence_read_test(current_setting('test.support_thread')::uuid)->>'online')::boolean AND NOT (public.alani_support_presence_read_test(current_setting('test.support_thread')::uuid)->>'typing')::boolean AND public.alani_support_presence_read_test(current_setting('test.support_thread')::uuid)->>'last_seen_at' IS NULL THEN 1 ELSE 0 END AS expired_presence_hidden;
RESET ROLE;
SELECT 'PASS: team permission, realtime publication, private presence, receipts, isolation and expiry' AS result;
