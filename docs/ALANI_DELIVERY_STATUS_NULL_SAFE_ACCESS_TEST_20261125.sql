-- Security hardening on TEST: nonparticipant must be denied even with no assigned courier.
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
  AND COALESCE(v_job.courier_id<>v_actor,true)
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
