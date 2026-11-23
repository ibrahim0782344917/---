-- TEST-ONLY security hardening for Supabase project shitreed-test.
-- Applied in the test database on 2026-11-23 as two migrations:
--   20261123133305 test_lockdown_merchant_store_approval_and_public_ddl_privileges_20261123
--   test_restrict_future_postgres_public_table_privileges_20261123
--
-- DO NOT RUN AGAINST PRODUCTION OR MERGE/PUBLISH AUTOMATICALLY.
-- This is an audit/reference copy, not a production rollout migration.
--
-- Security issue: store owner UPDATE policy constrained only owner_id while
-- table-level UPDATE also permitted updates to store approval status.
-- PostgreSQL RLS alone cannot restrict columns.
--
-- 1. Existing table grants. RPCs owned by postgres still handle approvals.
REVOKE TRUNCATE, TRIGGER, REFERENCES, MAINTAIN
  ON ALL TABLES IN SCHEMA public FROM anon, authenticated;
REVOKE UPDATE, DELETE ON TABLE public.stores FROM anon, authenticated;
GRANT UPDATE (
  name, area, category, address, phone, latitude, longitude,
  description, opening_hours, logo_url
) ON TABLE public.stores TO authenticated;

-- 2. Future tables created by postgres in public (test DB only).
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public
  REVOKE TRUNCATE, TRIGGER, REFERENCES, MAINTAIN
  ON TABLES FROM anon, authenticated;

-- Verified in test (claims simulated with SET LOCAL ROLE authenticated):
-- - merchant status UPDATE denied (SQLSTATE 42501); name UPDATE retained
-- - merchant forged user_metadata/app_metadata cannot become super_admin
-- - admin can approve a transaction-scoped pending test store
-- - all transaction-scoped test records ROLLBACK; counts unchanged
-- - anonymous sees no orders/order items/admin staff
-- - 0 anon-executable SECURITY DEFINER RPCs; 39 authenticated RPCs remain
--
-- WARNING: Supabase-managed supabase_admin default ACLs are NOT changed.
-- Real signed-JWT HTTP/PostgREST E2E and full review of 39 definer RPCs
-- remain requirements before deployment.
