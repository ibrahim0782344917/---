-- REVIEW ONLY — NOT EXECUTED ON PRODUCTION.
-- Run on a separate Supabase staging project after backup, ownership review,
-- and explicit approval. Allows the approved store's owner to publish videos,
-- recipes, articles and short text posts. This is NOT a medical claims review.

begin;

create table if not exists public.alani_publications (
  id uuid primary key default gen_random_uuid(),
  store_id uuid not null references public.stores(id) on delete restrict,
  kind text not null check (kind in ('video','recipe','article','post')),
  title text not null check (char_length(title) between 3 and 180),
  body text not null default '' check (char_length(body) <= 30000),
  ingredients text not null default '' check (char_length(ingredients) <= 8000),
  safety_note text not null default '' check (char_length(safety_note) <= 4000),
  image_url text check (image_url is null or image_url ~ '^https://'),
  video_url text check (video_url is null or video_url ~ '^https://'),
  related_product_id uuid references public.products(id) on delete set null,
  status text not null default 'draft'
    check (status in ('draft','published')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  published_at timestamptz
);

create index if not exists alani_publications_store_published_idx
  on public.alani_publications (store_id, published_at desc)
  where status = 'published';

alter table public.alani_publications enable row level security;

-- Data API GRANT and RLS are separate checks.
revoke all on public.alani_publications from anon, authenticated;
grant select on public.alani_publications to anon, authenticated;
grant insert, update, delete on public.alani_publications to authenticated;

-- The entire row is readable only if published for an approved shop, or
-- if the current authenticated user owns that shop. Do not use user_metadata.
drop policy if exists alani_publications_read on public.alani_publications;
create policy alani_publications_read
  on public.alani_publications for select to anon, authenticated
  using (
    (
      status = 'published'
      and exists (
        select 1 from public.stores s
        where s.id = store_id and s.status = 'approved'
      )
    )
    or exists (
      select 1 from public.stores s
      where s.id = store_id and s.owner_id = (select auth.uid())
    )
  );

drop policy if exists alani_publications_insert on public.alani_publications;
create policy alani_publications_insert
  on public.alani_publications for insert to authenticated
  with check (exists (
    select 1 from public.stores s
    where s.id = store_id
      and s.owner_id = (select auth.uid())
      and s.status = 'approved'
  ));

drop policy if exists alani_publications_update on public.alani_publications;
create policy alani_publications_update
  on public.alani_publications for update to authenticated
  using (exists (
    select 1 from public.stores s
    where s.id = store_id and s.owner_id = (select auth.uid())
  ))
  with check (exists (
    select 1 from public.stores s
    where s.id = store_id
      and s.owner_id = (select auth.uid())
      and s.status = 'approved'
  ));

drop policy if exists alani_publications_delete on public.alani_publications;
create policy alani_publications_delete
  on public.alani_publications for delete to authenticated
  using (exists (
    select 1 from public.stores s
    where s.id = store_id and s.owner_id = (select auth.uid())
  ));

commit;

-- BEFORE ACCEPTANCE:
-- 1. Verify logged-out user sees only published rows, never drafts.
-- 2. Verify a different merchant cannot insert/update/delete a row.
-- 3. Verify row store_id and related_product_id belong to same shop;
--    add an explicit DB trigger or composite FK if related_product_id is used.
-- 4. Verify large-video upload policy (private signing/CDN, size, MIME,
--    storage limits, copyright, moderation) before allowing uploads.
-- 5. Verify medical/supplement claims and adverse effect disclaimers.
-- 6. Run Supabase security advisors, test backup/restore and RLS policies.
