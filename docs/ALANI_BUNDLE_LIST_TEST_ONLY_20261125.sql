-- TEST ONLY: list active bundle previews; final quote checks stock and price.
CREATE FUNCTION public.alani_list_bundles_test()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE result jsonb;
BEGIN
 IF auth.uid() IS NULL THEN RAISE EXCEPTION 'LOGIN_REQUIRED'; END IF;
 SELECT coalesce(jsonb_agg(to_jsonb(t) ORDER BY t.starts_at DESC,t.id),'[]'::jsonb) INTO result FROM (
 SELECT id,title,price_iqd,free_delivery,starts_at,ends_at FROM private_checkout.alani_bundle_test
 WHERE enabled AND starts_at<=now() AND ends_at>now() ORDER BY starts_at DESC,id LIMIT 100
 ) t;
 RETURN result;
END $$;
REVOKE ALL ON FUNCTION public.alani_list_bundles_test() FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.alani_list_bundles_test() TO authenticated;
