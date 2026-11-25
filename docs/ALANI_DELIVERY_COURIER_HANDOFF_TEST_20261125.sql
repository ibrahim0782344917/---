-- Al-Ani delivery assignment, courier pickup, and buyer-authorized handover.
-- ISOLATED SHITREED-TEST ONLY (tgvdwotbrnhcoykuxdpr).
-- Production requires a verified restored backup and an approved release review.
-- Fee remains 5,000 IQD, calculated by the pre-existing server-side checkout.
BEGIN;

ALTER TABLE public.orders DROP CONSTRAINT IF EXISTS orders_status_check;
ALTER TABLE public.orders ADD CONSTRAINT orders_status_check CHECK
 (status IN ('placed','accepted','preparing','ready','out_for_delivery',
             'delivered','rejected','cancelled'));
ALTER TABLE public.order_status_history DROP CONSTRAINT IF EXISTS order_status_history_new_status_check;
ALTER TABLE public.order_status_history ADD CONSTRAINT order_status_history_new_status_check CHECK
 (new_status IN ('placed','accepted','preparing','ready','out_for_delivery',
                 'delivered','rejected','cancelled'));

CREATE TABLE public.alani_delivery_couriers (
  store_id uuid NOT NULL REFERENCES public.stores(id) ON DELETE RESTRICT,
  courier_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
  enabled boolean NOT NULL DEFAULT true,
  added_by uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
  added_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (store_id,courier_id),
  CONSTRAINT alani_delivery_courier_store_check CHECK
    (store_id='25091ca2-c0da-416c-b634-81b188ee66be'::uuid)
);
CREATE TABLE public.alani_delivery_jobs (
  order_id uuid PRIMARY KEY REFERENCES public.orders(id) ON DELETE RESTRICT,
  store_id uuid NOT NULL REFERENCES public.stores(id) ON DELETE RESTRICT,
  courier_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
  dispatched_by uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
  dispatched_at timestamptz NOT NULL DEFAULT now(),
  picked_up_at timestamptz,
  delivered_at timestamptz,
  delivery_note text NOT NULL DEFAULT '' CHECK (char_length(delivery_note)<=300),
  proof_method text CHECK (proof_method IS NULL OR proof_method='buyer_one_time_pin'),
  pin_salt uuid,
  pin_hash text,
  pin_issued_at timestamptz,
  pin_expires_at timestamptz,
  failed_attempts integer NOT NULL DEFAULT 0 CHECK (failed_attempts BETWEEN 0 AND 5),
  CONSTRAINT alani_delivery_job_store_check CHECK
    (store_id='25091ca2-c0da-416c-b634-81b188ee66be'::uuid),
  CONSTRAINT alani_delivery_job_pin_pair CHECK (
    (pin_salt IS NULL AND pin_hash IS NULL AND pin_expires_at IS NULL)
    OR (pin_salt IS NOT NULL AND pin_hash IS NOT NULL AND pin_expires_at IS NOT NULL))
);
CREATE INDEX alani_delivery_courier_jobs_idx
  ON public.alani_delivery_jobs(courier_id,dispatched_at DESC);
ALTER TABLE public.alani_delivery_couriers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.alani_delivery_jobs ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.alani_delivery_couriers FROM PUBLIC,anon,authenticated;
REVOKE ALL ON public.alani_delivery_jobs FROM PUBLIC,anon,authenticated;
-- No direct client access to delivery jobs or customer addresses.
-- Read and write access is only through the participant-checked functions below.

CREATE OR REPLACE FUNCTION public.alani_set_delivery_courier(
 p_courier_id uuid,p_enabled boolean
) RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $fn$
DECLARE
 v_actor uuid := (SELECT auth.uid());
 v_store constant uuid:='25091ca2-c0da-416c-b634-81b188ee66be'::uuid;
BEGIN
 IF v_actor IS NULL THEN RAISE EXCEPTION 'LOGIN_REQUIRED'; END IF;
 IF NOT EXISTS (SELECT 1 FROM public.stores s
     WHERE s.id=v_store AND s.status='approved'
       AND (s.owner_id=v_actor OR public.shitreed_is_admin()))
 THEN RAISE EXCEPTION 'STORE_PERMISSION_DENIED'; END IF;
 IF p_courier_id IS NULL OR p_enabled IS NULL OR
    NOT EXISTS (SELECT 1 FROM auth.users u WHERE u.id=p_courier_id)
 THEN RAISE EXCEPTION 'COURIER_ACCOUNT_NOT_FOUND'; END IF;
 IF NOT p_enabled AND EXISTS(
   SELECT 1 FROM public.alani_delivery_jobs j
   JOIN public.orders o ON o.id=j.order_id
   WHERE j.courier_id=p_courier_id AND o.status='out_for_delivery'
 ) THEN RAISE EXCEPTION 'COURIER_HAS_ACTIVE_DELIVERIES'; END IF;
 INSERT INTO public.alani_delivery_couriers(
   store_id,courier_id,enabled,added_by)
 VALUES(v_store,p_courier_id,p_enabled,v_actor)
 ON CONFLICT (store_id,courier_id) DO UPDATE SET
  enabled=EXCLUDED.enabled, updated_at=now();
 RETURN p_enabled;
END $fn$;

CREATE OR REPLACE FUNCTION public.alani_list_delivery_couriers()
RETURNS TABLE (courier_id uuid, enabled boolean, active_jobs bigint)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO '' AS $fn$
DECLARE
 v_actor uuid:=(SELECT auth.uid());
 v_store constant uuid:='25091ca2-c0da-416c-b634-81b188ee66be'::uuid;
BEGIN
 IF v_actor IS NULL THEN RAISE EXCEPTION 'LOGIN_REQUIRED'; END IF;
 IF NOT EXISTS(
   SELECT 1 FROM public.stores s WHERE s.id=v_store
     AND (s.owner_id=v_actor OR public.shitreed_is_admin()))
 THEN RAISE EXCEPTION 'STORE_PERMISSION_DENIED'; END IF;
 RETURN QUERY SELECT c.courier_id,c.enabled,
  (SELECT count(*) FROM public.alani_delivery_jobs j
     JOIN public.orders o ON o.id=j.order_id
     WHERE j.courier_id=c.courier_id AND o.status='out_for_delivery')
   FROM public.alani_delivery_couriers c
   WHERE c.store_id=v_store ORDER BY c.added_at DESC LIMIT 100;
END $fn$;

CREATE OR REPLACE FUNCTION public.alani_dispatch_delivery(
 p_order_id uuid,p_courier_id uuid
) RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $fn$
DECLARE
 v_actor uuid:=(SELECT auth.uid());
 v_order public.orders%ROWTYPE;
BEGIN
 IF v_actor IS NULL THEN RAISE EXCEPTION 'LOGIN_REQUIRED'; END IF;
 SELECT * INTO v_order FROM public.orders o
  WHERE o.id=p_order_id FOR UPDATE;
 IF NOT FOUND OR v_order.store_id <>
  '25091ca2-c0da-416c-b634-81b188ee66be'::uuid
 THEN RAISE EXCEPTION 'ORDER_NOT_FOUND'; END IF;
 IF NOT EXISTS(
  SELECT 1 FROM public.stores s WHERE s.id=v_order.store_id
   AND s.status='approved' AND
   (s.owner_id=v_actor OR public.shitreed_is_admin()))
 THEN RAISE EXCEPTION 'PERMISSION_DENIED'; END IF;
 IF v_order.status<>'ready' THEN RAISE EXCEPTION 'ORDER_NOT_READY'; END IF;
 IF p_courier_id IS NULL OR NOT EXISTS(
   SELECT 1 FROM public.alani_delivery_couriers c
   WHERE c.store_id=v_order.store_id AND c.courier_id=p_courier_id
     AND c.enabled=true)
 THEN RAISE EXCEPTION 'COURIER_NOT_APPROVED'; END IF;
 INSERT INTO public.alani_delivery_jobs(
   order_id,store_id,courier_id,dispatched_by)
 VALUES(p_order_id,v_order.store_id,p_courier_id,v_actor);
 UPDATE public.orders SET
   status='out_for_delivery',updated_at=now()
 WHERE id=p_order_id;
 RETURN 'out_for_delivery';
END $fn$;

CREATE OR REPLACE FUNCTION public.alani_courier_pickup(p_order_id uuid)
RETURNS timestamptz LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $fn$
DECLARE
 v_actor uuid:=(SELECT auth.uid());v_job public.alani_delivery_jobs%ROWTYPE;
 v_status text;
BEGIN
 IF v_actor IS NULL THEN RAISE EXCEPTION 'LOGIN_REQUIRED'; END IF;
 SELECT * INTO v_job FROM public.alani_delivery_jobs
  WHERE order_id=p_order_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'DELIVERY_NOT_FOUND'; END IF;
 IF v_job.courier_id<>v_actor OR NOT EXISTS(
  SELECT 1 FROM public.alani_delivery_couriers c
   WHERE c.courier_id=v_actor AND c.store_id=v_job.store_id
     AND c.enabled=true)
 THEN RAISE EXCEPTION 'PERMISSION_DENIED'; END IF;
 SELECT status INTO v_status FROM public.orders WHERE id=p_order_id FOR UPDATE;
 IF v_status<>'out_for_delivery' THEN RAISE EXCEPTION 'ORDER_NOT_DISPATCHED'; END IF;
 UPDATE public.alani_delivery_jobs
  SET picked_up_at=COALESCE(picked_up_at,now())
  WHERE order_id=p_order_id RETURNING picked_up_at INTO v_job.picked_up_at;
 RETURN v_job.picked_up_at;
END $fn$;

CREATE OR REPLACE FUNCTION public.alani_issue_delivery_pin(p_order_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $fn$
DECLARE
 v_actor uuid:=(SELECT auth.uid());v_order public.orders%ROWTYPE;
 v_job public.alani_delivery_jobs%ROWTYPE;
 v_nonce bytea;v_number bigint;v_code text;v_salt uuid;
 v_expires timestamptz;
BEGIN
 IF v_actor IS NULL THEN RAISE EXCEPTION 'LOGIN_REQUIRED'; END IF;
 SELECT * INTO v_order FROM public.orders
  WHERE id=p_order_id FOR UPDATE;
 IF NOT FOUND OR v_order.store_id<>
    '25091ca2-c0da-416c-b634-81b188ee66be'::uuid
 THEN RAISE EXCEPTION 'ORDER_NOT_FOUND'; END IF;
 IF v_order.buyer_id<>v_actor THEN RAISE EXCEPTION 'PERMISSION_DENIED'; END IF;
 IF v_order.status<>'out_for_delivery' THEN
  RAISE EXCEPTION 'ORDER_NOT_OUT_FOR_DELIVERY'; END IF;
 SELECT * INTO v_job FROM public.alani_delivery_jobs
  WHERE order_id=p_order_id FOR UPDATE;
 IF NOT FOUND OR v_job.picked_up_at IS NULL
 THEN RAISE EXCEPTION 'COURIER_HAS_NOT_PICKED_UP'; END IF;
 IF v_job.pin_issued_at IS NOT NULL AND
    v_job.pin_issued_at>now()-interval '60 seconds'
 THEN RAISE EXCEPTION 'CODE_REISSUE_WAIT'; END IF;
 v_nonce:=extensions.gen_random_bytes(4);
 v_number:=get_byte(v_nonce,0)::bigint*16777216+
    get_byte(v_nonce,1)::bigint*65536+
    get_byte(v_nonce,2)::bigint*256+get_byte(v_nonce,3);
 v_code:=lpad((100000+(v_number%900000))::text,6,'0');
 v_salt:=gen_random_uuid();
 v_expires:=now()+interval '15 minutes';
 UPDATE public.alani_delivery_jobs SET
   pin_salt=v_salt,
   pin_hash=encode(sha256(convert_to(
      v_code||':'||p_order_id::text||':'||v_salt::text,'UTF8')),'hex'),
   pin_issued_at=now(),pin_expires_at=v_expires,failed_attempts=0
 WHERE order_id=p_order_id;
 -- PIN is returned ONCE to the buyer; never to the courier or owner.
 RETURN jsonb_build_object('code',v_code,'expires_at',v_expires);
END $fn$;

CREATE OR REPLACE FUNCTION public.alani_courier_complete_delivery(
 p_order_id uuid,p_code text,p_note text DEFAULT ''
) RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $fn$
DECLARE
 v_actor uuid:=(SELECT auth.uid());
 v_job public.alani_delivery_jobs%ROWTYPE;
 v_order public.orders%ROWTYPE;
 v_candidate_hash text;
BEGIN
 IF v_actor IS NULL THEN RAISE EXCEPTION 'LOGIN_REQUIRED'; END IF;
 IF p_code IS NULL OR p_code !~ '^[0-9]{6}$' OR
    p_note IS NULL OR char_length(btrim(p_note))>300
 THEN RAISE EXCEPTION 'INVALID_DELIVERY_PROOF'; END IF;
 SELECT * INTO v_order FROM public.orders WHERE id=p_order_id FOR UPDATE;
 IF NOT FOUND OR v_order.store_id<>
   '25091ca2-c0da-416c-b634-81b188ee66be'::uuid
 THEN RAISE EXCEPTION 'ORDER_NOT_FOUND'; END IF;
 SELECT * INTO v_job FROM public.alani_delivery_jobs
  WHERE order_id=p_order_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'DELIVERY_NOT_FOUND'; END IF;
 IF v_job.courier_id<>v_actor OR NOT EXISTS(
   SELECT 1 FROM public.alani_delivery_couriers c WHERE c.store_id=v_job.store_id
    AND c.courier_id=v_actor AND c.enabled=true)
 THEN RAISE EXCEPTION 'PERMISSION_DENIED'; END IF;
 IF v_order.status='delivered' AND v_job.delivered_at IS NOT NULL
 THEN RETURN 'delivered'; END IF;
 IF v_order.status<>'out_for_delivery'
 THEN RAISE EXCEPTION 'ORDER_NOT_OUT_FOR_DELIVERY'; END IF;
 IF v_job.picked_up_at IS NULL THEN RAISE EXCEPTION 'COURIER_HAS_NOT_PICKED_UP'; END IF;
 IF v_job.pin_hash IS NULL THEN RETURN 'CODE_NOT_ISSUED'; END IF;
 IF v_job.pin_expires_at<=now() THEN RETURN 'CODE_EXPIRED'; END IF;
 IF v_job.failed_attempts>=5 THEN RETURN 'CODE_LOCKED'; END IF;
 v_candidate_hash:=encode(sha256(convert_to(
   p_code||':'||p_order_id::text||':'||v_job.pin_salt::text,'UTF8')),'hex');
 IF v_candidate_hash<>v_job.pin_hash THEN
  UPDATE public.alani_delivery_jobs SET
    failed_attempts=LEAST(failed_attempts+1,5) WHERE order_id=p_order_id;
  -- Never RAISE here: the attempt counter must commit on a wrong PIN.
  RETURN 'WRONG_CODE';
 END IF;
 UPDATE public.alani_delivery_jobs SET
  delivered_at=now(),proof_method='buyer_one_time_pin',
  delivery_note=btrim(p_note),
  pin_salt=NULL,pin_hash=NULL,pin_expires_at=NULL
 WHERE order_id=p_order_id;
 UPDATE public.orders SET status='delivered',
  delivered_at=now(),updated_at=now()
 WHERE id=p_order_id;
 RETURN 'delivered';
END $fn$;

CREATE OR REPLACE FUNCTION public.alani_my_delivery_tasks()
RETURNS TABLE(order_id uuid,delivery_address text,total_iqd bigint,
 delivery_fee_iqd bigint,status text,dispatched_at timestamptz,
 picked_up_at timestamptz)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO '' AS $fn$
DECLARE v_actor uuid:=(SELECT auth.uid());
BEGIN
 IF v_actor IS NULL THEN RAISE EXCEPTION 'LOGIN_REQUIRED'; END IF;
 RETURN QUERY SELECT o.id,o.delivery_address,o.total_iqd,o.delivery_fee_iqd,
   o.status,j.dispatched_at,j.picked_up_at
 FROM public.alani_delivery_jobs j
 JOIN public.orders o ON o.id=j.order_id
 JOIN public.alani_delivery_couriers c
  ON c.store_id=j.store_id AND c.courier_id=j.courier_id
 WHERE j.courier_id=v_actor AND c.enabled=true
  AND o.status='out_for_delivery'
 ORDER BY j.dispatched_at DESC LIMIT 100;
END $fn$;

CREATE OR REPLACE FUNCTION public.alani_owner_delivery_jobs()
RETURNS TABLE(order_id uuid,courier_id uuid,status text,
 dispatched_at timestamptz,picked_up_at timestamptz,delivered_at timestamptz)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO '' AS $fn$
DECLARE v_actor uuid:=(SELECT auth.uid());
BEGIN
 IF v_actor IS NULL THEN RAISE EXCEPTION 'LOGIN_REQUIRED'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.stores s
  WHERE s.id='25091ca2-c0da-416c-b634-81b188ee66be'::uuid AND
  (s.owner_id=v_actor OR public.shitreed_is_admin()))
 THEN RAISE EXCEPTION 'STORE_PERMISSION_DENIED'; END IF;
 RETURN QUERY SELECT j.order_id,j.courier_id,o.status,
  j.dispatched_at,j.picked_up_at,j.delivered_at
 FROM public.alani_delivery_jobs j
 JOIN public.orders o ON o.id=j.order_id
 ORDER BY j.dispatched_at DESC LIMIT 100;
END $fn$;

CREATE OR REPLACE FUNCTION public.alani_order_delivery_status(p_order_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO '' AS $fn$
DECLARE v_actor uuid:=(SELECT auth.uid());v_order public.orders%ROWTYPE;
 v_job public.alani_delivery_jobs%ROWTYPE;
BEGIN
 IF v_actor IS NULL THEN RAISE EXCEPTION 'LOGIN_REQUIRED'; END IF;
 SELECT * INTO v_order FROM public.orders WHERE id=p_order_id;
 IF NOT FOUND OR v_order.store_id<>
  '25091ca2-c0da-416c-b634-81b188ee66be'::uuid
 THEN RAISE EXCEPTION 'ORDER_NOT_FOUND'; END IF;
 SELECT * INTO v_job FROM public.alani_delivery_jobs WHERE order_id=p_order_id;
 IF v_order.buyer_id<>v_actor AND NOT EXISTS(
  SELECT 1 FROM public.stores s
   WHERE s.id=v_order.store_id AND s.owner_id=v_actor)
  AND NOT (v_job.courier_id=v_actor)
  AND NOT public.shitreed_is_admin()
 THEN RAISE EXCEPTION 'PERMISSION_DENIED'; END IF;
 RETURN jsonb_build_object(
  'order_id',v_order.id,'status',v_order.status,
  'assigned',v_job.order_id IS NOT NULL,
  'dispatched_at',v_job.dispatched_at,
  'picked_up_at',v_job.picked_up_at,
  'delivered_at',v_job.delivered_at,
  'proof_method',v_job.proof_method,
  'delivery_fee_iqd',v_order.delivery_fee_iqd);
END $fn$;

-- Disable only the two legacy receipt shortcuts for this store:
-- all other stores retain their original order lifecycle.
CREATE OR REPLACE FUNCTION public.alani_confirm_received(p_order_id uuid)
RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $fn$
DECLARE v_actor uuid:=(SELECT auth.uid());v_order public.orders%ROWTYPE;
BEGIN
 IF v_actor IS NULL THEN RAISE EXCEPTION 'LOGIN_REQUIRED'; END IF;
 SELECT * INTO v_order FROM public.orders WHERE id=p_order_id FOR UPDATE;
 IF NOT FOUND OR v_order.store_id<>
  '25091ca2-c0da-416c-b634-81b188ee66be'::uuid
 THEN RAISE EXCEPTION 'ORDER_NOT_FOUND'; END IF;
 IF v_order.buyer_id<>v_actor THEN RAISE EXCEPTION 'PERMISSION_DENIED'; END IF;
 IF v_order.status='delivered' THEN RETURN 'delivered'; END IF;
 RAISE EXCEPTION 'ALANI_USE_VERIFIED_DELIVERY_HANDOFF';
END $fn$;
CREATE OR REPLACE FUNCTION public.confirm_cash_order_receipt(p_order_id uuid)
RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $fn$
DECLARE v_order public.orders%ROWTYPE;
BEGIN
 IF auth.uid() IS NULL THEN RAISE EXCEPTION 'LOGIN_REQUIRED'; END IF;
 SELECT * INTO v_order FROM public.orders WHERE id=p_order_id FOR UPDATE;
 IF NOT FOUND OR v_order.buyer_id IS DISTINCT FROM auth.uid()
 THEN RAISE EXCEPTION 'ORDER_NOT_FOUND'; END IF;
 IF v_order.store_id='25091ca2-c0da-416c-b634-81b188ee66be'::uuid
 THEN RAISE EXCEPTION 'ALANI_USE_VERIFIED_DELIVERY_HANDOFF'; END IF;
 IF v_order.status<>'ready' THEN RAISE EXCEPTION 'ORDER_NOT_READY_FOR_RECEIPT'; END IF;
 UPDATE public.orders SET status='delivered',delivered_at=now(),updated_at=now()
 WHERE id=v_order.id;
 RETURN 'delivered';
END $fn$;

REVOKE ALL ON FUNCTION public.alani_set_delivery_courier(uuid,boolean) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.alani_list_delivery_couriers() FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.alani_dispatch_delivery(uuid,uuid) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.alani_courier_pickup(uuid) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.alani_issue_delivery_pin(uuid) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.alani_courier_complete_delivery(uuid,text,text) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.alani_my_delivery_tasks() FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.alani_owner_delivery_jobs() FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.alani_order_delivery_status(uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.alani_set_delivery_courier(uuid,boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION public.alani_list_delivery_couriers() TO authenticated;
GRANT EXECUTE ON FUNCTION public.alani_dispatch_delivery(uuid,uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.alani_courier_pickup(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.alani_issue_delivery_pin(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.alani_courier_complete_delivery(uuid,text,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.alani_my_delivery_tasks() TO authenticated;
GRANT EXECUTE ON FUNCTION public.alani_owner_delivery_jobs() TO authenticated;
GRANT EXECUTE ON FUNCTION public.alani_order_delivery_status(uuid) TO authenticated;

COMMENT ON TABLE public.alani_delivery_jobs IS
 'TEST only: assigned delivery and buyer-PIN handoff, with no client table grants.';
COMMENT ON FUNCTION public.alani_issue_delivery_pin(uuid) IS
 'Short lived six-digit buyer PIN, server stores salted SHA256 hash only.';
COMMENT ON FUNCTION public.alani_courier_complete_delivery(uuid,text,text) IS
 'Assigned courier only: five persisted incorrect attempts and verified delivery.';
COMMIT;
