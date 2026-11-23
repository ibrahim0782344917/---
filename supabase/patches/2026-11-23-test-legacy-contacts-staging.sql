-- Isolated staging schema for historical contact import. TEST DATABASE ONLY.
-- Never deploy or migrate to production without approval and privacy review.
BEGIN;
CREATE SCHEMA IF NOT EXISTS private_legacy;
REVOKE ALL ON SCHEMA private_legacy FROM PUBLIC, anon, authenticated;
CREATE TABLE IF NOT EXISTS private_legacy.contacts (
 source_serial integer PRIMARY KEY CHECK(source_serial>0),
 recipient_name text NOT NULL,
 phone_primary text NOT NULL UNIQUE CHECK(phone_primary ~ '^07[0-9]{9}$'),
 phone_secondary text CHECK(phone_secondary IS NULL OR phone_secondary ~ '^07[0-9]{9}$'),
 historical_order_count integer NOT NULL DEFAULT 0 CHECK(historical_order_count>=0),
 governorate text NOT NULL DEFAULT '',
 district text NOT NULL DEFAULT '',
 address_details text NOT NULL DEFAULT '',
 goods_type text NOT NULL DEFAULT '',
 source_row integer NOT NULL UNIQUE CHECK(source_row>0),
 name_quality text GENERATED ALWAYS AS (
 CASE WHEN btrim(recipient_name) IN ('لا','لا يوجد','0','-')
 THEN 'placeholder' ELSE 'unverified' END) STORED,
 source_batch text NOT NULL DEFAULT 'alani_2026_11_18',
 consent_verified boolean NOT NULL DEFAULT false,
 contact_verified boolean NOT NULL DEFAULT false,
 created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS private_legacy.review_queue (
 source_serial integer PRIMARY KEY CHECK(source_serial>0),
 recipient_name text, phone_primary text, phone_secondary text,
 historical_order_count integer, governorate text, district text,
 address_details text, goods_type text,
 source_row integer NOT NULL UNIQUE CHECK(source_row>0),
 review_reason text NOT NULL,
 review_status text NOT NULL DEFAULT 'pending'
 CHECK(review_status IN ('pending','verified','duplicate','rejected')),
 reviewer_notes text NOT NULL DEFAULT '',
 reviewed_at timestamptz,
 source_batch text NOT NULL DEFAULT 'alani_2026_11_18',
 created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE private_legacy.contacts ENABLE ROW LEVEL SECURITY;
ALTER TABLE private_legacy.review_queue ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON ALL TABLES IN SCHEMA private_legacy FROM PUBLIC, anon, authenticated;
GRANT USAGE ON SCHEMA private_legacy TO service_role;
GRANT SELECT, INSERT, UPDATE ON ALL TABLES IN SCHEMA private_legacy TO service_role;
COMMIT;
