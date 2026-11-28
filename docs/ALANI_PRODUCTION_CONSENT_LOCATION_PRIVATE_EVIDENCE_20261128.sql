
SET LOCAL lock_timeout='3s';
CREATE TABLE private_checkout.alani_delivery_location (
 order_id uuid PRIMARY KEY REFERENCES public.orders(id) ON DELETE CASCADE,
 courier_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE UNIQUE,
 latitude double precision NOT NULL CHECK(latitude BETWEEN -90 AND 90),
 longitude double precision NOT NULL CHECK(longitude BETWEEN -180 AND 180),
 accuracy_m double precision NOT NULL CHECK(accuracy_m BETWEEN 0 AND 1000),
 updated_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
ALTER TABLE private_checkout.alani_delivery_location ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE private_checkout.alani_delivery_location FROM PUBLIC,anon,authenticated;
CREATE FUNCTION public.alani_publish_location(p_order_id uuid,p_lat double precision,p_lon double precision,p_accuracy_m double precision,p_consent boolean)
RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
DECLARE a uuid:=auth.uid(); o public.orders%rowtype; j public.alani_delivery_jobs%rowtype;
BEGIN
 IF a IS NULL OR NOT EXISTS(SELECT 1 FROM auth.sessions s WHERE s.user_id=a AND s.id::text=auth.jwt()->>'session_id' AND (s.not_after IS NULL OR s.not_after>now())) THEN RAISE EXCEPTION 'SESSION_EXPIRED'; END IF;
 SELECT * INTO o FROM public.orders WHERE id=p_order_id AND store_id='25091ca2-c0da-416c-b634-81b188ee66be'::uuid FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'ORDER_NOT_AVAILABLE'; END IF;
 SELECT * INTO j FROM public.alani_delivery_jobs WHERE order_id=o.id;
 IF j.courier_id IS DISTINCT FROM a THEN RAISE EXCEPTION 'PERMISSION_DENIED'; END IF;
 IF p_consent IS FALSE THEN
  DELETE FROM private_checkout.alani_delivery_location WHERE order_id=o.id AND courier_id=a;
  RETURN 'stopped';
 END IF;
 IF p_consent IS DISTINCT FROM true THEN RAISE EXCEPTION 'CONSENT_REQUIRED'; END IF;
 IF o.status<>'out_for_delivery' OR j.picked_up_at IS NULL OR NOT EXISTS(SELECT 1 FROM public.alani_delivery_couriers c WHERE c.store_id=o.store_id AND c.courier_id=a AND c.enabled) THEN RAISE EXCEPTION 'DELIVERY_NOT_ACTIVE'; END IF;
 IF p_lat IS NULL OR p_lon IS NULL OR p_accuracy_m IS NULL OR NOT(p_lat BETWEEN -90 AND 90 AND p_lon BETWEEN -180 AND 180 AND p_accuracy_m BETWEEN 0 AND 1000) THEN RAISE EXCEPTION 'INVALID_LOCATION'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('alani-location:'||a::text,42117));
 IF EXISTS(SELECT 1 FROM private_checkout.alani_delivery_location WHERE courier_id=a AND updated_at>clock_timestamp()-interval '10 seconds') THEN RETURN 'rate_limited'; END IF;
 DELETE FROM private_checkout.alani_delivery_location WHERE updated_at<=clock_timestamp()-interval '90 seconds' OR (courier_id=a AND order_id<>o.id);
 INSERT INTO private_checkout.alani_delivery_location(order_id,courier_id,latitude,longitude,accuracy_m) VALUES(o.id,a,round(p_lat::numeric,3)::double precision,round(p_lon::numeric,3)::double precision,greatest(p_accuracy_m,120))
 ON CONFLICT(order_id) DO UPDATE SET courier_id=excluded.courier_id,latitude=excluded.latitude,longitude=excluded.longitude,accuracy_m=excluded.accuracy_m,updated_at=clock_timestamp();
 RETURN 'published';
END $fn$;
CREATE FUNCTION public.alani_read_location(p_order_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $fn$
DECLARE a uuid:=auth.uid(); result jsonb;
BEGIN
 IF a IS NULL OR NOT EXISTS(SELECT 1 FROM auth.sessions s WHERE s.user_id=a AND s.id::text=auth.jwt()->>'session_id' AND (s.not_after IS NULL OR s.not_after>now())) THEN RAISE EXCEPTION 'SESSION_EXPIRED'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.orders o WHERE o.id=p_order_id AND o.buyer_id=a AND o.store_id='25091ca2-c0da-416c-b634-81b188ee66be'::uuid) THEN RAISE EXCEPTION 'ORDER_NOT_AVAILABLE'; END IF;
 SELECT jsonb_build_object('latitude',l.latitude,'longitude',l.longitude,'accuracy_m',l.accuracy_m,'updated_at',l.updated_at) INTO result
 FROM private_checkout.alani_delivery_location l JOIN public.orders o ON o.id=l.order_id JOIN public.alani_delivery_jobs j ON j.order_id=o.id AND j.courier_id=l.courier_id
 JOIN public.alani_delivery_couriers c ON c.store_id=o.store_id AND c.courier_id=l.courier_id AND c.enabled
 WHERE o.id=p_order_id AND o.status='out_for_delivery' AND j.picked_up_at IS NOT NULL AND l.updated_at>clock_timestamp()-interval '90 seconds';
 RETURN result;
END $fn$;
REVOKE ALL ON FUNCTION public.alani_publish_location(uuid,double precision,double precision,double precision,boolean),public.alani_read_location(uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.alani_publish_location(uuid,double precision,double precision,double precision,boolean),public.alani_read_location(uuid) TO authenticated;
CREATE FUNCTION private_checkout.alani_clear_delivery_location() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
BEGIN
 IF NEW.status IS DISTINCT FROM 'out_for_delivery' THEN DELETE FROM private_checkout.alani_delivery_location WHERE order_id=NEW.id; END IF;
 RETURN NEW;
END $fn$;
REVOKE ALL ON FUNCTION private_checkout.alani_clear_delivery_location() FROM PUBLIC,anon,authenticated;
CREATE TRIGGER alani_clear_delivery_location AFTER UPDATE OF status ON public.orders FOR EACH ROW EXECUTE FUNCTION private_checkout.alani_clear_delivery_location();

-- Private evidence: one immutable JPEG per delivery and one per return request.
INSERT INTO storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
VALUES('alani-private-evidence','alani-private-evidence',false,3145728,ARRAY['image/jpeg']);
CREATE FUNCTION public.alani_evidence_access(p_name text,p_write boolean)
RETURNS boolean LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $fn$
DECLARE a uuid:=auth.uid(); k text; target uuid;
BEGIN
 IF a IS NULL OR p_write IS NULL OR p_name IS NULL OR p_name !~ '^(delivery|return)/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/proof[.]jpg$' THEN RETURN false; END IF;
 IF NOT EXISTS(SELECT 1 FROM auth.sessions s WHERE s.user_id=a AND s.id::text=auth.jwt()->>'session_id' AND (s.not_after IS NULL OR s.not_after>now())) THEN RETURN false; END IF;
 k:=split_part(p_name,'/',1); target:=split_part(p_name,'/',2)::uuid;
 IF k='delivery' THEN
  RETURN EXISTS(SELECT 1 FROM public.orders o JOIN public.alani_delivery_jobs j ON j.order_id=o.id JOIN public.stores s ON s.id=o.store_id
   WHERE o.id=target AND o.store_id='25091ca2-c0da-416c-b634-81b188ee66be'::uuid AND
   CASE WHEN p_write THEN o.status='out_for_delivery' AND j.picked_up_at IS NOT NULL AND j.courier_id=a AND EXISTS(SELECT 1 FROM public.alani_delivery_couriers c WHERE c.store_id=o.store_id AND c.courier_id=a AND c.enabled)
   ELSE o.buyer_id=a OR s.owner_id=a OR public.shitreed_admin_role()='super_admin' OR (o.status='out_for_delivery' AND j.courier_id=a AND EXISTS(SELECT 1 FROM public.alani_delivery_couriers c WHERE c.store_id=o.store_id AND c.courier_id=a AND c.enabled)) END);
 ELSE
  RETURN EXISTS(SELECT 1 FROM public.alani_return_requests r JOIN public.stores s ON s.id=r.store_id
   WHERE r.id=target AND r.store_id='25091ca2-c0da-416c-b634-81b188ee66be'::uuid AND
   CASE WHEN p_write THEN r.customer_id=a AND r.status IN ('submitted','reviewing') AND r.reason IN ('damaged','wrong_item','defective','delivery_issue')
   ELSE r.customer_id=a OR s.owner_id=a OR public.shitreed_admin_role()='super_admin' END);
 END IF;
END $fn$;
REVOKE ALL ON FUNCTION public.alani_evidence_access(text,boolean) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.alani_evidence_access(text,boolean) TO authenticated;
CREATE POLICY alani_evidence_insert ON storage.objects FOR INSERT TO authenticated WITH CHECK(bucket_id='alani-private-evidence' AND public.alani_evidence_access(name,true));
CREATE POLICY alani_evidence_read ON storage.objects FOR SELECT TO authenticated USING(bucket_id='alani-private-evidence' AND public.alani_evidence_access(name,false));
CREATE POLICY alani_evidence_restrict_insert ON storage.objects AS RESTRICTIVE FOR INSERT TO authenticated WITH CHECK(bucket_id<>'alani-private-evidence' OR public.alani_evidence_access(name,true));
CREATE POLICY alani_evidence_restrict_read ON storage.objects AS RESTRICTIVE FOR SELECT TO authenticated USING(bucket_id<>'alani-private-evidence' OR public.alani_evidence_access(name,false));
CREATE POLICY alani_evidence_no_update ON storage.objects AS RESTRICTIVE FOR UPDATE TO authenticated USING(bucket_id<>'alani-private-evidence') WITH CHECK(bucket_id<>'alani-private-evidence');
CREATE POLICY alani_evidence_no_delete ON storage.objects AS RESTRICTIVE FOR DELETE TO authenticated USING(bucket_id<>'alani-private-evidence');
CREATE POLICY alani_evidence_no_guest ON storage.objects AS RESTRICTIVE FOR ALL TO anon USING(bucket_id<>'alani-private-evidence') WITH CHECK(bucket_id<>'alani-private-evidence');
