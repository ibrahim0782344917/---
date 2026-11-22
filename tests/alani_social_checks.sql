set role anon;
select 1/(case when
(public.alani_social_summary('11111111-1111-4111-8111-111111111111')->>'likes')::int=0
then 1 else 0 end) as public_counts;
do $x$ begin
 begin
 perform public.alani_toggle_reaction('11111111-1111-4111-8111-111111111111','like');
 raise exception 'ANON_REACTED';
 exception when insufficient_privilege then null;
 end;
end $x$;
reset role;
select set_config('request.jwt.claim.sub','bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',false);
set role authenticated;
select 1/(case when public.alani_toggle_reaction(
'11111111-1111-4111-8111-111111111111','like') then 1 else 0 end) as like;
select 1/(case when not public.alani_toggle_reaction(
'11111111-1111-4111-8111-111111111111','like') then 1 else 0 end) as unlike;
select public.alani_rate_publication('11111111-1111-4111-8111-111111111111',5);
select set_config('test.comment_id',public.alani_submit_comment(
'11111111-1111-4111-8111-111111111111','تعليق للمراجعة')::text,false);
reset role;
set role anon;
select 1/(case when count(*)=0 then 1 else 0 end) as unapproved_hidden
from public.alani_post_comments;
reset role;
select set_config('request.jwt.claim.sub','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',false);
set role authenticated;
select public.alani_moderate_comment(current_setting('test.comment_id')::uuid,'approved');
reset role;
set role anon;
select 1/(case when count(*)=1 then 1 else 0 end) as approved_visible
from public.alani_post_comments;
reset role;
select set_config('request.jwt.claim.sub','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',false);
set role authenticated;
select public.alani_set_content_staff('cccccccc-cccc-4ccc-8ccc-cccccccccccc','writer',true);
reset role;
select set_config('request.jwt.claim.sub','cccccccc-cccc-4ccc-8ccc-cccccccccccc',false);
set role authenticated;
select 1/(case when public.alani_save_writer_draft(null,'article','عنوان مفصل','محتوى')
is not null then 1 else 0 end) as writer_draft;
reset role;
select 'PASS social reactions, comments, moderation and author roles' as result;
