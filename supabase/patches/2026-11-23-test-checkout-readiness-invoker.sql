-- Shitreed test-only: non-sensitive readiness check should not bypass RLS.
-- After conversion this still returns the same boolean to authenticated clients,
-- but runs under their normal PostgreSQL role rather than the function owner.
BEGIN;
ALTER FUNCTION public.shitreed_alani_checkout_schema_ready() SECURITY INVOKER;
COMMIT;