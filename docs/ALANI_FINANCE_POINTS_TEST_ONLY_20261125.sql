-- TEST ONLY. Simulated ledger, no bank or payment integration.
-- Each journal row represents exactly one balanced debit/credit pair.
CREATE TABLE private_checkout.alani_journal_test (
 order_id uuid NOT NULL REFERENCES public.orders(id) ON DELETE RESTRICT,
 kind text NOT NULL CHECK(kind IN ('cod_settlement','full_refund_simulated')),
 amount_iqd bigint NOT NULL CHECK(amount_iqd>0),
 debit_account text NOT NULL,
 credit_account text NOT NULL,
 return_id uuid REFERENCES public.alani_return_requests(id) ON DELETE RESTRICT,
 recorded_by uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
 recorded_at timestamptz NOT NULL DEFAULT now(),
 PRIMARY KEY(order_id,kind),
 CHECK ((kind='cod_settlement' AND debit_account='cash_simulated' AND credit_account='cod_clearing' AND return_id IS NULL)
 OR (kind='full_refund_simulated' AND debit_account='cod_clearing' AND credit_account='cash_simulated' AND return_id IS NOT NULL))
);
CREATE TABLE private_checkout.alani_points_test (
 order_id uuid NOT NULL REFERENCES public.orders(id) ON DELETE RESTRICT,
 user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
 kind text NOT NULL CHECK(kind IN ('purchase','refund_reversal')),
 points bigint NOT NULL,
 created_at timestamptz NOT NULL DEFAULT now(),
 PRIMARY KEY(order_id,kind),
 CHECK ((kind='purchase' AND points>0) OR (kind='refund_reversal' AND points<0))
);
ALTER TABLE private_checkout.alani_journal_test ENABLE ROW LEVEL SECURITY;
ALTER TABLE private_checkout.alani_points_test ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private_checkout.alani_journal_test,private_checkout.alani_points_test FROM PUBLIC,anon,authenticated;
CREATE FUNCTION public.alani_post_cod_settlement_test(p_order_id uuid)
RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE a uuid:=auth.uid(); o public.orders%ROWTYPE; r private_checkout.alani_cod_receipts_test%ROWTYPE; pts bigint;
BEGIN
 IF a IS NULL OR NOT public.shitreed_is_admin() THEN RAISE EXCEPTION 'ADMIN_ACCESS_REQUIRED'; END IF;
 SELECT * INTO o FROM public.orders WHERE id=p_order_id FOR UPDATE;
 IF NOT FOUND OR o.store_id<>'25091ca2-c0da-416c-b634-81b188ee66be'::uuid THEN RAISE EXCEPTION 'ORDER_NOT_FOUND'; END IF;
 IF EXISTS(SELECT 1 FROM private_checkout.alani_journal_test WHERE order_id=o.id AND kind='cod_settlement') THEN RETURN 'posted'; END IF;
 SELECT * INTO r FROM private_checkout.alani_cod_receipts_test WHERE order_id=o.id;
 IF NOT FOUND OR r.confirmed_at IS NULL OR r.amount_iqd<>o.total_iqd OR o.status<>'delivered' OR o.payment_method<>'cash_on_delivery' THEN RAISE EXCEPTION 'CONFIRMED_COD_REQUIRED'; END IF;
 INSERT INTO private_checkout.alani_journal_test(order_id,kind,amount_iqd,debit_account,credit_account,recorded_by) VALUES(o.id,'cod_settlement',r.amount_iqd,'cash_simulated','cod_clearing',a);
 -- Provisional TEST rate only, 1 point per 1000 IQD of goods, excluding delivery.
 pts:=greatest(0,o.total_iqd-o.delivery_fee_iqd)/1000;
 IF pts>0 THEN INSERT INTO private_checkout.alani_points_test(order_id,user_id,kind,points) VALUES(o.id,o.buyer_id,'purchase',pts); END IF;
 RETURN 'posted';
END $$;
CREATE FUNCTION public.alani_post_full_refund_test(p_return_id uuid)
RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE a uuid:=auth.uid(); rr public.alani_return_requests%ROWTYPE; o public.orders%ROWTYPE; j private_checkout.alani_journal_test%ROWTYPE; pts bigint;
BEGIN
 IF a IS NULL OR NOT public.shitreed_is_admin() THEN RAISE EXCEPTION 'ADMIN_ACCESS_REQUIRED'; END IF;
 SELECT * INTO rr FROM public.alani_return_requests WHERE id=p_return_id;
 IF NOT FOUND THEN RAISE EXCEPTION 'RETURN_NOT_FOUND'; END IF;
 SELECT * INTO o FROM public.orders WHERE id=rr.order_id FOR UPDATE;
 IF NOT FOUND OR o.store_id<>'25091ca2-c0da-416c-b634-81b188ee66be'::uuid OR o.buyer_id<>rr.customer_id OR rr.store_id<>o.store_id THEN RAISE EXCEPTION 'ORDER_NOT_FOUND'; END IF;
 SELECT * INTO rr FROM public.alani_return_requests WHERE id=p_return_id FOR UPDATE;
 SELECT * INTO j FROM private_checkout.alani_journal_test WHERE order_id=o.id AND kind='full_refund_simulated';
 IF FOUND THEN
  IF j.return_id<>rr.id THEN RAISE EXCEPTION 'ORDER_ALREADY_REFUNDED'; END IF;
  RETURN 'posted';
 END IF;
 IF rr.status<>'approved' THEN RAISE EXCEPTION 'APPROVED_RETURN_REQUIRED'; END IF;
 SELECT * INTO j FROM private_checkout.alani_journal_test WHERE order_id=o.id AND kind='cod_settlement';
 IF NOT FOUND THEN RAISE EXCEPTION 'SETTLEMENT_REQUIRED'; END IF;
 INSERT INTO private_checkout.alani_journal_test(order_id,kind,amount_iqd,debit_account,credit_account,return_id,recorded_by) VALUES(o.id,'full_refund_simulated',j.amount_iqd,'cod_clearing','cash_simulated',rr.id,a);
 SELECT points INTO pts FROM private_checkout.alani_points_test WHERE order_id=o.id AND kind='purchase';
 IF FOUND THEN INSERT INTO private_checkout.alani_points_test(order_id,user_id,kind,points) VALUES(o.id,o.buyer_id,'refund_reversal',-pts); END IF;
 RETURN 'posted';
END $$;
CREATE FUNCTION public.alani_my_points_test()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE a uuid:=auth.uid(); result jsonb;
BEGIN
 IF a IS NULL THEN RAISE EXCEPTION 'LOGIN_REQUIRED'; END IF;
 SELECT jsonb_build_object('points',coalesce(sum(points),0),'cash_balance_available',false,'entries',count(*)) INTO result FROM private_checkout.alani_points_test WHERE user_id=a;
 RETURN result;
END $$;
REVOKE ALL ON FUNCTION public.alani_post_cod_settlement_test(uuid),public.alani_post_full_refund_test(uuid),public.alani_my_points_test() FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.alani_post_cod_settlement_test(uuid),public.alani_post_full_refund_test(uuid),public.alani_my_points_test() TO authenticated;
