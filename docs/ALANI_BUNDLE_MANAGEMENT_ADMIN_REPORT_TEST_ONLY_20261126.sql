-- TEST ONLY. Staff bundle management and admin-only reporting.
CREATE FUNCTION public.alani_manage_bundles_list_test()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE result jsonb;
BEGIN
 IF NOT private_checkout.alani_offer_staff_test() THEN RAISE EXCEPTION 'PERMISSION_DENIED'; END IF;
 SELECT coalesce(jsonb_agg(to_jsonb(t) ORDER BY t.starts_at DESC,t.id),'[]') INTO result FROM (
 SELECT id,title,items,price_iqd,free_delivery,starts_at,ends_at,enabled FROM private_checkout.alani_bundle_test ORDER BY starts_at DESC,id LIMIT 200) t;
 RETURN result;
END $$;
CREATE FUNCTION public.alani_bundle_enabled_test(p_bundle uuid,p_enabled boolean)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN
 IF NOT private_checkout.alani_offer_staff_test() THEN RAISE EXCEPTION 'PERMISSION_DENIED'; END IF;
 IF p_enabled IS NULL THEN RAISE EXCEPTION 'INVALID_INPUT'; END IF;
 UPDATE private_checkout.alani_bundle_test SET enabled=p_enabled WHERE id=p_bundle;
 IF NOT FOUND THEN RAISE EXCEPTION 'BUNDLE_UNAVAILABLE'; END IF;
 RETURN p_enabled;
END $$;
CREATE FUNCTION public.alani_admin_business_overview_test()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
BEGIN
 IF auth.uid() IS NULL OR NOT public.shitreed_is_admin() THEN RAISE EXCEPTION 'ADMIN_ACCESS_REQUIRED'; END IF;
 RETURN jsonb_build_object('operations',public.alani_business_report_test(),'debts',public.alani_debt_report_test(),'trial_balance',public.alani_operational_trial_balance_test(),'pos_margin',public.alani_pos_margin_test());
END $$;
REVOKE ALL ON FUNCTION public.alani_manage_bundles_list_test(),public.alani_bundle_enabled_test(uuid,boolean),public.alani_admin_business_overview_test() FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.alani_manage_bundles_list_test(),public.alani_bundle_enabled_test(uuid,boolean),public.alani_admin_business_overview_test() TO authenticated;
