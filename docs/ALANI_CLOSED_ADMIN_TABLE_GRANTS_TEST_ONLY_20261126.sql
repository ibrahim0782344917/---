-- TEST ONLY: remove redundant API grants from four closed, RLS-protected admin/audit tables.
DO $$ BEGIN
 IF to_regclass('private_checkout.alani_wallet_accounts_test') IS NULL OR to_regclass('private_checkout.alani_fcm_gate') IS NOT NULL THEN RAISE EXCEPTION 'TEST_ONLY_REQUIRED'; END IF;
 IF EXISTS(SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename IN ('shitreed_admin_activity','shitreed_admin_staff','shitreed_profile_admin_audit','store_review_audit')) THEN RAISE EXCEPTION 'POLICY_CHANGED'; END IF;
END $$;
REVOKE ALL ON public.shitreed_admin_activity,public.shitreed_admin_staff,public.shitreed_profile_admin_audit,public.store_review_audit FROM PUBLIC,anon,authenticated;
