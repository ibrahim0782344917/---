-- TEST ONLY. No payment, order placement, referral reward, or cash wallet.
CREATE TABLE private_checkout.alani_favorites_test(
 user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
 product_id uuid NOT NULL REFERENCES public.products(id) ON DELETE CASCADE,
 saved_price_iqd integer NOT NULL CHECK(saved_price_iqd>=0),
 saved_stock integer NOT NULL CHECK(saved_stock>=0),
 created_at timestamptz NOT NULL DEFAULT now(), PRIMARY KEY(user_id,product_id)
);
CREATE TABLE private_checkout.alani_invite_codes_test(
 user_id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
 code uuid NOT NULL UNIQUE DEFAULT gen_random_uuid()
);
CREATE TABLE private_checkout.alani_referrals_test(
 invitee_id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
 inviter_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
 created_at timestamptz NOT NULL DEFAULT now(),
 CHECK(invitee_id<>inviter_id)
);
ALTER TABLE private_checkout.alani_favorites_test ENABLE ROW LEVEL SECURITY;
ALTER TABLE private_checkout.alani_invite_codes_test ENABLE ROW LEVEL SECURITY;
ALTER TABLE private_checkout.alani_referrals_test ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private_checkout.alani_favorites_test,private_checkout.alani_invite_codes_test,private_checkout.alani_referrals_test FROM PUBLIC,anon,authenticated;
CREATE FUNCTION public.alani_set_favorite_test(p_product_id uuid,p_saved boolean)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE a uuid:=auth.uid(); p public.products%ROWTYPE;
BEGIN
 IF a IS NULL THEN RAISE EXCEPTION 'LOGIN_REQUIRED'; END IF;
 IF p_saved IS NULL OR p_product_id IS NULL THEN RAISE EXCEPTION 'INVALID_INPUT'; END IF;
 IF NOT p_saved THEN
  DELETE FROM private_checkout.alani_favorites_test WHERE user_id=a AND product_id=p_product_id;
  RETURN false;
 END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('alani_favorites:'||a::text,0));
 SELECT pr.* INTO p FROM public.products pr JOIN public.stores s ON s.id=pr.store_id
 WHERE pr.id=p_product_id AND pr.is_active AND s.status='approved' AND pr.store_id='25091ca2-c0da-416c-b634-81b188ee66be'::uuid;
 IF NOT FOUND THEN RAISE EXCEPTION 'PRODUCT_UNAVAILABLE'; END IF;
 IF EXISTS(SELECT 1 FROM private_checkout.alani_favorites_test WHERE user_id=a AND product_id=p.id) THEN RETURN true; END IF;
 IF (SELECT count(*) FROM private_checkout.alani_favorites_test WHERE user_id=a)>=200 THEN RAISE EXCEPTION 'FAVORITES_LIMIT'; END IF;
 INSERT INTO private_checkout.alani_favorites_test(user_id,product_id,saved_price_iqd,saved_stock)
 VALUES(a,p.id,public.alani_active_campaign_price(p.id,p.price_iqd),p.stock_quantity);
 RETURN true;
END $$;
CREATE FUNCTION public.alani_my_favorites_test()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE a uuid:=auth.uid(); result jsonb;
BEGIN
 IF a IS NULL THEN RAISE EXCEPTION 'LOGIN_REQUIRED'; END IF;
 SELECT coalesce(jsonb_agg(to_jsonb(t) ORDER BY t.created_at DESC),'[]'::jsonb) INTO result FROM (
 SELECT p.id,p.store_id,p.name,p.description,p.image_url,p.stock_quantity,
 public.alani_active_campaign_price(p.id,p.price_iqd) AS price_iqd,
 f.saved_price_iqd,f.saved_stock,f.created_at,
 public.alani_active_campaign_price(p.id,p.price_iqd)<f.saved_price_iqd AS price_dropped,
 f.saved_stock=0 AND p.stock_quantity>0 AS restocked
 FROM private_checkout.alani_favorites_test f JOIN public.products p ON p.id=f.product_id JOIN public.stores s ON s.id=p.store_id
 WHERE f.user_id=a AND p.is_active AND s.status='approved' AND p.store_id='25091ca2-c0da-416c-b634-81b188ee66be'::uuid
 ) t;
 RETURN result;
END $$;
CREATE FUNCTION public.alani_reorder_quote_test(p_order_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE a uuid:=auth.uid(); o public.orders%ROWTYPE; result jsonb;
BEGIN
 IF a IS NULL THEN RAISE EXCEPTION 'LOGIN_REQUIRED'; END IF;
 SELECT * INTO o FROM public.orders WHERE id=p_order_id AND buyer_id=a AND store_id='25091ca2-c0da-416c-b634-81b188ee66be'::uuid AND status='delivered';
 IF NOT FOUND THEN RAISE EXCEPTION 'ORDER_NOT_AVAILABLE'; END IF;
 WITH lines AS (
 SELECT i.product_id AS id,o.store_id,coalesce(p.name,i.product_name) AS name,
 coalesce(p.description,'') AS description,p.image_url,i.quantity,
 coalesce(p.stock_quantity,0) AS stock_quantity,
 CASE WHEN p.id IS NOT NULL AND p.is_active AND s.status='approved' THEN public.alani_active_campaign_price(p.id,p.price_iqd) END AS price_iqd,
 coalesce(p.id IS NOT NULL AND p.is_active AND s.status='approved' AND p.stock_quantity>=i.quantity AND i.quantity BETWEEN 1 AND 20,false) AS available
 FROM public.order_items i LEFT JOIN public.products p ON p.id=i.product_id AND p.store_id=o.store_id LEFT JOIN public.stores s ON s.id=p.store_id WHERE i.order_id=o.id
 )
 SELECT jsonb_build_object('items',coalesce(jsonb_agg(to_jsonb(lines) ORDER BY id),'[]'::jsonb),'all_available',count(*) BETWEEN 1 AND 20 AND coalesce(bool_and(available),false),'delivery_fee_iqd',5000,'total_iqd',CASE WHEN count(*) BETWEEN 1 AND 20 AND coalesce(bool_and(available),false) THEN 5000+sum(price_iqd::bigint*quantity) END) INTO result FROM lines;
 RETURN result;
END $$;
CREATE FUNCTION public.alani_my_invite_test()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE a uuid:=auth.uid(); c uuid;
BEGIN
 IF a IS NULL THEN RAISE EXCEPTION 'LOGIN_REQUIRED'; END IF;
 INSERT INTO private_checkout.alani_invite_codes_test(user_id) VALUES(a) ON CONFLICT(user_id) DO NOTHING;
 SELECT code INTO c FROM private_checkout.alani_invite_codes_test WHERE user_id=a;
 RETURN jsonb_build_object('code',c,'invite_count',(SELECT count(*) FROM private_checkout.alani_referrals_test WHERE inviter_id=a),'already_referred',EXISTS(SELECT 1 FROM private_checkout.alani_referrals_test WHERE invitee_id=a),'reward_enabled',false);
END $$;
CREATE FUNCTION public.alani_claim_invite_test(p_code uuid)
RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE a uuid:=auth.uid(); inviter uuid; existing uuid;
BEGIN
 IF a IS NULL THEN RAISE EXCEPTION 'LOGIN_REQUIRED'; END IF;
 -- Serialize referral graph changes to prevent mutual/cyclic claims.
 PERFORM pg_advisory_xact_lock(hashtextextended('alani_referral_graph_test',0));
 SELECT user_id INTO inviter FROM private_checkout.alani_invite_codes_test WHERE code=p_code;
 IF inviter IS NULL OR inviter=a THEN RAISE EXCEPTION 'INVALID_INVITE'; END IF;
 SELECT inviter_id INTO existing FROM private_checkout.alani_referrals_test WHERE invitee_id=a;
 IF FOUND THEN IF existing=inviter THEN RETURN 'registered'; END IF; RAISE EXCEPTION 'INVITE_ALREADY_CLAIMED'; END IF;
 IF EXISTS(SELECT 1 FROM public.orders WHERE buyer_id=a) THEN RAISE EXCEPTION 'INVITE_BEFORE_FIRST_ORDER'; END IF;
 IF EXISTS(WITH RECURSIVE ancestors(id) AS (SELECT inviter UNION SELECT r.inviter_id FROM private_checkout.alani_referrals_test r JOIN ancestors x ON r.invitee_id=x.id) SELECT 1 FROM ancestors WHERE id=a) THEN RAISE EXCEPTION 'INVITE_CYCLE'; END IF;
 INSERT INTO private_checkout.alani_referrals_test(invitee_id,inviter_id) VALUES(a,inviter);
 RETURN 'registered';
END $$;
REVOKE ALL ON FUNCTION public.alani_set_favorite_test(uuid,boolean),public.alani_my_favorites_test(),public.alani_reorder_quote_test(uuid),public.alani_my_invite_test(),public.alani_claim_invite_test(uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.alani_set_favorite_test(uuid,boolean),public.alani_my_favorites_test(),public.alani_reorder_quote_test(uuid),public.alani_my_invite_test(),public.alani_claim_invite_test(uuid) TO authenticated;
