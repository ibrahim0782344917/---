-- TEST ONLY; no actual money transfer. Report scoped by actor, not by client IDs.
CREATE FUNCTION public.alani_cod_report_test(p_mode text)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE a uuid:=auth.uid(); s constant uuid:='25091ca2-c0da-416c-b634-81b188ee66be'; result jsonb;
BEGIN
 IF a IS NULL THEN RAISE EXCEPTION 'LOGIN_REQUIRED'; END IF;
 IF p_mode='staff' THEN
  IF NOT EXISTS(SELECT 1 FROM public.stores st WHERE st.id=s AND (st.owner_id=a OR public.shitreed_is_admin())) THEN RAISE EXCEPTION 'PERMISSION_DENIED'; END IF;
 ELSIF p_mode='courier' THEN
  IF NOT EXISTS(SELECT 1 FROM public.alani_delivery_couriers c WHERE c.store_id=s AND c.courier_id=a AND c.enabled) THEN RAISE EXCEPTION 'PERMISSION_DENIED'; END IF;
 ELSE RAISE EXCEPTION 'INVALID_MODE';
 END IF;
 WITH scoped AS (
 SELECT o.id AS order_id,o.total_iqd,j.courier_id,j.delivered_at,
 CASE WHEN r.confirmed_at IS NOT NULL THEN 'confirmed' WHEN r.order_id IS NOT NULL THEN 'recorded' ELSE 'unrecorded' END AS status,
 r.recorded_at,r.confirmed_at,
 (SELECT count(*) FROM public.alani_return_requests rr WHERE rr.order_id=o.id AND rr.status='approved') AS approved_returns,
 (p_mode='staff' AND r.order_id IS NOT NULL AND r.confirmed_at IS NULL AND r.courier_id<>a) AS can_confirm
 FROM public.orders o JOIN public.alani_delivery_jobs j ON j.order_id=o.id AND j.store_id=o.store_id
 LEFT JOIN private_checkout.alani_cod_receipts_test r ON r.order_id=o.id
 WHERE o.store_id=s AND o.status='delivered' AND o.payment_method='cash_on_delivery' AND j.proof_method='buyer_one_time_pin' AND j.delivered_at IS NOT NULL
 AND (p_mode='staff' OR j.courier_id=a)
 )
 SELECT jsonb_build_object(
 'unrecorded_iqd',coalesce(sum(total_iqd) FILTER(WHERE status='unrecorded'),0),
 'recorded_iqd',coalesce(sum(total_iqd) FILTER(WHERE status='recorded'),0),
 'confirmed_iqd',coalesce(sum(total_iqd) FILTER(WHERE status='confirmed'),0),
 'total_count',count(*),
 'items',coalesce((SELECT jsonb_agg(to_jsonb(t) ORDER BY t.delivered_at DESC,t.order_id) FROM (SELECT * FROM scoped ORDER BY delivered_at DESC,order_id LIMIT 100) t),'[]'::jsonb)
 ) INTO result FROM scoped;
 RETURN result;
END $$;
REVOKE ALL ON FUNCTION public.alani_cod_report_test(text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.alani_cod_report_test(text) TO authenticated;
