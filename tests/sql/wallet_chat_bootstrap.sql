-- Minimal, fake Supabase dependencies for an isolated PostgreSQL 17 CI test.
create role anon nologin;
create role authenticated nologin;
create role service_role nologin bypassrls;
create schema auth;
grant usage on schema auth to authenticated;
create table auth.users (
  id uuid primary key,
  raw_app_meta_data jsonb not null default '{}'::jsonb
);
create function auth.uid() returns uuid language sql stable as $$
  select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid
$$;
grant execute on function auth.uid() to authenticated;
create table public.stores (
  id uuid primary key,
  owner_id uuid not null references auth.users(id),
  status text not null check(status in ('pending','approved','suspended'))
);
alter table public.stores enable row level security;
grant select on public.stores to authenticated;
create policy fixture_public_store_read on public.stores
for select to authenticated using (
  status='approved' or owner_id=(select auth.uid())
);
create function public.shitreed_is_admin() returns boolean
language sql stable security definer set search_path='' as $$
  select exists (
    select 1 from auth.users u
    where u.id=(select auth.uid())
      and u.raw_app_meta_data->>'shitreed_role'='admin'
  )
$$;
revoke all on function public.shitreed_is_admin() from public,anon,authenticated;
grant execute on function public.shitreed_is_admin() to authenticated;
