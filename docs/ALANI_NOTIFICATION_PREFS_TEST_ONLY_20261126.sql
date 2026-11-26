-- TEST ONLY: user preference storage for future push delivery.
-- No device tokens, FCM credentials, or network sending.
CREATE TABLE public.alani_notification_preferences_test(
 user_id uuid PRIMARY KEY DEFAULT auth.uid() REFERENCES auth.users(id) ON DELETE CASCADE,
 order_updates boolean NOT NULL DEFAULT false,
 favorite_updates boolean NOT NULL DEFAULT false,
 monthly_reviews boolean NOT NULL DEFAULT false
);
ALTER TABLE public.alani_notification_preferences_test ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.alani_notification_preferences_test FROM PUBLIC,anon,authenticated;
GRANT SELECT,INSERT,UPDATE ON public.alani_notification_preferences_test TO authenticated;
CREATE POLICY alani_notification_prefs_select_test ON public.alani_notification_preferences_test
 FOR SELECT TO authenticated USING ((SELECT auth.uid())=user_id);
CREATE POLICY alani_notification_prefs_insert_test ON public.alani_notification_preferences_test
 FOR INSERT TO authenticated WITH CHECK ((SELECT auth.uid())=user_id);
CREATE POLICY alani_notification_prefs_update_test ON public.alani_notification_preferences_test
 FOR UPDATE TO authenticated USING ((SELECT auth.uid())=user_id) WITH CHECK ((SELECT auth.uid())=user_id);
