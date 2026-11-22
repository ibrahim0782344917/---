-- Al-Ani content: additive table, no change to existing customer/order data.
-- Source of truth for all three connected app content views.
-- Tested first against disposable PostgreSQL with owner/visitor RLS checks.
-- Video URLs are HTTPS links; separate video binary uploads are not enabled.

begin;

create table public.alani_publications (
  id uuid primary key default gen_random_uuid(),
  store_id uuid not null
    references public.stores(id) on delete restrict
    constraint alani_only_store
      check (store_id = '25091ca2-c0da-416c-b634-81b188ee66be'::uuid),
  kind text not null check (kind in ('video','recipe','article','post')),
  title text not null check (char_length(trim(title)) between 3 and 180),
  body text not null default '' check (char_length(body) <= 30000),
  ingredients text not null default '' check (char_length(ingredients) <= 8000),
  safety_note text not null default '' check (char_length(safety_note) <= 4000),
  image_url text check (
    image_url is null or
    (char_length(image_url) <= 1000 and image_url ~ '^https://[^/ ]+')
  ),
  video_url text check (
    video_url is null or
    (char_length(video_url) <= 1000 and video_url ~ '^https://[^/ ]+')
  ),
  status text not null default 'draft'
    check (status in ('draft','published')),
  published_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint alani_publish_has_time check (
    status <> 'published' or published_at is not null
  ),
  constraint alani_published_video_has_link check (
    status <> 'published' or kind <> 'video' or video_url is not null
  )
);

create index alani_publications_visible_idx
  on public.alani_publications(store_id,published_at desc)
  where status = 'published';

create index alani_publications_store_created_idx
  on public.alani_publications(store_id,created_at desc);

alter table public.alani_publications enable row level security;

revoke all on public.alani_publications from public, anon, authenticated;
grant select on public.alani_publications to anon, authenticated;
grant insert, update, delete on public.alani_publications to authenticated;

create policy alani_publications_read
  on public.alani_publications for select to anon, authenticated
  using (
    (status = 'published' and exists (
      select 1 from public.stores s
      where s.id = store_id and s.status = 'approved'
    ))
    or exists (
      select 1 from public.stores s
      where s.id = store_id and s.owner_id = (select auth.uid())
    )
  );

create policy alani_publications_insert
  on public.alani_publications for insert to authenticated
  with check (
    exists (
      select 1 from public.stores s
      where s.id = store_id and s.status = 'approved'
        and s.owner_id = (select auth.uid())
    )
  );

create policy alani_publications_update
  on public.alani_publications for update to authenticated
  using (
    exists (
      select 1 from public.stores s
      where s.id = store_id and s.owner_id = (select auth.uid())
    )
  )
  with check (
    exists (
      select 1 from public.stores s
      where s.id = store_id and s.status = 'approved'
        and s.owner_id = (select auth.uid())
    )
  );

create policy alani_publications_delete
  on public.alani_publications for delete to authenticated
  using (
    exists (
      select 1 from public.stores s
      where s.id = store_id and s.owner_id = (select auth.uid())
    )
  );

commit;
