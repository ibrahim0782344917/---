-- The existing application starts locked before the COD migration.
set role anon;
select 1/(case when not public.shitreed_alani_checkout_schema_ready()
  then 1 else 0 end) as missing_schema_keeps_sales_locked;
reset role;
