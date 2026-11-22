-- Database authorization integration test. Each assertion fails the job on error.
select 1 / (case when count(*)=1 then 1 else 0 end) as bucket_config_ok
from storage.buckets where id='alani-reels' and public is true
and file_size_limit=41943040 and allowed_mime_types=array['video/mp4'];

select set_config('request.jwt.claim.sub',
  '11111111-1111-4111-8111-111111111111',false);
set role authenticated;
insert into storage.objects(bucket_id,name) values (
'alani-reels',
'25091ca2-c0da-416c-b634-81b188ee66be/11111111-1111-4111-8111-111111111111/random.mp4');
select 1 / (case when count(*)=1 then 1 else 0 end) as owner_can_list
from storage.objects;
do $owner$
begin
  begin
    insert into storage.objects(bucket_id,name) values
    ('alani-reels','25091ca2-c0da-416c-b634-81b188ee66be/11111111-1111-4111-8111-111111111111/evil.exe');
    raise exception 'FILE_EXTENSION_BYPASS';
  exception when insufficient_privilege then null;
  end;
end
$owner$;
reset role;

select set_config('request.jwt.claim.sub',
  '22222222-2222-4222-8222-222222222222',false);
set role authenticated;
select 1 / (case when count(*)=0 then 1 else 0 end) as nonowner_cannot_list
from storage.objects;
do $attacker$
begin
  begin
    insert into storage.objects(bucket_id,name) values
    ('alani-reels','25091ca2-c0da-416c-b634-81b188ee66be/22222222-2222-4222-8222-222222222222/evil.mp4');
    raise exception 'CROSS_STORE_OWNER_UPLOAD_BYPASS';
  exception when insufficient_privilege then null;
  end;
end
$attacker$;
delete from storage.objects where bucket_id='alani-reels';
reset role;

set role anon;
do $guest$
begin
  begin
    insert into storage.objects(bucket_id,name) values
    ('alani-reels','25091ca2-c0da-416c-b634-81b188ee66be/11111111-1111-4111-8111-111111111111/anon.mp4');
    raise exception 'ANONYMOUS_UPLOAD_BYPASS';
  exception when insufficient_privilege then null;
  end;
end
$guest$;
reset role;

select set_config('request.jwt.claim.sub',
  '11111111-1111-4111-8111-111111111111',false);
set role authenticated;
delete from storage.objects where bucket_id='alani-reels';
reset role;

select 1 / (case when count(*)=0 then 1 else 0 end) as owner_can_remove
from storage.objects;
select 'PASS: owner upload/delete, anon and cross-owner denied' as result;
