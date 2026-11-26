-- Emergency disable only. Preserves all conversations, messages and receipts.
BEGIN;
SET LOCAL lock_timeout='3s';
REVOKE EXECUTE ON FUNCTION public.alani_open_support_thread(),public.alani_send_support_message(uuid,text),public.alani_mark_support_read(uuid,uuid),public.alani_support_unread_counts(),public.alani_support_presence_ping(uuid,boolean),public.alani_support_presence_read(uuid) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON public.alani_support_threads,public.alani_support_messages,public.alani_support_read_receipts,private_checkout.alani_support_presence FROM PUBLIC,anon,authenticated;
COMMIT;
