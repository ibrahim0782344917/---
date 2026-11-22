-- All checks run against synthetic data in a disposable PostgreSQL container.
-- No real orders, passwords, users, customer data, or merchant transactions.
select 1 / (case when
 (select total_iqd from public.orders where id='f0000000-0000-4000-8000-000000000001')=9500
 and (select delivery_fee_iqd from public.orders where id='f0000000-0000-4000-8000-000000000001')=0
then 1 else 0 end) as historical_orders_unchanged;

-- Unauthenticated clients must not invoke Al-Ani's protected checkout.
set role anon;
do $$
begin
 begin
   perform public.place_alani_cash_order('[]'::jsonb,
    'عنوان واضح في بغداد','07700000000','',
    'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee',5000);
   raise exception 'TEST_ANON_NOT_REJECTED';
 exception when others then
   if sqlerrm='TEST_ANON_NOT_REJECTED' then raise; end if;
   if position('permission denied' in sqlerrm)=0 then raise; end if;
 end;
end $$;
reset role;

select set_config('request.jwt.claim.sub',
  'cccccccc-cccc-4ccc-8ccc-cccccccccccc',false);
set role authenticated;

-- Two products: subtotal 30,000 + single 5,000 delivery fee = 35,000.
select set_config('test.alani_order_id',
  public.place_alani_cash_order(
    '[{"product_id":"11111111-1111-4111-8111-111111111111","quantity":1},
      {"product_id":"22222222-2222-4222-8222-222222222221","quantity":2}]'::jsonb,
    'الغزالية، شارع تجريبي، منزل ١٢','07700000001','',
    'aaaaaaaa-1111-4111-8111-111111111111',35000
  )::text,false);
select 1 / (case when count(*)=1 then 1 else 0 end)
  as order_total_delivery_correct
from public.orders
where id=current_setting('test.alani_order_id')::uuid
  and buyer_id='cccccccc-cccc-4ccc-8ccc-cccccccccccc'
  and total_iqd=35000 and delivery_fee_iqd=5000
  and payment_method='cash_on_delivery';

select 1 / (case when sum(line_total_iqd)=30000 then 1 else 0 end)
  as price_snapshots_correct
from public.order_items where order_id=current_setting('test.alani_order_id')::uuid;

select 1 / (case when count(*)=2 then 1 else 0 end)
  as correct_two_lines
from public.order_items where order_id=current_setting('test.alani_order_id')::uuid;

select 1 / (case when
 (select stock_quantity from public.products
  where id='11111111-1111-4111-8111-111111111111')=4 and
 (select stock_quantity from public.products
  where id='22222222-2222-4222-8222-222222222221')=6
then 1 else 0 end) as stock_once;

-- Same request key returns the same order without another charge or stock change.
select 1 / (case when public.place_alani_cash_order(
    '[{"product_id":"11111111-1111-4111-8111-111111111111","quantity":1},
      {"product_id":"22222222-2222-4222-8222-222222222221","quantity":2}]'::jsonb,
    'الغزالية، شارع تجريبي، منزل ١٢','07700000001','',
    'aaaaaaaa-1111-4111-8111-111111111111',35000
)=current_setting('test.alani_order_id')::uuid then 1 else 0 end)
as same_request_same_order;

-- Another payload using same key is forbidden.
do $$
begin
 begin
   perform public.place_alani_cash_order(
     '[{"product_id":"11111111-1111-4111-8111-111111111111","quantity":1}]'::jsonb,
     'الغزالية، شارع تجريبي، منزل ١٢','07700000001','',
     'aaaaaaaa-1111-4111-8111-111111111111',25000);
   raise exception 'TEST_CHANGED_PAYLOAD_NOT_REJECTED';
 exception when others then
   if position('IDEMPOTENCY_PAYLOAD_MISMATCH' in sqlerrm)=0 then raise; end if;
 end;
end $$;

-- If a price changed after a customer saw a quote, reject the whole order.
do $$
begin
 begin
   perform public.place_alani_cash_order(
     '[{"product_id":"11111111-1111-4111-8111-111111111111","quantity":1}]'::jsonb,
     'الغزالية، شارع تجريبي، منزل ١٢','07700000001','',
     'aaaaaaaa-2222-4222-8222-222222222222',24000);
   raise exception 'TEST_TOTAL_MISMATCH_NOT_REJECTED';
 exception when others then
   if position('ORDER_TOTAL_CHANGED' in sqlerrm)=0 then raise; end if;
 end;
end $$;

-- Check internal idempotency storage only as the test database superuser;
-- real app roles have NO access to private_checkout.
reset role;
-- No additional order, no new idempotency record on price mismatch.
select 1 / (case when
 (select count(*) from public.orders)=2 and
 (select count(*) from private_checkout.web_checkout_requests)=1 and
 (select stock_quantity from public.products
  where id='11111111-1111-4111-8111-111111111111')=4
then 1 else 0 end) as price_mismatch_atomic_rollback;
set role authenticated;

do $
begin
 begin
   perform public.place_alani_cash_order(
     '[{"product_id":"11111111-1111-4111-8111-111111111111","quantity":20}]'::jsonb,
     'الغزالية، شارع تجريبي، منزل ١٢','07700000001','',
     'aaaaaaaa-3333-4333-8333-333333333333',405000);
   raise exception 'TEST_STOCK_ERROR_NOT_REJECTED';
 exception when others then
   if position('OUT_OF_STOCK' in sqlerrm)=0 then raise; end if;
 end;
end $$;

-- Existing generic RPC MUST refuse Al-Ani, since old clients omit the fee.
do $$
begin
 begin
   perform public.place_cash_order(
     '25091ca2-c0da-416c-b634-81b188ee66be',
     '[{"product_id":"11111111-1111-4111-8111-111111111111","quantity":1}]'::jsonb,
     'الغزالية، شارع تجريبي، منزل ١٢','07700000001','');
   raise exception 'TEST_LEGACY_ALANI_NOT_BLOCKED';
 exception when others then
   if position('ALANI_USE_VERIFIED_CHECKOUT' in sqlerrm)=0 then raise; end if;
 end;
end $$;

-- Other merchants must continue to have their existing no-fee semantics.
select set_config('test.other_order_id',
 public.place_cash_order(
   '22222222-2222-4222-8222-222222222222',
   '[{"product_id":"33333333-3333-4333-8333-333333333331","quantity":1}]'::jsonb,
   'عنوان اختبار في العراق','07700000002',''
 )::text,false);
select 1 / (case when count(*)=1 then 1 else 0 end)
 as other_store_unchanged
from public.orders
where id=current_setting('test.other_order_id')::uuid
  and total_iqd=7000 and delivery_fee_iqd=0;

reset role;
select 1 / (case when count(*)=3 then 1 else 0 end) as exactly_three_orders_including_old;
select 'PASS - AlAni 5000 delivery once; idempotency; rollback; other stores; historic orders' as result;
