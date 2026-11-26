-- TEST ONLY. Real legacy import is an explicit MFA-authenticated admin action.
DO $$ BEGIN IF to_regprocedure('private_legacy.validate_import_batch_test(jsonb)') IS NULL OR to_regclass('private_checkout.alani_fcm_gate') IS NOT NULL THEN RAISE EXCEPTION 'TEST_ONLY_REQUIRED'; END IF; END $$;
CREATE TABLE private_legacy.import_audit_test(
 batch_sha256 text PRIMARY KEY CHECK(batch_sha256 ~ '^[0-9a-f]{64}$'),
 actor_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
 row_count integer NOT NULL CHECK(row_count BETWEEN 1 AND 100),
 inserted_count integer NOT NULL CHECK(inserted_count BETWEEN 0 AND row_count),
 created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE private_legacy.import_audit_test ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private_legacy.import_audit_test FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION private_legacy.commit_import_batch_test(p_rows jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE uid uuid:=auth.uid(); sid text:=auth.jwt()->>'session_id'; validation jsonb; n integer; added integer; h text; prior private_legacy.import_audit_test%ROWTYPE;
BEGIN
 IF uid IS NULL OR sid IS NULL OR auth.jwt()->>'aal' IS DISTINCT FROM 'aal2' OR NOT EXISTS(SELECT 1 FROM auth.sessions s WHERE s.id::text=sid AND s.user_id=uid AND s.aal::text='aal2' AND (s.not_after IS NULL OR s.not_after>now())) THEN RAISE EXCEPTION 'MFA_REQUIRED'; END IF;
 IF public.shitreed_admin_role() IS DISTINCT FROM 'super_admin' THEN RAISE EXCEPTION 'PERMISSION_DENIED'; END IF;
 IF p_rows IS NULL OR jsonb_typeof(p_rows)<>'array' OR octet_length(p_rows::text)>300000 THEN RAISE EXCEPTION 'INVALID_BATCH'; END IF;
 n:=jsonb_array_length(p_rows);
 IF n NOT BETWEEN 1 AND 100 THEN RAISE EXCEPTION 'INVALID_BATCH_SIZE'; END IF;
 h:=encode(extensions.digest(p_rows::text,'sha256'),'hex');
 PERFORM pg_catalog.pg_advisory_xact_lock(26001126);
 validation:=private_legacy.validate_import_batch_test(p_rows);
 IF validation->>'ready' IS DISTINCT FROM 'true' THEN RAISE EXCEPTION 'IMPORT_VALIDATION_FAILED'; END IF;
 SELECT * INTO prior FROM private_legacy.import_audit_test WHERE batch_sha256=h;
 IF FOUND THEN
  IF (validation->>'existing')::integer<>n THEN RAISE EXCEPTION 'IMPORT_STATE_CHANGED'; END IF;
  RETURN jsonb_build_object('rows',n,'inserted',0,'existing',n,'retry',true);
 END IF;
 INSERT INTO private_legacy.contacts(source_serial,recipient_name,phone_primary,phone_secondary,historical_order_count,governorate,district,address_details,goods_type,source_row,source_batch,consent_verified,contact_verified)
 SELECT x.source_serial,btrim(x.recipient_name),x.phone_primary,nullif(x.phone_secondary,''),x.historical_order_count,coalesce(x.governorate,''),coalesce(x.district,''),coalesce(x.address_details,''),coalesce(x.goods_type,''),x.source_row,'alani_2026_11_18',false,false
 FROM jsonb_to_recordset(p_rows) AS x(source_serial integer,recipient_name text,phone_primary text,phone_secondary text,historical_order_count integer,governorate text,district text,address_details text,goods_type text,source_row integer)
 WHERE NOT EXISTS(SELECT 1 FROM private_legacy.contacts c WHERE c.source_serial=x.source_serial);
 GET DIAGNOSTICS added=ROW_COUNT;
 INSERT INTO private_legacy.import_audit_test(batch_sha256,actor_id,row_count,inserted_count) VALUES(h,uid,n,added);
 RETURN jsonb_build_object('rows',n,'inserted',added,'existing',n-added,'retry',false);
END $$;
REVOKE ALL ON FUNCTION private_legacy.commit_import_batch_test(jsonb) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION private_legacy.commit_import_batch_test(jsonb) TO authenticated;
CREATE FUNCTION public.alani_commit_legacy_import_test(p_rows jsonb)
RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path=''
RETURN private_legacy.commit_import_batch_test(p_rows);
REVOKE ALL ON FUNCTION public.alani_commit_legacy_import_test(jsonb) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.alani_commit_legacy_import_test(jsonb) TO authenticated;
