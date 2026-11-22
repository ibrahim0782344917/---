-- Additive SOCIAL staging migration. Execute on an isolated DB first.
-- No modification to orders, stock, prior comments or customer accounts.
begin;
alter table public.alani_publications
  add column if not exists created_by uuid references auth.users(id) on delete set null;
alter table public.alani_publications
  alter column created_by set default auth.uid();

create table if not exists public.alani_content_staff (
 user_id uuid primary key references auth.users(id) on delete cascade,
 role text not null check(role in ('writer','moderator')),
 active boolean not null default true,
 granted_by uuid not null references auth.users(id) on delete restrict,
 created_at timestamptz not null default now()
);
alter table public.alani_content_staff enable row level security;
revoke all on public.alani_content_staff from public,anon,authenticated;
-- Anonymous roles need SELECT privilege to evaluate read policies; RLS returns zero staff rows.
grant select on public.alani_content_staff to anon,authenticated;
create policy "social staff self and owner read"
 on public.alani_content_staff for select to authenticated
 using(user_id=(select auth.uid()) or exists(
   select 1 from public.stores s
   where s.id='25091ca2-c0da-416c-b634-81b188ee66be'::uuid
   and s.owner_id=(select auth.uid())
 ));

drop policy if exists alani_publications_read on public.alani_publications;
drop policy if exists alani_publications_read_public on public.alani_publications;
drop policy if exists alani_publications_read_authenticated on public.alani_publications;
create policy alani_publications_read_public on public.alani_publications
 for select to anon using(
   status='published' and exists(select 1 from public.stores s
     where s.id=store_id and s.status='approved')
 );
create policy alani_publications_read_authenticated on public.alani_publications
 for select to authenticated using(
   (status='published' and exists(select 1 from public.stores s
     where s.id=store_id and s.status='approved'))
   or exists(select 1 from public.stores s
     where s.id=store_id and s.owner_id=(select auth.uid()))
   or (created_by=(select auth.uid()) and exists(
     select 1 from public.alani_content_staff st
     where st.user_id=(select auth.uid()) and st.active
       and st.role in ('writer','moderator')))
);

drop policy if exists alani_publications_insert on public.alani_publications;
create policy alani_publications_insert on public.alani_publications
 for insert to authenticated with check(
   (exists(select 1 from public.stores s where s.id=store_id
      and s.status='approved' and s.owner_id=(select auth.uid())))
   or (created_by=(select auth.uid()) and status='draft'
      and exists(select 1 from public.alani_content_staff st
        where st.user_id=(select auth.uid()) and st.active=true
        and st.role in ('writer','moderator')))
 );
drop policy if exists alani_publications_update on public.alani_publications;
create policy alani_publications_update on public.alani_publications
 for update to authenticated
 using(exists(select 1 from public.stores s where s.id=store_id
     and s.owner_id=(select auth.uid()))
   or (created_by=(select auth.uid()) and status='draft'
     and exists(select 1 from public.alani_content_staff st
       where st.user_id=(select auth.uid()) and st.active and st.role='writer')))
 with check(exists(select 1 from public.stores s where s.id=store_id
     and s.owner_id=(select auth.uid()) and s.status='approved')
   or (created_by=(select auth.uid()) and status='draft'
     and exists(select 1 from public.alani_content_staff st
       where st.user_id=(select auth.uid()) and st.active and st.role='writer')));
drop policy if exists alani_publications_delete on public.alani_publications;
create policy alani_publications_delete on public.alani_publications
 for delete to authenticated using(
    exists(select 1 from public.stores s where s.id=store_id
      and s.owner_id=(select auth.uid()))
   or (created_by=(select auth.uid()) and status='draft'
     and exists(select 1 from public.alani_content_staff st
       where st.user_id=(select auth.uid()) and st.active and st.role='writer')));

create table if not exists public.alani_publication_reactions (
 publication_id uuid not null references public.alani_publications(id) on delete cascade,
 user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
 action text not null check(action in ('like','save')),
 created_at timestamptz not null default now(),
 primary key(publication_id,user_id,action)
);
create index if not exists alani_reactions_user_idx on public.alani_publication_reactions(user_id,created_at desc);
alter table public.alani_publication_reactions enable row level security;
revoke all on public.alani_publication_reactions from public,anon,authenticated;
grant select,insert,delete on public.alani_publication_reactions to authenticated;
create policy "social own reactions read" on public.alani_publication_reactions
 for select to authenticated using(user_id=(select auth.uid()));
create policy "social own reactions insert" on public.alani_publication_reactions
 for insert to authenticated with check(user_id=(select auth.uid())
  and exists(select 1 from public.alani_publications p
    where p.id=publication_id and p.status='published'));
create policy "social own reactions delete" on public.alani_publication_reactions
 for delete to authenticated using(user_id=(select auth.uid()));

create table if not exists public.alani_publication_comments (
 id uuid primary key default gen_random_uuid(),
 publication_id uuid not null references public.alani_publications(id) on delete cascade,
 user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
 body text not null check(char_length(pg_catalog.btrim(body)) between 2 and 1200),
 status text not null default 'pending' check(status in ('pending','approved','hidden')),
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);
create index if not exists alani_comments_post_idx
 on public.alani_publication_comments(publication_id,status,created_at desc);
create index if not exists alani_comments_author_idx
 on public.alani_publication_comments(user_id,created_at desc);
alter table public.alani_publication_comments enable row level security;
revoke all on public.alani_publication_comments from public,anon,authenticated;
grant select on public.alani_publication_comments to anon,authenticated;
grant insert,delete on public.alani_publication_comments to authenticated;
create policy "social anonymous approved comments" on public.alani_publication_comments
 for select to anon using(
   status='approved' and exists(select 1 from public.alani_publications p
     where p.id=publication_id and p.status='published')
 );
create policy "social authenticated comments" on public.alani_publication_comments
 for select to authenticated using(
  (status='approved' and exists(select 1 from public.alani_publications p
      where p.id=publication_id and p.status='published'))
  or user_id=(select auth.uid())
  or exists(select 1 from public.alani_publications p
      join public.stores s on s.id=p.store_id
      where p.id=publication_id and s.owner_id=(select auth.uid()))
  or exists(select 1 from public.alani_content_staff st
      where st.user_id=(select auth.uid()) and st.active and st.role='moderator')
 );
create policy "social comments author inserts pending" on public.alani_publication_comments
 for insert to authenticated with check(
  user_id=(select auth.uid()) and status='pending'
  and exists(select 1 from public.alani_publications p
      where p.id=publication_id and p.status='published')
 );
create policy "social comments author delete" on public.alani_publication_comments
 for delete to authenticated using(user_id=(select auth.uid()));

create table if not exists public.alani_publication_reports (
 id uuid primary key default gen_random_uuid(),
 publication_id uuid not null references public.alani_publications(id) on delete cascade,
 comment_id uuid references public.alani_publication_comments(id) on delete cascade,
 reporter_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
 reason text not null check(reason in ('spam','harmful','misleading','abuse','other')),
 details text not null default '' check(char_length(details)<=1000),
 status text not null default 'open' check(status in ('open','reviewed','dismissed')),
 staff_note text not null default '' check(char_length(staff_note)<=1000),
 created_at timestamptz not null default now()
);
create unique index if not exists alani_unique_report_target
 on public.alani_publication_reports(reporter_id,publication_id,coalesce(comment_id,'00000000-0000-0000-0000-000000000000'::uuid));
alter table public.alani_publication_reports enable row level security;
revoke all on public.alani_publication_reports from public,anon,authenticated;
grant select,insert on public.alani_publication_reports to authenticated;
create policy "social report author or staff read"
 on public.alani_publication_reports for select to authenticated
 using(reporter_id=(select auth.uid())
    or exists(select 1 from public.alani_publications p
      join public.stores s on s.id=p.store_id
      where p.id=publication_id and s.owner_id=(select auth.uid()))
    or exists(select 1 from public.alani_content_staff st
      where st.user_id=(select auth.uid()) and st.active and st.role='moderator'));
create policy "social report own insert" on public.alani_publication_reports
 for insert to authenticated with check(
   reporter_id=(select auth.uid()) and status='open' and staff_note=''
   and exists(select 1 from public.alani_publications p
     where p.id=publication_id and p.status='published')
   and (comment_id is null or exists(
     select 1 from public.alani_publication_comments c
     where c.id=comment_id and c.publication_id=publication_id and c.status='approved'))
 );

create table if not exists public.alani_content_moderation_audit (
 id uuid primary key default gen_random_uuid(),
 actor_id uuid not null references auth.users(id) on delete restrict,
 target_type text not null check(target_type in ('comment','publication','report','staff')),
 target_id uuid not null,
 action text not null,
 created_at timestamptz not null default now()
);
alter table public.alani_content_moderation_audit enable row level security;
revoke all on public.alani_content_moderation_audit from public,anon,authenticated;
grant select on public.alani_content_moderation_audit to authenticated;
create policy "social audit owner" on public.alani_content_moderation_audit
 for select to authenticated using(exists(
    select 1 from public.stores s where s.id='25091ca2-c0da-416c-b634-81b188ee66be'::uuid
    and s.owner_id=(select auth.uid())));

create or replace function public.alani_social_stats(p_publication_id uuid)
returns jsonb language plpgsql stable security definer set search_path=''
as $stats$
declare v_like bigint; v_comment bigint;
begin
 if not exists(select 1 from public.alani_publications p
   where p.id=p_publication_id and p.status='published') then
   return pg_catalog.jsonb_build_object('likes',0,'comments',0);
 end if;
 select count(*) into v_like from public.alani_publication_reactions
   where publication_id=p_publication_id and action='like';
 select count(*) into v_comment from public.alani_publication_comments
   where publication_id=p_publication_id and status='approved';
 return pg_catalog.jsonb_build_object('likes',v_like,'comments',v_comment);
end;
$stats$;
revoke all on function public.alani_social_stats(uuid) from public,anon,authenticated;
grant execute on function public.alani_social_stats(uuid) to anon,authenticated;

create or replace function public.alani_content_manage_staff(
 p_user_id uuid,p_role text,p_active boolean)
returns boolean language plpgsql security definer set search_path=''
as $staff$
declare v_actor uuid := (select auth.uid());
begin
 if v_actor is null or not exists(select 1 from public.stores s
   where s.id='25091ca2-c0da-416c-b634-81b188ee66be'::uuid
     and s.owner_id=v_actor) then raise exception 'PERMISSION_DENIED'; end if;
 if p_user_id is null or p_role not in ('writer','moderator') or p_active is null
 then raise exception 'INVALID_STAFF_ASSIGNMENT'; end if;
 insert into public.alani_content_staff(user_id,role,active,granted_by)
 values(p_user_id,p_role,p_active,v_actor)
 on conflict(user_id) do update set role=excluded.role,
   active=excluded.active,granted_by=excluded.granted_by;
 insert into public.alani_content_moderation_audit(actor_id,target_type,target_id,action)
 values(v_actor,'staff',p_user_id,case when p_active then p_role else 'disabled' end);
 return true;
end;
$staff$;
revoke all on function public.alani_content_manage_staff(uuid,text,boolean)
 from public,anon,authenticated;
grant execute on function public.alani_content_manage_staff(uuid,text,boolean) to authenticated;

create or replace function public.alani_moderate_comment(p_comment_id uuid,p_status text)
returns text language plpgsql security definer set search_path=''
as $moderate$
declare v_actor uuid := (select auth.uid());
begin
 if v_actor is null or not (
   exists(select 1 from public.stores s where s.id='25091ca2-c0da-416c-b634-81b188ee66be'::uuid
     and s.owner_id=v_actor)
   or exists(select 1 from public.alani_content_staff st where st.user_id=v_actor
     and st.active and st.role='moderator')
 ) then raise exception 'PERMISSION_DENIED'; end if;
 if p_status not in ('approved','hidden') then raise exception 'INVALID_STATUS'; end if;
 update public.alani_publication_comments set status=p_status,updated_at=now()
 where id=p_comment_id;
 if not found then raise exception 'COMMENT_NOT_FOUND'; end if;
 insert into public.alani_content_moderation_audit(actor_id,target_type,target_id,action)
 values(v_actor,'comment',p_comment_id,p_status);
 return p_status;
end;
$moderate$;
revoke all on function public.alani_moderate_comment(uuid,text) from public,anon,authenticated;
grant execute on function public.alani_moderate_comment(uuid,text) to authenticated;

create or replace function public.alani_moderate_publication(p_publication_id uuid,p_action text)
returns text language plpgsql security definer set search_path=''
as $moderate$
declare v_actor uuid := (select auth.uid()); v_new text;
begin
 if v_actor is null or not (
   exists(select 1 from public.stores s where s.id='25091ca2-c0da-416c-b634-81b188ee66be'::uuid
     and s.owner_id=v_actor)
   or exists(select 1 from public.alani_content_staff st where st.user_id=v_actor
     and st.active and st.role='moderator')
 ) then raise exception 'PERMISSION_DENIED'; end if;
 if p_action not in ('publish','hide') then raise exception 'INVALID_ACTION'; end if;
 v_new := case when p_action='publish' then 'published' else 'draft' end;
 update public.alani_publications
   set status=v_new,published_at=case when v_new='published' then now() else null end,
       updated_at=now()
 where id=p_publication_id and store_id='25091ca2-c0da-416c-b634-81b188ee66be'::uuid;
 if not found then raise exception 'POST_NOT_FOUND'; end if;
 insert into public.alani_content_moderation_audit(actor_id,target_type,target_id,action)
 values(v_actor,'publication',p_publication_id,p_action);
 return v_new;
end;
$moderate$;
revoke all on function public.alani_moderate_publication(uuid,text) from public,anon,authenticated;
grant execute on function public.alani_moderate_publication(uuid,text) to authenticated;

create or replace function public.alani_review_social_report(
 p_report_id uuid,p_status text,p_note text)
returns text language plpgsql security definer set search_path=''
as $review$
declare v_actor uuid := (select auth.uid());
begin
 if v_actor is null or not (
   exists(select 1 from public.stores s where s.id='25091ca2-c0da-416c-b634-81b188ee66be'::uuid
     and s.owner_id=v_actor)
   or exists(select 1 from public.alani_content_staff st where st.user_id=v_actor
     and st.active and st.role='moderator')
 ) then raise exception 'PERMISSION_DENIED'; end if;
 if p_status not in ('reviewed','dismissed') or p_note is null or
   char_length(pg_catalog.btrim(p_note)) not between 8 and 1000 then
   raise exception 'INVALID_REVIEW'; end if;
 update public.alani_publication_reports
   set status=p_status,staff_note=pg_catalog.btrim(p_note)
   where id=p_report_id and status='open';
 if not found then raise exception 'REPORT_NOT_OPEN'; end if;
 insert into public.alani_content_moderation_audit(actor_id,target_type,target_id,action)
 values(v_actor,'report',p_report_id,p_status);
 return p_status;
end;
$review$;
revoke all on function public.alani_review_social_report(uuid,text,text)
 from public,anon,authenticated;
grant execute on function public.alani_review_social_report(uuid,text,text)
 to authenticated;
commit;
