-- STAGING REVIEW ONLY. NOT APPLIED TO THE LIVE SHITREED DATABASE.
-- Existing: public.customer_deletion_requests has RLS policies restricting
-- INSERT and SELECT to user_id=auth.uid(), defaults user_id to auth.uid(),
-- status to pending and requested_at to now().
-- Observed missing: authenticated role has no table INSERT or SELECT GRANTS.
BEGIN;
REVOKE ALL ON public.customer_deletion_requests FROM anon, PUBLIC;
REVOKE UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER
  ON public.customer_deletion_requests FROM authenticated;
GRANT SELECT(id,user_id,reason,status,requested_at,processed_at),
      INSERT(reason) ON public.customer_deletion_requests TO authenticated;
COMMIT;
-- Before applying anywhere: verify existing owner-only RLS policies,
-- Data API grants, and schema with Supabase advisors in isolated staging.
-- Test as user A: submit request and read own status.
-- Test as user B: cannot read A's request or forge another user_id.
-- Test unauthenticated: no SELECT/INSERT.
-- Test no UPDATE/DELETE even for the owner; deletion executed by an
-- authorized server-side privacy workflow with a retained audit.
-- A request record alone does NOT delete an Auth user.
