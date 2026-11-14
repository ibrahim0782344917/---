\set ON_ERROR_STOP on

-- Isolated PostgreSQL fixture. No Supabase project or live users are touched.
create role anon;
create role authenticated;
create role service_role;
create schema auth;
create table auth.users (id uuid primary key);
create function auth.uid() returns uuid
  language sql stable as $$
    select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid
  $$;

create table public.stores (
  id uuid primary key,
  owner_id uuid not null references auth.users(id),
  status text not null
);
create table public.products (
  id uuid primary key,
  store_id uuid not null references public.stores(id),
  name text not null,
  price_iqd integer not null,
  is_active boolean not null default true
);

\ir ../migrations/20261107220000_cash_orders_and_inventory.sql
\ir ../migrations/20261114120000_checkout_idempotency.sql

insert into auth.users(id) values
  ('10000000-0000-4000-8000-000000000001'),
  ('10000000-0000-4000-8000-000000000002'),
  ('10000000-0000-4000-8000-000000000003');
insert into public.stores(id,owner_id,status) values
  ('20000000-0000-4000-8000-000000000001',
   '10000000-0000-4000-8000-000000000003','approved');
insert into public.products(id,store_id,name,price_iqd,is_active,stock_quantity)
  values ('30000000-0000-4000-8000-000000000001',
          '20000000-0000-4000-8000-000000000001',
          'اختبار منتج', 12000, true, 5);

select set_config('request.jwt.claim.sub',
  '10000000-0000-4000-8000-000000000001',false);

do $test$
declare
  first_id uuid;
  retry_id uuid;
  second_id uuid;
  first_count integer;
  current_stock integer;
begin
  first_id := public.place_cash_order(
    '20000000-0000-4000-8000-000000000001',
    '[{"product_id":"30000000-0000-4000-8000-000000000001","quantity":2}]'::jsonb,
    'بغداد - عنوان اختبار كامل', '07700000000', '',
    '40000000-0000-4000-8000-000000000001'
  );
  retry_id := public.place_cash_order(
    '20000000-0000-4000-8000-000000000001',
    '[{"quantity":2,"product_id":"30000000-0000-4000-8000-000000000001"}]'::jsonb,
    'بغداد - عنوان اختبار كامل', '07700000000', '',
    '40000000-0000-4000-8000-000000000001'
  );
  if first_id is distinct from retry_id then
    raise exception 'Retry created a different order';
  end if;
  select count(*) into first_count from public.orders;
  select stock_quantity into current_stock from public.products;
  if first_count <> 1 or current_stock <> 3 then
    raise exception 'Replay changed order count or stock: %, %',
      first_count,current_stock;
  end if;

  begin
    perform public.place_cash_order(
      '20000000-0000-4000-8000-000000000001',
      '[{"product_id":"30000000-0000-4000-8000-000000000001","quantity":1}]'::jsonb,
      'بغداد - عنوان اختبار كامل', '07700000000', '',
      '40000000-0000-4000-8000-000000000001'
    );
    raise exception 'EXPECTED_REPLAY_REJECTION';
  exception when others then
    if sqlerrm <> 'IDEMPOTENCY_KEY_REUSED' then raise; end if;
  end;

  second_id := public.place_cash_order(
    '20000000-0000-4000-8000-000000000001',
    '[{"product_id":"30000000-0000-4000-8000-000000000001","quantity":1}]'::jsonb,
    'بغداد - عنوان اختبار كامل', '07700000000', '',
    '40000000-0000-4000-8000-000000000002'
  );
  if second_id = first_id then
    raise exception 'New request key reused a prior order';
  end if;
  select count(*) into first_count from public.orders;
  select stock_quantity into current_stock from public.products;
  if first_count <> 2 or current_stock <> 2 then
    raise exception 'New order failed: %, %',first_count,current_stock;
  end if;
  if has_function_privilege('anon',
      'public.place_cash_order(uuid,jsonb,text,text,text,uuid)', 'EXECUTE') then
    raise exception 'Anonymous users can execute checkout RPC';
  end if;
  raise notice 'Checkout idempotency tests passed (retries, stock, mismatch, grants)';
end
$test$;

-- Another buyer may use the same opaque request UUID without seeing a
-- different buyer's order. Legacy Android clients still call with five args.
select set_config('request.jwt.claim.sub',
  '10000000-0000-4000-8000-000000000002',false);

do $test$
declare
  buyer_two_id uuid;
  legacy_id uuid;
  total_orders integer;
  stock_left integer;
begin
  buyer_two_id := public.place_cash_order(
    '20000000-0000-4000-8000-000000000001',
    '[{"product_id":"30000000-0000-4000-8000-000000000001","quantity":1}]'::jsonb,
    'بغداد - عنوان اختبار كامل', '07700000000', '',
    '40000000-0000-4000-8000-000000000001'
  );
  legacy_id := public.place_cash_order(
    '20000000-0000-4000-8000-000000000001',
    '[{"product_id":"30000000-0000-4000-8000-000000000001","quantity":1}]'::jsonb,
    'بغداد - عنوان اختبار كامل', '07700000000', ''
  );
  if buyer_two_id = legacy_id then
    raise exception 'Different calls yielded same order';
  end if;
  select count(*) into total_orders from public.orders;
  select stock_quantity into stock_left from public.products;
  if total_orders <> 4 or stock_left <> 0 then
    raise exception 'User isolation or legacy call failed: %, %',
      total_orders, stock_left;
  end if;
  raise notice 'Buyer isolation and legacy RPC compatibility passed';
end
$test$;
