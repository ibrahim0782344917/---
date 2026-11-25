-- TEST-only lock order correction for concurrency safety.
CREATE OR REPLACE FUNCTION public.alani_courier_pickup(p_order_id uuid)
RETURNS timestamptz LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $fn$
DECLARE
 v_actor uuid:=(SELECT auth.uid());v_job public.alani_delivery_jobs%ROWTYPE;
 v_status text;
BEGIN
 IF v_actor IS NULL THEN RAISE EXCEPTION 'LOGIN_REQUIRED'; END IF;
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
END $fn$;
