-- Run on disposable PostgreSQL 17 only.
do $$
declare
  v_store uuid:='25091ca2-c0da-416c-b634-81b188ee66be';
  v_user uuid:='11111111-1111-4111-8111-111111111111';
  v_actor uuid:='99999999-9999-4999-8999-999999999999';
  v_balance bigint;
  v_failed boolean:=false;
begin
  v_balance:=private_finance.apply_store_credit(
    v_store,v_user,v_actor,5000,'credit',
    '10101010-1010-4010-8010-101010101010','تعويض تجريبي معتمد');
  if v_balance<>5000 then raise exception 'Credit balance should be 5000'; end if;
  v_balance:=private_finance.apply_store_credit(
    v_store,v_user,v_actor,5000,'credit',
    '10101010-1010-4010-8010-101010101010','تعويض تجريبي معتمد');
  if v_balance<>5000 then raise exception 'Duplicate credit changed balance'; end if;
  if (select count(*) from private_finance.store_credit_movements
      where store_id=v_store and user_id=v_user)<>1 then
    raise exception 'Duplicate ledger row recorded'; end if;

  v_balance:=private_finance.apply_store_credit(
    v_store,v_user,v_actor,2000,'debit',
    '20202020-2020-4020-8020-202020202020','شراء اختبار بالرصيد');
  if v_balance<>3000 then raise exception 'Debit balance should be 3000'; end if;

  begin
    perform private_finance.apply_store_credit(
      v_store,v_user,v_actor,5000,'credit',
      '10101010-1010-4010-8010-101010101010','تعويض مختلف غير مسموح');
  exception when others then
    if sqlerrm<>'CREDIT_IDEMPOTENCY_MISMATCH' then raise; end if;
    v_failed:=true;
  end;
  if not v_failed then raise exception 'Idempotency mismatch was accepted'; end if;

  v_failed:=false;
  begin
    perform private_finance.apply_store_credit(
      v_store,v_user,v_actor,4000,'debit',
      '30303030-3030-4030-8030-303030303030','شراء يفوق الرصيد');
  exception when others then
    if sqlerrm<>'INSUFFICIENT_STORE_CREDIT' then raise; end if;
    v_failed:=true;
  end;
  if not v_failed then raise exception 'Negative balance was allowed'; end if;
  if (select balance_iqd from private_finance.store_credit_balances
      where store_id=v_store and user_id=v_user)<>3000 then
    raise exception 'Failed debit changed balance'; end if;

  v_failed:=false;
  begin
    update private_finance.store_credit_movements set reason='تم تغيير السجل'
      where request_key='10101010-1010-4010-8010-101010101010';
  exception when others then
    if sqlerrm<>'IMMUTABLE_LEDGER' then raise; end if;
    v_failed:=true;
  end;
  if not v_failed then raise exception 'Ledger entry was mutable'; end if;

  if has_schema_privilege('authenticated','private_finance','USAGE') then
    raise exception 'End user can access internal finance schema';
  end if;
  raise notice 'PASS: credit and debit serialization, idempotency, immutable ledger, no direct access';
end$$;
