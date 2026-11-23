-- Shitreed pre-publish security pass; test project tgvdwotbrnhcoykuxdpr ONLY.
-- For user-callable RPCs, require a signed-in role (internal auth.uid() and
-- ownership/admin checks still apply). Internal helpers only run via trigger,
-- privileged wrapper, or server service_role. No production deploy.
BEGIN;
DO $guard$
DECLARE
 r record;
 v_found integer;
 v_remaining integer;
 v_names text[] := ARRAY['alani_can_moderate','alani_edit_own_comment','alani_rate_publication','alani_report_content','alani_save_writer_draft','alani_social_assert_published','alani_social_summary','alani_submit_comment','alani_toggle_reaction','shitreed_alani_checkout_schema_ready','shitreed_merchant_open_ticket','shitreed_merchant_request_deletion','shitreed_my_store_contacts','shitreed_pending_store_reviews','shitreed_profile_after_write','shitreed_review_store','try_consume_google_places_budget','try_consume_shitreed_osm_quota'];
 v_internal text[] := ARRAY['create_customer_profile','rls_auto_enable','shitreed_log_order_status','shitreed_profile_after_write','alani_social_assert_published','try_consume_google_places_budget','try_consume_shitreed_osm_quota'];
BEGIN
 SELECT count(*) INTO v_found FROM pg_catalog.pg_proc p
 JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.prosecdef AND p.proname=ANY(v_names);
 IF v_found<>18 THEN
  RAISE EXCEPTION 'EXPECTED_18_ANON_DEFINER_FUNCTIONS_FOUND_%',v_found;
 END IF;

 FOR r IN SELECT p.oid::regprocedure AS signature,p.proname AS name
    FROM pg_catalog.pg_proc p
    JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public' AND p.prosecdef AND p.proname=ANY(v_names)
 LOOP
   EXECUTE format('REVOKE EXECUTE ON FUNCTION %s FROM PUBLIC, anon',r.signature);
   -- Re-grant deliberately for signed-in user-facing operations.
   IF r.name=ANY(v_internal) THEN
     EXECUTE format('REVOKE EXECUTE ON FUNCTION %s FROM authenticated',r.signature);
   ELSE
     EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO authenticated',r.signature);
   END IF;
   EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO service_role',r.signature);
 END LOOP;

 -- Other internal trigger/event-trigger helpers were already hidden from anon,
 -- but could still be directly called by arbitrary signed-in users.
 FOR r IN SELECT p.oid::regprocedure AS signature,p.proname AS name
    FROM pg_catalog.pg_proc p
    JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public' AND p.prosecdef
       AND p.proname IN ('create_customer_profile','rls_auto_enable','shitreed_log_order_status')
 LOOP
    EXECUTE format('REVOKE EXECUTE ON FUNCTION %s FROM PUBLIC, anon, authenticated',r.signature);
    EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO service_role',r.signature);
 END LOOP;
 SELECT count(*) INTO v_remaining FROM pg_catalog.pg_proc p
 JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.prosecdef AND
  pg_catalog.has_function_privilege('anon',p.oid,'EXECUTE');
 IF v_remaining<>0 THEN
   RAISE EXCEPTION 'PUBLIC_DEFINER_RPC_STILL_ACCESSIBLE_%',v_remaining;
 END IF;
END
$guard$;
COMMIT;
