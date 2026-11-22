-- This is run only on an ephemeral local PostgreSQL container.

insert into public.alani_publications(
  store_id,kind,title,body,video_url,status,published_at
)
values
('25091ca2-c0da-416c-b634-81b188ee66be','video',
 'اختبار فيديو منشور','فيديو موثوق','https://example.org/clip.mp4',
 'published',now()),
('25091ca2-c0da-416c-b634-81b188ee66be','recipe',
 'وصفة قيد التحضير','معلومات أولية',null,'draft',null);

set role anon;
select 1 / (case when count(*)=1 then 1 else 0 end) as visitor_can_see_only_published
  from public.alani_publications;
reset role;

select set_config('request.jwt.claim.sub',
  '11111111-1111-4111-8111-111111111111',false);
set role authenticated;
select 1 / (case when count(*)=2 then 1 else 0 end) as owner_sees_own_drafts
  from public.alani_publications;
insert into public.alani_publications(store_id,kind,title,body,status)
values ('25091ca2-c0da-416c-b634-81b188ee66be','article',
        'مقال من المالك','وصف','draft');
update public.alani_publications set title='مقال محدث'
where title='مقال من المالك';
select 1 / (case when count(*)=1 then 1 else 0 end) as owner_can_edit
  from public.alani_publications where title='مقال محدث';
reset role;

select set_config('request.jwt.claim.sub',
  '33333333-3333-4333-8333-333333333333',false);
set role authenticated;
select 1 / (case when count(*)=1 then 1 else 0 end) as merchant_only_sees_published
  from public.alani_publications;
select 1 / (case when count(*)=0 then 1 else 0 end) as merchant_cannot_see_drafts
  from public.alani_publications where status='draft';
do $$
declare changed integer;
begin
  update public.alani_publications set title='مخترق'
  where title='مقال محدث';
  get diagnostics changed=row_count;
  if changed<>0 then raise exception 'FAILED_SECURITY_CROSS_OWNER_WRITE'; end if;
end
$$;
do $$
begin
  begin
    insert into public.alani_publications(store_id,kind,title)
    values ('25091ca2-c0da-416c-b634-81b188ee66be',
            'post','محتوى غير مخول');
    raise exception 'FAILED_SECURITY_CROSS_OWNER_INSERT';
  exception when insufficient_privilege then null;
  end;
end
$$;
reset role;

set role anon;
do $$
begin
  begin
    insert into public.alani_publications(store_id,kind,title)
    values ('25091ca2-c0da-416c-b634-81b188ee66be',
            'post','زائر غير مخول');
    raise exception 'FAILED_SECURITY_ANON_INSERT';
  exception when insufficient_privilege then null;
  end;
end
$$;
reset role;

do $$
begin
  begin
    insert into public.alani_publications(store_id,kind,title)
    values ('22222222-2222-4222-8222-222222222222',
            'post','متجر آخر');
    raise exception 'FAILED_SECURITY_OTHER_STORE_ALLOWED';
  exception when check_violation then null;
  end;
end
$$;

do $$
begin
  begin
    insert into public.alani_publications(store_id,kind,title,status,published_at)
    values ('25091ca2-c0da-416c-b634-81b188ee66be',
            'video','فيديو بدون رابط','published',now());
    raise exception 'FAILED_VALIDATION_MISSING_VIDEO_LINK';
  exception when check_violation then null;
  end;
end
$$;

select 'PASS: published only, owner CRUD, cross-store and visitor denied' as result;
