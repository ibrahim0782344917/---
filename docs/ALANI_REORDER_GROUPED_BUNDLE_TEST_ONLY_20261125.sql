-- TEST ONLY: combine price-allocation rows from a previous bundle.
CREATE OR REPLACE FUNCTION public.alani_reorder_quote_test(p_order_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE a uuid:=auth.uid(); o public.orders%ROWTYPE; result jsonb;
BEGIN
 IF a IS NULL THEN RAISE EXCEPTION 'LOGIN_REQUIRED'; END IF;
 SELECT * INTO o FROM public.orders WHERE id=p_order_id AND buyer_id=a AND store_id='25091ca2-c0da-416c-b634-81b188ee66be'::uuid AND status='delivered';
 IF NOT FOUND THEN RAISE EXCEPTION 'ORDER_NOT_AVAILABLE'; END IF;
 WITH grouped AS (
 SELECT product_id,min(product_name) AS product_name,sum(quantity)::bigint AS quantity
 FROM public.order_items WHERE order_id=o.id GROUP BY product_id
 ), lines AS (
 SELECT i.product_id AS id,o.store_id,coalesce(p.name,i.product_name) AS name,
 coalesce(p.description,'') AS description,p.image_url,i.quantity,coalesce(p.stock_quantity,0) AS stock_quantity,
 CASE WHEN p.id IS NOT NULL AND p.is_active AND s.status='approved' THEN public.alani_active_campaign_price(p.id,p.price_iqd) END AS price_iqd,
 coalesce(p.id IS NOT NULL AND p.is_active AND s.status='approved' AND p.stock_quantity>=i.quantity AND i.quantity BETWEEN 1 AND 20,false) AS available
 FROM grouped i LEFT JOIN public.products p ON p.id=i.product_id AND p.store_id=o.store_id LEFT JOIN public.stores s ON s.id=p.store_id
 )
 SELECT jsonb_build_object('items',coalesce(jsonb_agg(to_jsonb(lines) ORDER BY id),'[]'::jsonb),'all_available',count(*) BETWEEN 1 AND 20 AND coalesce(bool_and(available),false),'delivery_fee_iqd',5000,'total_iqd',CASE WHEN count(*) BETWEEN 1 AND 20 AND coalesce(bool_and(available),false) THEN 5000+sum(price_iqd::bigint*quantity) END) INTO result FROM lines;
 RETURN result;
END $$;
REVOKE ALL ON FUNCTION public.alani_reorder_quote_test(uuid) FROM PUBLIC,anon;
