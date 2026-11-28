CREATE EXTENSION IF NOT EXISTS pg_cron WITH SCHEMA pg_catalog;
GRANT USAGE ON SCHEMA cron TO postgres;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA cron TO postgres;
SELECT cron.schedule('alani-expired-location-cleanup','* * * * *',$job$DELETE FROM private_checkout.alani_delivery_location WHERE updated_at <= clock_timestamp()-interval '90 seconds'$job$);