-- TEST ONLY: defense in depth for private idempotency records. Existing definer owners remain unchanged; no FORCE RLS.
ALTER TABLE private_checkout.web_checkout_requests ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private_checkout.web_checkout_requests FROM PUBLIC,anon,authenticated;
