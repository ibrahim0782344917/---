-- TEST ONLY: read-only location and notification catalog regression.
BEGIN READ ONLY;
DO $$ BEGIN
 IF (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname IN ('alani_customer_alerts_test','alani_order_notifications_test','alani_publish_location_test','alani_read_location_test','alani_read_notification_test') AND NOT has_function_privilege('anon',p.oid,'EXECUTE') AND has_function_privilege('authenticated',p.oid,'EXECUTE'))<>5 THEN RAISE EXCEPTION 'FAIL authenticated-only location and notification endpoints'; END IF;
 IF (SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='private_checkout' AND c.relname IN ('alani_delivery_location_test','alani_order_notification_reads_test') AND c.relrowsecurity AND NOT has_table_privilege('anon',c.oid,'SELECT,INSERT,UPDATE,DELETE') AND NOT has_table_privilege('authenticated',c.oid,'SELECT,INSERT,UPDATE,DELETE'))<>2 THEN RAISE EXCEPTION 'FAIL private location and read state'; END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='public' AND c.relname='alani_notification_preferences_test' AND c.relrowsecurity AND NOT has_table_privilege('anon',c.oid,'SELECT,INSERT,UPDATE,DELETE')) THEN RAISE EXCEPTION 'FAIL notification preferences'; END IF;
END $$;
SELECT 'PASS: 3 batch16 catalog assertions' AS result;
ROLLBACK;
