-- Production foundation only: no public API, bank details, collection, upload or credit.
BEGIN;
SET LOCAL lock_timeout='3s';
SET LOCAL statement_timeout='30s';
DO $guard$ BEGIN
 IF NOT public.shitreed_alani_checkout_schema_ready()
 OR EXISTS(SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
 WHERE n.nspname='private_checkout' AND c.relname LIKE 'alani_wallet%')
 THEN RAISE EXCEPTION 'WALLET_FOUNDATION_PREFLIGHT_FAILED'; END IF;
END $guard$;
CREATE TABLE private_checkout.alani_wallet_funding_gate (
 singleton boolean PRIMARY KEY DEFAULT true CHECK(singleton),
 request_intake_enabled boolean NOT NULL DEFAULT false,
 credit_enabled boolean NOT NULL DEFAULT false,
 CHECK(NOT credit_enabled OR request_intake_enabled)
);
INSERT INTO private_checkout.alani_wallet_funding_gate(singleton) VALUES(true);
CREATE TABLE private_checkout.alani_wallet_topup_requests (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
 request_key uuid NOT NULL,
 amount_iqd bigint NOT NULL CHECK(amount_iqd>0 AND amount_iqd<=1000000000),
 currency text NOT NULL DEFAULT 'IQD' CHECK(currency='IQD'),
 provider_code text NOT NULL CHECK(provider_code ~ '^[a-z0-9_]{2,40}$'),
 declared_reference text NOT NULL CHECK(char_length(btrim(declared_reference)) BETWEEN 4 AND 120),
 proof_object_path text NOT NULL UNIQUE,
 created_at timestamptz NOT NULL DEFAULT now(),
 UNIQUE(user_id,request_key),
 CHECK(proof_object_path ~ ('^'||user_id::text||'/'||id::text||'/[a-f0-9-]{36}[.](jpg|png|pdf)$'))
);
CREATE INDEX alani_wallet_topup_owner_time_idx ON private_checkout.alani_wallet_topup_requests(user_id,created_at DESC);
CREATE TABLE private_checkout.alani_wallet_topup_reviews (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 request_id uuid NOT NULL REFERENCES private_checkout.alani_wallet_topup_requests(id) ON DELETE RESTRICT,
 reviewer_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
 decision text NOT NULL CHECK(decision IN ('under_review','needs_information','rejected','externally_verified')),
 reason text NOT NULL CHECK(char_length(btrim(reason)) BETWEEN 12 AND 1000),
 created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX alani_wallet_topup_review_time_idx ON private_checkout.alani_wallet_topup_reviews(request_id,created_at DESC,id);
CREATE TABLE private_checkout.alani_wallet_verified_transfers (
 request_id uuid PRIMARY KEY REFERENCES private_checkout.alani_wallet_topup_requests(id) ON DELETE RESTRICT,
 provider_code text NOT NULL CHECK(provider_code ~ '^[a-z0-9_]{2,40}$'),
 verified_reference text NOT NULL CHECK(char_length(btrim(verified_reference)) BETWEEN 4 AND 120),
 settled_amount_iqd bigint NOT NULL CHECK(settled_amount_iqd>0 AND settled_amount_iqd<=1000000000),
 verified_by uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
 verified_at timestamptz NOT NULL DEFAULT now(),
 UNIQUE(provider_code,verified_reference)
);
ALTER TABLE private_checkout.alani_wallet_funding_gate ENABLE ROW LEVEL SECURITY;
ALTER TABLE private_checkout.alani_wallet_topup_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE private_checkout.alani_wallet_topup_reviews ENABLE ROW LEVEL SECURITY;
ALTER TABLE private_checkout.alani_wallet_verified_transfers ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private_checkout.alani_wallet_funding_gate,private_checkout.alani_wallet_topup_requests,private_checkout.alani_wallet_topup_reviews,private_checkout.alani_wallet_verified_transfers FROM PUBLIC,anon,authenticated;
COMMENT ON TABLE private_checkout.alani_wallet_funding_gate IS 'Closed foundation. No credit or intake RPC exists. Opening flags alone cannot enable collection.';
COMMENT ON TABLE private_checkout.alani_wallet_topup_requests IS 'Declared transfer proof request, never a balance or payment confirmation. File upload requires separate private Storage API, RLS and reconciliation.';
COMMENT ON TABLE private_checkout.alani_wallet_verified_transfers IS 'Reserved verified transfer reference uniqueness; no wallet credit function or client grants.';
DO $verify$ BEGIN
 IF EXISTS(SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='private_checkout' AND c.relname LIKE 'alani_wallet%' AND c.relkind='r' AND (NOT c.relrowsecurity OR has_table_privilege('authenticated',c.oid,'SELECT,INSERT,UPDATE,DELETE') OR has_table_privilege('anon',c.oid,'SELECT,INSERT,UPDATE,DELETE')))
 OR NOT EXISTS(SELECT 1 FROM private_checkout.alani_wallet_funding_gate WHERE singleton AND NOT request_intake_enabled AND NOT credit_enabled)
 OR NOT public.shitreed_alani_checkout_schema_ready()
 THEN RAISE EXCEPTION 'WALLET_FOUNDATION_POSTCHECK_FAILED'; END IF;
END $verify$;
COMMIT;
