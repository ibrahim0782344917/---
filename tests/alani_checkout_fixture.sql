-- Disposable PG16 ONLY. No actual Supabase data or keys.
create role anon nologin;
create role authenticated nologin;
create schema auth;
create schema private_checkout;
create function auth.uid() returns uuid language sql stable
as $$ select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid $$;
grant usage on schema auth to anon,authenticated;
grant execute on function auth.uid() to anon,authenticated;

create table public.stores (
  id uuid primary key,
  owner_id uuid not null,
  status text not null
);
create table public.products (
  id uuid primary key,
  store_id uuid not null references public.stores(id),
  name text not null,
  price_iqd integer not null,
  stock_quantity integer not null,
  is_active boolean not null default true
);
create table public.orders (
  id uuid primary key default gen_random_uuid(),
  buyer_id uuid not null,
  store_id uuid not null references public.stores(id),
  status text not null default 'placed',
  payment_method text not null default 'cash_on_delivery',
  delivery_address text not null,
  phone text not null,
  notes text not null default '',
  total_iqd bigint not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
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
create table private_checkout.web_checkout_requests (
  buyer_id uuid not null,
  request_key uuid not null,
  payload_hash text not null,
  order_id uuid not null references public.orders(id),
  primary key (buyer_id,request_key)
);

insert into public.stores(id,owner_id,status) values
 ('25091ca2-c0da-416c-b634-81b188ee66be','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','approved'),
 ('22222222-2222-4222-8222-222222222222','bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb','approved');
insert into public.products(id,store_id,name,price_iqd,stock_quantity) values
 ('11111111-1111-4111-8111-111111111111','25091ca2-c0da-416c-b634-81b188ee66be','زيت',20000,5),
 ('22222222-2222-4222-8222-222222222221','25091ca2-c0da-416c-b634-81b188ee66be','عسل',5000,8),
 ('33333333-3333-4333-8333-333333333331','22222222-2222-4222-8222-222222222222','منتج آخر',7000,5);
-- Synthetic read permissions match buyer-visible order reads in the live
-- application. Live Supabase uses RLS to further enforce ownership.
grant select on public.orders,public.order_items,public.products
  to authenticated;

-- Historical order must NOT be retroactively increased by delivery fee.
insert into public.orders (id,buyer_id,store_id,delivery_address,phone,total_iqd)
values ('f0000000-0000-4000-8000-000000000001',
 'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
 '25091ca2-c0da-416c-b634-81b188ee66be',
 'عنوان قديم في بغداد','07700000000',9500);
