-- TEST ONLY. On-demand account alerts, not a push queue or auto-order scheduler.
CREATE FUNCTION public.alani_customer_alerts_test()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE result jsonb;
BEGIN
 IF auth.uid() IS NULL THEN RAISE EXCEPTION 'LOGIN_REQUIRED'; END IF;
 WITH favorites AS (SELECT value AS v FROM jsonb_array_elements(public.alani_my_favorites_test())),
 subscriptions AS (SELECT value AS v FROM jsonb_array_elements(public.alani_my_subscriptions_test())),
 alerts AS (
 SELECT 'price_drop'::text AS kind,v->>'id' AS product_id,v->>'name' AS name,v->'price_iqd' AS price_iqd,NULL::text AS review_at FROM favorites WHERE (v->>'price_dropped')::boolean
 UNION ALL SELECT 'restocked',v->>'id',v->>'name',v->'price_iqd',NULL FROM favorites WHERE (v->>'restocked')::boolean
 UNION ALL SELECT 'monthly_review',v->>'product_id',v->>'name',NULL::jsonb,v->>'next_review_at' FROM subscriptions WHERE (v->>'active')::boolean AND (v->>'next_review_at')::timestamptz<=now()
 )
 SELECT coalesce(jsonb_agg(to_jsonb(t) ORDER BY kind,product_id),'[]') INTO result FROM (SELECT * FROM alerts ORDER BY kind,product_id LIMIT 100)t;
 RETURN result;
END $$;
REVOKE ALL ON FUNCTION public.alani_customer_alerts_test() FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.alani_customer_alerts_test() TO authenticated;
