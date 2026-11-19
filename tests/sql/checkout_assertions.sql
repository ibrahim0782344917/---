-- Assert shipped delivery SQL against the disposable PostgreSQL sandbox.
select set_config('request.jwt.claim.sub',
  '11111111-1111-4111-8111-111111111111',false);

do $$
declare
  alani_order uuid;
  other_order uuid;
  product_after integer;
  existing_count integer;
  failed boolean;
begin
  alani_order := public.place_cash_order(
    '25091ca2-c0da-416c-b634-81b188ee66be',
    '[{"product_id":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","quantity":2}]'::jsonb,
    'شارع افتراضي رقم ١٠ - بغداد', '07812345678',''
  );
  if (select total_iqd from public.orders where id=alani_order) <> 25000 then
    raise exception 'Al-Ani 20000 subtotal + 5000 shipping not saved';
  end if;
  if (select delivery_fee_iqd from public.orders where id=alani_order) <> 5000 then
    raise exception 'Al-Ani delivery_fee_iqd should be 5000';
  end if;
  if (select sum(line_total_iqd) from public.order_items
      where order_id=alani_order) <> 20000 then
    raise exception 'Order product snapshots wrong';
  end if;
  if (select stock_quantity from public.products
      where id='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa') <> 8 then
    raise exception 'Al-Ani stock not reduced atomically';
  end if;

  other_order := public.place_cash_order(
    '33333333-3333-4333-8333-333333333333',
    '[{"product_id":"bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb","quantity":2}]'::jsonb,
    'شارع افتراضي رقم ١١ - بغداد','07812345678',''
  );
  if (select total_iqd from public.orders where id=other_order) <> 14000 then
    raise exception 'Other merchant was charged Al-Ani shipping';
  end if;
  if (select delivery_fee_iqd from public.orders where id=other_order) <> 0 then
    raise exception 'Other merchant shipping should remain zero';
  end if;

  select count(*) into existing_count from public.orders;
  select stock_quantity into product_after from public.products
    where id='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
  failed := false;
  begin
    perform public.place_cash_order(
      '25091ca2-c0da-416c-b634-81b188ee66be',
      '[{"product_id":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","quantity":20}]',
      'عنوان اختبار صالح', '07812345678',''
    );
  exception when others then
    if sqlerrm <> 'OUT_OF_STOCK' then raise; end if;
    failed := true;
  end;
  if not failed or (select count(*) from public.orders)<>existing_count or
     (select stock_quantity from public.products
      where id='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa')<>product_after then
    raise exception 'Out of stock validation or atomic rollback failed';
  end if;

  failed := false;
  begin
    perform public.place_cash_order(
      '25091ca2-c0da-416c-b634-81b188ee66be',
      '[{"product_id":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","quantity":1},'||
      '{"product_id":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","quantity":1}]',
      'عنوان اختبار صالح', '07812345678',''
    );
  exception when others then
    if sqlerrm <> 'INVALID_OR_DUPLICATE_ITEM' then raise; end if;
    failed := true;
  end;
  if not failed or (select count(*) from public.orders)<>existing_count then
    raise exception 'Duplicate line detection failed';
  end if;

  raise notice 'PASS: delivery 5000, other stores unaffected, stock, rollback, duplicate items';
end$$;

select set_config('request.jwt.claim.sub','',false);
do $$
declare
  refused boolean:=false;
begin
  begin
    perform public.place_cash_order(
      '25091ca2-c0da-416c-b634-81b188ee66be',
      '[{"product_id":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","quantity":1}]',
      'عنوان اختبار صالح','07812345678',''
    );
  exception when others then
    if sqlerrm <> 'LOGIN_REQUIRED' then raise; end if;
    refused:=true;
  end;
  if not refused then raise exception 'Anonymous checkout was not blocked'; end if;
  raise notice 'PASS: anonymous user rejected';
end$$;
