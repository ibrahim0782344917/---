-- Only run against disposable GitHub Actions database.
insert into public.alani_publications
  (store_id,kind,title,body,status,published_at)
values
('25091ca2-c0da-416c-b634-81b188ee66be','video',
 'فيديو تجريبي','محتوى منشور','published',now()),
('25091ca2-c0da-416c-b634-81b188ee66be','article',
 'مسودة خاصة','محتوى غير منشور','draft',null),
('22222222-2222-4222-8222-222222222222','article',
 'مسودة تاجر آخر','محتوى غير منشور','draft',null),
('44444444-4444-4444-8444-444444444444','video',
 'فيديو متجر معلق','غير متاح','published',now());

-- Anonymous visitors must see only the one published, approved-store post.
set role anon;
select 1 / (case when count(*)=1 then 1 else 0 end) as anonymous_only_one
  from public.alani_publications;
reset role;

-- Owner sees own published + drafts but no other merchant drafts,
-- and no pending-shop publication just because it was published.
select set_config('request.jwt.claim.sub',
  '11111111-1111-4111-8111-111111111111', false);
set role authenticated;
select 1 / (case when count(*)=3 then 1 else 0 end) as owner_visibility
  from public.alani_publications;

-- Authorised owner of an approved store can add and edit a draft.
insert into public.alani_publications (store_id,kind,title,body,status)
  values ('25091ca2-c0da-416c-b634-81b188ee66be',
          'article','خبر من المالك','تجربة','draft');
select 1 / (case when count(*)=4 then 1 else 0 end) as insert_visible_to_owner
  from public.alani_publications;

-- Updating to another merchant's store must be refused by RLS.
do $$
begin
  begin
    update public.alani_publications
      set store_id='22222222-2222-4222-8222-222222222222'
      where title='خبر من المالك';
    raise exception 'RLS_ALLOWED_CROSS_STORE_WRITE';
  exception
    when insufficient_privilege then null;
  end;
end;
$$;

-- Owner cannot add to an unapproved shop, even if they own it.
do $$
begin
  begin
    insert into public.alani_publications (store_id,kind,title,status)
      values ('44444444-4444-4444-8444-444444444444',
              'post','يجب رفضه','draft');
    raise exception 'RLS_ALLOWED_UNAPPROVED_SHOP_WRITE';
  exception
    when insufficient_privilege then null;
  end;
end;
$$;
reset role;

-- Different merchant must not see private Al-Ani drafts or mutate them.
select set_config('request.jwt.claim.sub',
  '33333333-3333-4333-8333-333333333333', false);
set role authenticated;
select 1 / (case when count(*)=2 then 1 else 0 end) as other_merchant_visibility
  from public.alani_publications;
select 1 / (case when count(*)=0 then 1 else 0 end) as no_unauthorized_drafts
  from public.alani_publications
  where store_id='25091ca2-c0da-416c-b634-81b188ee66be'
  and status='draft';
do $$
declare
  changed int;
begin
  update public.alani_publications
    set body='هجوم' where title='مسودة خاصة';
  get diagnostics changed=row_count;
  if changed<>0 then raise exception 'RLS_ALLOWED_CROSS_OWNER_UPDATE'; end if;
end;
$$;
reset role;

-- Anonymous publish attempt fails with permission denial.
set role anon;
do $$
begin
  begin
    insert into public.alani_publications (store_id,kind,title)
      values ('25091ca2-c0da-416c-b634-81b188ee66be',
              'post','زائر غير مخول');
    raise exception 'RLS_ALLOWED_ANON_INSERT';
  exception
    when insufficient_privilege then null;
  end;
end;
$$;
reset role;
select 'PASS: isolated publication RLS and content schema smoke tests' as result;
