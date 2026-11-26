-- Catalog-only readiness check. Preserve existing EXECUTE grants; no private schema grants.
SET LOCAL lock_timeout='3s';
CREATE OR REPLACE FUNCTION public.shitreed_alani_checkout_schema_ready() RETURNS boolean LANGUAGE sql STABLE SECURITY INVOKER SET search_path TO '' AS $f$
SELECT EXISTS(SELECT 1 FROM pg_catalog.pg_attribute a WHERE a.attrelid='public.orders'::pg_catalog.regclass AND a.attname='delivery_fee_iqd' AND NOT a.attisdropped)
AND EXISTS(SELECT 1 FROM pg_catalog.pg_class c JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='private_checkout' AND c.relname='web_checkout_requests' AND c.relkind='r' AND c.relrowsecurity)
AND EXISTS(SELECT 1 FROM pg_catalog.pg_proc p WHERE p.oid=pg_catalog.to_regprocedure('public.place_alani_cash_order(jsonb,text,text,text,uuid,bigint)') AND pg_catalog.has_function_privilege('authenticated',p.oid,'EXECUTE') AND NOT pg_catalog.has_function_privilege('anon',p.oid,'EXECUTE'));
$f$;
DO $$ BEGIN IF public.shitreed_alani_checkout_schema_ready() IS DISTINCT FROM true THEN RAISE EXCEPTION 'production readiness changed'; END IF; END $$;