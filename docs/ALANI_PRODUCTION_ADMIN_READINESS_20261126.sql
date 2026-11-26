-- Production administrator readiness dashboard. Read-only catalog and approved status APIs.
BEGIN;
SET LOCAL lock_timeout='3s';
CREATE FUNCTION public.alani_admin_release_readiness()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path TO '' AS $f$
DECLARE w jsonb; chat_schema boolean; chat_active boolean; legacy_schema boolean; delivery_schema boolean; return_schema boolean; campaign_schema boolean; pos_schema boolean;
BEGIN
 IF auth.uid() IS NULL OR public.shitreed_admin_role() IS DISTINCT FROM 'super_admin' THEN RAISE EXCEPTION 'SUPER_ADMIN_REQUIRED'; END IF;
 w:=public.alani_wallet_status();
 chat_schema:=pg_catalog.to_regclass('public.alani_support_threads') IS NOT NULL AND pg_catalog.to_regclass('public.alani_support_messages') IS NOT NULL;
 chat_active:=chat_schema AND coalesce(pg_catalog.has_function_privilege('authenticated',pg_catalog.to_regprocedure('public.alani_open_support_thread()'),'EXECUTE'),false) AND coalesce(pg_catalog.has_function_privilege('authenticated',pg_catalog.to_regprocedure('public.alani_send_support_message(uuid,text)'),'EXECUTE'),false) AND coalesce(pg_catalog.has_table_privilege('authenticated',pg_catalog.to_regclass('public.alani_support_messages'),'SELECT'),false);
 SELECT EXISTS(SELECT 1 FROM pg_catalog.pg_class c JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='app_private' AND c.relname='alani_legacy_customers' AND c.relrowsecurity) INTO legacy_schema;
 delivery_schema:=pg_catalog.to_regclass('public.alani_delivery_jobs') IS NOT NULL;
 return_schema:=pg_catalog.to_regclass('public.alani_return_requests') IS NOT NULL;
 campaign_schema:=pg_catalog.to_regclass('public.shitreed_store_campaigns') IS NOT NULL;
 SELECT EXISTS(SELECT 1 FROM pg_catalog.pg_class c JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='private_checkout' AND c.relname='alani_pos_invoice') INTO pos_schema;
 RETURN pg_catalog.jsonb_build_object(
  'checkout_ready',public.shitreed_alani_checkout_schema_ready(),
  'chat_schema',chat_schema,'chat_api_enabled',chat_active,
  'wallet_intake_enabled',coalesce((w->>'intake_enabled')::boolean,false),
  'wallet_credit_enabled',coalesce((w->>'credit_enabled')::boolean,false),
  'enabled_provider_count',pg_catalog.jsonb_array_length(w->'providers'),
  'legacy_schema',legacy_schema,'delivery_schema',delivery_schema,
  'return_schema',return_schema,'campaign_schema',campaign_schema,'pos_schema',pos_schema,
  'public_tables_missing_rls',(SELECT count(*) FROM pg_catalog.pg_class c JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='public' AND c.relkind IN ('r','p') AND NOT c.relrowsecurity));
END $f$;
REVOKE ALL ON FUNCTION public.alani_admin_release_readiness() FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.alani_admin_release_readiness() TO authenticated;
DO $v$ BEGIN
 IF has_function_privilege('anon','public.alani_admin_release_readiness()','EXECUTE')
 OR NOT has_function_privilege('authenticated','public.alani_admin_release_readiness()','EXECUTE')
 OR (SELECT prosecdef FROM pg_proc WHERE oid='public.alani_admin_release_readiness()'::regprocedure)
 THEN RAISE EXCEPTION 'RELEASE_READINESS_ACL_FAILED'; END IF;
END $v$;
COMMIT;
