-- Test the private support workflow as three unrelated fake users.
select set_config('request.jwt.claim.sub',
  '11111111-1111-4111-8111-111111111111',false);
set role authenticated;
insert into public.alani_support_threads(
  id,store_id,buyer_id,merchant_id
) values(
  'abababab-abab-4aba-8aba-abababababab',
  '25091ca2-c0da-416c-b634-81b188ee66be',
  '11111111-1111-4111-8111-111111111111',
  '99999999-9999-4999-8999-999999999999'
);
insert into public.alani_support_messages(thread_id,sender_id,body)
values(
  'abababab-abab-4aba-8aba-abababababab',
  '11111111-1111-4111-8111-111111111111',
  'مرحبا، أريد الاستفسار عن طلبي'
);
reset role;

select set_config('request.jwt.claim.sub',
  '99999999-9999-4999-8999-999999999999',false);
set role authenticated;
do $$
begin
  if (select count(*) from public.alani_support_threads)<>1 or
     (select count(*) from public.alani_support_messages)<>1 then
    raise exception 'Store owner cannot read legitimate customer support';
  end if;
end $$;
insert into public.alani_support_messages(thread_id,sender_id,body)
values(
  'abababab-abab-4aba-8aba-abababababab',
  '99999999-9999-4999-8999-999999999999',
  'أهلاً بك، نحن نراجع استفسارك'
);
reset role;

select set_config('request.jwt.claim.sub',
  '77777777-7777-4777-8777-777777777777',false);
set role authenticated;
do $$
declare refused boolean:=false;
begin
  if (select count(*) from public.alani_support_threads)<>0 or
     (select count(*) from public.alani_support_messages)<>0 then
    raise exception 'Third-party can read confidential support';
  end if;
  begin
    insert into public.alani_support_messages(thread_id,sender_id,body)
    values(
      'abababab-abab-4aba-8aba-abababababab',
      '77777777-7777-4777-8777-777777777777',
      'رسالة غير مصرح بها'
    );
  exception when others then
    if sqlstate <> '42501' then raise; end if;
    refused:=true;
  end;
  if not refused then raise exception 'Third-party message was accepted'; end if;
end $$;
reset role;
select 'PASS: support participants only; outsider cannot see or write' as result;
