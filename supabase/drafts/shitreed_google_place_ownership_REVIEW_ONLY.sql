-- DRAFT / REVIEW ONLY — NOT EXECUTED ON PRODUCTION
-- Google Places place ID is the only Google-derived field stored here.
-- Do not copy Google business names, reviews, hours, photos or coordinates.
-- Requires authorized review workflow, private evidence storage and migrations testing.

create table if not exists public.shitreed_place_claims (
  id uuid primary key default gen_random_uuid(),
  store_id uuid not null references public.stores(id),
  google_place_id text not null
    check (char_length(google_place_id) between 4 and 512),
  claimant_id uuid not null default auth.uid() references auth.users(id),
  evidence_private_ref text not null
    check (char_length(evidence_private_ref) between 8 and 500),
  status text not null default 'pending'
    check (status in ('pending', 'approved', 'rejected', 'disputed', 'withdrawn')),
  reviewer_id uuid references auth.users(id),
  review_reason text,
  created_at timestamptz not null default now(),
  reviewed_at timestamptz
);
-- Prevent simultaneous duplicate claims from the SAME merchant.
-- Different merchants may dispute the same Google place; approved linking is unique.
create unique index if not exists shitreed_claim_open_per_store_place
  on public.shitreed_place_claims(store_id,google_place_id)
  where status in ('pending','approved');
create index if not exists shitreed_claim_admin_queue
  on public.shitreed_place_claims(status,created_at);

alter table public.shitreed_place_claims enable row level security;
revoke all on table public.shitreed_place_claims from public, anon, authenticated;
grant select (id,store_id,google_place_id,status,created_at,reviewed_at,review_reason)
  on public.shitreed_place_claims to authenticated;
grant insert (store_id,google_place_id,evidence_private_ref)
  on public.shitreed_place_claims to authenticated;

drop policy if exists "Read own place claims" on public.shitreed_place_claims;
create policy "Read own place claims" on public.shitreed_place_claims
  for select to authenticated
  using (claimant_id=(select auth.uid()));

drop policy if exists "Owners request claim for own stores"
  on public.shitreed_place_claims;
create policy "Owners request claim for own stores" on public.shitreed_place_claims
  for insert to authenticated
  with check (
    claimant_id=(select auth.uid())
    and status='pending' and reviewer_id is null and reviewed_at is null
    and exists (
      select 1 from public.stores s
      where s.id=store_id and s.owner_id=(select auth.uid())
    )
  );
-- Do not give clients UPDATE/DELETE on the claims.
-- A privileged server RPC must review claims with MFA/role checks, audit and
-- check the claimed Google Place ID against fresh Places API data and evidence.

create table if not exists public.shitreed_verified_place_links (
  google_place_id text primary key
    check (char_length(google_place_id) between 4 and 512),
  store_id uuid not null references public.stores(id),
  claim_id uuid not null unique references public.shitreed_place_claims(id),
  linked_by uuid not null references auth.users(id),
  linked_at timestamptz not null default now()
);
alter table public.shitreed_verified_place_links enable row level security;
revoke all on table public.shitreed_verified_place_links
  from public, anon, authenticated;
grant select (google_place_id,store_id) on public.shitreed_verified_place_links
  to anon, authenticated;
drop policy if exists "View links for approved stores"
  on public.shitreed_verified_place_links;
create policy "View links for approved stores"
  on public.shitreed_verified_place_links for select to anon, authenticated
  using (exists (
    select 1 from public.stores s
    where s.id=store_id and s.status='approved'
  ));
-- Never assume a merchant is verified just because the Place ID was submitted.
-- The admin review handler must atomically verify proof, reject conflicts,
-- update the claims status, link the approved store, and record its audit.
