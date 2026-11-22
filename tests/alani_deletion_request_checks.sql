set role anon;
do $x$
begin
 begin
  perform public.shitreed_customer_request_deletion('');
  raise exception 'ANON_DELETE_REQUEST_BYPASS';
 exception when insufficient_privilege then null;
 end;
end
$x$;
reset role;
select set_config('request.jwt.claim.sub',
 'cccccccc-cccc-4ccc-8ccc-cccccccccccc',false);
set role authenticated;
select set_config('test.customer_delete',
 public.shitreed_customer_request_deletion('أرغب بطلب حذف حسابي')::text,false);
select 1/(case when public.shitreed_customer_request_deletion('')
  =current_setting('test.customer_delete')::uuid then 1 else 0 end)
 as deletion_request_idempotent;
select 1/(case when count(*)=1 then 1 else 0 end) as customer_own_request
 from public.customer_deletion_requests;
do $deny$
begin
 begin
   insert into public.customer_deletion_requests(user_id,reason)
     values ('dddddddd-dddd-4ddd-8ddd-dddddddddddd','impersonation');
   raise exception 'CUSTOMER_DIRECT_WRITE_BYPASS';
 exception when insufficient_privilege then null;
 end;
end
$deny$;
reset role;
select set_config('request.jwt.claim.sub',
 'dddddddd-dddd-4ddd-8ddd-dddddddddddd',false);
set role authenticated;
select 1/(case when count(*)=0 then 1 else 0 end) as other_customers_not_visible
 from public.customer_deletion_requests;
reset role;
select 1/(case when count(*)=1 then 1 else 0 end) as request_only_no_delete
 from public.customer_deletion_requests;
select 'PASS: customer deletion requests isolated, idempotent, not actual user erasure' as result;

-- Anonymous users cannot retrieve readiness or private history.
set role anon;
do $a$
begin
  begin
    perform public.shitreed_customer_deletion_preflight();
    raise exception 'ANON_READINESS_BYPASS';
  exception when insufficient_privilege then null;
  end;
end $a$;
reset role;

select set_config('request.jwt.claim.sub',
 'cccccccc-cccc-4ccc-8ccc-cccccccccccc',false);
set role authenticated;
select 1/(case when
  (public.shitreed_customer_deletion_preflight()->>'open_orders')::bigint=1
  and (public.shitreed_customer_deletion_preflight()->>'historical_orders')::bigint=2
  and (public.shitreed_customer_deletion_preflight()->>'owned_stores')::bigint=0
  and public.shitreed_customer_deletion_preflight()->>'can_delete_immediately'='false'
  then 1 else 0 end) as customer_only_gets_own_preflight;

select set_config('request.jwt.claim.sub',
 'dddddddd-dddd-4ddd-8ddd-dddddddddddd',false);
select 1/(case when
  (public.shitreed_customer_deletion_preflight()->>'open_orders')::bigint=1
  and (public.shitreed_customer_deletion_preflight()->>'historical_orders')::bigint=1
  and (public.shitreed_customer_deletion_preflight()->>'owned_stores')::bigint=1
  then 1 else 0 end) as merchant_owner_has_extra_blocker;
reset role;
select 'PASS: read-only preflight remains private and NEVER executes deletion' as result;
