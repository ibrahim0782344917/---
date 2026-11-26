BEGIN;
INSERT INTO auth.users(id,aud,role,email,raw_app_meta_data,raw_user_meta_data) VALUES ('00000000-0000-4000-8000-000000014001','authenticated','authenticated','alani-prefs-a@example.invalid','{}','{}'),('00000000-0000-4000-8000-000000014002','authenticated','authenticated','alani-prefs-b@example.invalid','{}','{}');
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000014001',true) IS NOT NULL;
SELECT set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('request.jwt.claim.sub'),'role','authenticated')::text,true) IS NOT NULL;
INSERT INTO public.alani_notification_preferences_test DEFAULT VALUES;
DO $$ BEGIN
IF NOT COALESCE(((SELECT NOT order_updates AND NOT favorite_updates AND NOT monthly_reviews FROM public.alani_notification_preferences_test)),false) THEN RAISE EXCEPTION 'FAIL default off'; END IF;
END $$;

UPDATE public.alani_notification_preferences_test SET favorite_updates=true;
DO $$ BEGIN
IF NOT COALESCE(((SELECT favorite_updates FROM public.alani_notification_preferences_test)),false) THEN RAISE EXCEPTION 'FAIL explicit opt-in'; END IF;
END $$;

SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000014002',true) IS NOT NULL;
SELECT set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('request.jwt.claim.sub'),'role','authenticated')::text,true) IS NOT NULL;
DO $$ BEGIN
IF NOT COALESCE(((SELECT count(*) FROM public.alani_notification_preferences_test)=0),false) THEN RAISE EXCEPTION 'FAIL read isolation'; END IF;
BEGIN INSERT INTO public.alani_notification_preferences_test(user_id) VALUES('00000000-0000-4000-8000-000000014001'); RAISE EXCEPTION 'FAIL cross-user insert'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;

UPDATE public.alani_notification_preferences_test SET favorite_updates=false WHERE user_id='00000000-0000-4000-8000-000000014001';
SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000014001',true) IS NOT NULL;
SELECT set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('request.jwt.claim.sub'),'role','authenticated')::text,true) IS NOT NULL;
DO $$ BEGIN
IF NOT COALESCE(((SELECT favorite_updates FROM public.alani_notification_preferences_test)),false) THEN RAISE EXCEPTION 'FAIL other user cannot update'; END IF;
END $$;

UPDATE public.alani_notification_preferences_test SET favorite_updates=false;
DO $$ BEGIN
IF NOT COALESCE(((SELECT NOT favorite_updates FROM public.alani_notification_preferences_test)),false) THEN RAISE EXCEPTION 'FAIL opt-out'; END IF;
END $$;

RESET ROLE;
DO $$ BEGIN
IF NOT COALESCE((NOT has_table_privilege('anon','public.alani_notification_preferences_test','SELECT,INSERT,UPDATE,DELETE')),false) THEN RAISE EXCEPTION 'FAIL anon blocked'; END IF;
IF NOT COALESCE((NOT has_table_privilege('authenticated','public.alani_notification_preferences_test','DELETE')),false) THEN RAISE EXCEPTION 'FAIL no client delete'; END IF;
END $$;

SELECT 'PASS: 8 notification preference assertions' AS result;
ROLLBACK;