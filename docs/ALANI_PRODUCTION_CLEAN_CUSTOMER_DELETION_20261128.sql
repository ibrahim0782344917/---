
SET LOCAL lock_timeout='3s';
ALTER TABLE app_private.alani_deletion_review_audit DROP CONSTRAINT alani_deletion_review_audit_action_check,
 ADD CONSTRAINT alani_deletion_review_audit_action_check CHECK(action IN ('processing','completed'));
CREATE UNIQUE INDEX alani_deletion_completed_once ON app_private.alani_deletion_review_audit(request_id) WHERE action='completed';

-- Only personal records with known cascading foreign keys can be removed automatically.
CREATE FUNCTION app_private.alani_clean_deletion_check(p_user_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path=''
AS $fn$
DECLARE f record; found_ref boolean; blockers integer:=0; summary jsonb;
BEGIN
 summary:=app_private.alani_deletion_dependency_summary(p_user_id);
 FOR f IN
 SELECT n.nspname AS ns,c.relname AS tab,a.attname AS col
 FROM pg_catalog.pg_class c
 JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace
 JOIN pg_catalog.pg_attribute a ON a.attrelid=c.oid
 WHERE n.nspname IN ('public','app_private','private_checkout','private_places','private_osm')
 AND c.relkind IN ('r','p') AND a.attnum>0 AND NOT a.attisdropped AND a.atttypid='uuid'::regtype
 AND NOT (
 (n.nspname,c.relname,a.attname) IN (
 ('public','customer_profiles','id'),
 ('public','shitreed_profiles','user_id'),
 ('public','shitreed_saved_addresses','user_id'),
 ('public','customer_deletion_requests','user_id'),
 ('public','alani_notification_preferences','user_id'),
 ('public','alani_post_reactions','user_id'),
 ('public','alani_post_ratings','user_id'),
 ('public','alani_support_read_receipts','user_id'),
 ('private_checkout','alani_favorites','user_id'),
 ('private_checkout','alani_fcm_devices','user_id'),
 ('private_checkout','alani_fcm_outbox','recipient_id'),
 ('private_checkout','alani_order_notification_reads','user_id'),
 ('private_checkout','alani_support_presence','user_id')
 ) AND EXISTS (SELECT 1 FROM pg_catalog.pg_constraint k WHERE k.conrelid=c.oid AND k.contype='f' AND k.confrelid='auth.users'::regclass AND k.conkey=ARRAY[a.attnum] AND k.confdeltype='c')
 )
 LOOP
 EXECUTE pg_catalog.format('SELECT EXISTS(SELECT 1 FROM %I.%I WHERE %I=$1)',f.ns,f.tab,f.col) INTO found_ref USING p_user_id;
 IF found_ref THEN blockers:=blockers+1; END IF;
 END LOOP;
 -- Historical imported contacts require separate identity matching and privacy review.
 IF EXISTS(SELECT 1 FROM app_private.alani_legacy_customers) THEN
   blockers:=blockers+1;
 END IF;
 -- Do not let managed storage ownership or old avatar paths survive deletion.
 IF EXISTS(SELECT 1 FROM storage.objects o WHERE o.owner=p_user_id OR o.owner_id=p_user_id::text OR (o.bucket_id='shitreed-avatars' AND split_part(o.name,'/',1)=p_user_id::text)) THEN blockers:=blockers+1; END IF;
 RETURN summary || jsonb_build_object('additional_review_blockers',blockers,
 'execution_enabled',true,
 'eligible_for_clean_account_deletion',coalesce((summary->>'direct_delete_dependency_check_clear')::boolean,false) AND blockers=0);
END;
$fn$;
REVOKE ALL ON FUNCTION app_private.alani_clean_deletion_check(uuid) FROM PUBLIC,anon,authenticated,service_role;

-- Atomic implementation; the original request is removed by its existing cascade.
-- A non-identifying completion receipt remains in a private administrative audit.
CREATE FUNCTION app_private.alani_delete_clean_customer(p_request_id uuid,p_actor uuid)
RETURNS text LANGUAGE plpgsql SECURITY INVOKER SET search_path=''
AS $fn$
DECLARE r public.customer_deletion_requests%rowtype; check_result jsonb;
BEGIN
 IF p_request_id IS NULL OR p_actor IS NULL THEN RAISE EXCEPTION 'INVALID_CONFIRMATION'; END IF;
 IF EXISTS(SELECT 1 FROM app_private.alani_deletion_review_audit WHERE request_id=p_request_id AND action='completed') THEN RETURN 'completed'; END IF;
 SELECT * INTO r FROM public.customer_deletion_requests WHERE id=p_request_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'REQUEST_NOT_FOUND'; END IF;
 IF r.status<>'processing' THEN RAISE EXCEPTION 'REVIEW_REQUIRED'; END IF;
 IF r.user_id=p_actor THEN RAISE EXCEPTION 'PROTECTED_ACCOUNT'; END IF;
 PERFORM 1 FROM auth.users WHERE id=r.user_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'ACCOUNT_NOT_FOUND'; END IF;
 check_result:=app_private.alani_clean_deletion_check(r.user_id);
 IF coalesce((check_result->>'protected_account')::boolean,true) THEN RAISE EXCEPTION 'PROTECTED_ACCOUNT'; END IF;
 IF NOT coalesce((check_result->>'eligible_for_clean_account_deletion')::boolean,false) THEN RAISE EXCEPTION 'MANUAL_PRIVACY_REVIEW_REQUIRED'; END IF;
 INSERT INTO app_private.alani_deletion_review_audit(request_id,actor_id,action) VALUES(p_request_id,p_actor,'completed');
 DELETE FROM auth.users WHERE id=r.user_id;
 IF NOT FOUND THEN RAISE EXCEPTION 'ACCOUNT_DELETE_FAILED'; END IF;
 IF EXISTS(SELECT 1 FROM auth.sessions WHERE user_id=r.user_id) THEN RAISE EXCEPTION 'SESSION_REVOCATION_FAILED'; END IF;
 RETURN 'completed';
END;
$fn$;
REVOKE ALL ON FUNCTION app_private.alani_delete_clean_customer(uuid,uuid) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.alani_deletion_review_preview(p_request_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=''
AS $fn$
DECLARE a uuid:=auth.uid(); r public.customer_deletion_requests%rowtype;
BEGIN
 IF a IS NULL OR public.shitreed_admin_role() IS DISTINCT FROM 'super_admin' THEN RAISE EXCEPTION 'SUPER_ADMIN_REQUIRED'; END IF;
 IF auth.jwt()->>'aal' IS DISTINCT FROM 'aal2' THEN RAISE EXCEPTION 'MFA_REQUIRED'; END IF;
 IF NOT EXISTS(SELECT 1 FROM auth.sessions s WHERE s.user_id=a AND s.id::text=auth.jwt()->>'session_id' AND s.aal::text='aal2' AND (s.not_after IS NULL OR s.not_after>now())) THEN RAISE EXCEPTION 'SESSION_EXPIRED'; END IF;
 SELECT * INTO r FROM public.customer_deletion_requests WHERE id=p_request_id AND status IN ('pending','processing');
 IF NOT FOUND THEN RAISE EXCEPTION 'REQUEST_NOT_FOUND'; END IF;
 RETURN app_private.alani_clean_deletion_check(r.user_id)||jsonb_build_object('request_id',r.id,'status',r.status);
END;
$fn$;
CREATE FUNCTION public.alani_deletion_finalize(p_request_id uuid,p_confirmation text)
RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $fn$
DECLARE a uuid:=auth.uid();
BEGIN
 IF a IS NULL OR public.shitreed_admin_role() IS DISTINCT FROM 'super_admin' THEN RAISE EXCEPTION 'SUPER_ADMIN_REQUIRED'; END IF;
 IF auth.jwt()->>'aal' IS DISTINCT FROM 'aal2' THEN RAISE EXCEPTION 'MFA_REQUIRED'; END IF;
 IF NOT EXISTS(SELECT 1 FROM auth.sessions s WHERE s.user_id=a AND s.id::text=auth.jwt()->>'session_id' AND s.aal::text='aal2' AND (s.not_after IS NULL OR s.not_after>now())) THEN RAISE EXCEPTION 'SESSION_EXPIRED'; END IF;
 IF p_request_id IS NULL OR p_confirmation IS DISTINCT FROM 'DELETE '||p_request_id::text THEN RAISE EXCEPTION 'INVALID_CONFIRMATION'; END IF;
 RETURN app_private.alani_delete_clean_customer(p_request_id,a);
END;
$fn$;
REVOKE ALL ON FUNCTION public.alani_deletion_finalize(uuid,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.alani_deletion_finalize(uuid,text) TO authenticated;

-- A deleted account's still-unexpired JWT cannot create or update an avatar.
CREATE POLICY alani_avatar_existing_customer_insert ON storage.objects AS RESTRICTIVE FOR INSERT TO authenticated
 WITH CHECK(bucket_id<>'shitreed-avatars' OR EXISTS(SELECT 1 FROM public.customer_profiles p WHERE p.id=(SELECT auth.uid())));
CREATE POLICY alani_avatar_existing_customer_update ON storage.objects AS RESTRICTIVE FOR UPDATE TO authenticated
 USING(bucket_id<>'shitreed-avatars' OR EXISTS(SELECT 1 FROM public.customer_profiles p WHERE p.id=(SELECT auth.uid())))
 WITH CHECK(bucket_id<>'shitreed-avatars' OR EXISTS(SELECT 1 FROM public.customer_profiles p WHERE p.id=(SELECT auth.uid())));
