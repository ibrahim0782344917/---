
SET LOCAL lock_timeout = '3s';

CREATE TABLE app_private.alani_deletion_review_audit (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 request_id uuid NOT NULL,
 actor_id uuid NOT NULL,
 action text NOT NULL CHECK(action IN ('processing')),
 created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE app_private.alani_deletion_review_audit ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE app_private.alani_deletion_review_audit FROM PUBLIC,anon,authenticated;

CREATE FUNCTION app_private.alani_deletion_dependency_summary(p_user_id uuid)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path=''
AS $fn$
DECLARE
 f record; v_exists boolean; v_blockers integer:=0; v_unknown integer:=0;
 v_storage bigint; v_protected boolean; v_open bigint; v_account_exists boolean;
BEGIN
 IF p_user_id IS NULL THEN RAISE EXCEPTION 'INVALID_ACCOUNT'; END IF;
 SELECT EXISTS(SELECT 1 FROM auth.users u WHERE u.id=p_user_id) INTO v_account_exists;
 SELECT EXISTS(SELECT 1 FROM auth.users u WHERE u.id=p_user_id AND u.raw_app_meta_data->>'shitreed_role'='admin')
 OR EXISTS(SELECT 1 FROM public.shitreed_admin_staff a WHERE a.user_id=p_user_id AND a.enabled)
 OR EXISTS(SELECT 1 FROM public.stores s WHERE s.owner_id=p_user_id)
 INTO v_protected;
 SELECT count(*) INTO v_open FROM public.orders o WHERE o.buyer_id=p_user_id AND o.status NOT IN ('cancelled','rejected','delivered');
 SELECT count(*) INTO v_storage FROM storage.objects o WHERE o.owner=p_user_id OR o.owner_id=p_user_id::text;
 FOR f IN
 SELECT n.nspname AS schema_name,c.relname AS table_name,a.attname AS col_name,
 pg_catalog.array_length(k.conkey,1) AS key_size,k.confkey[1] AS target_col
 FROM pg_catalog.pg_constraint k
 JOIN pg_catalog.pg_class c ON c.oid=k.conrelid
 JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace
 LEFT JOIN pg_catalog.pg_attribute a ON a.attrelid=c.oid AND a.attnum=k.conkey[1]
 WHERE k.contype='f' AND k.confrelid='auth.users'::regclass
 AND n.nspname NOT IN ('auth','storage') AND k.confdeltype IN ('a','r')
 LOOP
 IF f.key_size<>1 OR f.col_name IS NULL OR f.target_col IS DISTINCT FROM
 (SELECT attnum FROM pg_catalog.pg_attribute WHERE attrelid='auth.users'::regclass AND attname='id') THEN
 v_unknown:=v_unknown+1; CONTINUE;
 END IF;
 EXECUTE pg_catalog.format('SELECT EXISTS (SELECT 1 FROM %I.%I WHERE %I = $1)',f.schema_name,f.table_name,f.col_name)
 INTO v_exists USING p_user_id;
 IF v_exists THEN v_blockers:=v_blockers+1; END IF;
 END LOOP;
 RETURN pg_catalog.jsonb_build_object(
 'account_exists',v_account_exists,'protected_account',v_protected,
 'open_orders',v_open,'blocking_relationships',v_blockers,
 'unclassified_relationships',v_unknown,'owned_storage_objects',v_storage,
 'direct_delete_dependency_check_clear',v_account_exists AND NOT v_protected AND v_open=0 AND v_blockers=0 AND v_unknown=0 AND v_storage=0,
 'manual_review_required',true,'execution_enabled',false);
END;
$fn$;
REVOKE ALL ON FUNCTION app_private.alani_deletion_dependency_summary(uuid) FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION public.alani_deletion_review_queue(p_limit integer DEFAULT 30)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=''
AS $fn$
DECLARE a uuid:=auth.uid(); result jsonb;
BEGIN
 IF a IS NULL OR public.shitreed_admin_role() IS DISTINCT FROM 'super_admin' THEN RAISE EXCEPTION 'SUPER_ADMIN_REQUIRED'; END IF;
 IF auth.jwt()->>'aal' IS DISTINCT FROM 'aal2' THEN RAISE EXCEPTION 'MFA_REQUIRED'; END IF;
 IF NOT EXISTS(SELECT 1 FROM auth.sessions s WHERE s.user_id=a AND s.id::text=auth.jwt()->>'session_id' AND s.aal::text='aal2' AND (s.not_after IS NULL OR s.not_after>now())) THEN RAISE EXCEPTION 'SESSION_EXPIRED'; END IF;
 IF p_limit IS NULL OR p_limit NOT BETWEEN 1 AND 50 THEN RAISE EXCEPTION 'INVALID_LIMIT'; END IF;
 SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY x.requested_at,x.id),'[]'::jsonb) INTO result
 FROM (SELECT id,status,requested_at FROM public.customer_deletion_requests WHERE status IN ('pending','processing') ORDER BY requested_at,id LIMIT p_limit) x;
 RETURN result;
END;
$fn$;
REVOKE ALL ON FUNCTION public.alani_deletion_review_queue(integer) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.alani_deletion_review_queue(integer) TO authenticated;

CREATE FUNCTION public.alani_deletion_review_preview(p_request_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=''
AS $fn$
DECLARE a uuid:=auth.uid(); r public.customer_deletion_requests%rowtype;
BEGIN
 IF a IS NULL OR public.shitreed_admin_role() IS DISTINCT FROM 'super_admin' THEN RAISE EXCEPTION 'SUPER_ADMIN_REQUIRED'; END IF;
 IF auth.jwt()->>'aal' IS DISTINCT FROM 'aal2' THEN RAISE EXCEPTION 'MFA_REQUIRED'; END IF;
 IF NOT EXISTS(SELECT 1 FROM auth.sessions s WHERE s.user_id=a AND s.id::text=auth.jwt()->>'session_id' AND s.aal::text='aal2' AND (s.not_after IS NULL OR s.not_after>now())) THEN RAISE EXCEPTION 'SESSION_EXPIRED'; END IF;
 SELECT * INTO r FROM public.customer_deletion_requests WHERE id=p_request_id AND status IN ('pending','processing');
 IF NOT FOUND THEN RAISE EXCEPTION 'REQUEST_NOT_FOUND'; END IF;
 RETURN app_private.alani_deletion_dependency_summary(r.user_id) || jsonb_build_object('request_id',r.id,'status',r.status);
END;
$fn$;
REVOKE ALL ON FUNCTION public.alani_deletion_review_preview(uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.alani_deletion_review_preview(uuid) TO authenticated;

CREATE FUNCTION public.alani_deletion_begin_review(p_request_id uuid)
RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $fn$
DECLARE a uuid:=auth.uid(); r public.customer_deletion_requests%rowtype;
BEGIN
 IF a IS NULL OR public.shitreed_admin_role() IS DISTINCT FROM 'super_admin' THEN RAISE EXCEPTION 'SUPER_ADMIN_REQUIRED'; END IF;
 IF auth.jwt()->>'aal' IS DISTINCT FROM 'aal2' THEN RAISE EXCEPTION 'MFA_REQUIRED'; END IF;
 IF NOT EXISTS(SELECT 1 FROM auth.sessions s WHERE s.user_id=a AND s.id::text=auth.jwt()->>'session_id' AND s.aal::text='aal2' AND (s.not_after IS NULL OR s.not_after>now())) THEN RAISE EXCEPTION 'SESSION_EXPIRED'; END IF;
 SELECT * INTO r FROM public.customer_deletion_requests WHERE id=p_request_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'REQUEST_NOT_FOUND'; END IF;
 IF r.status='processing' THEN RETURN 'processing'; END IF;
 IF r.status<>'pending' THEN RAISE EXCEPTION 'INVALID_REQUEST_STATUS'; END IF;
 UPDATE public.customer_deletion_requests SET status='processing' WHERE id=r.id;
 INSERT INTO app_private.alani_deletion_review_audit(request_id,actor_id,action) VALUES(r.id,a,'processing');
 RETURN 'processing';
END;
$fn$;
REVOKE ALL ON FUNCTION public.alani_deletion_begin_review(uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.alani_deletion_begin_review(uuid) TO authenticated;
