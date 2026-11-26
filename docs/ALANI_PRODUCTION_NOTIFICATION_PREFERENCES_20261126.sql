-- Production port of tested private notification preferences.
-- No device tokens, push delivery, external credential or order writes.
BEGIN;
SET LOCAL lock_timeout='3s';
DO $guard$ BEGIN
 IF NOT public.shitreed_alani_checkout_schema_ready() OR to_regclass('public.alani_notification_preferences') IS NOT NULL THEN RAISE EXCEPTION 'PREFS_PREFLIGHT_FAILED'; END IF;
END $guard$;
CREATE TABLE public.alani_notification_preferences(
 user_id uuid PRIMARY KEY DEFAULT auth.uid() REFERENCES auth.users(id) ON DELETE CASCADE,
 order_updates boolean NOT NULL DEFAULT false,
 favorite_updates boolean NOT NULL DEFAULT false,
 monthly_reviews boolean NOT NULL DEFAULT false
);
ALTER TABLE public.alani_notification_preferences ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.alani_notification_preferences FROM PUBLIC,anon,authenticated;
GRANT SELECT,INSERT,UPDATE ON public.alani_notification_preferences TO authenticated;
CREATE POLICY alani_notification_prefs_select ON public.alani_notification_preferences
 FOR SELECT TO authenticated USING ((SELECT auth.uid())=user_id);
CREATE POLICY alani_notification_prefs_insert ON public.alani_notification_preferences
 FOR INSERT TO authenticated WITH CHECK ((SELECT auth.uid())=user_id);
CREATE POLICY alani_notification_prefs_update ON public.alani_notification_preferences
 FOR UPDATE TO authenticated USING ((SELECT auth.uid())=user_id) WITH CHECK ((SELECT auth.uid())=user_id);

ALTER TABLE public.alani_notification_preferences ADD COLUMN support_updates boolean NOT NULL DEFAULT false;
DO $verify$ BEGIN
 IF NOT (SELECT relrowsecurity FROM pg_class WHERE oid='public.alani_notification_preferences'::regclass)
 OR has_table_privilege('anon','public.alani_notification_preferences','SELECT,INSERT,UPDATE,DELETE')
 OR has_table_privilege('authenticated','public.alani_notification_preferences','DELETE')
 OR (SELECT count(*) FROM pg_policies WHERE schemaname='public' AND tablename='alani_notification_preferences')<>3
 OR NOT public.shitreed_alani_checkout_schema_ready() THEN RAISE EXCEPTION 'PREFS_POSTCHECK_FAILED'; END IF;
END $verify$;
COMMIT;
