-- Disposable PostgreSQL 17 fixture. NO real or copied user records.
-- This creates a minimal Supabase-compatible auth.uid() test shim
-- and exact table columns used by docs/ALANI_DELIVERY_COD_STAGE_ONLY_SQL.sql.
create schema auth;
create function auth.uid() returns uuid
  language sql stable
  as $$ select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid $$;

create role anon nologin;
create role authenticated nologin;

create table public.stores (
  id uuid primary key,
  owner_id uuid not null,
  status text not null
);
create table public.products (
  id uuid primary key,
  store_id uuid not null references public.stores(id),
  name text not null,
  price_iqd integer not null check (price_iqd>=0),
  stock_quantity integer not null check (stock_quantity>=0),
  is_active boolean not null default false
);
create table public.orders (
  id uuid primary key default gen_random_uuid(),
  buyer_id uuid not null,
  store_id uuid not null references public.stores(id),
  delivery_address text not null,
  phone text not null,
  notes text not null default '',
  total_iqd bigint not null default 0,
  status text not null default 'placed'
);
create table public.order_items (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders(id),
  product_id uuid not null references public.products(id),
  product_name text not null,
  unit_price_iqd integer not null,
  quantity integer not null,
  line_total_iqd bigint not null
);

insert into public.stores(id,owner_id,status) values
 ('25091ca2-c0da-416c-b634-81b188ee66be','99999999-9999-4999-8999-999999999999','approved'),
 ('33333333-3333-4333-8333-333333333333','88888888-8888-4888-8888-888888888888','approved');
insert into public.products(id,store_id,name,price_iqd,stock_quantity,is_active) values
 ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','25091ca2-c0da-416c-b634-81b188ee66be','عسل اختبار',10000,10,true),
 ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb','33333333-3333-4333-8333-333333333333','منتج تاجر آخر',7000,5,true);
