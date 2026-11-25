-- TEST ONLY: derived, balanced operational trial balance. No COGS, no bank movement.
CREATE FUNCTION public.alani_operational_trial_balance_test()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE result jsonb;
BEGIN
 IF NOT private_checkout.alani_offer_staff_test() THEN RAISE EXCEPTION 'PERMISSION_DENIED'; END IF;
 WITH journal AS (
 SELECT 'inventory_purchases'::text AS debit,'supplier_payable'::text AS credit,quantity::numeric*unit_cost_iqd AS amount FROM private_checkout.alani_purchase_test WHERE on_credit
 UNION ALL SELECT 'inventory_purchases','cash_simulated',quantity::numeric*unit_cost_iqd FROM private_checkout.alani_purchase_test WHERE NOT on_credit
 UNION ALL SELECT 'cash_simulated','pos_revenue',quantity::numeric*unit_price_iqd FROM private_checkout.alani_pos_test
 UNION ALL SELECT 'operating_expenses','cash_simulated',amount_iqd::numeric FROM private_checkout.alani_expenses_test
 UNION ALL SELECT 'supplier_payable','cash_simulated',amount_iqd::numeric FROM private_checkout.alani_debt_payments_test
 ), legs AS (
 SELECT debit AS account,amount AS dr,0::numeric AS cr FROM journal
 UNION ALL SELECT credit,0::numeric,amount FROM journal
 ), balances AS (
 SELECT account,sum(dr) AS debit_iqd,sum(cr) AS credit_iqd,sum(dr-cr) AS net_debit_iqd FROM legs GROUP BY account
 )
 SELECT jsonb_build_object('debit_iqd',coalesce(sum(debit_iqd),0),'credit_iqd',coalesce(sum(credit_iqd),0),
 'balanced',coalesce(sum(debit_iqd),0)=coalesce(sum(credit_iqd),0),
 'accounts',coalesce(jsonb_agg(to_jsonb(balances) ORDER BY account),'[]'::jsonb),
 'includes_cost_of_goods_sold',false,'includes_online_cod',false,'is_cash_movement',false)
 INTO result FROM balances;
 RETURN result;
END $$;
REVOKE ALL ON FUNCTION public.alani_operational_trial_balance_test() FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.alani_operational_trial_balance_test() TO authenticated;
