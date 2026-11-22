-- Al-Ani social features: additive; does not touch orders, finance or storage.
begin;
alter table public.alani_publications
 add column if not exists created_by uuid references auth.users(id) on delete set null;
create table if not exists public.alani_content_staff(
 store_id uuid not null references public.stores(id) on delete cascade,
 user_id uuid not null references auth.users(id) on delete cascade,
 role text not null check(role in ('writer','editor','moderator')),
 granted_by uuid references auth.users(id) on delete set null,
 primary key(store_id,user_id)
);
create table if not exists public.alani_post_reactions(
 publication_id uuid not null references public.alani_publications(id) on delete cascade,
 user_id uuid not null references auth.users(id) on delete cascade,
 kind text not null check(kind in ('like','save')),
 created_at timestamptz not null default now(),
 primary key(publication_id,user_id,kind)
);
create table if not exists public.alani_post_ratings(
 publication_id uuid not null references public.alani_publications(id) on delete cascade,
 user_id uuid not null references auth.users(id) on delete cascade,
 stars smallint not null check(stars between 1 and 5),
 updated_at timestamptz not null default now(),
 primary key(publication_id,user_id)
);
create table if not exists public.alani_post_comments(
 id uuid primary key default gen_random_uuid(),
 publication_id uuid not null references public.alani_publications(id) on delete cascade,
 user_id uuid not null references auth.users(id) on delete cascade,
 body text not null check(char_length(body) between 3 and 500),
 status text not null default 'pending' check(status in ('pending','approved','rejected','hidden','deleted')),
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);
create index if not exists alani_social_comment_recent
 on public.alani_post_comments(publication_id,status,created_at desc);
create table if not exists public.alani_post_reports(
 id uuid primary key default gen_random_uuid(),
 publication_id uuid not null references public.alani_publications(id) on delete cascade,
 comment_id uuid references public.alani_post_comments(id) on delete set null,
 reporter_id uuid not null references auth.users(id) on delete cascade,
 reason text not null check(reason in ('spam','abuse','misleading','unsafe','other')),
 status text not null default 'open' check(status in ('open','reviewed','dismissed')),
 created_at timestamptz not null default now()
);
create table if not exists public.alani_moderation_audit(
 id uuid primary key default gen_random_uuid(),
 publication_id uuid references public.alani_publications(id) on delete set null,
 actor_id uuid references auth.users(id) on delete set null,
 action text not null, target_id uuid not null,
 created_at timestamptz not null default now()
);
alter table public.alani_content_staff enable row level security;
alter table public.alani_post_reactions enable row level security;
alter table public.alani_post_ratings enable row level security;
alter table public.alani_post_comments enable row level security;
alter table public.alani_post_reports enable row level security;
alter table public.alani_moderation_audit enable row level security;
revoke all on public.alani_content_staff,public.alani_post_reactions,
 public.alani_post_ratings,public.alani_post_comments,public.alani_post_reports,
 public.alani_moderation_audit from public,anon,authenticated;

create or replace function public.alani_can_moderate(p_publication_id uuid)
returns boolean language sql stable security definer set search_path=''
as $m$
select (select auth.uid()) is not null and exists(
 select 1 from public.alani_publications p
 join public.stores s on s.id=p.store_id
 where p.id=p_publication_id and p.store_id='25091ca2-c0da-416c-b634-81b188ee66be'::uuid
 and (s.owner_id=(select auth.uid()) or public.shitreed_is_admin()
 or exists(select 1 from public.alani_content_staff sf
 where sf.store_id=s.id and sf.user_id=(select auth.uid())
 and sf.role in ('editor','moderator')))
);
$m$;
revoke all on function public.alani_can_moderate(uuid) from public,anon,authenticated;
grant execute on function public.alani_can_moderate(uuid) to anon,authenticated;

create policy alani_staff_read on public.alani_content_staff for select to authenticated
using (user_id=(select auth.uid()) or
 exists(select 1 from public.stores s where s.id=store_id and s.owner_id=(select auth.uid()))
 or public.shitreed_is_admin());
grant select on public.alani_content_staff to authenticated;
create policy alani_writer_draft_read on public.alani_publications for select to authenticated
using(status='draft' and (created_by=(select auth.uid()) or
 exists(select 1 from public.alani_content_staff sf where sf.store_id=store_id
 and sf.user_id=(select auth.uid()) and sf.role='editor')));
create policy alani_reactions_own_read on public.alani_post_reactions
 for select to authenticated using(user_id=(select auth.uid()));
create policy alani_ratings_own_read on public.alani_post_ratings
 for select to authenticated using(user_id=(select auth.uid()));
grant select on public.alani_post_reactions,public.alani_post_ratings to authenticated;
create policy alani_comments_read on public.alani_post_comments
 for select to anon,authenticated using(
 (status='approved' and exists(select 1 from public.alani_publications p
 join public.stores s on s.id=p.store_id where p.id=publication_id
 and p.status='published' and s.status='approved'))
 or user_id=(select auth.uid()) or public.alani_can_moderate(publication_id));
grant select on public.alani_post_comments to anon,authenticated;
create policy alani_reports_moderator on public.alani_post_reports
 for select to authenticated using(reporter_id=(select auth.uid())
 or public.alani_can_moderate(publication_id));
grant select on public.alani_post_reports to authenticated;
create policy alani_audit_moderator on public.alani_moderation_audit
 for select to authenticated using(public.alani_can_moderate(publication_id));
grant select on public.alani_moderation_audit to authenticated;

create or replace function public.alani_social_assert_published(p_id uuid)
returns void language plpgsql stable security definer set search_path=''
as $a$
begin
 if not exists(select 1 from public.alani_publications p join public.stores s
 on s.id=p.store_id where p.id=p_id and p.status='published'
 and s.status='approved' and p.store_id='25091ca2-c0da-416c-b634-81b188ee66be'::uuid)
 then raise exception 'PUBLICATION_UNAVAILABLE'; end if;
end $a$;
revoke all on function public.alani_social_assert_published(uuid)
 from public,anon,authenticated;

create or replace function public.alani_toggle_reaction(p_id uuid,p_kind text)
returns boolean language plpgsql security definer set search_path=''
as $t$
declare v_user uuid:=(select auth.uid());v_removed uuid;
begin
 if v_user is null then raise exception 'LOGIN_REQUIRED'; end if;
 if p_kind not in ('like','save') or p_kind is null then raise exception 'BAD_REACTION'; end if;
 perform public.alani_social_assert_published(p_id);
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
 'alani:'||v_user::text||p_id::text||p_kind,201));
 delete from public.alani_post_reactions where publication_id=p_id
 and user_id=v_user and kind=p_kind returning user_id into v_removed;
 if v_removed is not null then return false; end if;
 insert into public.alani_post_reactions(publication_id,user_id,kind)
 values(p_id,v_user,p_kind);
 return true;
end $t$;

create or replace function public.alani_rate_publication(p_id uuid,p_stars integer)
returns void language plpgsql security definer set search_path=''
as $r$
declare v_user uuid:=(select auth.uid());
begin
 if v_user is null then raise exception 'LOGIN_REQUIRED'; end if;
 if p_stars is null or p_stars not between 1 and 5 then raise exception 'BAD_STARS'; end if;
 perform public.alani_social_assert_published(p_id);
 insert into public.alani_post_ratings(publication_id,user_id,stars)
 values(p_id,v_user,p_stars)
 on conflict(publication_id,user_id) do update
 set stars=excluded.stars,updated_at=now();
end $r$;

create or replace function public.alani_social_summary(p_id uuid)
returns jsonb language plpgsql stable security definer set search_path=''
as $s$
declare v_user uuid:=(select auth.uid()); v_likes bigint;v_comments bigint;
 v_liked boolean;v_saved boolean;v_rating numeric;v_rating_count bigint;
begin
 perform public.alani_social_assert_published(p_id);
 select count(*) filter(where kind='like'),
 coalesce(bool_or(kind='like' and user_id=v_user),false),
 coalesce(bool_or(kind='save' and user_id=v_user),false)
 into v_likes,v_liked,v_saved from public.alani_post_reactions where publication_id=p_id;
 select count(*) into v_comments from public.alani_post_comments
 where publication_id=p_id and status='approved';
 select round(avg(stars)::numeric,1),count(*) into v_rating,v_rating_count
 from public.alani_post_ratings where publication_id=p_id;
 return pg_catalog.jsonb_build_object('likes',v_likes,'liked',v_liked,'saved',v_saved,
 'comments',v_comments,'rating',v_rating,'rating_count',v_rating_count);
end $s$;

create or replace function public.alani_submit_comment(p_id uuid,p_body text)
returns uuid language plpgsql security definer set search_path=''
as $c$
declare v_user uuid:=(select auth.uid());v_id uuid;
begin
 if v_user is null then raise exception 'LOGIN_REQUIRED'; end if;
 if p_body is null or char_length(pg_catalog.btrim(p_body)) not between 3 and 500
 then raise exception 'BAD_COMMENT'; end if;
 perform public.alani_social_assert_published(p_id);
 perform pg_catalog.pg_advisory_xact_lock(
 pg_catalog.hashtextextended('comment:'||v_user::text,202));
 if (select count(*) from public.alani_post_comments
 where user_id=v_user and created_at>now()-interval '1 minute')>=5
 then raise exception 'RATE_LIMIT'; end if;
 insert into public.alani_post_comments(publication_id,user_id,body)
 values(p_id,v_user,pg_catalog.btrim(p_body)) returning id into v_id;
 return v_id;
end $c$;

create or replace function public.alani_edit_own_comment(
 p_id uuid,p_body text,p_delete boolean default false
) returns void language plpgsql security definer set search_path=''
as $e$
declare v_user uuid:=(select auth.uid());v_old public.alani_post_comments%rowtype;
begin
 if v_user is null then raise exception 'LOGIN_REQUIRED'; end if;
 select * into v_old from public.alani_post_comments where id=p_id for update;
 if not found or v_old.user_id<>v_user or v_old.status='deleted'
 then raise exception 'NOT_YOUR_COMMENT'; end if;
 if p_delete then
 update public.alani_post_comments set status='deleted',body='[حُذف التعليق]',
 updated_at=now() where id=p_id;
 else
 if p_body is null or char_length(pg_catalog.btrim(p_body)) not between 3 and 500
 then raise exception 'BAD_COMMENT'; end if;
 update public.alani_post_comments set body=pg_catalog.btrim(p_body),
 status='pending',updated_at=now() where id=p_id;
 end if;
end $e$;

create or replace function public.alani_report_content(
 p_id uuid,p_comment_id uuid,p_reason text
) returns uuid language plpgsql security definer set search_path=''
as $report$
declare v_user uuid:=(select auth.uid());v_id uuid;
begin
 if v_user is null then raise exception 'LOGIN_REQUIRED'; end if;
 if p_reason not in ('spam','abuse','misleading','unsafe','other') or p_reason is null
 then raise exception 'BAD_REPORT'; end if;
 perform public.alani_social_assert_published(p_id);
 if p_comment_id is not null and not exists(
 select 1 from public.alani_post_comments where id=p_comment_id and
 publication_id=p_id and status='approved') then raise exception 'BAD_COMMENT_ID'; end if;
 perform pg_catalog.pg_advisory_xact_lock(
 pg_catalog.hashtextextended('report:'||v_user::text,203));
 if (select count(*) from public.alani_post_reports where reporter_id=v_user
 and created_at>now()-interval '1 hour')>=10 then raise exception 'RATE_LIMIT'; end if;
 select id into v_id from public.alani_post_reports where reporter_id=v_user
 and publication_id=p_id and comment_id is not distinct from p_comment_id
 and status='open' limit 1;
 if v_id is not null then return v_id; end if;
 insert into public.alani_post_reports(publication_id,comment_id,reporter_id,reason)
 values(p_id,p_comment_id,v_user,p_reason) returning id into v_id;
 return v_id;
end $report$;

create or replace function public.alani_moderate_comment(p_id uuid,p_status text)
returns void language plpgsql security definer set search_path=''
as $m$
declare v_user uuid:=(select auth.uid());v_pub uuid;
begin
 if v_user is null then raise exception 'LOGIN_REQUIRED'; end if;
 if p_status not in ('approved','hidden','rejected') or p_status is null
 then raise exception 'BAD_STATUS'; end if;
 select publication_id into v_pub from public.alani_post_comments where id=p_id for update;
 if not found or not public.alani_can_moderate(v_pub)
 then raise exception 'MODERATION_DENIED'; end if;
 update public.alani_post_comments set status=p_status,updated_at=now()
 where id=p_id and status<>'deleted';
 insert into public.alani_moderation_audit(publication_id,actor_id,target_id,action)
 values(v_pub,v_user,p_id,'comment:'||p_status);
end $m$;

create or replace function public.alani_review_report(p_id uuid,p_status text)
returns void language plpgsql security definer set search_path=''
as $m$
declare v_user uuid:=(select auth.uid());v_pub uuid;
begin
 if v_user is null then raise exception 'LOGIN_REQUIRED'; end if;
 if p_status not in ('reviewed','dismissed') or p_status is null
 then raise exception 'BAD_STATUS'; end if;
 select publication_id into v_pub from public.alani_post_reports where id=p_id for update;
 if not found or not public.alani_can_moderate(v_pub)
 then raise exception 'MODERATION_DENIED'; end if;
 update public.alani_post_reports set status=p_status where id=p_id;
 insert into public.alani_moderation_audit(publication_id,actor_id,target_id,action)
 values(v_pub,v_user,p_id,'report:'||p_status);
end $m$;

create or replace function public.alani_set_content_staff(
 p_user_id uuid,p_role text,p_enabled boolean
) returns void language plpgsql security definer set search_path=''
as $s$
declare v_user uuid:=(select auth.uid());
 v_store constant uuid:='25091ca2-c0da-416c-b634-81b188ee66be'::uuid;
begin
 if v_user is null or not(
 exists(select 1 from public.stores where id=v_store and owner_id=v_user)
 or public.shitreed_is_admin()) then raise exception 'STAFF_DENIED'; end if;
 if p_user_id is null or p_enabled is null
 or (p_enabled and p_role not in ('writer','editor','moderator'))
 then raise exception 'BAD_STAFF_ROLE'; end if;
 if p_enabled then
 insert into public.alani_content_staff(store_id,user_id,role,granted_by)
 values(v_store,p_user_id,p_role,v_user)
 on conflict(store_id,user_id) do update
 set role=excluded.role,granted_by=excluded.granted_by;
 else
 delete from public.alani_content_staff where store_id=v_store and user_id=p_user_id;
 end if;
end $s$;

create or replace function public.alani_save_writer_draft(
 p_id uuid,p_kind text,p_title text,p_body text
) returns uuid language plpgsql security definer set search_path=''
as $w$
declare v_user uuid:=(select auth.uid());v_id uuid;
 v_store constant uuid:='25091ca2-c0da-416c-b634-81b188ee66be'::uuid;
 v_owner boolean;
begin
 if v_user is null then raise exception 'LOGIN_REQUIRED'; end if;
 v_owner:=exists(select 1 from public.stores where id=v_store and owner_id=v_user)
 or public.shitreed_is_admin();
 if not v_owner and not exists(select 1 from public.alani_content_staff
 where store_id=v_store and user_id=v_user and role in ('writer','editor'))
 then raise exception 'AUTHOR_DENIED'; end if;
 if p_kind not in ('video','article','recipe','post') or p_kind is null
 or p_title is null or char_length(pg_catalog.btrim(p_title)) not between 3 and 180
 or p_body is null or char_length(p_body)>10000 then raise exception 'BAD_DRAFT'; end if;
 if p_id is null then
 insert into public.alani_publications(store_id,kind,title,body,status,created_by)
 values(v_store,p_kind,pg_catalog.btrim(p_title),p_body,'draft',v_user)
 returning id into v_id;
 else
 update public.alani_publications set kind=p_kind,title=pg_catalog.btrim(p_title),
 body=p_body,updated_at=now() where id=p_id and store_id=v_store and status='draft'
 and (created_by=v_user or v_owner or exists(
 select 1 from public.alani_content_staff where store_id=v_store
 and user_id=v_user and role='editor')) returning id into v_id;
 if v_id is null then raise exception 'DRAFT_PERMISSION_DENIED'; end if;
 end if;
 return v_id;
end $w$;

create or replace function public.alani_publish_reviewed(
 p_id uuid,p_publish boolean
) returns void language plpgsql security definer set search_path=''
as $p$
declare v_user uuid:=(select auth.uid());
 v_store constant uuid:='25091ca2-c0da-416c-b634-81b188ee66be'::uuid;
begin
 if v_user is null or p_publish is null then raise exception 'BAD_REQUEST'; end if;
 if not (exists(select 1 from public.stores where id=v_store and owner_id=v_user)
 or public.shitreed_is_admin() or exists(
 select 1 from public.alani_content_staff where store_id=v_store
 and user_id=v_user and role='editor'))
 then raise exception 'PUBLISH_DENIED'; end if;
 update public.alani_publications set
 status=case when p_publish then 'published' else 'draft' end,
 published_at=case when p_publish then now() else null end,
 updated_at=now()
 where id=p_id and store_id=v_store;
 if not found then raise exception 'NO_PUBLICATION'; end if;
 insert into public.alani_moderation_audit(publication_id,actor_id,target_id,action)
 values(p_id,v_user,p_id,case when p_publish then 'publish' else 'unpublish' end);
end $p$;

revoke all on function public.alani_toggle_reaction(uuid,text),
 public.alani_rate_publication(uuid,integer),public.alani_social_summary(uuid),
 public.alani_submit_comment(uuid,text),
 public.alani_edit_own_comment(uuid,text,boolean),
 public.alani_report_content(uuid,uuid,text),
 public.alani_moderate_comment(uuid,text),
 public.alani_review_report(uuid,text),
 public.alani_set_content_staff(uuid,text,boolean),
 public.alani_save_writer_draft(uuid,text,text,text),
 public.alani_publish_reviewed(uuid,boolean)
 from public,anon,authenticated;
grant execute on function public.alani_social_summary(uuid) to anon,authenticated;
grant execute on function public.alani_toggle_reaction(uuid,text),
 public.alani_rate_publication(uuid,integer),
 public.alani_submit_comment(uuid,text),
 public.alani_edit_own_comment(uuid,text,boolean),
 public.alani_report_content(uuid,uuid,text),
 public.alani_moderate_comment(uuid,text),
 public.alani_review_report(uuid,text),
 public.alani_set_content_staff(uuid,text,boolean),
 public.alani_save_writer_draft(uuid,text,text,text),
 public.alani_publish_reviewed(uuid,boolean)
 to authenticated;
commit;
