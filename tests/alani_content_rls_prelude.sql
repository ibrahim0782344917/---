-- Disposable GitHub Actions Postgres only. This is not a production migration.
create role anon nologin;
create role authenticated nologin;
create schema auth;
create function auth.uid() returns uuid language sql stable as $$
  select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid
$$;
grant usage on schema auth to anon,authenticated;
grant execute on function auth.uid() to anon,authenticated;

-- Minimal test fixtures approximating the store/product FK contracts.
create table public.stores (
  id uuid primary key,
  owner_id uuid not null,
  status text not null
);
create table public.products (
  id uuid primary key,
  store_id uuid not null references public.stores(id)
);
grant select on public.stores,public.products to anon,authenticated;

insert into public.stores(id,owner_id,status) values
('25091ca2-c0da-416c-b634-81b188ee66be',
 '11111111-1111-4111-8111-111111111111','approved'),
('22222222-2222-4222-8222-222222222222',
 '33333333-3333-4333-8333-333333333333','approved'),
('44444444-4444-4444-8444-444444444444',
 '11111111-1111-4111-8111-111111111111','pending');
