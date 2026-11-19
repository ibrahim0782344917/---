-- STAGING ONLY: requires isolated Supabase branch and role A/B RLS acceptance.
-- Never run against Production without backup, dry-run and approved deployment.
-- Both schemas match the existing Al-Ani server.js API endpoints.
begin;

create table if not exists public.alani_publications (
  id uuid primary key default gen_random_uuid(),
  store_id uuid not null references public.stores(id) on delete restrict,
  kind text not null check(kind in ('video','recipe','article','post')),
  title text not null check(char_length(btrim(title)) between 3 and 180),
  body text not null default '' check(char_length(body)<=30000),
  ingredients text not null default '' check(char_length(ingredients)<=8000),
  safety_note text not null default '' check(char_length(safety_note)<=4000),
  image_url text check(image_url is null or
    (left(image_url,8)='https://' and char_length(image_url)<=1000)),
  video_url text check(video_url is null or
    (left(video_url,8)='https://' and char_length(video_url)<=1000)),
  status text not null default 'draft'
    check(status in ('draft','published','archived')),
  published_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint actual_video_url check (kind<>'video' or video_url is not null),
  constraint published_date check (status<>'published' or published_at is not null)
);
create index if not exists alani_publications_feed_idx
  on public.alani_publications(store_id,status,published_at desc);
alter table public.alani_publications enable row level security;
revoke all on public.alani_publications from public,anon,authenticated;
grant select on public.alani_publications to anon,authenticated;
grant insert on public.alani_publications to authenticated;
grant update(kind,title,body,ingredients,safety_note,image_url,video_url,
  status,published_at,updated_at) on public.alani_publications to authenticated;

drop policy if exists alani_posts_public on public.alani_publications;
create policy alani_posts_public on public.alani_publications
  for select to anon,authenticated using(
    status='published' and exists(
      select 1 from public.stores s
      where s.id=store_id and s.status='approved'
    )
  );
drop policy if exists alani_posts_owner_read on public.alani_publications;
create policy alani_posts_owner_read on public.alani_publications
  for select to authenticated using(
    exists(select 1 from public.stores s
      where s.id=store_id and s.owner_id=(select auth.uid()))
  );
drop policy if exists alani_posts_owner_insert on public.alani_publications;
create policy alani_posts_owner_insert on public.alani_publications
  for insert to authenticated with check(
    exists(select 1 from public.stores s
      where s.id=store_id and s.status='approved'
        and s.owner_id=(select auth.uid()))
  );
drop policy if exists alani_posts_owner_update on public.alani_publications;
create policy alani_posts_owner_update on public.alani_publications
  for update to authenticated using(
    exists(select 1 from public.stores s
      where s.id=store_id and s.owner_id=(select auth.uid()))
  ) with check(
    exists(select 1 from public.stores s
      where s.id=store_id and s.owner_id=(select auth.uid()))
  );

create table if not exists public.alani_return_requests (
  id uuid primary key default gen_random_uuid(),
  store_id uuid not null references public.stores(id) on delete restrict,
  order_id uuid not null references public.orders(id) on delete restrict,
  customer_id uuid not null references auth.users(id) on delete restrict,
  reason text not null check(reason in
    ('change_mind','damaged','wrong_item','defective')),
  details text not null check(char_length(btrim(details)) between 15 and 2000),
  photo_url text check(photo_url is null or
    (left(photo_url,8)='https://' and char_length(photo_url)<=1000)),
  status text not null default 'submitted'
    check(status in ('submitted','reviewing','approved','declined','resolved')),
  resolution_note text not null default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(order_id,customer_id)
);
create index if not exists alani_returns_status_idx
  on public.alani_return_requests(store_id,status,created_at desc);
alter table public.alani_return_requests enable row level security;
revoke all on public.alani_return_requests from public,anon,authenticated;
grant select,insert on public.alani_return_requests to authenticated;
grant update(status,resolution_note,updated_at)
  on public.alani_return_requests to authenticated;

drop policy if exists alani_return_customer_read on public.alani_return_requests;
create policy alani_return_customer_read on public.alani_return_requests
  for select to authenticated using(
    customer_id=(select auth.uid())
  );
drop policy if exists alani_return_owner_read on public.alani_return_requests;
create policy alani_return_owner_read on public.alani_return_requests
  for select to authenticated using(
    exists(select 1 from public.stores s where
      s.id=store_id and s.owner_id=(select auth.uid()))
  );
drop policy if exists alani_return_customer_submit on public.alani_return_requests;
create policy alani_return_customer_submit on public.alani_return_requests
  for insert to authenticated with check(
    customer_id=(select auth.uid()) and status='submitted'
    and resolution_note='' and exists(
      select 1 from public.orders o
      where o.id=order_id and o.buyer_id=(select auth.uid())
      and o.store_id=alani_return_requests.store_id
    )
  );
drop policy if exists alani_return_owner_review on public.alani_return_requests;
create policy alani_return_owner_review on public.alani_return_requests
  for update to authenticated using(
    exists(select 1 from public.stores s where s.id=store_id
      and s.owner_id=(select auth.uid()))
  ) with check(
    exists(select 1 from public.stores s where s.id=store_id
      and s.owner_id=(select auth.uid()))
  );

create or replace function public.alani_return_transition_guard()
  returns trigger
  language plpgsql
  security invoker
  set search_path=''
as $$
begin
  if (new.status=old.status) then
    raise exception 'RETURN_STATUS_UNCHANGED';
  end if;
  if not (
    (old.status='submitted' and new.status='reviewing') or
    (old.status='reviewing' and new.status in ('approved','declined')) or
    (old.status='approved' and new.status='resolved')
  ) then
    raise exception 'INVALID_RETURN_TRANSITION';
  end if;
  if char_length(btrim(new.resolution_note)) < 10 then
    raise exception 'RETURN_REVIEW_NOTE_REQUIRED';
  end if;
  if new.updated_at < old.updated_at then
    raise exception 'RETURN_UPDATE_TIME_REVERSED';
  end if;
  return new;
end;
$$;
drop trigger if exists trg_alani_return_transition
  on public.alani_return_requests;
create trigger trg_alani_return_transition before update
  on public.alani_return_requests for each row
  execute function public.alani_return_transition_guard();

commit;

-- SECURITY ACCEPTANCE IN STAGING:
-- anonymous sees only published posts from approved stores; cannot insert
-- seller A cannot edit drafts or returns of seller B
-- customer A cannot see customer B's return or private order metadata
-- customer cannot change return status or fake compensation
-- invalid return transitions fail; no cash credit is paid automatically
-- video files must have verified rights and independently managed storage.
