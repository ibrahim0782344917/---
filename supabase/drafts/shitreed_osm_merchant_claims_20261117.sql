-- Shitreed: merchant OSM-place claim application. No auto-verification.
-- Claims are separate from stores and do not change approval or product access.
create table if not exists public.shitreed_osm_claim_requests (
  id uuid primary key default gen_random_uuid(),
  store_id uuid not null references public.stores(id),
  osm_object_id text not null check (
    osm_object_id ~ '^(node|way|relation)/[1-9][0-9]{0,17}$'
  ),
  claimant_id uuid not null default auth.uid() references auth.users(id),
  note text not null check (char_length(btrim(note)) between 12 and 600),
  status text not null default 'pending'
    check (status in ('pending','approved','rejected','disputed','withdrawn')),
  reviewer_id uuid references auth.users(id),
  review_reason text,
  created_at timestamptz not null default now(),
  reviewed_at timestamptz
);
create unique index if not exists shitreed_pending_osm_claim_unique
  on public.shitreed_osm_claim_requests(store_id,osm_object_id)
  where status='pending';
create index if not exists shitreed_osm_claim_queue
  on public.shitreed_osm_claim_requests(status,created_at);
alter table public.shitreed_osm_claim_requests enable row level security;
revoke all on public.shitreed_osm_claim_requests from public,anon,authenticated;
grant select (id,store_id,osm_object_id,note,status,review_reason,created_at,reviewed_at)
  on public.shitreed_osm_claim_requests to authenticated;
grant insert (store_id,osm_object_id,note)
  on public.shitreed_osm_claim_requests to authenticated;
drop policy if exists "Merchants read own OSM claims"
  on public.shitreed_osm_claim_requests;
create policy "Merchants read own OSM claims"
  on public.shitreed_osm_claim_requests for select to authenticated
  using (claimant_id=(select auth.uid()));
drop policy if exists "Owners submit pending OSM claims"
  on public.shitreed_osm_claim_requests;
create policy "Owners submit pending OSM claims"
  on public.shitreed_osm_claim_requests for insert to authenticated
  with check (
    claimant_id=(select auth.uid())
    and status='pending'
    and reviewer_id is null and reviewed_at is null
    and exists (
      select 1 from public.stores s
      where s.id=store_id and s.owner_id=(select auth.uid())
    )
  );
-- No update/delete policy. Administrator will review separately with
-- server-side role + evidence verification + audit before approval.
