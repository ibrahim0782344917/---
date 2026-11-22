-- Test post-migration privilege and schema under the anonymous role.
set role anon;
select 1/(case when public.shitreed_alani_checkout_schema_ready()
  then 1 else 0 end) as schema_ready_when_migrated;
reset role;
-- If a required function permission is revoked, fail-closed to false.
revoke execute on function public.place_alani_cash_order(
 jsonb,text,text,text,uuid,bigint) from authenticated;
select 1/(case when not public.shitreed_alani_checkout_schema_ready()
  then 1 else 0 end) as permission_removed_sales_locked;
