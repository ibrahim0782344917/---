-- Shitreed profiles/levels/addresses: additive only, no existing row modifications.
-- Profiles and addresses are private to their owner.
-- XP and badges cannot be created or edited directly by mobile clients.
create table if not exists public.shitreed_profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null check (char_length(btrim(display_name)) between 2 and 80),
  bio text not null default '' check (char_length(bio) <= 500),
  city text not null default '' check (char_length(city) <= 80),
  avatar_url text,
  updated_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  constraint shitreed_avatar_owner check (
    avatar_url is null or avatar_url like (
      'https://ltwncrewggdrjevakwpb.supabase.co/storage/v1/object/public/shitreed-avatars/' ||
      user_id::text || '/avatar.%'
    )
  )
);
alter table public.shitreed_profiles enable row level security;
revoke all on public.shitreed_profiles from public,anon,authenticated;
grant select (user_id,display_name,bio,city,avatar_url,created_at,updated_at)
  on public.shitreed_profiles to authenticated;
grant insert (user_id,display_name,bio,city,avatar_url)
  on public.shitreed_profiles to authenticated;
grant update (display_name,bio,city,avatar_url)
  on public.shitreed_profiles to authenticated;
create policy "shitreed profile owner view" on public.shitreed_profiles
  for select to authenticated using (user_id = (select auth.uid()));
create policy "shitreed profile owner create" on public.shitreed_profiles
  for insert to authenticated with check (user_id = (select auth.uid()));
create policy "shitreed profile owner edit" on public.shitreed_profiles
  for update to authenticated using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

create table if not exists public.shitreed_saved_addresses (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  label text not null check (char_length(btrim(label)) between 2 and 60),
  address_text text not null check (char_length(btrim(address_text)) between 8 and 300),
  contact_phone text not null default '' check (char_length(contact_phone) <= 25),
  created_at timestamptz not null default now()
);
create index if not exists shitreed_saved_addresses_user
 on public.shitreed_saved_addresses(user_id,created_at desc);
alter table public.shitreed_saved_addresses enable row level security;
revoke all on public.shitreed_saved_addresses from public,anon,authenticated;
grant select (id,user_id,label,address_text,contact_phone,created_at)
  on public.shitreed_saved_addresses to authenticated;
grant insert (user_id,label,address_text,contact_phone)
  on public.shitreed_saved_addresses to authenticated;
grant update (label,address_text,contact_phone)
  on public.shitreed_saved_addresses to authenticated;
grant delete on public.shitreed_saved_addresses to authenticated;
create policy "shitreed address owner view" on public.shitreed_saved_addresses
 for select to authenticated using (user_id=(select auth.uid()));
create policy "shitreed address owner create" on public.shitreed_saved_addresses
 for insert to authenticated with check (user_id=(select auth.uid()));
create policy "shitreed address owner edit" on public.shitreed_saved_addresses
 for update to authenticated using (user_id=(select auth.uid()))
 with check (user_id=(select auth.uid()));
create policy "shitreed address owner delete" on public.shitreed_saved_addresses
 for delete to authenticated using (user_id=(select auth.uid()));

create table if not exists public.shitreed_xp_rules (
 event_type text primary key,
 points integer not null check(points between 0 and 1000),
 enabled boolean not null default false,
 updated_at timestamptz not null default now()
);
alter table public.shitreed_xp_rules enable row level security;
revoke all on public.shitreed_xp_rules from public,anon,authenticated;
grant select on public.shitreed_xp_rules to authenticated;
create policy "shitreed xp rules readable" on public.shitreed_xp_rules
 for select to authenticated using (true);
insert into public.shitreed_xp_rules(event_type,points,enabled) values
 ('profile_completed',20,true),
 ('verified_purchase',30,false),
 ('verified_review',10,false),
 ('qualified_share',5,false),
 ('merchant_completed_sale',40,false),
 ('daily_eligible_activity',5,false)
on conflict (event_type) do nothing;

create table if not exists public.shitreed_xp_events (
 id uuid primary key default gen_random_uuid(),
 user_id uuid not null references auth.users(id) on delete cascade,
 event_type text not null references public.shitreed_xp_rules(event_type),
 source_key text not null check (char_length(source_key) between 1 and 200),
 points integer not null check (points between 1 and 1000),
 issued_by uuid references auth.users(id),
 created_at timestamptz not null default now(),
 unique(user_id,event_type,source_key)
);
create index if not exists shitreed_xp_events_owner
 on public.shitreed_xp_events(user_id,created_at desc);
alter table public.shitreed_xp_events enable row level security;
revoke all on public.shitreed_xp_events from public,anon,authenticated;
grant select (id,user_id,event_type,points,created_at)
  on public.shitreed_xp_events to authenticated;
create policy "shitreed xp owner read" on public.shitreed_xp_events
 for select to authenticated using (user_id=(select auth.uid()));
-- No client-facing insert/update/delete policy for XP events.

create table if not exists public.shitreed_level_thresholds (
 level integer primary key check (level between 1 and 100),
 min_xp integer not null unique check (min_xp>=0)
);
alter table public.shitreed_level_thresholds enable row level security;
revoke all on public.shitreed_level_thresholds from public,anon,authenticated;
grant select on public.shitreed_level_thresholds to authenticated;
create policy "shitreed level levels readable" on public.shitreed_level_thresholds
 for select to authenticated using (true);
insert into public.shitreed_level_thresholds(level,min_xp)
 select x, (x-1)*100 from generate_series(1,100) as x
on conflict(level) do nothing;

create table if not exists public.shitreed_user_badges (
 id uuid primary key default gen_random_uuid(),
 user_id uuid not null references auth.users(id) on delete cascade,
 badge_kind text not null check (badge_kind in (
 'verified_identity','verified_merchant','gold','king','merchant_pro','custom')),
 label text not null check (char_length(btrim(label)) between 2 and 80),
 icon text not null default '⭐' check (char_length(icon) between 1 and 10),
 reason text not null check (char_length(btrim(reason)) between 12 and 500),
 granted_by uuid not null references auth.users(id),
 granted_at timestamptz not null default now(),
 expires_at timestamptz,
 active boolean not null default true,
 unique(user_id,badge_kind,label)
);
create index if not exists shitreed_user_badges_owner
 on public.shitreed_user_badges(user_id,active);
alter table public.shitreed_user_badges enable row level security;
revoke all on public.shitreed_user_badges from public,anon,authenticated;
grant select (id,user_id,badge_kind,label,icon,granted_at,expires_at,active)
  on public.shitreed_user_badges to authenticated;
create policy "shitreed badges owner view" on public.shitreed_user_badges
 for select to authenticated using (user_id=(select auth.uid()));

create table if not exists public.shitreed_profile_admin_audit (
 id uuid primary key default gen_random_uuid(),
 actor_id uuid not null references auth.users(id),
 target_user_id uuid,
 action text not null,
 reason text not null,
 changed_at timestamptz not null default now()
);
alter table public.shitreed_profile_admin_audit enable row level security;
revoke all on public.shitreed_profile_admin_audit from public,anon,authenticated;

-- Avoid client-controlled "XP" by awarding profile completion only once
-- when meaningful profile fields are present. The trigger checks the rule.
create or replace function public.shitreed_profile_after_write()
 returns trigger
 language plpgsql security definer set search_path=''
as $$
declare reward int;
begin
 if char_length(btrim(new.display_name))>=2 and
    char_length(btrim(new.city))>=2 and
    char_length(btrim(new.bio))>=2 then
   select points into reward from public.shitreed_xp_rules
    where event_type='profile_completed' and enabled=true;
   if reward is not null and reward>0 then
     insert into public.shitreed_xp_events
       (user_id,event_type,source_key,points)
       values(new.user_id,'profile_completed','first_complete_profile',reward)
       on conflict(user_id,event_type,source_key) do nothing;
   end if;
 end if;
 new.updated_at := now();
 return new;
end;
$$;
revoke all on function public.shitreed_profile_after_write() from public,anon,authenticated;
drop trigger if exists shitreed_profile_completion on public.shitreed_profiles;
create trigger shitreed_profile_completion before insert or update of display_name,bio,city
 on public.shitreed_profiles for each row execute function public.shitreed_profile_after_write();

-- Admin controls: only super_admin; users cannot change these through the Data API.
create or replace function public.shitreed_admin_set_level_threshold(
 p_level integer,p_min_xp integer,p_reason text
) returns boolean
language plpgsql security definer set search_path=''
as $$
declare old_min int; previous_min int; next_min int; actor uuid := (select auth.uid());
begin
 if actor is null or public.shitreed_admin_role() is distinct from 'super_admin' then
  raise exception 'PERMISSION_DENIED';
 end if;
 if p_level not between 2 and 100 or p_min_xp<1 or
   char_length(btrim(coalesce(p_reason,'')))<12 then
  raise exception 'INVALID_LEVEL_REQUEST';
 end if;
 select min_xp into previous_min from public.shitreed_level_thresholds where level=p_level-1;
 select min_xp into next_min from public.shitreed_level_thresholds where level=p_level+1;
 if previous_min is null or p_min_xp<=previous_min or
    (next_min is not null and p_min_xp>=next_min) then
  raise exception 'LEVEL_THRESHOLD_OUT_OF_ORDER';
 end if;
 select min_xp into old_min from public.shitreed_level_thresholds where level=p_level;
 update public.shitreed_level_thresholds set min_xp=p_min_xp where level=p_level;
 insert into public.shitreed_profile_admin_audit(actor_id,action,reason)
 values(actor,'level_threshold_change',
    btrim(p_reason)||' (level '||p_level||', old '||old_min||', new '||p_min_xp||')');
 return true;
end;
$$;
revoke all on function public.shitreed_admin_set_level_threshold(integer,integer,text)
 from public,anon;
grant execute on function public.shitreed_admin_set_level_threshold(integer,integer,text)
 to authenticated;

create or replace function public.shitreed_admin_set_badge(
 p_user_id uuid,p_badge_kind text,p_label text,p_icon text,
 p_enabled boolean,p_reason text
) returns boolean
language plpgsql security definer set search_path=''
as $$
declare actor uuid := (select auth.uid());
begin
 if actor is null or public.shitreed_admin_role() is distinct from 'super_admin' then
   raise exception 'PERMISSION_DENIED';
 end if;
 if p_user_id is null or p_badge_kind not in
 ('verified_identity','verified_merchant','gold','king','merchant_pro','custom')
 or char_length(btrim(coalesce(p_label,''))) not between 2 and 80
 or char_length(coalesce(p_icon,'')) not between 1 and 10
 or char_length(btrim(coalesce(p_reason,''))) not between 12 and 500 then
   raise exception 'INVALID_BADGE_REQUEST';
 end if;
 if p_enabled then
   insert into public.shitreed_user_badges
    (user_id,badge_kind,label,icon,reason,granted_by,active)
   values(p_user_id,p_badge_kind,btrim(p_label),p_icon,btrim(p_reason),actor,true)
   on conflict(user_id,badge_kind,label) do update set
    active=true,icon=excluded.icon,reason=excluded.reason,
    granted_by=excluded.granted_by,granted_at=now(),expires_at=null;
 else
   update public.shitreed_user_badges set active=false
    where user_id=p_user_id and badge_kind=p_badge_kind and label=btrim(p_label);
 end if;
 insert into public.shitreed_profile_admin_audit(actor_id,target_user_id,action,reason)
 values(actor,p_user_id,case when p_enabled then 'badge_granted' else 'badge_revoked' end,btrim(p_reason));
 return true;
end;
$$;
revoke all on function public.shitreed_admin_set_badge(uuid,text,text,text,boolean,text)
 from public,anon;
grant execute on function public.shitreed_admin_set_badge(uuid,text,text,text,boolean,text)
 to authenticated;

-- Public avatars with fixed three filenames per user and 2 MB max/object.
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
 values('shitreed-avatars','shitreed-avatars',true,2097152,
 array['image/jpeg','image/png','image/webp'])
 on conflict(id) do nothing;
create policy "Shitreed avatars owner insert" on storage.objects
 for insert to authenticated
 with check(bucket_id='shitreed-avatars'
  and (storage.foldername(name))[1]=(select auth.uid())::text
  and (storage.filename(name)) in ('avatar.jpg','avatar.png','avatar.webp'));
create policy "Shitreed avatars owner select" on storage.objects
 for select to authenticated
 using(bucket_id='shitreed-avatars'
  and (storage.foldername(name))[1]=(select auth.uid())::text);
create policy "Shitreed avatars owner update" on storage.objects
 for update to authenticated
 using(bucket_id='shitreed-avatars'
  and (storage.foldername(name))[1]=(select auth.uid())::text
  and (storage.filename(name)) in ('avatar.jpg','avatar.png','avatar.webp'))
 with check(bucket_id='shitreed-avatars'
  and (storage.foldername(name))[1]=(select auth.uid())::text
  and (storage.filename(name)) in ('avatar.jpg','avatar.png','avatar.webp'));
-- No public user deletes through database; overwrite limited filenames only.
