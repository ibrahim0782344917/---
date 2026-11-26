-- Production private chat pilot, authorized participants only.
-- Previously tested RPC and RLS definitions verified against TEST.
-- No chat messages, account changes, notifications or financial writes.
BEGIN;
SET LOCAL lock_timeout='3s';
SET LOCAL statement_timeout='30s';
DO $guard$ BEGIN
 IF NOT public.shitreed_alani_checkout_schema_ready()
 OR (SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE (n.nspname,c.relname) IN (('public','alani_support_threads'),('public','alani_support_messages'),('public','alani_support_read_receipts'),('private_checkout','alani_support_presence')) AND c.relrowsecurity)<>4
 OR (SELECT count(*) FROM pg_publication_tables WHERE pubname='supabase_realtime' AND schemaname='public' AND tablename IN ('alani_support_threads','alani_support_messages'))<>2
 OR (SELECT count(*) FROM pg_policies WHERE schemaname='public' AND tablename IN ('alani_support_threads','alani_support_messages') AND cmd='SELECT' AND roles=ARRAY['authenticated']::name[])<>2
 OR EXISTS(SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename IN ('alani_support_threads','alani_support_messages','alani_support_read_receipts') AND cmd<>'SELECT')
 OR EXISTS(SELECT 1 FROM public.alani_support_threads)
 OR EXISTS(SELECT 1 FROM public.alani_support_messages)
 THEN RAISE EXCEPTION 'CHAT_PILOT_PREFLIGHT_FAILED'; END IF;
END $guard$;
GRANT SELECT ON public.alani_support_threads,public.alani_support_messages TO authenticated;
GRANT EXECUTE ON FUNCTION public.alani_open_support_thread(),public.alani_send_support_message(uuid,text),public.alani_mark_support_read(uuid,uuid),public.alani_support_unread_counts(),public.alani_support_presence_ping(uuid,boolean),public.alani_support_presence_read(uuid) TO authenticated;
DO $verify$ BEGIN
 IF EXISTS(SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE c.relkind='r' AND (n.nspname,c.relname) IN (('public','alani_support_threads'),('public','alani_support_messages'),('public','alani_support_read_receipts'),('private_checkout','alani_support_presence')) AND (NOT c.relrowsecurity OR has_table_privilege('authenticated',c.oid,'INSERT,UPDATE,DELETE') OR has_table_privilege('anon',c.oid,'SELECT,INSERT,UPDATE,DELETE')))
 OR has_table_privilege('authenticated','private_checkout.alani_support_presence','SELECT')
 OR has_table_privilege('authenticated','public.alani_support_read_receipts','SELECT')
 OR (SELECT count(*) FROM pg_proc f JOIN pg_namespace n ON n.oid=f.pronamespace WHERE n.nspname='public' AND f.proname IN ('alani_open_support_thread','alani_send_support_message','alani_mark_support_read','alani_support_unread_counts','alani_support_presence_ping','alani_support_presence_read') AND has_function_privilege('authenticated',f.oid,'EXECUTE') AND NOT has_function_privilege('anon',f.oid,'EXECUTE'))<>6
 OR NOT public.shitreed_alani_checkout_schema_ready()
 THEN RAISE EXCEPTION 'CHAT_PILOT_POSTCHECK_FAILED'; END IF;
END $verify$;
COMMIT;
