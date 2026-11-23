-- PRE-PUBLISH TEST ONLY. No actual refunds or money movements.
-- Receipt confirmation is explicitly a buyer acknowledgment, not courier proof.
BEGIN;
ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS delivered_at timestamptz;
ALTER TABLE public.orders DROP CONSTRAINT IF EXISTS orders_status_check;
ALTER TABLE public.orders ADD CONSTRAINT orders_status_check
  CHECK (status = ANY(ARRAY['placed','accepted','preparing','ready','delivered','rejected','cancelled']));
ALTER TABLE public.order_status_history
  DROP CONSTRAINT IF EXISTS order_status_history_new_status_check;
ALTER TABLE public.order_status_history
  ADD CONSTRAINT order_status_history_new_status_check
  CHECK (new_status = ANY(ARRAY['placed','accepted','preparing','ready','delivered','rejected','cancelled']));

CREATE TABLE IF NOT EXISTS public.return_requests (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id uuid NOT NULL UNIQUE REFERENCES public.orders(id) ON DELETE RESTRICT,
  buyer_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
  reason text NOT NULL CHECK (char_length(btrim(reason)) BETWEEN 10 AND 1000),
  status text NOT NULL DEFAULT 'requested'
    CHECK (status IN ('requested','under_review','approved','rejected','resolved')),
  review_notes text NOT NULL DEFAULT '',
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  reviewed_at timestamptz
);
CREATE INDEX IF NOT EXISTS return_requests_buyer_created_idx
  ON public.return_requests(buyer_id,created_at DESC);
ALTER TABLE public.return_requests ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE public.return_requests FROM PUBLIC,anon,authenticated;
GRANT SELECT,INSERT ON TABLE public.return_requests TO authenticated;

DROP POLICY IF EXISTS "buyer_and_merchant_view_return_requests" ON public.return_requests;
CREATE POLICY "buyer_and_merchant_view_return_requests"
  ON public.return_requests FOR SELECT TO authenticated
  USING (
    buyer_id=(SELECT auth.uid()) OR
    EXISTS (SELECT 1 FROM public.orders o
      JOIN public.stores s ON s.id=o.store_id
      WHERE o.id=return_requests.order_id
        AND s.owner_id=(SELECT auth.uid()))
  );

DROP POLICY IF EXISTS "buyer_request_delivered_order_return" ON public.return_requests;
CREATE POLICY "buyer_request_delivered_order_return"
  ON public.return_requests FOR INSERT TO authenticated
  WITH CHECK (
    buyer_id=(SELECT auth.uid()) AND
    status='requested' AND review_notes='' AND reviewed_at IS NULL AND
    EXISTS (SELECT 1 FROM public.orders o
      WHERE o.id=return_requests.order_id
        AND o.buyer_id=(SELECT auth.uid())
        AND o.status='delivered'
        AND o.delivered_at>=now()-interval '14 days')
  );

CREATE OR REPLACE FUNCTION public.confirm_cash_order_receipt(p_order_id uuid)
RETURNS text
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $receipt$
DECLARE v_order public.orders%ROWTYPE;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'LOGIN_REQUIRED'; END IF;
  SELECT * INTO v_order FROM public.orders WHERE id=p_order_id FOR UPDATE;
  IF NOT FOUND OR v_order.buyer_id IS DISTINCT FROM auth.uid() THEN
    RAISE EXCEPTION 'ORDER_NOT_FOUND';
  END IF;
  IF v_order.status <> 'ready' THEN
    RAISE EXCEPTION 'ORDER_NOT_READY_FOR_RECEIPT';
  END IF;
  UPDATE public.orders SET status='delivered',delivered_at=now(),updated_at=now()
    WHERE id=v_order.id;
  RETURN 'delivered';
END
$receipt$;

CREATE OR REPLACE FUNCTION public.review_return_request(
  p_request_id uuid,p_new_status text,p_review_notes text DEFAULT ''
) RETURNS text
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $review$
DECLARE v_request public.return_requests%ROWTYPE;
BEGIN
  IF NOT public.shitreed_is_admin() THEN
    RAISE EXCEPTION 'ADMIN_REQUIRED';
  END IF;
  IF p_new_status NOT IN ('under_review','approved','rejected','resolved')
     OR p_review_notes IS NULL OR char_length(p_review_notes)>1000 THEN
    RAISE EXCEPTION 'INVALID_REVIEW';
  END IF;
  SELECT * INTO v_request FROM public.return_requests WHERE id=p_request_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'REQUEST_NOT_FOUND'; END IF;
  IF v_request.status NOT IN ('requested','under_review','approved')
     OR (v_request.status='approved' AND p_new_status<>'resolved') THEN
    RAISE EXCEPTION 'INVALID_REVIEW_TRANSITION';
  END IF;
  UPDATE public.return_requests
  SET status=p_new_status,review_notes=p_review_notes,
      reviewed_at=now(),updated_at=now()
  WHERE id=v_request.id;
  -- Approval records a decision; NO automatic refund or wallet operation occurs.
  RETURN p_new_status;
END
$review$;

REVOKE ALL ON FUNCTION public.confirm_cash_order_receipt(uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.confirm_cash_order_receipt(uuid)
  TO authenticated,service_role;
REVOKE ALL ON FUNCTION public.review_return_request(uuid,text,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.review_return_request(uuid,text,text)
  TO authenticated,service_role;
COMMIT;
