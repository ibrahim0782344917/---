-- Synthetic delivery test: anonymous, buyer, courier, owner and admin.
-- Fail fast for any unauthorized action or missing audit.
SELECT 1/CASE WHEN
 NOT has_table_privilege('anon','public.alani_delivery_jobs','SELECT')
 AND NOT has_table_privilege('authenticated','public.alani_delivery_jobs','SELECT')
 AND NOT has_table_privilege('authenticated','public.alani_delivery_jobs','UPDATE')
 AND NOT has_table_privilege('authenticated','public.alani_delivery_couriers','INSERT')
THEN 1 ELSE 0 END AS no_direct_delivery_access;

SET ROLE anon;
DO $anon$
BEGIN
 BEGIN
  PERFORM public.alani_my_delivery_tasks();
  RAISE EXCEPTION 'ANON_TASK_ACCESS_BYPASS';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN
  PERFORM public.alani_issue_delivery_pin(
    '11111111-1111-4111-8111-111111111111');
  RAISE EXCEPTION 'ANON_CODE_ACCESS_BYPASS';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $anon$;
RESET ROLE;

-- An unrelated customer must not see an unassigned order:
-- this also catches nullable courier authorization bugs.
SELECT set_config('request.jwt.claim.sub',
 'dddddddd-dddd-4ddd-8ddd-dddddddddddd',false);
SET ROLE authenticated;
SELECT 1/CASE WHEN (SELECT count(*) FROM public.alani_my_delivery_tasks())=0
 THEN 1 ELSE 0 END AS unauthorized_courier_no_tasks;
DO $unauthorized$
BEGIN
 BEGIN
  PERFORM public.alani_order_delivery_status(
   '22222222-2222-4222-8222-222222222222');
  RAISE EXCEPTION 'UNASSIGNED_ORDER_READ_BYPASS';
 EXCEPTION WHEN OTHERS THEN
  IF SQLERRM<>'PERMISSION_DENIED' THEN RAISE; END IF;
 END;
 BEGIN
  PERFORM public.alani_set_delivery_courier(
   'dddddddd-dddd-4ddd-8ddd-dddddddddddd',true);
  RAISE EXCEPTION 'UNAUTHORIZED_COURIER_ASSIGNMENT_BYPASS';
 EXCEPTION WHEN OTHERS THEN
  IF SQLERRM<>'STORE_PERMISSION_DENIED' THEN RAISE; END IF;
 END;
END $unauthorized$;
RESET ROLE;

-- Owner alone authorizes the courier and dispatches a READY order.
SELECT set_config('request.jwt.claim.sub',
 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',false);
SET ROLE authenticated;
SELECT public.alani_set_delivery_courier(
 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',true);
SELECT 1/CASE WHEN (SELECT count(*) FROM public.alani_list_delivery_couriers()
 WHERE courier_id='bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb' AND enabled)=1
 THEN 1 ELSE 0 END AS owner_roster;
SELECT 1/CASE WHEN public.alani_dispatch_delivery(
 '11111111-1111-4111-8111-111111111111',
 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb')='out_for_delivery'
 THEN 1 ELSE 0 END AS owner_dispatched;
SELECT 1/CASE WHEN (SELECT count(*) FROM public.alani_owner_delivery_jobs()
 WHERE order_id='11111111-1111-4111-8111-111111111111')=1
 THEN 1 ELSE 0 END AS owner_has_dispatch_record;
RESET ROLE;

-- Buyer cannot generate a delivery code until courier picked it up.
SELECT set_config('request.jwt.claim.sub',
 'cccccccc-cccc-4ccc-8ccc-cccccccccccc',false);
SET ROLE authenticated;
DO $not_picked_up$
BEGIN
 BEGIN
  PERFORM public.alani_issue_delivery_pin(
   '11111111-1111-4111-8111-111111111111');
  RAISE EXCEPTION 'BUYER_ISSUED_BEFORE_PICKUP';
 EXCEPTION WHEN OTHERS THEN
  IF SQLERRM<>'COURIER_HAS_NOT_PICKED_UP' THEN RAISE; END IF;
 END;
END $not_picked_up$;
RESET ROLE;

-- Only the assigned courier sees the delivery address and can pick up.
SELECT set_config('request.jwt.claim.sub',
 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',false);
SET ROLE authenticated;
SELECT 1/CASE WHEN
 (SELECT count(*) FROM public.alani_my_delivery_tasks())=1
 AND (SELECT delivery_fee_iqd FROM public.alani_my_delivery_tasks()
 WHERE order_id='11111111-1111-4111-8111-111111111111')=5000
 THEN 1 ELSE 0 END AS courier_sees_assigned_fee_only;
SELECT 1/CASE WHEN public.alani_courier_pickup(
 '11111111-1111-4111-8111-111111111111') IS NOT NULL
 THEN 1 ELSE 0 END AS courier_pickup;
RESET ROLE;

-- Buyer alone receives the code once; only a hash is persisted.
SELECT set_config('request.jwt.claim.sub',
 'cccccccc-cccc-4ccc-8ccc-cccccccccccc',false);
SET ROLE authenticated;
SELECT set_config('test.synthetic.pin',
 (public.alani_issue_delivery_pin(
  '11111111-1111-4111-8111-111111111111')->>'code'),false) IS NOT NULL
 AS buyer_receives_code;
RESET ROLE;

SELECT set_config('request.jwt.claim.sub',
 'dddddddd-dddd-4ddd-8ddd-dddddddddddd',false);
SET ROLE authenticated;
DO $other$
BEGIN
 BEGIN
  PERFORM public.alani_issue_delivery_pin(
    '11111111-1111-4111-8111-111111111111');
  RAISE EXCEPTION 'OTHER_BUYER_RECEIVED_CODE';
 EXCEPTION WHEN OTHERS THEN
  IF SQLERRM<>'PERMISSION_DENIED' THEN RAISE; END IF;
 END;
END $other$;
SELECT 1/CASE WHEN (SELECT count(*) FROM public.alani_my_delivery_tasks())=0
 THEN 1 ELSE 0 END AS unrelated_user_has_no_tasks;
RESET ROLE;

-- A wrong PIN is recorded, but does not deliver the order.
SELECT set_config('request.jwt.claim.sub',
 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',false);
SET ROLE authenticated;
SELECT 1/CASE WHEN public.alani_courier_complete_delivery(
 '11111111-1111-4111-8111-111111111111','000000','wrong test')='WRONG_CODE'
 THEN 1 ELSE 0 END AS rejected_wrong_pin;
SELECT 1/CASE WHEN public.alani_courier_complete_delivery(
 '11111111-1111-4111-8111-111111111111',
 current_setting('test.synthetic.pin'),'customer physically received goods')='delivered'
 THEN 1 ELSE 0 END AS correct_pin_delivers;
SELECT 1/CASE WHEN public.alani_courier_complete_delivery(
 '11111111-1111-4111-8111-111111111111',
 current_setting('test.synthetic.pin'),'retry')='delivered'
 THEN 1 ELSE 0 END AS idempotent_delivery;
RESET ROLE;

SELECT 1/CASE WHEN
 (SELECT status FROM public.orders WHERE id='11111111-1111-4111-8111-111111111111')='delivered'
 AND (SELECT delivered_at IS NOT NULL FROM public.orders
   WHERE id='11111111-1111-4111-8111-111111111111')
 AND (SELECT proof_method='buyer_one_time_pin' AND pin_hash IS NULL
  AND pin_salt IS NULL AND failed_attempts=1
  FROM public.alani_delivery_jobs
  WHERE order_id='11111111-1111-4111-8111-111111111111')
 AND (SELECT count(*) FROM public.order_status_history
   WHERE order_id='11111111-1111-4111-8111-111111111111'
   AND new_status='out_for_delivery')=1
 AND (SELECT count(*) FROM public.order_status_history
   WHERE order_id='11111111-1111-4111-8111-111111111111'
   AND new_status='delivered')=1
THEN 1 ELSE 0 END AS audited_delivery_with_one_failed_guess;

-- The PIN from a different thread/order cannot be used.
-- Five incorrect attempts persist and lock the delivery until reissuance.
SELECT set_config('request.jwt.claim.sub',
 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',false);
SET ROLE authenticated;
SELECT public.alani_dispatch_delivery(
 '22222222-2222-4222-8222-222222222222',
 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb');
RESET ROLE;
SELECT set_config('request.jwt.claim.sub',
 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',false);
SET ROLE authenticated;
SELECT public.alani_courier_pickup('22222222-2222-4222-8222-222222222222');
RESET ROLE;
SELECT set_config('request.jwt.claim.sub',
 'cccccccc-cccc-4ccc-8ccc-cccccccccccc',false);
SET ROLE authenticated;
SELECT (public.alani_issue_delivery_pin(
  '22222222-2222-4222-8222-222222222222')->>'code') ~ '^[0-9]{6}$'
 AS second_valid_code;
RESET ROLE;
SELECT set_config('request.jwt.claim.sub',
 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',false);
SET ROLE authenticated;
SELECT 1/CASE WHEN public.alani_courier_complete_delivery(
 '22222222-2222-4222-8222-222222222222','000000','')='WRONG_CODE'
 THEN 1 ELSE 0 END AS wrong1;
SELECT 1/CASE WHEN public.alani_courier_complete_delivery(
 '22222222-2222-4222-8222-222222222222','000000','')='WRONG_CODE'
 THEN 1 ELSE 0 END AS wrong2;
SELECT 1/CASE WHEN public.alani_courier_complete_delivery(
 '22222222-2222-4222-8222-222222222222','000000','')='WRONG_CODE'
 THEN 1 ELSE 0 END AS wrong3;
SELECT 1/CASE WHEN public.alani_courier_complete_delivery(
 '22222222-2222-4222-8222-222222222222','000000','')='WRONG_CODE'
 THEN 1 ELSE 0 END AS wrong4;
SELECT 1/CASE WHEN public.alani_courier_complete_delivery(
 '22222222-2222-4222-8222-222222222222','000000','')='WRONG_CODE'
 THEN 1 ELSE 0 END AS wrong5;
SELECT 1/CASE WHEN public.alani_courier_complete_delivery(
 '22222222-2222-4222-8222-222222222222','000000','')='CODE_LOCKED'
 THEN 1 ELSE 0 END AS sixth_guess_blocked;
RESET ROLE;
SELECT 1/CASE WHEN
 (SELECT status FROM public.orders WHERE id='22222222-2222-4222-8222-222222222222')='out_for_delivery'
 AND (SELECT failed_attempts FROM public.alani_delivery_jobs
 WHERE order_id='22222222-2222-4222-8222-222222222222')=5
THEN 1 ELSE 0 END AS locked_job_not_delivered;

SELECT 'PASS: role isolation, delivery fee, pickup, code handoff, audit, and five-guess lock' AS result;
