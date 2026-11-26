-- TEST ONLY: read-only catalog regression after private checkout RLS hardening.
BEGIN READ ONLY;
DO $$ BEGIN
 IF NOT EXISTS (SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='private_checkout' AND c.relname='web_checkout_requests' AND c.relrowsecurity) THEN RAISE EXCEPTION 'FAIL checkout requests RLS'; END IF;
 IF EXISTS (SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname IN ('private_checkout','public') AND c.relkind IN ('r','p') AND NOT c.relrowsecurity) THEN RAISE EXCEPTION 'FAIL public/private RLS coverage'; END IF;
 IF EXISTS (SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='private_checkout' AND c.relkind IN ('r','p') AND (has_table_privilege('anon',c.oid,'SELECT,INSERT,UPDATE,DELETE') OR has_table_privilege('authenticated',c.oid,'SELECT,INSERT,UPDATE,DELETE'))) THEN RAISE EXCEPTION 'FAIL private direct client grants'; END IF;
 IF NOT public.shitreed_alani_checkout_schema_ready() THEN RAISE EXCEPTION 'FAIL checkout schema readiness'; END IF;
 IF EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.prosecdef AND has_function_privilege('anon',p.oid,'EXECUTE')) THEN RAISE EXCEPTION 'FAIL anonymous definer execution'; END IF;
 IF EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.prosecdef AND NOT EXISTS(SELECT 1 FROM unnest(p.proconfig) c WHERE c LIKE 'search_path=%')) THEN RAISE EXCEPTION 'FAIL missing search path'; END IF;
END $$;
SELECT 'PASS: 6 batch15 catalog assertions' AS result;
ROLLBACK;
