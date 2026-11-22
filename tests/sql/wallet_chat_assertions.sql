-- Isolated CI exercise: NO real customers, NO hosted Supabase traffic.
insert into auth.users(id,raw_app_meta_data) values
('00000000-0000-4000-8000-000000000001','{}'),
('00000000-0000-4000-8000-000000000002','{}'),
('00000000-0000-4000-8000-000000000003','{}'),
('00000000-0000-4000-8000-000000000004','{"shitreed_role":"admin"}');

insert into public.stores(id,owner_id,status) values
('10000000-0000-4000-8000-000000000001',
 '00000000-0000-4000-8000-000000000002','approved');

insert into shitreed_finance.accounts(id,owner_user_id,kind,currency) values
('30000000-0000-4000-8000-000000000001',
 '00000000-0000-4000-8000-000000000001','customer_wallet','IQD'),
('30000000-0000-4000-8000-000000000002',
 null,'platform_clearing','IQD');
begin;
insert into shitreed_finance.journals(id,currency,reference_key,description) values
('20000000-0000-4000-8000-000000000001',
 'IQD','fixture_wallet_credit_1','CI balanced journal');
insert into shitreed_finance.entries(journal_id,account_id,currency,delta) values
('20000000-0000-4000-8000-000000000001',
 '30000000-0000-4000-8000-000000000001','IQD',1000),
('20000000-0000-4000-8000-000000000001',
 '30000000-0000-4000-8000-000000000002','IQD',-1000);
commit;

set role authenticated;
select set_config('request.jwt.claim.sub',
 '00000000-0000-4000-8000-000000000001',false);
do $$
begin
 if (select cash_balance_iqd from public.shitreed_wallet_overview()) <> 1000
 then raise exception 'CUSTOMER_BALANCE_INCORRECT'; end if;
 if (select reward_points from public.shitreed_wallet_overview()) <> 0
 then raise exception 'POINT_BALANCE_INCORRECT'; end if;
end $$;
select set_config('fixture.thread_id',
 public.shitreed_chat_open('10000000-0000-4000-8000-000000000001')::text,
 false);
select public.shitreed_chat_send(
 current_setting('fixture.thread_id')::uuid,'رسالة اختبار من الزبون');

select set_config('request.jwt.claim.sub',
 '00000000-0000-4000-8000-000000000002',false);
do $$
begin
 if (select count(*) from public.shitreed_chat_threads) <> 1
 then raise exception 'MERCHANT_CANNOT_SEE_OWN_THREAD'; end if;
end $$;
select public.shitreed_chat_send(
 current_setting('fixture.thread_id')::uuid,'رسالة اختبار من التاجر');

select set_config('request.jwt.claim.sub',
 '00000000-0000-4000-8000-000000000003',false);
do $$
begin
 if exists (select 1 from public.shitreed_chat_threads)
 then raise exception 'OUTSIDER_SEES_THREAD'; end if;
 if exists (select 1 from public.shitreed_chat_messages)
 then raise exception 'OUTSIDER_SEES_MESSAGES'; end if;
 if (select cash_balance_iqd from public.shitreed_wallet_overview()) <> 0
 then raise exception 'OUTSIDER_SEES_MONEY'; end if;
 begin
   perform public.shitreed_chat_send(
     current_setting('fixture.thread_id')::uuid,'رسالة غير مخوّلة');
   raise exception 'UNAUTHORIZED_SEND_SUCCEEDED';
 exception when others then
   if sqlerrm='UNAUTHORIZED_SEND_SUCCEEDED' then raise; end if;
 end;
 begin
   perform public.shitreed_admin_finance_chat_summary();
   raise exception 'UNAUTHORIZED_ADMIN_SUCCEEDED';
 exception when others then
   if sqlerrm='UNAUTHORIZED_ADMIN_SUCCEEDED' then raise; end if;
 end;
 begin
   perform count(*) from shitreed_finance.entries;
   raise exception 'PRIVATE_LEDGER_EXPOSED';
 exception when insufficient_privilege then
   null;
 end;
end $$;

select set_config('request.jwt.claim.sub',
 '00000000-0000-4000-8000-000000000004',false);
do $$
declare v jsonb;
begin
 select public.shitreed_admin_finance_chat_summary() into v;
 if (v->>'chat_messages')::integer <> 2
 then raise exception 'ADMIN_METRICS_INCORRECT'; end if;
end $$;
reset role;
