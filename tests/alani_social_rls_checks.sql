-- All checks operate exclusively on synthetic records in a disposable PG container.
insert into public.alani_publications
(store_id,kind,title,body,status,published_at) values
('25091ca2-c0da-416c-b634-81b188ee66be',
 'post','منشور تجريبي للعامة','نص اختبار','published',now());
select set_config('test.post_id',
 (select id from public.alani_publications where title='منشور تجريبي للعامة')::text,false);

set role anon;
select 1/(case when count(*)=1 then 1 else 0 end) as public_post_visible from public.alani_publications;
select 1/(case when public.alani_social_stats(current_setting('test.post_id')::uuid)->>'likes'='0' then 1 else 0 end)
 as public_counter_anonymous;
do $x$ begin
 begin
  insert into public.alani_publication_comments(publication_id,user_id,body)
  values(current_setting('test.post_id')::uuid,'cccccccc-cccc-4ccc-8ccc-cccccccccccc','زائر');
  raise exception 'ANON_COMMENT_BYPASS';
 exception when insufficient_privilege then null; end;
end $x$;
reset role;

select set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',false);
set role authenticated;
select 1/(case when public.alani_content_manage_staff(
 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','writer',true) then 1 else 0 end) as owner_can_assign_writer;
select 1/(case when public.alani_content_manage_staff(
 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb','moderator',true) then 1 else 0 end) as owner_can_assign_moderator;
reset role;

select set_config('request.jwt.claim.sub','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',false);
set role authenticated;
insert into public.alani_publications(store_id,kind,title,body,status)
values('25091ca2-c0da-416c-b634-81b188ee66be',
 'article','مقال الكاتب الاختباري','المقال قيد المراجعة','draft');
select 1/(case when count(*)=1 then 1 else 0 end) as author_sees_draft
 from public.alani_publications where title='مقال الكاتب الاختباري';
select set_config('test.draft_id',(select id from public.alani_publications
 where title='مقال الكاتب الاختباري')::text,false);
do $x$ begin
 begin
  update public.alani_publications set status='published',published_at=now()
    where id=current_setting('test.draft_id')::uuid;
  raise exception 'WRITER_PUBLISH_BYPASS';
 exception when check_violation then null;
 when insufficient_privilege then null; end;
end $x$;
do $x$ begin
 begin
  perform public.alani_content_manage_staff(
   'dddddddd-dddd-4ddd-8ddd-dddddddddddd','moderator',true);
  raise exception 'WRITER_ASSIGN_STAFF_BYPASS';
 exception when others then
   if sqlerrm<>'PERMISSION_DENIED' then raise; end if; end;
end $x$;
reset role;

set role anon;
select 1/(case when count(*)=1 then 1 else 0 end) as anon_cannot_view_draft
 from public.alani_publications;
reset role;
select set_config('request.jwt.claim.sub','bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',false);
set role authenticated;
select 1/(case when public.alani_moderate_publication(current_setting('test.draft_id')::uuid,'publish')='published' then 1 else 0 end)
 as moderator_can_approve_writer_draft;
reset role;

select set_config('request.jwt.claim.sub','cccccccc-cccc-4ccc-8ccc-cccccccccccc',false);
set role authenticated;
insert into public.alani_publication_reactions(publication_id,action)
 values(current_setting('test.post_id')::uuid,'like'),(current_setting('test.post_id')::uuid,'save');
select 1/(case when count(*)=2 then 1 else 0 end) as user_owns_reactions
 from public.alani_publication_reactions;
do $x$ begin
 begin
  insert into public.alani_publication_reactions(publication_id,user_id,action)
   values(current_setting('test.post_id')::uuid,
   'dddddddd-dddd-4ddd-8ddd-dddddddddddd','save');
  raise exception 'IMPERSONATED_REACTION_BYPASS';
 exception when check_violation then null;
 when insufficient_privilege then null; end;
end $x$;
insert into public.alani_publication_comments(publication_id,body)
 values(current_setting('test.post_id')::uuid,'تعليق ينتظر موافقة الإشراف');
select set_config('test.comment_id',(select id from public.alani_publication_comments
 where user_id='cccccccc-cccc-4ccc-8ccc-cccccccccccc' limit 1)::text,false);
select 1/(case when count(*)=1 then 1 else 0 end) as author_sees_pending_comment
 from public.alani_publication_comments;
insert into public.alani_publication_reports(publication_id,reason,details)
values(current_setting('test.post_id')::uuid,'misleading','محتوى يحتاج مراجعة');
reset role;

set role anon;
select 1/(case when count(*)=0 then 1 else 0 end) as pending_comment_hidden_from_guests
 from public.alani_publication_comments;
select 1/(case when public.alani_social_stats(current_setting('test.post_id')::uuid)->>'likes'='1'
 and public.alani_social_stats(current_setting('test.post_id')::uuid)->>'comments'='0'
 then 1 else 0 end) as aggregate_does_not_count_unapproved;
reset role;

select set_config('request.jwt.claim.sub','bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',false);
set role authenticated;
select 1/(case when public.alani_moderate_comment(
 current_setting('test.comment_id')::uuid,'approved')='approved'
 then 1 else 0 end) as moderator_approves_comment;
select 1/(case when count(*)=1 then 1 else 0 end) as moderator_sees_reports
 from public.alani_publication_reports;
reset role;

set role anon;
select 1/(case when count(*)=1 then 1 else 0 end) as approved_comment_public
 from public.alani_publication_comments;
select 1/(case when public.alani_social_stats(current_setting('test.post_id')::uuid)->>'comments'='1'
 then 1 else 0 end) as public_count_approved_only;
reset role;

select set_config('request.jwt.claim.sub','dddddddd-dddd-4ddd-8ddd-dddddddddddd',false);
set role authenticated;
select 1/(case when count(*)=0 then 1 else 0 end) as another_customer_cannot_see_reactions
 from public.alani_publication_reactions;
select 1/(case when count(*)=0 then 1 else 0 end) as another_customer_cannot_see_reports
 from public.alani_publication_reports;
do $x$ begin
 begin
  perform public.alani_moderate_comment(current_setting('test.comment_id')::uuid,'hidden');
  raise exception 'CUSTOMER_MODERATE_BYPASS';
 exception when others then
   if sqlerrm<>'PERMISSION_DENIED' then raise; end if;
 end;
end $x$;
reset role;
select 'PASS: user/staff/owner, published feed, comments moderation, likes, saves and reports' as result;
