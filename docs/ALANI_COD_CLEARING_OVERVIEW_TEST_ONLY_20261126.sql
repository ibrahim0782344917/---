-- TEST ONLY. Add existing simulated COD clearing and refund journal pairs to the overview. Clearing is not earned revenue.
CREATE OR REPLACE FUNCTION public.alani_accounting_overview_test()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE base jsonb; margin jsonb; ledger jsonb; expenses numeric; old_sales numeric; online_sales numeric; online_refunds numeric; missing bigint; net numeric; adjustments bigint;
BEGIN
 IF NOT private_checkout.alani_offer_staff_test() THEN RAISE EXCEPTION 'PERMISSION_DENIED'; END IF;
 base:=public.alani_operational_trial_balance_test(); margin:=public.alani_pos_margin_test();
 SELECT coalesce(sum(amount_iqd),0) INTO expenses FROM private_checkout.alani_expenses_test;
 SELECT coalesce(sum(quantity::numeric*unit_price_iqd),0) INTO old_sales FROM private_checkout.alani_pos_test;
 SELECT coalesce(sum(amount_iqd) FILTER(WHERE kind='cod_settlement'),0),coalesce(sum(amount_iqd) FILTER(WHERE kind='full_refund_simulated'),0) INTO online_sales,online_refunds FROM private_checkout.alani_journal_test;
 SELECT count(*) INTO adjustments FROM private_checkout.alani_stock_counts_test WHERE counted_qty<>expected_qty;
 missing:=(margin->>'missing_cost_lines')::bigint;
 WITH journal AS (
 SELECT 'cash_simulated'::text AS dr,'pos_revenue'::text AS cr,total_iqd::numeric AS amount FROM private_checkout.alani_pos_invoice_test
 UNION ALL SELECT 'pos_returns','cash_simulated',r.quantity::numeric*l.price_iqd FROM private_checkout.alani_pos_return_test r JOIN private_checkout.alani_pos_invoice_line_test l USING(invoice_id,product_id)
 UNION ALL SELECT 'estimated_cogs','inventory_purchases',l.quantity::numeric*l.estimated_cost_iqd FROM private_checkout.alani_pos_invoice_line_test l WHERE l.estimated_cost_iqd IS NOT NULL
 UNION ALL SELECT 'inventory_purchases','estimated_cogs',r.quantity::numeric*l.estimated_cost_iqd FROM private_checkout.alani_pos_return_test r JOIN private_checkout.alani_pos_invoice_line_test l USING(invoice_id,product_id) WHERE r.restock AND l.estimated_cost_iqd IS NOT NULL
 UNION ALL SELECT debit_account,credit_account,amount_iqd::numeric FROM private_checkout.alani_journal_test
 ), legs AS (
 SELECT x->>'account' AS account,(x->>'debit_iqd')::numeric AS debit,(x->>'credit_iqd')::numeric AS credit FROM jsonb_array_elements(base->'accounts') x
 UNION ALL SELECT dr,amount,0 FROM journal UNION ALL SELECT cr,0,amount FROM journal
 ), balances AS (SELECT account,sum(debit) AS debit_iqd,sum(credit) AS credit_iqd FROM legs GROUP BY account)
 SELECT jsonb_build_object('debit_iqd',coalesce(sum(debit_iqd),0),'credit_iqd',coalesce(sum(credit_iqd),0),'balanced',coalesce(sum(debit_iqd),0)=coalesce(sum(credit_iqd),0),'accounts',coalesce(jsonb_agg(to_jsonb(balances) ORDER BY account),'[]')) INTO ledger FROM balances;
 IF missing=0 AND old_sales=0 AND online_sales=0 AND online_refunds=0 AND adjustments=0 THEN net:=(margin->>'estimated_gross_margin_iqd')::numeric-expenses; END IF;
 RETURN jsonb_build_object('trial_balance',ledger,'pos_net_sales_iqd',margin->'net_sales_iqd','pos_estimated_cost_iqd',margin->'estimated_cost_iqd','pos_estimated_gross_margin_iqd',margin->'estimated_gross_margin_iqd',
 'expenses_iqd',expenses,'legacy_pos_sales_iqd',old_sales,'online_cod_recorded_iqd',online_sales,'online_refund_recorded_iqd',online_refunds,'missing_cost_lines',missing,'unvalued_stock_counts',adjustments,'limited_estimated_result_iqd',net,'includes_cod_clearing_pairs',true,'is_final_profit',false,'method','latest_purchase_cost_partial_scope');
END $$;
REVOKE ALL ON FUNCTION public.alani_accounting_overview_test() FROM PUBLIC,anon;
