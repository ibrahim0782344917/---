-- Synthetic security and lifecycle assertions. Fail on any unexpected behavior.
-- Anonymous must have no privileged RPC access.
set role anon;
do $a$
begin
 begin
   perform public.alani_confirm_received('f0000000-0000-4000-8000-000000000002');
   raise exception 'ANON_DELIVERY_BYPASS';
 exception when insufficient_privilege then null;
 end;
end
$a$;
reset role;

select set_config('request.jwt.claim.sub','cccccccc-cccc-4ccc-8ccc-cccccccccccc',false);
set role authenticated;

-- A buyer cannot confirm another buyer's or another store's order.
do $x$
begin
 begin
  perform public.alani_confirm_received('f0000000-0000-4000-8000-000000000003');
  raise exception 'CROSS_BUYER_DELIVERY_BYPASS';
 exception when others then
  if sqlerrm<>'PERMISSION_DENIED' then raise; end if;
 end;
 begin
  perform public.alani_confirm_received('f0000000-0000-4000-8000-000000000004');
  raise exception 'OTHER_STORE_DELIVERY_BYPASS';
 exception when others then
  if sqlerrm<>'ORDER_NOT_FOUND' then raise; end if;
 end;
 begin
  perform public.alani_confirm_received('f0000000-0000-4000-8000-000000000001');
  raise exception 'DELIVERY_BEFORE_READY_BYPASS';
 exception when others then
  if sqlerrm<>'INVALID_DELIVERY_STATE' then raise; end if;
 end;
end
$x$;

select 1/(case when public.alani_confirm_received(
 'f0000000-0000-4000-8000-000000000002')='delivered'
 then 1 else 0 end) as buyer_delivery_confirmed;
select 1/(case when public.alani_confirm_received(
 'f0000000-0000-4000-8000-000000000002')='delivered'
 then 1 else 0 end) as delivery_retries_idempotent;

select set_config('test.return_id',public.alani_request_return(
 'f0000000-0000-4000-8000-000000000002','damaged',
 'المنتج وصل متضرراً وأحتاج مراجعة الحالة والأدلة')::text,false);
select 1/(case when public.alani_request_return(
 'f0000000-0000-4000-8000-000000000002','damaged',
 'المنتج وصل متضرراً وأحتاج مراجعة الحالة والأدلة')::text
 =current_setting('test.return_id') then 1 else 0 end)
 as active_return_idempotent;
do $x$
begin
 begin
  perform public.alani_request_return(
   'f0000000-0000-4000-8000-000000000003','wrong_item',
   'هذه محاولة على طلب زبون آخر ممنوعة');
  raise exception 'CROSS_BUYER_RETURN_BYPASS';
 exception when others then
  if sqlerrm<>'PERMISSION_DENIED' then raise; end if;
 end;
 begin
  perform public.alani_review_return(
   current_setting('test.return_id')::uuid,'approved','محاولة غير مصرح بها');
  raise exception 'BUYER_CANNOT_APPROVE_RETURN';
 exception when others then
  if sqlerrm<>'PERMISSION_DENIED' then raise; end if;
 end;
end
$x$;
select 1/(case when count(*)=1 then 1 else 0 end) as customer_own_return
 from public.alani_return_requests;
reset role;

select set_config('request.jwt.claim.sub','dddddddd-dddd-4ddd-8ddd-dddddddddddd',false);
set role authenticated;
select 1/(case when count(*)=0 then 1 else 0 end) as different_customer_return_hidden
 from public.alani_return_requests;
reset role;

select set_config('request.jwt.claim.sub','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',false);
set role authenticated;
select 1/(case when count(*)=1 then 1 else 0 end) as owner_can_review_own_shop
 from public.alani_return_requests;
do $x$
begin
 begin
  perform public.alani_review_return(
   current_setting('test.return_id')::uuid,'approved','لا يمكن القفز للموافقة');
  raise exception 'INVALID_REVIEW_STATE_BYPASS';
 exception when others then
  if sqlerrm<>'INVALID_RETURN_TRANSITION' then raise; end if;
 end;
end
$x$;
select public.alani_review_return(current_setting('test.return_id')::uuid,
 'reviewing','استلام الطلب وفحص التفاصيل');
select public.alani_review_return(current_setting('test.return_id')::uuid,
 'approved','تمت مراجعة وصف الضرر وموافقة المالك');
select public.alani_review_return(current_setting('test.return_id')::uuid,
 'resolved','تم إنهاء المراجعة دون ادعاء دفع تعويض');
reset role;

select 1/(case when
 (select count(*) from public.order_status_history where
   order_id='f0000000-0000-4000-8000-000000000002'
   and new_status='delivered')=1
 and (select total_iqd from public.orders where
   id='f0000000-0000-4000-8000-000000000001')=9500
 and (select count(*) from public.alani_return_status_history where
   return_id=current_setting('test.return_id')::uuid)=4
then 1 else 0 end) as audit_and_historic_amounts_intact;
select 'PASS: buyer confirms delivered; customer requests return; owner reviews; other users denied' as result;
