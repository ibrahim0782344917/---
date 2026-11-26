-- Production FCM foundation. Disabled until authenticated device registration,
-- private worker credentials, end-to-end tests and a verified activation.
BEGIN;
SET LOCAL lock_timeout='3s';
SET LOCAL statement_timeout='30s';
DO $guard$ BEGIN
 IF NOT public.shitreed_alani_checkout_schema_ready()
 OR to_regclass('private_checkout.alani_fcm_devices') IS NOT NULL
 OR to_regclass('private_checkout.alani_fcm_outbox') IS NOT NULL
 OR to_regclass('private_checkout.alani_fcm_gate') IS NOT NULL
 THEN RAISE EXCEPTION 'FCM_PREFLIGHT_FAILED'; END IF;
END $guard$;
CREATE TABLE private_checkout.alani_fcm_gate (
 singleton boolean PRIMARY KEY DEFAULT true CHECK(singleton),
 registration_enabled boolean NOT NULL DEFAULT false,
 sending_enabled boolean NOT NULL DEFAULT false,
 activated_at timestamptz,
 CHECK(NOT sending_enabled OR (registration_enabled AND activated_at IS NOT NULL))
);
INSERT INTO private_checkout.alani_fcm_gate(singleton) VALUES(true);
CREATE TABLE private_checkout.alani_fcm_devices (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
 session_id uuid NOT NULL,
 app_kind text NOT NULL CHECK(app_kind IN ('customer','merchant','admin')),
 fcm_token text NOT NULL UNIQUE CHECK(char_length(fcm_token) BETWEEN 20 AND 4096),
 verified_at timestamptz,
 consent_at timestamptz NOT NULL,
 updated_at timestamptz NOT NULL DEFAULT now(),
 revoked_at timestamptz,
 CHECK(verified_at IS NULL OR verified_at>=consent_at)
);
CREATE INDEX alani_fcm_device_owner_idx ON private_checkout.alani_fcm_devices(user_id,app_kind) WHERE revoked_at IS NULL;
CREATE TABLE private_checkout.alani_fcm_outbox (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 event_kind text NOT NULL CHECK(event_kind IN ('order_update','support_update')),
 event_id uuid NOT NULL,
 recipient_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
 device_id uuid NOT NULL REFERENCES private_checkout.alani_fcm_devices(id) ON DELETE CASCADE,
 created_at timestamptz NOT NULL DEFAULT now(),
 expires_at timestamptz NOT NULL DEFAULT (now()+interval '1 hour'),
 state text NOT NULL DEFAULT 'pending' CHECK(state IN ('pending','leased','sent','failed','expired','suppressed')),
 attempts integer NOT NULL DEFAULT 0 CHECK(attempts BETWEEN 0 AND 5),
 next_attempt_at timestamptz NOT NULL DEFAULT now(),
 lease_until timestamptz,
 sent_at timestamptz,
 last_error_code text CHECK(last_error_code IS NULL OR last_error_code ~ '^[A-Z0-9_]{1,60}$'),
 UNIQUE(event_kind,event_id,device_id),
 CHECK(expires_at>created_at),
 CHECK(state<>'sent' OR sent_at IS NOT NULL)
);
CREATE INDEX alani_fcm_outbox_pending_idx ON private_checkout.alani_fcm_outbox(next_attempt_at,created_at) WHERE state='pending';
ALTER TABLE private_checkout.alani_fcm_gate ENABLE ROW LEVEL SECURITY;
ALTER TABLE private_checkout.alani_fcm_devices ENABLE ROW LEVEL SECURITY;
ALTER TABLE private_checkout.alani_fcm_outbox ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private_checkout.alani_fcm_gate,private_checkout.alani_fcm_devices,private_checkout.alani_fcm_outbox FROM PUBLIC,anon,authenticated;
-- No public registration/send API, triggers, cron jobs or worker grants.
-- No private message text, addresses, phones or balances are copied to queue.
COMMENT ON TABLE private_checkout.alani_fcm_devices IS 'Closed FCM foundation; verify token possession and session binding before registration activation.';
COMMENT ON TABLE private_checkout.alani_fcm_outbox IS 'Private deduplicated event reference queue; recipients must be reauthorized before delivery. Sending remains disabled.';
DO $verify$ BEGIN
 IF EXISTS(SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
 WHERE n.nspname='private_checkout' AND c.relname IN ('alani_fcm_gate','alani_fcm_devices','alani_fcm_outbox') AND (NOT c.relrowsecurity OR has_table_privilege('anon',c.oid,'SELECT,INSERT,UPDATE,DELETE') OR has_table_privilege('authenticated',c.oid,'SELECT,INSERT,UPDATE,DELETE')))
 OR NOT EXISTS(SELECT 1 FROM private_checkout.alani_fcm_gate WHERE singleton AND NOT registration_enabled AND NOT sending_enabled)
 OR NOT public.shitreed_alani_checkout_schema_ready()
 THEN RAISE EXCEPTION 'FCM_POSTCHECK_FAILED'; END IF;
END $verify$;
COMMIT;
