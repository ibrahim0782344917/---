-- Al-Ani master plan: read-only catalog security preflight.
-- Run ONLY against verified shitreed-test (tgvdwotbrnhcoykuxdpr).
-- All six rows must be true. Never substitute this for role/ownership E2E tests.
WITH expected_tables(name) AS (VALUES ('alani_delivery_jobs'),('alani_delivery_couriers'),('alani_support_read_receipts')),
expected_functions(name) AS (VALUES ('alani_courier_complete_delivery'),('alani_courier_pickup'),('alani_dispatch_delivery'),('alani_issue_delivery_pin'),('alani_list_delivery_couriers'),('alani_my_delivery_tasks'),('alani_order_delivery_status'),('alani_owner_delivery_jobs'),('alani_set_delivery_courier'),('alani_mark_support_read'),('alani_support_unread_counts')),
tables AS (SELECT c.oid,c.relname,c.relrowsecurity FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='public' AND c.relkind IN ('r','p')),
funcs AS (SELECT p.oid,p.proname FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public'),
checks AS (
SELECT 'public_rls' AS check_name, count(*)>0 AND bool_and(relrowsecurity) AS passed FROM tables
UNION ALL SELECT 'private_tables_exist_and_rls',count(t.oid)=3 AND coalesce(bool_and(t.relrowsecurity),false) FROM expected_tables e LEFT JOIN tables t ON t.relname=e.name
UNION ALL SELECT 'private_tables_no_direct_client_grants',count(t.oid)=3 AND coalesce(bool_and(NOT has_table_privilege('anon',t.oid,'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER') AND NOT has_table_privilege('authenticated',t.oid,'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER') AND NOT has_any_column_privilege('anon',t.oid,'SELECT,INSERT,UPDATE,REFERENCES') AND NOT has_any_column_privilege('authenticated',t.oid,'SELECT,INSERT,UPDATE,REFERENCES')),false) FROM expected_tables e LEFT JOIN tables t ON t.relname=e.name
UNION ALL SELECT 'expected_rpc_names',count(DISTINCT f.proname)=11 FROM expected_functions e LEFT JOIN funcs f ON f.proname=e.name
UNION ALL SELECT 'rpc_no_anon_execute',count(DISTINCT f.proname)=11 AND coalesce(bool_and(NOT has_function_privilege('anon',f.oid,'EXECUTE')),false) FROM expected_functions e LEFT JOIN funcs f ON f.proname=e.name
UNION ALL SELECT 'rpc_authenticated_execute',count(DISTINCT f.proname)=11 AND coalesce(bool_and(has_function_privilege('authenticated',f.oid,'EXECUTE')),false) FROM expected_functions e LEFT JOIN funcs f ON f.proname=e.name)
SELECT check_name,passed FROM checks ORDER BY check_name;
