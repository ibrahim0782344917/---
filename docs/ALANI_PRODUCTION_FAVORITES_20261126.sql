-- Production port of TEST favorites only. No rewards, automatic orders or financial writes.
BEGIN;
SET LOCAL lock_timeout='3s';
SET LOCAL statement_timeout='30s';
DO $guard$ BEGIN
 IF NOT public.shitreed_alani_checkout_schema_ready()
 OR to_regclass('private_checkout.alani_favorites') IS NOT NULL
 OR NOT EXISTS(SELECT 1 FROM public.stores WHERE id='25091ca2-c0da-416c-b634-81b188ee66be' AND status='approved')
 THEN RAISE EXCEPTION 'FAVORITES_PREFLIGHT_FAILED'; END IF;
END $guard$;
CREATE TABLE private_checkout.alani_favorites(
 user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
 product_id uuid NOT NULL REFERENCES public.products(id) ON DELETE CASCADE,
 saved_price_iqd integer NOT NULL CHECK(saved_price_iqd>=0),
 saved_stock integer NOT NULL CHECK(saved_stock>=0),
 created_at timestamptz NOT NULL DEFAULT now(), PRIMARY KEY(user_id,product_id)
);
ALTER TABLE private_checkout.alani_favorites ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private_checkout.alani_favorites FROM PUBLIC,anon,authenticated;
CREATE FUNCTION public.alani_set_favorite(p_product_id uuid,p_saved boolean)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE a uuid:=auth.uid(); p public.products%ROWTYPE;
BEGIN
 IF a IS NULL THEN RAISE EXCEPTION 'LOGIN_REQUIRED'; END IF;
 IF p_saved IS NULL OR p_product_id IS NULL THEN RAISE EXCEPTION 'INVALID_INPUT'; END IF;
 IF NOT p_saved THEN
  DELETE FROM private_checkout.alani_favorites WHERE user_id=a AND product_id=p_product_id;
  RETURN false;
 END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('alani_favorites:'||a::text,0));
 SELECT pr.* INTO p FROM public.products pr JOIN public.stores s ON s.id=pr.store_id
 WHERE pr.id=p_product_id AND pr.is_active AND s.status='approved' AND pr.store_id='25091ca2-c0da-416c-b634-81b188ee66be'::uuid;
 IF NOT FOUND THEN RAISE EXCEPTION 'PRODUCT_UNAVAILABLE'; END IF;
 IF EXISTS(SELECT 1 FROM private_checkout.alani_favorites WHERE user_id=a AND product_id=p.id) THEN RETURN true; END IF;
 IF (SELECT count(*) FROM private_checkout.alani_favorites WHERE user_id=a)>=200 THEN RAISE EXCEPTION 'FAVORITES_LIMIT'; END IF;
 INSERT INTO private_checkout.alani_favorites(user_id,product_id,saved_price_iqd,saved_stock)
 VALUES(a,p.id,p.price_iqd,p.stock_quantity);
 RETURN true;
END $$;
CREATE FUNCTION public.alani_my_favorites()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE a uuid:=auth.uid(); result jsonb;
BEGIN
 IF a IS NULL THEN RAISE EXCEPTION 'LOGIN_REQUIRED'; END IF;
 SELECT coalesce(jsonb_agg(to_jsonb(t) ORDER BY t.created_at DESC),'[]'::jsonb) INTO result FROM (
 SELECT p.id,p.store_id,p.name,p.description,p.image_url,p.stock_quantity,
 p.price_iqd AS price_iqd,
 f.saved_price_iqd,f.saved_stock,f.created_at,
 p.price_iqd<f.saved_price_iqd AS price_dropped,
 f.saved_stock=0 AND p.stock_quantity>0 AS restocked
 FROM private_checkout.alani_favorites f JOIN public.products p ON p.id=f.product_id JOIN public.stores s ON s.id=p.store_id
 WHERE f.user_id=a AND p.is_active AND s.status='approved' AND p.store_id='25091ca2-c0da-416c-b634-81b188ee66be'::uuid
 ) t;
 RETURN result;
END $$;

REVOKE ALL ON FUNCTION public.alani_set_favorite(uuid,boolean),public.alani_my_favorites() FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.alani_set_favorite(uuid,boolean),public.alani_my_favorites() TO authenticated;
DO $verify$ BEGIN
 IF NOT (SELECT relrowsecurity FROM pg_class WHERE oid='private_checkout.alani_favorites'::regclass)
 OR has_table_privilege('authenticated','private_checkout.alani_favorites','SELECT,INSERT,UPDATE,DELETE')
 OR has_function_privilege('anon','public.alani_my_favorites()','EXECUTE')
 OR has_function_privilege('anon','public.alani_set_favorite(uuid,boolean)','EXECUTE')
 OR NOT has_function_privilege('authenticated','public.alani_my_favorites()','EXECUTE')
 OR NOT has_function_privilege('authenticated','public.alani_set_favorite(uuid,boolean)','EXECUTE')
 OR NOT public.shitreed_alani_checkout_schema_ready()
 THEN RAISE EXCEPTION 'FAVORITES_POSTCHECK_FAILED'; END IF;
END $verify$;
COMMIT;
