-- Register requested provider candidates only; no merchant approval or money collection.
BEGIN;
SET LOCAL lock_timeout='3s';
DO $g$ BEGIN
 IF NOT EXISTS(SELECT 1 FROM private_checkout.alani_wallet_funding_gate WHERE singleton AND NOT request_intake_enabled AND NOT credit_enabled)
 THEN RAISE EXCEPTION 'FUNDING_GATE_NOT_CLOSED'; END IF;
END $g$;
INSERT INTO private_checkout.alani_wallet_allowed_providers(code,label,enabled) VALUES
 ('nbi','المصرف الأهلي العراقي',false),
 ('zaincash','زين كاش ZainCash',false),
 ('superqi','سوبر كي SuperQi',false),
 ('aps','العرب لخدمات الدفع الإلكتروني APS',false)
ON CONFLICT(code) DO NOTHING;
DO $v$ BEGIN
 IF (SELECT count(*) FROM private_checkout.alani_wallet_allowed_providers WHERE code IN ('nbi','zaincash','superqi','aps') AND NOT enabled)<>4
 OR EXISTS(SELECT 1 FROM private_checkout.alani_wallet_allowed_providers WHERE enabled)
 THEN RAISE EXCEPTION 'PROVIDERS_MUST_REMAIN_DISABLED'; END IF;
END $v$;
COMMIT;