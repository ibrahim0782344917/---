-- TEST ONLY. Never run in production. No money movement; record simulated COD only.
CREATE TABLE private_checkout.alani_cod_receipts_test (
 order_id uuid PRIMARY KEY REFERENCES public.orders(id) ON DELETE RESTRICT,
 courier_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
 amount_iqd bigint NOT NULL CHECK(amount_iqd>0),
 recorded_at timestamptz NOT NULL DEFAULT now(),
 confirmed_by uuid REFERENCES auth.users(id) ON DELETE RESTRICT,
 confirmed_at timestamptz,
 CHECK ((confirmed_by IS NULL)=(confirmed_at IS NULL)),
 CHECK (confirmed_by IS NULL OR confirmed_by<>courier_id)
);
ALTER TABLE private_checkout.alani_cod_receipts_test ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private_checkout.alani_cod_receipts_test FROM PUBLIC,anon,authenticated;
CREATE FUNCTION public.alani_record_cod_test(p_order_id uuid,p_amount_iqd bigint)
RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE a uuid:=auth.uid(); o public.orders%ROWTYPE; j public.alani_delivery_jobs%ROWTYPE; r private_checkout.alani_cod_receipts_test%ROWTYPE;
BEGIN
 IF a IS NULL THEN RAISE EXCEPTION 'LOGIN_REQUIRED'; END IF;
 SELECT * INTO o FROM public.orders WHERE id=p_order_id FOR UPDATE;
 IF NOT FOUND OR o.store_id<>'25091ca2-c0da-416c-b634-81b188ee66be'::uuid THEN RAISE EXCEPTION 'ORDER_NOT_FOUND'; END IF;
 SELECT * INTO j FROM public.alani_delivery_jobs WHERE order_id=o.id;
 IF j.courier_id IS DISTINCT FROM a OR NOT EXISTS(SELECT 1 FROM public.alani_delivery_couriers c WHERE c.store_id=o.store_id AND c.courier_id=a AND c.enabled) THEN RAISE EXCEPTION 'PERMISSION_DENIED'; END IF;
 IF o.status<>'delivered' OR o.payment_method<>'cash_on_delivery' OR j.proof_method IS DISTINCT FROM 'buyer_one_time_pin' OR j.delivered_at IS NULL THEN RAISE EXCEPTION 'DELIVERY_REQUIRED'; END IF;
 IF p_amount_iqd IS DISTINCT FROM o.total_iqd OR p_amount_iqd<=0 THEN RAISE EXCEPTION 'COD_AMOUNT_MISMATCH'; END IF;
 SELECT * INTO r FROM private_checkout.alani_cod_receipts_test WHERE order_id=o.id;
 IF FOUND THEN
   IF r.courier_id<>a OR r.amount_iqd<>p_amount_iqd THEN RAISE EXCEPTION 'COD_RECEIPT_CONFLICT'; END IF;
   RETURN CASE WHEN r.confirmed_at IS NULL THEN 'recorded' ELSE 'confirmed' END;
 END IF;
 INSERT INTO private_checkout.alani_cod_receipts_test(order_id,courier_id,amount_iqd) VALUES(o.id,a,p_amount_iqd);
 RETURN 'recorded';
END $$;
CREATE FUNCTION public.alani_confirm_cod_test(p_order_id uuid)
RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE a uuid:=auth.uid(); o public.orders%ROWTYPE; r private_checkout.alani_cod_receipts_test%ROWTYPE;
BEGIN
 IF a IS NULL THEN RAISE EXCEPTION 'LOGIN_REQUIRED'; END IF;
 SELECT * INTO o FROM public.orders WHERE id=p_order_id FOR UPDATE;
 IF NOT FOUND OR o.store_id<>'25091ca2-c0da-416c-b634-81b188ee66be'::uuid THEN RAISE EXCEPTION 'ORDER_NOT_FOUND'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.stores s WHERE s.id=o.store_id AND (s.owner_id=a OR public.shitreed_is_admin())) THEN RAISE EXCEPTION 'PERMISSION_DENIED'; END IF;
 SELECT * INTO r FROM private_checkout.alani_cod_receipts_test WHERE order_id=o.id;
 IF NOT FOUND THEN RAISE EXCEPTION 'COD_NOT_RECORDED'; END IF;
 IF r.courier_id=a THEN RAISE EXCEPTION 'SEPARATE_REVIEWER_REQUIRED'; END IF;
 IF o.status<>'delivered' OR r.amount_iqd<>o.total_iqd THEN RAISE EXCEPTION 'COD_RECEIPT_CONFLICT'; END IF;
 IF r.confirmed_at IS NOT NULL THEN RETURN 'confirmed'; END IF;
 UPDATE private_checkout.alani_cod_receipts_test SET confirmed_at=now(),confirmed_by=a WHERE order_id=o.id;
 RETURN 'confirmed';
END $$;
REVOKE ALL ON FUNCTION public.alani_record_cod_test(uuid,bigint),public.alani_confirm_cod_test(uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.alani_record_cod_test(uuid,bigint),public.alani_confirm_cod_test(uuid) TO authenticated;
