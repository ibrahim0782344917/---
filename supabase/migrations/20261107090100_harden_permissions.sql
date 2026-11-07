-- Harden the dedicated Shitreed project after the foundation migration.
-- Trigger functions should never be callable directly via RPC.
revoke execute on function public.create_customer_profile() from PUBLIC, anon, authenticated;

-- Index merchant ownership for efficient RLS policies and FK checks.
create index if not exists stores_owner_id_idx on public.stores(owner_id);
