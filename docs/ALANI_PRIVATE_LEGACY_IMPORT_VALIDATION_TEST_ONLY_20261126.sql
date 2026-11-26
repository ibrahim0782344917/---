-- TEST ONLY. Private import validation for administrator-owned file.
-- No client grants, no actual contact insertion outside the operator transaction.
DO $$ BEGIN
 IF to_regclass('private_checkout.alani_legacy_contacts_test') IS NULL OR to_regclass('private_checkout.alani_fcm_gate') IS NOT NULL OR to_regclass('private_legacy.contacts') IS NULL THEN RAISE EXCEPTION 'TEST_ONLY_REQUIRED'; END IF;
END $$;
CREATE FUNCTION private_legacy.validate_import_batch_test(p_rows jsonb)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path='' AS $$
DECLARE n integer; invalid integer; duplicate_count integer; conflicts integer; existing_count integer;
BEGIN
 IF p_rows IS NULL OR jsonb_typeof(p_rows)<>'array' THEN RAISE EXCEPTION 'INVALID_ROWS'; END IF;
 n:=jsonb_array_length(p_rows);
 IF n NOT BETWEEN 1 AND 100 THEN RAISE EXCEPTION 'INVALID_BATCH_SIZE'; END IF;
 WITH r AS (
 SELECT * FROM jsonb_to_recordset(p_rows) AS x(source_serial integer,recipient_name text,phone_primary text,phone_secondary text,historical_order_count integer,governorate text,district text,address_details text,goods_type text,source_row integer)
 ) SELECT count(*) FILTER(WHERE source_serial IS NULL OR source_serial<=0 OR source_row IS NULL OR source_row<=0 OR recipient_name IS NULL OR length(btrim(recipient_name)) NOT BETWEEN 1 AND 160 OR phone_primary IS NULL OR phone_primary !~ '^07[3-9][0-9]{8}$' OR (nullif(phone_secondary,'') IS NOT NULL AND phone_secondary !~ '^07[0-9]{9}$') OR historical_order_count IS NULL OR historical_order_count<0 OR length(coalesce(governorate,''))>=150 OR length(coalesce(district,''))>=200 OR length(coalesce(address_details,''))>=1500 OR length(coalesce(goods_type,''))>=1000), greatest(count(*)-count(DISTINCT source_serial),count(*)-count(DISTINCT source_row),count(*)-count(DISTINCT phone_primary)) INTO invalid,duplicate_count FROM r;
 WITH r AS (SELECT * FROM jsonb_to_recordset(p_rows) AS x(source_serial integer,recipient_name text,phone_primary text,phone_secondary text,historical_order_count integer,governorate text,district text,address_details text,goods_type text,source_row integer))
 SELECT count(*) FILTER(WHERE (c.source_serial,c.source_row,c.phone_primary,c.recipient_name,c.phone_secondary,c.historical_order_count,c.governorate,c.district,c.address_details,c.goods_type) IS DISTINCT FROM (r.source_serial,r.source_row,r.phone_primary,btrim(r.recipient_name),nullif(r.phone_secondary,''),r.historical_order_count,coalesce(r.governorate,''),coalesce(r.district,''),coalesce(r.address_details,''),coalesce(r.goods_type,''))),count(*) FILTER(WHERE (c.source_serial,c.source_row,c.phone_primary,c.recipient_name,c.phone_secondary,c.historical_order_count,c.governorate,c.district,c.address_details,c.goods_type) IS NOT DISTINCT FROM (r.source_serial,r.source_row,r.phone_primary,btrim(r.recipient_name),nullif(r.phone_secondary,''),r.historical_order_count,coalesce(r.governorate,''),coalesce(r.district,''),coalesce(r.address_details,''),coalesce(r.goods_type,''))) INTO conflicts,existing_count
 FROM r JOIN private_legacy.contacts c ON c.source_serial=r.source_serial OR c.source_row=r.source_row OR c.phone_primary=r.phone_primary;
 RETURN jsonb_build_object('rows',n,'invalid',invalid,'duplicate_count_lower_bound',duplicate_count,'conflicts',conflicts,'existing',existing_count,'ready',invalid=0 AND duplicate_count=0 AND conflicts=0,'writes_enabled',false);
END $$;
REVOKE ALL ON FUNCTION private_legacy.validate_import_batch_test(jsonb) FROM PUBLIC,anon,authenticated,service_role;
