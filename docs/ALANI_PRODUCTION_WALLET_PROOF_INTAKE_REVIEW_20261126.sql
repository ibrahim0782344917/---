-- Production transfer proof intake: explicit gate, provider allowlist, private storage.
-- No bank credentials, actual transfers, provider entries, monetary credit or balance changes.
BEGIN;
SET LOCAL lock_timeout='3s';
SET LOCAL statement_timeout='30s';
DO $g$ BEGIN
 IF NOT EXISTS(SELECT 1 FROM private_checkout.alani_wallet_funding_gate WHERE singleton AND NOT request_intake_enabled AND NOT credit_enabled)
 OR NOT public.shitreed_alani_checkout_schema_ready()
 THEN RAISE EXCEPTION 'WALLET_PRECHECK_FAILED'; END IF;
END $g$;
CREATE TABLE private_checkout.alani_wallet_allowed_providers (
 code text PRIMARY KEY CHECK(code ~ '^[a-z0-9_]{2,40}$'),
 label text NOT NULL CHECK(char_length(btrim(label)) BETWEEN 2 AND 80),
 enabled boolean NOT NULL DEFAULT false
);
ALTER TABLE private_checkout.alani_wallet_allowed_providers ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private_checkout.alani_wallet_allowed_providers FROM PUBLIC,anon,authenticated;
ALTER TABLE private_checkout.alani_wallet_topup_requests ADD COLUMN submitted_at timestamptz;

-- Public status returns no private settings or balance. Request intake requires
-- both approved provider configuration and a private bucket with size limits.
CREATE FUNCTION public.alani_wallet_status()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO '' AS $f$
DECLARE v_ready boolean; v_providers jsonb;
BEGIN
 IF auth.uid() IS NULL THEN RAISE EXCEPTION 'LOGIN_REQUIRED'; END IF;
 SELECT coalesce(request_intake_enabled,false) INTO v_ready FROM private_checkout.alani_wallet_funding_gate WHERE singleton;
 v_ready:=coalesce(v_ready,false)
 AND EXISTS(SELECT 1 FROM storage.buckets WHERE id='alani-wallet-proof-private' AND public=false AND file_size_limit BETWEEN 1 AND 5242880 AND allowed_mime_types @> ARRAY['image/jpeg','image/png','application/pdf']::text[] AND allowed_mime_types <@ ARRAY['image/jpeg','image/png','application/pdf']::text[])
 AND EXISTS(SELECT 1 FROM private_checkout.alani_wallet_allowed_providers WHERE enabled);
 SELECT coalesce(jsonb_agg(jsonb_build_object('code',code,'label',label) ORDER BY code),'[]'::jsonb)
 INTO v_providers FROM private_checkout.alani_wallet_allowed_providers WHERE enabled AND v_ready;
 RETURN jsonb_build_object('intake_enabled',v_ready,'credit_enabled',false,'providers',v_providers,'currency','IQD');
END $f$;
REVOKE ALL ON FUNCTION public.alani_wallet_status() FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.alani_wallet_status() TO authenticated;

CREATE FUNCTION public.alani_wallet_reserve_proof(p_key uuid,p_amount_iqd bigint,p_provider text,p_reference text,p_extension text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $f$
DECLARE a uuid:=auth.uid(); r private_checkout.alani_wallet_topup_requests%ROWTYPE; k uuid:=gen_random_uuid(); ref text:=btrim(p_reference); suffix text;
BEGIN
 IF a IS NULL THEN RAISE EXCEPTION 'LOGIN_REQUIRED'; END IF;
 IF NOT coalesce((public.alani_wallet_status()->>'intake_enabled')::boolean,false) THEN RAISE EXCEPTION 'FUNDING_CLOSED'; END IF;
 IF p_key IS NULL OR p_amount_iqd IS NULL OR p_amount_iqd NOT BETWEEN 1 AND 1000000000
 OR p_provider IS NULL OR NOT EXISTS(SELECT 1 FROM private_checkout.alani_wallet_allowed_providers WHERE code=p_provider AND enabled)
 OR ref IS NULL OR char_length(ref) NOT BETWEEN 4 AND 120 OR p_extension IS NULL OR p_extension NOT IN ('jpg','png','pdf')
 THEN RAISE EXCEPTION 'INVALID_PROOF_REQUEST'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended(a::text,0));
 SELECT * INTO r FROM private_checkout.alani_wallet_topup_requests WHERE user_id=a AND request_key=p_key;
 IF FOUND THEN
 IF r.amount_iqd<>p_amount_iqd OR r.provider_code<>p_provider OR r.declared_reference<>ref OR right(r.proof_object_path,length(p_extension)+1)<>'.'||p_extension THEN RAISE EXCEPTION 'REQUEST_KEY_CONFLICT'; END IF;
 ELSE
 IF (SELECT count(*) FROM private_checkout.alani_wallet_topup_requests WHERE user_id=a AND created_at>now()-interval '1 day')>=5 THEN RAISE EXCEPTION 'DAILY_LIMIT'; END IF;
 suffix:=gen_random_uuid()::text||'.'||p_extension;
 INSERT INTO private_checkout.alani_wallet_topup_requests(id,user_id,request_key,amount_iqd,provider_code,declared_reference,proof_object_path)
 VALUES(k,a,p_key,p_amount_iqd,p_provider,ref,a::text||'/'||k::text||'/'||suffix) RETURNING * INTO r;
 END IF;
 RETURN jsonb_build_object('id',r.id,'path',r.proof_object_path,'submitted',r.submitted_at IS NOT NULL);
END $f$;

CREATE FUNCTION public.alani_wallet_proof_access(p_path text,p_write boolean)
RETURNS boolean LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO '' AS $f$
DECLARE a uuid:=auth.uid(); r private_checkout.alani_wallet_topup_requests%ROWTYPE;
BEGIN
 IF a IS NULL OR p_write IS NULL OR p_path IS NULL THEN RETURN false; END IF;
 SELECT * INTO r FROM private_checkout.alani_wallet_topup_requests WHERE proof_object_path=p_path;
 IF NOT FOUND THEN RETURN false; END IF;
 IF p_write THEN RETURN r.user_id=a AND r.submitted_at IS NULL AND coalesce((public.alani_wallet_status()->>'intake_enabled')::boolean,false)
 AND EXISTS(SELECT 1 FROM private_checkout.alani_wallet_allowed_providers WHERE code=r.provider_code AND enabled); END IF;
 RETURN r.user_id=a OR (r.submitted_at IS NOT NULL AND public.shitreed_admin_role() IS NOT DISTINCT FROM 'super_admin');
END $f$;

CREATE FUNCTION public.alani_wallet_submit_proof(p_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $f$
DECLARE a uuid:=auth.uid(); r private_checkout.alani_wallet_topup_requests%ROWTYPE; m jsonb;
BEGIN
 IF a IS NULL THEN RAISE EXCEPTION 'LOGIN_REQUIRED'; END IF;
 SELECT * INTO r FROM private_checkout.alani_wallet_topup_requests WHERE id=p_id AND user_id=a FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'REQUEST_NOT_FOUND'; END IF;
 IF r.submitted_at IS NOT NULL THEN RETURN jsonb_build_object('id',r.id,'status','submitted'); END IF;
 IF NOT public.alani_wallet_proof_access(r.proof_object_path,true) THEN RAISE EXCEPTION 'FUNDING_CLOSED'; END IF;
 SELECT metadata INTO m FROM storage.objects WHERE bucket_id='alani-wallet-proof-private' AND name=r.proof_object_path;
 IF m IS NULL OR coalesce(m->>'size','') !~ '^[0-9]{1,8}$' THEN RAISE EXCEPTION 'PROOF_MISSING'; END IF;
 IF (m->>'size')::bigint NOT BETWEEN 1 AND 5242880 OR NOT (
 (right(r.proof_object_path,4)='.jpg' AND m->>'mimetype'='image/jpeg') OR
 (right(r.proof_object_path,4)='.png' AND m->>'mimetype'='image/png') OR
 (right(r.proof_object_path,4)='.pdf' AND m->>'mimetype'='application/pdf')) THEN RAISE EXCEPTION 'INVALID_PROOF_FILE'; END IF;
 UPDATE private_checkout.alani_wallet_topup_requests SET submitted_at=now() WHERE id=r.id;
 RETURN jsonb_build_object('id',r.id,'status','submitted');
END $f$;

CREATE FUNCTION public.alani_wallet_my_requests()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO '' AS $f$
DECLARE a uuid:=auth.uid(); result jsonb;
BEGIN
 IF a IS NULL THEN RAISE EXCEPTION 'LOGIN_REQUIRED'; END IF;
 SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY x.created_at DESC),'[]'::jsonb) INTO result
 FROM (SELECT r.id,r.amount_iqd,r.provider_code,r.created_at,r.submitted_at,
 CASE WHEN r.submitted_at IS NULL THEN 'draft' ELSE coalesce((SELECT v.decision FROM private_checkout.alani_wallet_topup_reviews v WHERE v.request_id=r.id ORDER BY v.created_at DESC,v.id DESC LIMIT 1),'submitted') END AS status
 FROM private_checkout.alani_wallet_topup_requests r WHERE r.user_id=a ORDER BY r.created_at DESC LIMIT 50) x;
 RETURN result;
END $f$;
CREATE FUNCTION public.alani_wallet_admin_requests()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO '' AS $f$
DECLARE result jsonb;
BEGIN
 IF auth.uid() IS NULL OR public.shitreed_admin_role() IS DISTINCT FROM 'super_admin' THEN RAISE EXCEPTION 'SUPER_ADMIN_REQUIRED'; END IF;
 SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY x.submitted_at DESC),'[]'::jsonb) INTO result
 FROM (SELECT r.id,r.amount_iqd,r.provider_code,r.declared_reference,r.proof_object_path,r.submitted_at,
 coalesce((SELECT v.decision FROM private_checkout.alani_wallet_topup_reviews v WHERE v.request_id=r.id ORDER BY v.created_at DESC,v.id DESC LIMIT 1),'submitted') AS status
 FROM private_checkout.alani_wallet_topup_requests r WHERE r.submitted_at IS NOT NULL ORDER BY r.submitted_at DESC LIMIT 50) x;
 RETURN result;
END $f$;
CREATE FUNCTION public.alani_wallet_admin_review(p_id uuid,p_decision text,p_reason text)
RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $f$
DECLARE a uuid:=auth.uid(); r private_checkout.alani_wallet_topup_requests%ROWTYPE; previous text;
BEGIN
 IF a IS NULL OR public.shitreed_admin_role() IS DISTINCT FROM 'super_admin' THEN RAISE EXCEPTION 'SUPER_ADMIN_REQUIRED'; END IF;
 IF p_decision IS NULL OR p_decision NOT IN ('under_review','needs_information','rejected') OR p_reason IS NULL OR char_length(btrim(p_reason)) NOT BETWEEN 12 AND 1000 THEN RAISE EXCEPTION 'INVALID_REVIEW'; END IF;
 SELECT * INTO r FROM private_checkout.alani_wallet_topup_requests WHERE id=p_id AND submitted_at IS NOT NULL FOR UPDATE;
 IF NOT FOUND OR r.user_id=a THEN RAISE EXCEPTION 'REQUEST_NOT_FOUND_OR_SELF_REVIEW'; END IF;
 SELECT v.decision INTO previous FROM private_checkout.alani_wallet_topup_reviews v WHERE v.request_id=r.id ORDER BY v.created_at DESC,v.id DESC LIMIT 1;
 IF previous IN ('rejected','externally_verified') THEN RAISE EXCEPTION 'REVIEW_FINAL'; END IF;
 IF previous=p_decision THEN RETURN previous; END IF;
 INSERT INTO private_checkout.alani_wallet_topup_reviews(request_id,reviewer_id,decision,reason) VALUES(r.id,a,p_decision,btrim(p_reason));
 RETURN p_decision;
END $f$;
REVOKE ALL ON FUNCTION public.alani_wallet_reserve_proof(uuid,bigint,text,text,text),public.alani_wallet_proof_access(text,boolean),public.alani_wallet_submit_proof(uuid),public.alani_wallet_my_requests(),public.alani_wallet_admin_requests(),public.alani_wallet_admin_review(uuid,text,text) FROM PUBLIC,anon,authenticated;
-- Access limited to status and read-only lists until separately reviewed intake activation.
GRANT EXECUTE ON FUNCTION public.alani_wallet_my_requests(),public.alani_wallet_admin_requests() TO authenticated;
-- The upload policies are deliberately not installed until a private bucket
-- is created through Storage API and file verification has been tested.
COMMIT;
