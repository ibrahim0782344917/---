-- Shitreed marketplace foundation: non-destructive, dedicated-project migration.
-- Run ONLY on the new Shitreed Supabase project after confirming the target.
create extension if not exists pgcrypto with schema extensions;

create table if not exists public.customer_profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null default '' check (char_length(display_name) <= 80),
  created_at timestamptz not null default now()
);

create table if not exists public.stores (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users(id) on delete restrict,
  name text not null check (char_length(name) between 2 and 120),
  area text not null check (char_length(area) between 2 and 100),
  category text not null default 'متاجر' check (char_length(category) <= 80),
  address text not null default '' check (char_length(address) <= 300),
  phone text check (phone is null or char_length(phone) <= 30),
  latitude double precision check (latitude is null or latitude between -90 and 90),
  longitude double precision check (longitude is null or longitude between -180 and 180),
  status text not null default 'pending'
    check (status in ('pending', 'approved', 'suspended')),
  created_at timestamptz not null default now()
);

create table if not exists public.products (
  id uuid primary key default gen_random_uuid(),
  store_id uuid not null references public.stores(id) on delete cascade,
  name text not null check (char_length(name) between 2 and 160),
  description text not null default '' check (char_length(description) <= 3000),
  price_iqd integer not null check (price_iqd >= 0),
  image_url text,
  is_active boolean not null default false,
  created_at timestamptz not null default now()
);

create index if not exists stores_area_status_idx
  on public.stores(area, status);
create index if not exists products_store_active_idx
  on public.products(store_id, is_active);

alter table public.customer_profiles enable row level security;
alter table public.stores enable row level security;
alter table public.products enable row level security;

-- No client permissions beyond these narrow column grants.
revoke all on public.customer_profiles from anon, authenticated;
revoke all on public.stores from anon, authenticated;
revoke all on public.products from anon, authenticated;

grant select on public.customer_profiles to authenticated;
grant update (display_name) on public.customer_profiles to authenticated;

grant select on public.stores to anon, authenticated;
grant insert (owner_id, name, area, category, address, phone, latitude, longitude)
  on public.stores to authenticated;
grant update (name, area, category, address, phone, latitude, longitude)
  on public.stores to authenticated;

grant select on public.products to anon, authenticated;
grant insert (store_id, name, description, price_iqd, image_url, is_active)
  on public.products to authenticated;
grant update (name, description, price_iqd, image_url, is_active)
  on public.products to authenticated;

create policy "customers can view own profile"
  on public.customer_profiles for select to authenticated
  using ((select auth.uid()) = id);

create policy "customers can edit own display name"
  on public.customer_profiles for update to authenticated
  using ((select auth.uid()) = id)
  with check ((select auth.uid()) = id);

-- A store is publicly visible only after manual approval.
create policy "approved stores are publicly visible"
  on public.stores for select to anon, authenticated
  using (status = 'approved');

create policy "merchants can read their stores"
  on public.stores for select to authenticated
  using (owner_id = (select auth.uid()));

create policy "merchants can submit pending stores"
  on public.stores for insert to authenticated
  with check (owner_id = (select auth.uid()) and status = 'pending');

create policy "merchants can edit their store details only"
  on public.stores for update to authenticated
  using (owner_id = (select auth.uid()))
  with check (owner_id = (select auth.uid()));

-- Products appear publicly only in approved stores and when active.
create policy "active products of approved stores are public"
  on public.products for select to anon, authenticated
  using (is_active = true and exists (
    select 1 from public.stores s
    where s.id = products.store_id and s.status = 'approved'
  ));

create policy "merchants can read own products"
  on public.products for select to authenticated
  using (exists (
    select 1 from public.stores s
    where s.id = products.store_id and s.owner_id = (select auth.uid())
  ));

create policy "merchants can add products to own stores"
  on public.products for insert to authenticated
  with check (exists (
    select 1 from public.stores s
    where s.id = products.store_id and s.owner_id = (select auth.uid())
  ));

create policy "merchants can edit products of own stores"
  on public.products for update to authenticated
  using (exists (
    select 1 from public.stores s
    where s.id = products.store_id and s.owner_id = (select auth.uid())
  ))
  with check (exists (
    select 1 from public.stores s
    where s.id = products.store_id and s.owner_id = (select auth.uid())
  ));

-- Auth trigger only copies a non-privileged display name from metadata.
create or replace function public.create_customer_profile()
returns trigger language plpgsql security definer set search_path = ''
as $$
begin
  insert into public.customer_profiles(id, display_name)
  values (
    new.id,
    left(coalesce(new.raw_user_meta_data ->> 'display_name', ''), 80)
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_shitreed_customer_created on auth.users;
create trigger on_shitreed_customer_created
  after insert on auth.users
  for each row execute function public.create_customer_profile();

revoke all on function public.create_customer_profile() from public;

-- No orders/payment write endpoints yet: price and inventory must be calculated
-- on a trusted server, never accepted directly from an untrusted mobile client.
