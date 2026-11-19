-- Run after checkout_fixture, delivery migration, checkout assertions, setup
-- and ALANI_CONTENT_RETURNS_STAGE_ONLY_SQL.sql in disposable PostgreSQL only.

-- Store owner can create a draft.
select set_config('request.jwt.claim.sub',
  '99999999-9999-4999-8999-999999999999',false);
set role authenticated;
insert into public.alani_publications(
  id,store_id,kind,title,body,status
) values(
  'dddddddd-dddd-4ddd-8ddd-dddddddddddd',
  '25091ca2-c0da-416c-b634-81b188ee66be',
  'article','مقال تعريفي للاختبار','نص تجريبي لا يدعي علاج الأمراض','draft'
);
insert into public.alani_publications(
  id,store_id,kind,title,body,status
) values(
  'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee',
  '25091ca2-c0da-416c-b634-81b188ee66be',
  'post','مسودة تجريبية','نص المسودة','draft'
);
update public.alani_publications
  set status='published',published_at=now()
  where id='dddddddd-dddd-4ddd-8ddd-dddddddddddd';
do $$
begin
  if (select count(*) from public.alani_publications
      where store_id='25091ca2-c0da-416c-b634-81b188ee66be')<>2 then
    raise exception 'Store owner cannot see own drafts';
  end if;
end $$;
reset role;

-- Anonymous can see only published content.
set role anon;
do $$
begin
  if (select count(*) from public.alani_publications)<>1 then
    raise exception 'Anon sees drafts or cannot see approved published article';
  end if;
end $$;
reset role;

-- Another merchant cannot see or alter draft.
select set_config('request.jwt.claim.sub',
  '88888888-8888-4888-8888-888888888888',false);
set role authenticated;
do $$
begin
  if (select count(*) from public.alani_publications where status='draft')<>0 then
    raise exception 'Unrelated store owner sees private draft';
  end if;
end $$;
reset role;

-- Buyer can request return only for their order.
select set_config('request.jwt.claim.sub',
  '11111111-1111-4111-8111-111111111111',false);
set role authenticated;
insert into public.alani_return_requests(
  id,store_id,order_id,customer_id,reason,details
) values(
  'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
  '25091ca2-c0da-416c-b634-81b188ee66be',
  (select id from public.orders
   where store_id='25091ca2-c0da-416c-b634-81b188ee66be' limit 1),
  '11111111-1111-4111-8111-111111111111',
  'damaged','وصلت العبوة مكسورة أثناء التوصيل وأريد مراجعة'
);
do $$
begin
  if (select count(*) from public.alani_return_requests)<>1 then
    raise exception 'Buyer cannot view own return';
  end if;
end $$;
reset role;

-- Different merchant cannot read buyer's return.
select set_config('request.jwt.claim.sub',
  '88888888-8888-4888-8888-888888888888',false);
set role authenticated;
do $$
begin
  if (select count(*) from public.alani_return_requests)<>0 then
    raise exception 'Unrelated merchant can see another store returns';
  end if;
end $$;
reset role;

-- Owner can advance return only through allowed states with note.
select set_config('request.jwt.claim.sub',
  '99999999-9999-4999-8999-999999999999',false);
set role authenticated;
update public.alani_return_requests
  set status='reviewing',resolution_note='تم استلام صور تلف المنتج وسنراجع الحالة',
      updated_at=now()
  where id='cccccccc-cccc-4ccc-8ccc-cccccccccccc';
do $$
declare failed boolean:=false;
begin
  begin
    update public.alani_return_requests set status='resolved',
      resolution_note='إغلاق من دون قرار غير مسموح'
    where id='cccccccc-cccc-4ccc-8ccc-cccccccccccc';
  exception when others then
    if sqlerrm<>'INVALID_RETURN_TRANSITION' then raise; end if;
    failed:=true;
  end;
  if not failed then raise exception 'Invalid return transition was allowed'; end if;
end $$;
reset role;

select 'PASS: customer, owner, draft and return workflow RLS' as result;
