-- Verifies that approved column grants enable account-deletion requests
-- and protect request history against another user.
select set_config('request.jwt.claim.sub',
  '11111111-1111-4111-8111-111111111111',false);
set role authenticated;
insert into public.customer_deletion_requests(reason)
  values('أرغب في حذف حسابي وبياناتي الشخصية');
do $$
begin
  if (select count(*) from public.customer_deletion_requests)<>1 then
    raise exception 'Owner cannot view their deletion request';
  end if;
end $$;
reset role;

select set_config('request.jwt.claim.sub',
  '77777777-7777-4777-8777-777777777777',false);
set role authenticated;
do $$
begin
  if (select count(*) from public.customer_deletion_requests)<>0 then
    raise exception 'Another customer can read deletion request';
  end if;
end $$;
reset role;

do $$
begin
  if has_table_privilege('anon','public.customer_deletion_requests','SELECT') then
    raise exception 'Anonymous can read deletion request table';
  end if;
  if has_table_privilege('authenticated','public.customer_deletion_requests','UPDATE') then
    raise exception 'Customers can edit existing deletion requests';
  end if;
  raise notice 'PASS: account deletion requests are insertable and private';
end $$;
