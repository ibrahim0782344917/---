-- Isolated customer+merchant deletion requests: no auth user is erased.
set role authenticated;
select set_config('request.jwt.claim.sub',
 '00000000-0000-4000-8000-000000000001', false);
select set_config('fixture.customer_deletion_id',
 public.shitreed_customer_request_deletion('حذف حساب تجريبي')::text, false);
do $$
declare v_id uuid;
begin
  v_id := public.shitreed_customer_request_deletion('طلب مكرر');
  if v_id <> current_setting('fixture.customer_deletion_id')::uuid
    then raise exception 'NON_IDEMPOTENT_CUSTOMER_DELETION_REQUEST'; end if;
  if (select count(*) from public.customer_deletion_requests) <> 1
    then raise exception 'CUSTOMER_DUPLICATE_REQUEST'; end if;
  if (select count(*) from public.customer_deletion_requests
       where user_id='00000000-0000-4000-8000-000000000001') <> 1
    then raise exception 'WRONG_DELETION_OWNER'; end if;
  begin
    delete from public.customer_deletion_requests;
    raise exception 'CLIENT_COULD_DELETE_REQUEST';
  exception when insufficient_privilege then null;
  end;
  begin
    insert into public.customer_deletion_requests
      (user_id,reason)
    values('00000000-0000-4000-8000-000000000003','forged');
    raise exception 'IMPERSONATION_WRITABLE';
  exception when insufficient_privilege then null;
  end;
end; $$;

-- Another signed-in customer must not see the first customer's request.
select set_config('request.jwt.claim.sub',
 '00000000-0000-4000-8000-000000000003', false);
do $$
begin
 if exists(select 1 from public.customer_deletion_requests)
  then raise exception 'CUSTOMER_DELETION_LEAK'; end if;
 if (select count(*) from public.shitreed_merchant_deletion_requests) <> 0
  then raise exception 'MERCHANT_DELETION_LEAK'; end if;
end $$;

-- Existing merchant RPC must be idempotent and user-scoped.
select set_config('request.jwt.claim.sub',
 '00000000-0000-4000-8000-000000000002', false);
select set_config('fixture.merchant_deletion_id',
 public.shitreed_merchant_request_deletion('أريد إغلاق حساب المتجر')::text, false);
do $$
begin
 if public.shitreed_merchant_request_deletion('طلب متكرر')
   <> current_setting('fixture.merchant_deletion_id')::uuid
   then raise exception 'NON_IDEMPOTENT_MERCHANT_REQUEST'; end if;
 if (select count(*) from public.shitreed_merchant_deletion_requests) <> 1
   then raise exception 'MERCHANT_DUPLICATE_REQUEST'; end if;
end $$;
select set_config('request.jwt.claim.sub',
 '00000000-0000-4000-8000-000000000001', false);
do $$
begin
 if exists(select 1 from public.shitreed_merchant_deletion_requests)
  then raise exception 'CROSS_ACCOUNT_MERCHANT_REQUEST_VISIBLE'; end if;
end $$;
reset role;

-- A pending request must NOT implicitly erase users or financial records.
-- These disposable test users are intentionally referenced by merchant and
-- wallet records. A trusted erasure workflow must resolve dependencies first.
do $
begin
  begin
    delete from auth.users
    where id='00000000-0000-4000-8000-000000000001';
    raise exception 'CUSTOMER_USER_WAS_ERASED_WITH_LEDGER';
  exception when foreign_key_violation then null;
  end;
  begin
    delete from auth.users
    where id='00000000-0000-4000-8000-000000000002';
    raise exception 'MERCHANT_USER_WAS_ERASED_WITH_STORE';
  exception when foreign_key_violation then null;
  end;
end $;

do $
begin
 if (select count(*) from auth.users) <> 4
   then raise exception 'AN_AUTH_USER_WAS_DELETED'; end if;
 if (select count(*) from public.customer_deletion_requests) <> 1
   then raise exception 'CUSTOMER_REQUEST_NOT_SAVED'; end if;
 if (select count(*) from public.shitreed_merchant_deletion_requests) <> 1
   then raise exception 'MERCHANT_REQUEST_NOT_SAVED'; end if;
end $$;
