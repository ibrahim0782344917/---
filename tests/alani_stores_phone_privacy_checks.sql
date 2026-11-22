-- All executed on disposable test-only PostgreSQL.
select 1/(case when not has_column_privilege('anon','public.stores','phone','SELECT')
  and not has_column_privilege('authenticated','public.stores','phone','SELECT')
  then 1 else 0 end) as no_private_phone_column_grants;
set role anon;
select 1/(case when count(*)=2 then 1 else 0 end) as public_store_metadata_read
 from public.stores;
do $deny$
begin
 begin
  perform phone from public.stores limit 1;
  raise exception 'ANON_CAN_READ_PHONE';
 exception when insufficient_privilege then null;
 end;
 begin
  perform * from public.shitreed_my_store_contacts();
  raise exception 'ANON_OWNER_CONTACT_RPC_BYPASS';
 exception when insufficient_privilege then null;
 end;
end
$deny$;
reset role;

select set_config('request.jwt.claim.sub',
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',false);
set role authenticated;
do $deny$
begin
 begin
  perform phone from public.stores limit 1;
  raise exception 'AUTH_USER_DIRECT_PHONE_LEAK';
 exception when insufficient_privilege then null;
 end;
end
$deny$;
select 1/(case when count(*)=1 then 1 else 0 end) as owner_can_read_only_owned_phone
 from public.shitreed_my_store_contacts()
 where store_id='25091ca2-c0da-416c-b634-81b188ee66be'
   and phone='07700000000';
reset role;

select set_config('request.jwt.claim.sub',
  'cccccccc-cccc-4ccc-8ccc-cccccccccccc',false);
set role authenticated;
select 1/(case when count(*)=0 then 1 else 0 end) as customer_cannot_read_owner_phone_rpc
 from public.shitreed_my_store_contacts();
reset role;
select 'PASS: public phone blocked; verified owner contact RPC only' as result;
