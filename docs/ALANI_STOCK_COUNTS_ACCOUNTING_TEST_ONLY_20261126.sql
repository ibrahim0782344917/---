-- TEST ONLY. Audit all subsequent stock changes; no historical reconstruction.
CREATE TABLE private_checkout.alani_stock_movements_test(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), product_id uuid NOT NULL REFERENCES public.products(id) ON DELETE RESTRICT,
 before_qty integer NOT NULL, after_qty integer NOT NULL, actor uuid, changed_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 CHECK(before_qty>=0 AND after_qty>=0 AND before_qty<>after_qty)
);
CREATE TABLE private_checkout.alani_stock_counts_test(
 id uuid PRIMARY KEY, product_id uuid NOT NULL REFERENCES public.products(id) ON DELETE RESTRICT,
 expected_qty integer NOT NULL CHECK(expected_qty>=0), counted_qty integer NOT NULL CHECK(counted_qty>=0),
 reason text NOT NULL CHECK(char_length(reason) BETWEEN 3 AND 200), actor uuid NOT NULL REFERENCES auth.users(id),
 created_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
ALTER TABLE private_checkout.alani_stock_movements_test ENABLE ROW LEVEL SECURITY;
ALTER TABLE private_checkout.alani_stock_counts_test ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private_checkout.alani_stock_movements_test,private_checkout.alani_stock_counts_test FROM PUBLIC,anon,authenticated;
CREATE INDEX alani_stock_movements_product_test_idx ON private_checkout.alani_stock_movements_test(product_id,changed_at DESC);
CREATE FUNCTION private_checkout.alani_capture_stock_test() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN
 IF NEW.store_id='25091ca2-c0da-416c-b634-81b188ee66be'::uuid AND OLD.stock_quantity IS DISTINCT FROM NEW.stock_quantity THEN
 INSERT INTO private_checkout.alani_stock_movements_test(product_id,before_qty,after_qty,actor) VALUES(NEW.id,OLD.stock_quantity,NEW.stock_quantity,auth.uid());
 END IF;
 RETURN NEW;
END $$;
REVOKE ALL ON FUNCTION private_checkout.alani_capture_stock_test() FROM PUBLIC,anon,authenticated;
CREATE TRIGGER alani_capture_stock_test AFTER UPDATE OF stock_quantity ON public.products FOR EACH ROW EXECUTE FUNCTION private_checkout.alani_capture_stock_test();
CREATE FUNCTION public.alani_record_stock_count_test(p_key uuid,p_product uuid,p_expected integer,p_counted integer,p_reason text)
RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE old private_checkout.alani_stock_counts_test%ROWTYPE; current_qty integer;
BEGIN
 IF NOT private_checkout.alani_offer_staff_test() THEN RAISE EXCEPTION 'PERMISSION_DENIED'; END IF;
 IF p_key IS NULL OR p_expected IS NULL OR p_counted IS NULL OR p_expected<0 OR p_counted<0 OR p_reason IS NULL OR char_length(btrim(p_reason)) NOT BETWEEN 3 AND 200 THEN RAISE EXCEPTION 'INVALID_COUNT'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('stock-count:'||p_key::text,0));
 SELECT * INTO old FROM private_checkout.alani_stock_counts_test WHERE id=p_key;
 IF FOUND THEN
 IF (old.product_id,old.expected_qty,old.counted_qty,old.reason) IS DISTINCT FROM (p_product,p_expected,p_counted,btrim(p_reason)) THEN RAISE EXCEPTION 'IDEMPOTENCY_PAYLOAD_MISMATCH'; END IF;
 RETURN 'recorded';
 END IF;
 SELECT stock_quantity INTO current_qty FROM public.products WHERE id=p_product AND store_id='25091ca2-c0da-416c-b634-81b188ee66be'::uuid FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'PRODUCT_UNAVAILABLE'; END IF;
 IF current_qty<>p_expected THEN RAISE EXCEPTION 'STOCK_CHANGED_RECOUNT'; END IF;
 INSERT INTO private_checkout.alani_stock_counts_test VALUES(p_key,p_product,p_expected,p_counted,btrim(p_reason),auth.uid(),clock_timestamp());
 UPDATE public.products SET stock_quantity=p_counted WHERE id=p_product;
 RETURN 'recorded';
END $$;
CREATE FUNCTION public.alani_stock_history_test(p_product uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
BEGIN
 IF NOT private_checkout.alani_offer_staff_test() THEN RAISE EXCEPTION 'PERMISSION_DENIED'; END IF;
 RETURN jsonb_build_object('movements',coalesce((SELECT jsonb_agg(to_jsonb(t) ORDER BY changed_at DESC,id) FROM (SELECT id,before_qty,after_qty,after_qty-before_qty AS delta,changed_at FROM private_checkout.alani_stock_movements_test WHERE product_id=p_product ORDER BY changed_at DESC,id LIMIT 100)t),'[]'::jsonb),
 'counts',coalesce((SELECT jsonb_agg(to_jsonb(t) ORDER BY created_at DESC,id) FROM (SELECT id,expected_qty,counted_qty,reason,created_at FROM private_checkout.alani_stock_counts_test WHERE product_id=p_product ORDER BY created_at DESC,id LIMIT 100)t),'[]'::jsonb));
END $$;
-- Combine original operational accounts, new POS revenue/refunds, and known cost entries.
-- Unknown costs are flagged, never treated as zero profit.
CREATE FUNCTION public.alani_accounting_overview_test()
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
 ), legs AS (
 SELECT x->>'account' AS account,(x->>'debit_iqd')::numeric AS debit,(x->>'credit_iqd')::numeric AS credit FROM jsonb_array_elements(base->'accounts') x
 UNION ALL SELECT dr,amount,0 FROM journal UNION ALL SELECT cr,0,amount FROM journal
 ), balances AS (SELECT account,sum(debit) AS debit_iqd,sum(credit) AS credit_iqd FROM legs GROUP BY account)
 SELECT jsonb_build_object('debit_iqd',coalesce(sum(debit_iqd),0),'credit_iqd',coalesce(sum(credit_iqd),0),'balanced',coalesce(sum(debit_iqd),0)=coalesce(sum(credit_iqd),0),'accounts',coalesce(jsonb_agg(to_jsonb(balances) ORDER BY account),'[]')) INTO ledger FROM balances;
 IF missing=0 AND old_sales=0 AND online_sales=0 AND adjustments=0 THEN net:=(margin->>'estimated_gross_margin_iqd')::numeric-expenses; END IF;
 RETURN jsonb_build_object('trial_balance',ledger,'pos_net_sales_iqd',margin->'net_sales_iqd','pos_estimated_cost_iqd',margin->'estimated_cost_iqd','pos_estimated_gross_margin_iqd',margin->'estimated_gross_margin_iqd',
 'expenses_iqd',expenses,'legacy_pos_sales_iqd',old_sales,'online_cod_recorded_iqd',online_sales,'online_refund_recorded_iqd',online_refunds,'missing_cost_lines',missing,'unvalued_stock_counts',adjustments,'limited_estimated_result_iqd',net,'is_final_profit',false,'method','latest_purchase_cost_partial_scope');
END $$;
REVOKE ALL ON FUNCTION public.alani_record_stock_count_test(uuid,uuid,integer,integer,text),public.alani_stock_history_test(uuid),public.alani_accounting_overview_test() FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.alani_record_stock_count_test(uuid,uuid,integer,integer,text),public.alani_stock_history_test(uuid),public.alani_accounting_overview_test() TO authenticated;
