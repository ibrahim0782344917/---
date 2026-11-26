-- TEST ONLY; private legacy import staging and simulated wallet. No real contacts or money.
DO $$ BEGIN
 IF to_regclass('private_checkout.alani_fcm_test_devices') IS NULL OR to_regclass('private_checkout.alani_fcm_gate') IS NOT NULL THEN RAISE EXCEPTION 'TEST_ONLY_REQUIRED'; END IF;
END $$;
CREATE TABLE private_checkout.alani_legacy_batches_test(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 source_sha256 text NOT NULL UNIQUE CHECK(source_sha256 ~ '^[a-f0-9]{64}$'),
 expected_rows integer NOT NULL CHECK(expected_rows BETWEEN 1 AND 100000),
 created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE private_checkout.alani_legacy_contacts_test(
 batch_id uuid NOT NULL REFERENCES private_checkout.alani_legacy_batches_test(id),
 source_row integer NOT NULL CHECK(source_row>=2),
 recipient_name text NOT NULL CHECK(length(btrim(recipient_name)) BETWEEN 1 AND 160),
 phone_primary text NOT NULL UNIQUE CHECK(phone_primary ~ '^07[3-9][0-9]{8}$'),
 PRIMARY KEY(batch_id,source_row)
);
CREATE FUNCTION private_checkout.alani_import_synthetic_contacts_test(p_batch uuid,p_rows jsonb)
RETURNS integer LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE expected integer; n integer; existing integer;
BEGIN
 IF p_rows IS NULL OR jsonb_typeof(p_rows)<>'array' THEN RAISE EXCEPTION 'INVALID_ROWS'; END IF;
 n:=jsonb_array_length(p_rows);
 IF n NOT BETWEEN 1 AND 100 THEN RAISE EXCEPTION 'INVALID_BATCH_SIZE'; END IF;
 SELECT expected_rows INTO expected FROM private_checkout.alani_legacy_batches_test WHERE id=p_batch FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'BATCH_NOT_FOUND'; END IF;
 -- Deliberately accepts synthetic fixtures only; no actual legacy PII in TEST.
 IF EXISTS(SELECT 1 FROM jsonb_to_recordset(p_rows) AS x(source_row int,recipient_name text,phone_primary text) WHERE x.source_row IS NULL OR x.source_row<2 OR x.recipient_name IS NULL OR x.recipient_name !~ '^Synthetic [0-9]+$' OR x.phone_primary IS NULL OR x.phone_primary !~ '^0790000[0-9]{4}$') THEN RAISE EXCEPTION 'SYNTHETIC_ONLY'; END IF;
 IF EXISTS(SELECT 1 FROM jsonb_to_recordset(p_rows) AS x(source_row int,recipient_name text,phone_primary text) JOIN private_checkout.alani_legacy_contacts_test c ON c.batch_id=p_batch AND c.source_row=x.source_row WHERE (c.recipient_name,c.phone_primary) IS DISTINCT FROM (x.recipient_name,x.phone_primary)) THEN RAISE EXCEPTION 'IMPORT_PAYLOAD_MISMATCH'; END IF;
 INSERT INTO private_checkout.alani_legacy_contacts_test(batch_id,source_row,recipient_name,phone_primary)
 SELECT p_batch,x.source_row,x.recipient_name,x.phone_primary FROM jsonb_to_recordset(p_rows) AS x(source_row int,recipient_name text,phone_primary text)
 ON CONFLICT(batch_id,source_row) DO NOTHING;
 GET DIAGNOSTICS n=ROW_COUNT;
 SELECT count(*) INTO existing FROM private_checkout.alani_legacy_contacts_test WHERE batch_id=p_batch;
 IF existing>expected THEN RAISE EXCEPTION 'BATCH_LIMIT'; END IF;
 RETURN n;
END $$;
CREATE TABLE private_checkout.alani_wallet_accounts_test(
 user_id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
 balance_iqd bigint NOT NULL DEFAULT 0 CHECK(balance_iqd BETWEEN 0 AND 1000000000)
);
CREATE TABLE private_checkout.alani_wallet_ledger_test(
 user_id uuid NOT NULL REFERENCES private_checkout.alani_wallet_accounts_test(user_id) ON DELETE RESTRICT,
 request_key uuid NOT NULL,
 delta_iqd bigint NOT NULL CHECK(delta_iqd<>0 AND delta_iqd BETWEEN -1000000000 AND 1000000000),
 balance_after_iqd bigint NOT NULL CHECK(balance_after_iqd BETWEEN 0 AND 1000000000),
 created_at timestamptz NOT NULL DEFAULT now(),
 PRIMARY KEY(user_id,request_key)
);
CREATE FUNCTION private_checkout.alani_wallet_simulate_test(p_user uuid,p_key uuid,p_delta bigint)
RETURNS bigint LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE b bigint; old_delta bigint; old_balance bigint;
BEGIN
 IF p_user IS NULL OR p_key IS NULL OR p_delta IS NULL OR p_delta=0 OR p_delta NOT BETWEEN -1000000000 AND 1000000000 THEN RAISE EXCEPTION 'INVALID_WALLET_REQUEST'; END IF;
 IF NOT EXISTS(SELECT 1 FROM auth.users u WHERE u.id=p_user AND u.email LIKE '%@example.invalid') THEN RAISE EXCEPTION 'SYNTHETIC_USER_ONLY'; END IF;
 INSERT INTO private_checkout.alani_wallet_accounts_test(user_id) VALUES(p_user) ON CONFLICT DO NOTHING;
 SELECT balance_iqd INTO b FROM private_checkout.alani_wallet_accounts_test WHERE user_id=p_user FOR UPDATE;
 SELECT delta_iqd,balance_after_iqd INTO old_delta,old_balance FROM private_checkout.alani_wallet_ledger_test WHERE user_id=p_user AND request_key=p_key;
 IF FOUND THEN IF old_delta<>p_delta THEN RAISE EXCEPTION 'WALLET_PAYLOAD_MISMATCH'; END IF; RETURN old_balance; END IF;
 IF b+p_delta<0 THEN RAISE EXCEPTION 'INSUFFICIENT_BALANCE'; END IF;
 IF b+p_delta>1000000000 THEN RAISE EXCEPTION 'BALANCE_LIMIT'; END IF;
 b:=b+p_delta;
 UPDATE private_checkout.alani_wallet_accounts_test SET balance_iqd=b WHERE user_id=p_user;
 INSERT INTO private_checkout.alani_wallet_ledger_test(user_id,request_key,delta_iqd,balance_after_iqd) VALUES(p_user,p_key,p_delta,b);
 RETURN b;
END $$;
ALTER TABLE private_checkout.alani_legacy_batches_test ENABLE ROW LEVEL SECURITY;
ALTER TABLE private_checkout.alani_legacy_contacts_test ENABLE ROW LEVEL SECURITY;
ALTER TABLE private_checkout.alani_wallet_accounts_test ENABLE ROW LEVEL SECURITY;
ALTER TABLE private_checkout.alani_wallet_ledger_test ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private_checkout.alani_legacy_batches_test,private_checkout.alani_legacy_contacts_test,private_checkout.alani_wallet_accounts_test,private_checkout.alani_wallet_ledger_test FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION private_checkout.alani_import_synthetic_contacts_test(uuid,jsonb),private_checkout.alani_wallet_simulate_test(uuid,uuid,bigint) FROM PUBLIC,anon,authenticated,service_role;
