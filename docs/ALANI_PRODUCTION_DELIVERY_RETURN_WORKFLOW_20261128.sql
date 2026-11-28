SET LOCAL lock_timeout = '3s';
ALTER TABLE public.orders ADD COLUMN delivered_at timestamptz;
ALTER TABLE public.orders DROP CONSTRAINT orders_status_check, ADD CONSTRAINT orders_status_check CHECK (status IN ('placed','accepted','preparing','ready','rejected','cancelled','out_for_delivery','delivered'));
ALTER TABLE public.order_status_history DROP CONSTRAINT order_status_history_new_status_check, ADD CONSTRAINT order_status_history_new_status_check CHECK (new_status IN ('placed','accepted','preparing','ready','rejected','cancelled','out_for_delivery','delivered'));
ALTER TABLE public.alani_return_requests ADD COLUMN resolution_kind text CHECK (resolution_kind IN ('refund','replacement','compensation','no_payment')), ADD COLUMN planned_amount_iqd bigint CHECK(planned_amount_iqd>=0), ADD COLUMN planned_outbound_fee_iqd bigint CHECK(planned_outbound_fee_iqd IN (0,5000)), ADD COLUMN planned_return_fee_iqd bigint CHECK(planned_return_fee_iqd IN (0,5000));
GRANT SELECT ON public.alani_return_requests, public.alani_return_status_history TO authenticated;
ALTER POLICY alani_returns_read_participant ON public.alani_return_requests USING (customer_id=(SELECT auth.uid()) OR EXISTS (SELECT 1 FROM public.stores s WHERE s.id=alani_return_requests.store_id AND s.owner_id=(SELECT auth.uid())) OR public.shitreed_is_admin());
ALTER POLICY alani_return_events_participant ON public.alani_return_status_history USING (EXISTS (SELECT 1 FROM public.alani_return_requests r WHERE r.id=alani_return_status_history.return_id));
CREATE OR REPLACE FUNCTION public.alani_courier_complete_delivery(p_order_id uuid, p_code text, p_note text DEFAULT ''::text)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
 v_actor uuid:=(SELECT auth.uid());
 v_job public.alani_delivery_jobs%ROWTYPE;
 v_order public.orders%ROWTYPE;
 v_candidate_hash text;
BEGIN
 IF v_actor IS NULL THEN RAISE EXCEPTION 'LOGIN_REQUIRED'; END IF;
 IF NOT EXISTS (SELECT 1 FROM auth.sessions s WHERE s.user_id=v_actor AND s.id::text=(auth.jwt()->>'session_id') AND (s.not_after IS NULL OR s.not_after>now())) THEN RAISE EXCEPTION 'SESSION_EXPIRED'; END IF;
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
END $function$
;
REVOKE ALL ON FUNCTION public.alani_courier_complete_delivery(p_order_id uuid, p_code text, p_note text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.alani_courier_complete_delivery(p_order_id uuid, p_code text, p_note text) TO authenticated;
CREATE OR REPLACE FUNCTION public.alani_courier_pickup(p_order_id uuid)
 RETURNS timestamp with time zone
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
 v_actor uuid:=(SELECT auth.uid());v_job public.alani_delivery_jobs%ROWTYPE;
 v_status text;
BEGIN
 IF v_actor IS NULL THEN RAISE EXCEPTION 'LOGIN_REQUIRED'; END IF;
 IF NOT EXISTS (SELECT 1 FROM auth.sessions s WHERE s.user_id=v_actor AND s.id::text=(auth.jwt()->>'session_id') AND (s.not_after IS NULL OR s.not_after>now())) THEN RAISE EXCEPTION 'SESSION_EXPIRED'; END IF;
 -- Always lock orders BEFORE delivery_jobs (same order as completion and
 -- buyer-code issuance) so concurrent scans cannot deadlock.
 SELECT o.status INTO v_status FROM public.orders o
  WHERE o.id=p_order_id AND o.store_id=
    '25091ca2-c0da-416c-b634-81b188ee66be'::uuid FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'ORDER_NOT_FOUND'; END IF;
 SELECT * INTO v_job FROM public.alani_delivery_jobs
  WHERE order_id=p_order_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'DELIVERY_NOT_FOUND'; END IF;
 IF v_job.courier_id<>v_actor OR NOT EXISTS(
  SELECT 1 FROM public.alani_delivery_couriers c
   WHERE c.courier_id=v_actor AND c.store_id=v_job.store_id
     AND c.enabled=true)
 THEN RAISE EXCEPTION 'PERMISSION_DENIED'; END IF;
 IF v_status<>'out_for_delivery' THEN RAISE EXCEPTION 'ORDER_NOT_DISPATCHED'; END IF;
 UPDATE public.alani_delivery_jobs
  SET picked_up_at=COALESCE(picked_up_at,now())
  WHERE order_id=p_order_id RETURNING picked_up_at INTO v_job.picked_up_at;
 RETURN v_job.picked_up_at;
END $function$
;
REVOKE ALL ON FUNCTION public.alani_courier_pickup(p_order_id uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.alani_courier_pickup(p_order_id uuid) TO authenticated;
CREATE OR REPLACE FUNCTION public.alani_dispatch_delivery(p_order_id uuid, p_courier_id uuid)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
 v_actor uuid:=(SELECT auth.uid());
 v_order public.orders%ROWTYPE;
BEGIN
 IF v_actor IS NULL THEN RAISE EXCEPTION 'LOGIN_REQUIRED'; END IF;
 IF NOT EXISTS (SELECT 1 FROM auth.sessions s WHERE s.user_id=v_actor AND s.id::text=(auth.jwt()->>'session_id') AND (s.not_after IS NULL OR s.not_after>now())) THEN RAISE EXCEPTION 'SESSION_EXPIRED'; END IF;
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
 IF p_courier_id IS NULL OR p_courier_id=v_order.buyer_id THEN RAISE EXCEPTION 'INVALID_COURIER'; END IF;
 PERFORM 1 FROM public.alani_delivery_couriers c WHERE c.store_id=v_order.store_id AND c.courier_id=p_courier_id FOR UPDATE;
 IF NOT FOUND OR NOT EXISTS(
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
END $function$
;
REVOKE ALL ON FUNCTION public.alani_dispatch_delivery(p_order_id uuid, p_courier_id uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.alani_dispatch_delivery(p_order_id uuid, p_courier_id uuid) TO authenticated;
CREATE OR REPLACE FUNCTION public.alani_issue_delivery_pin(p_order_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
 v_actor uuid:=(SELECT auth.uid());v_order public.orders%ROWTYPE;
 v_job public.alani_delivery_jobs%ROWTYPE;
 v_nonce bytea;v_number bigint;v_code text;v_salt uuid;
 v_expires timestamptz;
BEGIN
 IF v_actor IS NULL THEN RAISE EXCEPTION 'LOGIN_REQUIRED'; END IF;
 IF NOT EXISTS (SELECT 1 FROM auth.sessions s WHERE s.user_id=v_actor AND s.id::text=(auth.jwt()->>'session_id') AND (s.not_after IS NULL OR s.not_after>now())) THEN RAISE EXCEPTION 'SESSION_EXPIRED'; END IF;
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
END $function$
;
REVOKE ALL ON FUNCTION public.alani_issue_delivery_pin(p_order_id uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.alani_issue_delivery_pin(p_order_id uuid) TO authenticated;
CREATE OR REPLACE FUNCTION public.alani_list_delivery_couriers()
 RETURNS TABLE(courier_id uuid, enabled boolean, active_jobs bigint)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
 v_actor uuid:=(SELECT auth.uid());
 v_store constant uuid:='25091ca2-c0da-416c-b634-81b188ee66be'::uuid;
BEGIN
 IF v_actor IS NULL THEN RAISE EXCEPTION 'LOGIN_REQUIRED'; END IF;
 IF NOT EXISTS (SELECT 1 FROM auth.sessions s WHERE s.user_id=v_actor AND s.id::text=(auth.jwt()->>'session_id') AND (s.not_after IS NULL OR s.not_after>now())) THEN RAISE EXCEPTION 'SESSION_EXPIRED'; END IF;
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
END $function$
;
REVOKE ALL ON FUNCTION public.alani_list_delivery_couriers() FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.alani_list_delivery_couriers() TO authenticated;
CREATE OR REPLACE FUNCTION public.alani_my_delivery_tasks()
 RETURNS TABLE(order_id uuid, delivery_address text, total_iqd bigint, delivery_fee_iqd bigint, status text, dispatched_at timestamp with time zone, picked_up_at timestamp with time zone)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE v_actor uuid:=(SELECT auth.uid());
BEGIN
 IF v_actor IS NULL THEN RAISE EXCEPTION 'LOGIN_REQUIRED'; END IF;
 IF NOT EXISTS (SELECT 1 FROM auth.sessions s WHERE s.user_id=v_actor AND s.id::text=(auth.jwt()->>'session_id') AND (s.not_after IS NULL OR s.not_after>now())) THEN RAISE EXCEPTION 'SESSION_EXPIRED'; END IF;
 RETURN QUERY SELECT o.id,o.delivery_address,o.total_iqd,o.delivery_fee_iqd,
   o.status,j.dispatched_at,j.picked_up_at
 FROM public.alani_delivery_jobs j
 JOIN public.orders o ON o.id=j.order_id
 JOIN public.alani_delivery_couriers c
  ON c.store_id=j.store_id AND c.courier_id=j.courier_id
 WHERE j.courier_id=v_actor AND c.enabled=true
  AND o.status='out_for_delivery'
 ORDER BY j.dispatched_at DESC LIMIT 100;
END $function$
;
REVOKE ALL ON FUNCTION public.alani_my_delivery_tasks() FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.alani_my_delivery_tasks() TO authenticated;
CREATE OR REPLACE FUNCTION public.alani_order_delivery_status(p_order_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE v_actor uuid:=(SELECT auth.uid());v_order public.orders%ROWTYPE;
 v_job public.alani_delivery_jobs%ROWTYPE;
BEGIN
 IF v_actor IS NULL THEN RAISE EXCEPTION 'LOGIN_REQUIRED'; END IF;
 IF NOT EXISTS (SELECT 1 FROM auth.sessions s WHERE s.user_id=v_actor AND s.id::text=(auth.jwt()->>'session_id') AND (s.not_after IS NULL OR s.not_after>now())) THEN RAISE EXCEPTION 'SESSION_EXPIRED'; END IF;
 SELECT * INTO v_order FROM public.orders WHERE id=p_order_id;
 IF NOT FOUND OR v_order.store_id<>
  '25091ca2-c0da-416c-b634-81b188ee66be'::uuid
 THEN RAISE EXCEPTION 'ORDER_NOT_FOUND'; END IF;
 SELECT * INTO v_job FROM public.alani_delivery_jobs WHERE order_id=p_order_id;
 IF v_order.buyer_id<>v_actor AND NOT EXISTS(
  SELECT 1 FROM public.stores s
   WHERE s.id=v_order.store_id AND s.owner_id=v_actor)
  AND NOT EXISTS (SELECT 1 FROM public.alani_delivery_couriers c WHERE c.store_id=v_job.store_id AND c.courier_id=v_actor AND c.enabled AND v_job.courier_id=v_actor)
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
END $function$
;
REVOKE ALL ON FUNCTION public.alani_order_delivery_status(p_order_id uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.alani_order_delivery_status(p_order_id uuid) TO authenticated;
CREATE OR REPLACE FUNCTION public.alani_owner_delivery_jobs()
 RETURNS TABLE(order_id uuid, courier_id uuid, status text, dispatched_at timestamp with time zone, picked_up_at timestamp with time zone, delivered_at timestamp with time zone)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE v_actor uuid:=(SELECT auth.uid());
BEGIN
 IF v_actor IS NULL THEN RAISE EXCEPTION 'LOGIN_REQUIRED'; END IF;
 IF NOT EXISTS (SELECT 1 FROM auth.sessions s WHERE s.user_id=v_actor AND s.id::text=(auth.jwt()->>'session_id') AND (s.not_after IS NULL OR s.not_after>now())) THEN RAISE EXCEPTION 'SESSION_EXPIRED'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.stores s
  WHERE s.id='25091ca2-c0da-416c-b634-81b188ee66be'::uuid AND
  (s.owner_id=v_actor OR public.shitreed_is_admin()))
 THEN RAISE EXCEPTION 'STORE_PERMISSION_DENIED'; END IF;
 RETURN QUERY SELECT j.order_id,j.courier_id,o.status,
  j.dispatched_at,j.picked_up_at,j.delivered_at
 FROM public.alani_delivery_jobs j
 JOIN public.orders o ON o.id=j.order_id
 ORDER BY j.dispatched_at DESC LIMIT 100;
END $function$
;
REVOKE ALL ON FUNCTION public.alani_owner_delivery_jobs() FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.alani_owner_delivery_jobs() TO authenticated;
CREATE OR REPLACE FUNCTION public.alani_request_return(p_order_id uuid, p_reason text, p_details text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_actor uuid := (select auth.uid());
  v_order public.orders%rowtype;
  v_id uuid;
begin
  if v_actor is null then raise exception 'LOGIN_REQUIRED'; end if;
 IF NOT EXISTS (SELECT 1 FROM auth.sessions s WHERE s.user_id=v_actor AND s.id::text=(auth.jwt()->>'session_id') AND (s.not_after IS NULL OR s.not_after>now())) THEN RAISE EXCEPTION 'SESSION_EXPIRED'; END IF;
  if p_reason is null or
    p_reason not in ('change_mind','damaged','wrong_item','defective','delivery_issue')
    or p_details is null or char_length(pg_catalog.btrim(p_details)) not between 15 and 2000
    then raise exception 'INVALID_RETURN_DETAILS'; end if;
  select * into v_order from public.orders where id=p_order_id for update;
  if not found or v_order.store_id<>'25091ca2-c0da-416c-b634-81b188ee66be'::uuid
    then raise exception 'ORDER_NOT_FOUND'; end if;
  if v_order.buyer_id<>v_actor then raise exception 'PERMISSION_DENIED'; end if;
  if v_order.status<>'delivered' then raise exception 'RETURN_REQUIRES_DELIVERY'; end if;
  select id into v_id from public.alani_return_requests
    where order_id=p_order_id and customer_id=v_actor
      and status in ('submitted','reviewing','approved','resolved')
    order by created_at desc limit 1;
  if v_id is not null then return v_id; end if;
  insert into public.alani_return_requests(store_id,order_id,customer_id,reason,details)
  values (v_order.store_id,v_order.id,v_actor,p_reason,pg_catalog.btrim(p_details))
  returning id into v_id;
  insert into public.alani_return_status_history(return_id,old_status,new_status,changed_by)
    values (v_id,null,'submitted',v_actor);
  return v_id;
end
$function$
;
REVOKE ALL ON FUNCTION public.alani_request_return(p_order_id uuid, p_reason text, p_details text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.alani_request_return(p_order_id uuid, p_reason text, p_details text) TO authenticated;
CREATE OR REPLACE FUNCTION public.alani_review_return(p_request_id uuid, p_new_status text, p_note text)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_actor uuid := (select auth.uid());
  v_request public.alani_return_requests%rowtype;
  v_owner uuid;
begin
  if v_actor is null then raise exception 'LOGIN_REQUIRED'; end if;
 IF NOT EXISTS (SELECT 1 FROM auth.sessions s WHERE s.user_id=v_actor AND s.id::text=(auth.jwt()->>'session_id') AND (s.not_after IS NULL OR s.not_after>now())) THEN RAISE EXCEPTION 'SESSION_EXPIRED'; END IF;
  if p_note is null or char_length(pg_catalog.btrim(p_note)) not between 10 and 1000
    then raise exception 'INVALID_REVIEW_NOTE'; end if;
  select * into v_request from public.alani_return_requests
    where id=p_request_id for update;
  if not found then raise exception 'RETURN_NOT_FOUND'; end if;
  select owner_id into v_owner from public.stores where id=v_request.store_id;
  if (v_owner is distinct from v_actor and not public.shitreed_is_admin()) or
     v_request.store_id<>'25091ca2-c0da-416c-b634-81b188ee66be'::uuid
    then raise exception 'PERMISSION_DENIED'; end if;
  if p_new_status is null or not (
    (v_request.status='submitted' and p_new_status in ('reviewing','declined')) or
    (v_request.status='reviewing' and p_new_status in ('approved','declined')) or
    (v_request.status='approved' and p_new_status='resolved')
  ) then raise exception 'INVALID_RETURN_TRANSITION'; end if;
  if p_new_status='resolved' and v_request.resolution_kind is null then raise exception 'RESOLUTION_PLAN_REQUIRED'; end if;
  update public.alani_return_requests
    set status=p_new_status,resolution_note=pg_catalog.btrim(p_note),updated_at=now()
    where id=v_request.id;
  insert into public.alani_return_status_history(return_id,old_status,new_status,changed_by)
    values (v_request.id,v_request.status,p_new_status,v_actor);
  return p_new_status;
end
$function$
;
REVOKE ALL ON FUNCTION public.alani_review_return(p_request_id uuid, p_new_status text, p_note text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.alani_review_return(p_request_id uuid, p_new_status text, p_note text) TO authenticated;
CREATE OR REPLACE FUNCTION public.alani_set_delivery_courier(p_courier_id uuid, p_enabled boolean)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
 v_actor uuid := (SELECT auth.uid());
 v_store constant uuid:='25091ca2-c0da-416c-b634-81b188ee66be'::uuid;
BEGIN
 IF v_actor IS NULL THEN RAISE EXCEPTION 'LOGIN_REQUIRED'; END IF;
 IF NOT EXISTS (SELECT 1 FROM auth.sessions s WHERE s.user_id=v_actor AND s.id::text=(auth.jwt()->>'session_id') AND (s.not_after IS NULL OR s.not_after>now())) THEN RAISE EXCEPTION 'SESSION_EXPIRED'; END IF;
 IF NOT EXISTS (SELECT 1 FROM public.stores s
     WHERE s.id=v_store AND s.status='approved'
       AND (s.owner_id=v_actor OR public.shitreed_is_admin()))
 THEN RAISE EXCEPTION 'STORE_PERMISSION_DENIED'; END IF;
 IF p_courier_id IS NULL OR p_enabled IS NULL OR
    NOT EXISTS (SELECT 1 FROM auth.users u WHERE u.id=p_courier_id)
 THEN RAISE EXCEPTION 'COURIER_ACCOUNT_NOT_FOUND'; END IF;
 PERFORM 1 FROM public.alani_delivery_couriers c WHERE c.store_id=v_store AND c.courier_id=p_courier_id FOR UPDATE;
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
END $function$
;
REVOKE ALL ON FUNCTION public.alani_set_delivery_courier(p_courier_id uuid, p_enabled boolean) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.alani_set_delivery_courier(p_courier_id uuid, p_enabled boolean) TO authenticated;

CREATE FUNCTION public.alani_plan_return_resolution(p_request_id uuid,p_kind text,p_amount_iqd bigint,p_outbound_fee_iqd bigint,p_return_fee_iqd bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $fn$
DECLARE a uuid:=auth.uid(); r public.alani_return_requests%rowtype; o public.orders%rowtype;
BEGIN
 IF a IS NULL THEN RAISE EXCEPTION 'LOGIN_REQUIRED'; END IF;
 IF NOT EXISTS(SELECT 1 FROM auth.sessions s WHERE s.user_id=a AND s.id::text=auth.jwt()->>'session_id' AND (s.not_after IS NULL OR s.not_after>now())) THEN RAISE EXCEPTION 'SESSION_EXPIRED'; END IF;
 SELECT * INTO r FROM public.alani_return_requests WHERE id=p_request_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'RETURN_NOT_FOUND'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.stores s WHERE s.id=r.store_id AND (s.owner_id=a OR public.shitreed_is_admin())) THEN RAISE EXCEPTION 'PERMISSION_DENIED'; END IF;
 IF r.status<>'approved' THEN RAISE EXCEPTION 'RETURN_NOT_APPROVED'; END IF;
 SELECT * INTO o FROM public.orders WHERE id=r.order_id AND store_id=r.store_id AND status='delivered';
 IF NOT FOUND THEN RAISE EXCEPTION 'ORDER_NOT_DELIVERED'; END IF;
 IF p_kind IS NULL OR p_kind NOT IN ('refund','replacement','compensation','no_payment') OR p_amount_iqd IS NULL OR p_amount_iqd NOT BETWEEN 0 AND o.total_iqd OR p_outbound_fee_iqd IS NULL OR p_outbound_fee_iqd NOT IN (0,5000) OR p_return_fee_iqd IS NULL OR p_return_fee_iqd NOT IN (0,5000) OR (p_kind IN ('replacement','no_payment') AND p_amount_iqd<>0) OR (p_kind IN ('refund','compensation') AND p_amount_iqd=0) OR (r.reason<>'change_mind' AND (p_outbound_fee_iqd<>0 OR p_return_fee_iqd<>0)) THEN RAISE EXCEPTION 'INVALID_RESOLUTION_PLAN'; END IF;
 UPDATE public.alani_return_requests SET resolution_kind=p_kind,planned_amount_iqd=p_amount_iqd,planned_outbound_fee_iqd=p_outbound_fee_iqd,planned_return_fee_iqd=p_return_fee_iqd,updated_at=now() WHERE id=r.id;
 RETURN jsonb_build_object('kind',p_kind,'planned_amount_iqd',p_amount_iqd,'outbound_fee_iqd',p_outbound_fee_iqd,'return_fee_iqd',p_return_fee_iqd,'payment_executed',false);
END;
$fn$;
REVOKE ALL ON FUNCTION public.alani_plan_return_resolution(uuid,text,bigint,bigint,bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.alani_plan_return_resolution(uuid,text,bigint,bigint,bigint) TO authenticated;
