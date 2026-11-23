-- PRE-PUBLISH TEST ONLY: revoke anonymous execution of privileged RPC endpoints.
-- Admin operations remain available to signed-in accounts; each RPC must still
-- enforce its own internal admin authorization checks before production deployment.
BEGIN;
DO $secure$
DECLARE r RECORD;
BEGIN
  FOR r IN
    SELECT p.oid::regprocedure AS signature,
           p.proname AS name
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public' AND p.prosecdef AND (
      p.proname LIKE 'shitreed_admin_%'
      OR p.proname IN (
        'shitreed_is_admin',
        'change_cash_order_status',
        'place_cash_order_web',
        'shitreed_customer_request_deletion',
        'shitreed_customer_deletion_preflight',
        'alani_set_content_staff',
        'alani_publish_reviewed',
        'alani_moderate_comment',
        'alani_review_report',
        'rls_auto_enable',
        'shitreed_log_order_status',
        'create_customer_profile'
      )
    )
  LOOP
    EXECUTE format('REVOKE EXECUTE ON FUNCTION %s FROM PUBLIC, anon',r.signature);
    IF r.name NOT IN ('rls_auto_enable','shitreed_log_order_status','create_customer_profile') THEN
      EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO authenticated, service_role',r.signature);
    END IF;
  END LOOP;
END
$secure$;
COMMIT;
