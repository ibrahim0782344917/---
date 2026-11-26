-- TEST ONLY. Baghdad calendar reporting; latest purchase cost estimate, not certified valuation.
CREATE FUNCTION public.alani_period_report_test(p_period text,p_day date)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE start_day date; end_day date; lo timestamptz; hi timestamptz; result jsonb;
BEGIN
 IF NOT private_checkout.alani_offer_staff_test() THEN RAISE EXCEPTION 'PERMISSION_DENIED'; END IF;
 IF p_day IS NULL OR p_day<'2000-01-01'::date OR p_day>'2100-12-31'::date OR p_period IS NULL OR p_period NOT IN ('day','month','year') THEN RAISE EXCEPTION 'INVALID_PERIOD'; END IF;
 start_day:=CASE p_period WHEN 'day' THEN p_day WHEN 'month' THEN date_trunc('month',p_day::timestamp)::date ELSE date_trunc('year',p_day::timestamp)::date END;
 end_day:=CASE p_period WHEN 'day' THEN start_day+1 WHEN 'month' THEN (start_day+interval '1 month')::date ELSE (start_day+interval '1 year')::date END;
 lo:=start_day::timestamp AT TIME ZONE 'Asia/Baghdad';hi:=end_day::timestamp AT TIME ZONE 'Asia/Baghdad';
 WITH events AS (
 SELECT 'sale'::text AS kind,l.quantity::numeric*l.price_iqd AS revenue,l.quantity::numeric*l.estimated_cost_iqd AS cost
 FROM private_checkout.alani_pos_invoice_line_test l JOIN private_checkout.alani_pos_invoice_test i ON i.id=l.invoice_id WHERE i.created_at>=lo AND i.created_at<hi
 UNION ALL SELECT 'return',-r.quantity::numeric*l.price_iqd,CASE WHEN r.restock THEN -r.quantity::numeric*l.estimated_cost_iqd ELSE 0 END
 FROM private_checkout.alani_pos_return_test r JOIN private_checkout.alani_pos_invoice_line_test l USING(invoice_id,product_id) WHERE r.created_at>=lo AND r.created_at<hi
 ), totals AS (
 SELECT coalesce(sum(revenue) FILTER(WHERE kind='sale'),0) AS gross,coalesce(-sum(revenue) FILTER(WHERE kind='return'),0) AS refunds,coalesce(sum(cost),0) AS known_cost,count(*) FILTER(WHERE cost IS NULL) AS missing FROM events
 ), other AS (
 SELECT (SELECT coalesce(sum(amount_iqd),0) FROM private_checkout.alani_expenses_test WHERE created_at>=lo AND created_at<hi) AS expenses,
 (SELECT coalesce(sum(quantity::numeric*unit_price_iqd),0) FROM private_checkout.alani_pos_test WHERE created_at>=lo AND created_at<hi) AS legacy,
 (SELECT coalesce(sum(amount_iqd),0) FROM private_checkout.alani_journal_test WHERE kind='cod_settlement' AND recorded_at>=lo AND recorded_at<hi) AS cod,
 (SELECT coalesce(sum(amount_iqd),0) FROM private_checkout.alani_journal_test WHERE kind='full_refund_simulated' AND recorded_at>=lo AND recorded_at<hi) AS cod_refunds,
 (SELECT count(*) FROM private_checkout.alani_stock_counts_test WHERE counted_qty<>expected_qty AND created_at>=lo AND created_at<hi) AS unvalued_counts,
 (SELECT coalesce(sum(quantity::numeric*unit_cost_iqd),0) FROM private_checkout.alani_purchase_test WHERE created_at>=lo AND created_at<hi) AS purchases
 )
 SELECT jsonb_build_object('period',p_period,'start_day',start_day,'end_day_exclusive',end_day,'timezone','Asia/Baghdad','pos_sales_iqd',gross,'pos_returns_iqd',refunds,'pos_net_sales_iqd',gross-refunds,'pos_estimated_cost_iqd',CASE WHEN missing=0 THEN known_cost END,'missing_cost_events',missing,'expenses_iqd',expenses,'legacy_pos_sales_iqd',legacy,'cod_settlement_iqd',cod,'cod_refund_iqd',cod_refunds,'purchases_iqd',purchases,'unvalued_counts',unvalued_counts,'limited_result_iqd',CASE WHEN missing=0 AND legacy=0 AND cod=0 AND cod_refunds=0 AND unvalued_counts=0 THEN gross-refunds-known_cost-expenses END,'is_final_profit',false) INTO result FROM totals CROSS JOIN other;
 RETURN result;
END $$;
CREATE FUNCTION public.alani_stock_valuation_test()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE result jsonb;
BEGIN
 IF NOT private_checkout.alani_offer_staff_test() THEN RAISE EXCEPTION 'PERMISSION_DENIED'; END IF;
 WITH rows AS (
 SELECT p.id,p.name,p.stock_quantity,p.is_active,c.unit_cost_iqd,CASE WHEN p.stock_quantity=0 THEN 0 ELSE p.stock_quantity::numeric*c.unit_cost_iqd END AS estimated_value_iqd
 FROM public.products p LEFT JOIN LATERAL (SELECT unit_cost_iqd FROM private_checkout.alani_purchase_test WHERE product_id=p.id ORDER BY created_at DESC,request_key DESC LIMIT 1)c ON true
 WHERE p.store_id='25091ca2-c0da-416c-b634-81b188ee66be'::uuid
 )
 SELECT jsonb_build_object('known_value_iqd',coalesce(sum(estimated_value_iqd),0),'missing_cost_products',count(*) FILTER(WHERE estimated_value_iqd IS NULL),'complete_estimated_value_iqd',CASE WHEN count(*) FILTER(WHERE estimated_value_iqd IS NULL)=0 THEN coalesce(sum(estimated_value_iqd),0) END,'method','latest_purchase_estimate_not_fifo','is_final_valuation',false,'items',coalesce((SELECT jsonb_agg(to_jsonb(t) ORDER BY t.name,t.id) FROM (SELECT * FROM rows ORDER BY name,id LIMIT 200)t),'[]')) INTO result FROM rows;
 RETURN result;
END $$;
REVOKE ALL ON FUNCTION public.alani_period_report_test(text,date),public.alani_stock_valuation_test() FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.alani_period_report_test(text,date),public.alani_stock_valuation_test() TO authenticated;
