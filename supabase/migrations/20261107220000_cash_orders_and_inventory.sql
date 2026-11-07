-- Shitreed real-commerce foundation: non-destructive migration.
-- Only apply to dedicated Supabase project ltwncrewggdrjevakwpb.
alter table public.products
  add column if not exists stock_quantity integer not null default 0;
alter table public.products
  add constraint products_stock_nonnegative check (stock_quantity >= 0);
grant insert (stock_quantity), update (stock_quantity)
  on public.products to authenticated;

create table public.orders (
  id uuid primary key default gen_random_uuid(),
  buyer_id uuid not null references auth.users(id) on delete restrict,
  store_id uuid not null references public.stores(id) on delete restrict,
  status text not null default 'placed'
    check (status in ('placed', 'accepted', 'preparing', 'ready', 'rejected', 'cancelled')),
  payment_method text not null default 'cash_on_delivery'
    check (payment_method = 'cash_on_delivery'),
  delivery_address text not null check (char_length(delivery_address) between 8 and 300),
  phone text not null check (char_length(phone) between 8 and 25),
  notes text not null default '' check (char_length(notes) <= 400),
  total_iqd bigint not null check (total_iqd >= 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.order_items (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders(id) on delete restrict,
  product_id uuid not null references public.products(id) on delete restrict,
  product_name text not null,
  unit_price_iqd integer not null check (unit_price_iqd >= 0),
  quantity integer not null check (quantity between 1 and 20),
  line_total_iqd bigint not null check (line_total_iqd >= 0)
);

create index orders_buyer_date_idx on public.orders(buyer_id, created_at desc);
create index orders_store_date_idx on public.orders(store_id, created_at desc);
create index order_items_order_id_idx on public.order_items(order_id);
create index order_items_product_id_idx on public.order_items(product_id);

alter table public.orders enable row level security;
alter table public.order_items enable row level security;
revoke all on public.orders, public.order_items from anon, authenticated;
grant select on public.orders, public.order_items to authenticated;

create policy "buyers and merchants read their orders"
  on public.orders for select to authenticated
  using (
    buyer_id = (select auth.uid()) or
    exists (select 1 from public.stores s
      where s.id = orders.store_id and s.owner_id = (select auth.uid()))
  );

create policy "buyers and merchants read purchased items"
  on public.order_items for select to authenticated
  using (
    exists (
      select 1 from public.orders o
      where o.id = order_items.order_id
    )
  );

-- Prices, stock deduction and final totals are decided in one Postgres
-- transaction, never trusted from a mobile app payload.
create or replace function public.place_cash_order(
  p_store_id uuid,
  p_items jsonb,
  p_delivery_address text,
  p_phone text,
  p_notes text default ''
) returns uuid
language plpgsql security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
  v_order uuid;
  v_item jsonb;
  v_product public.products%rowtype;
  v_id uuid;
  v_quantity integer;
  v_total bigint := 0;
  v_seen uuid[] := array[]::uuid[];
begin
  if v_user is null then
    raise exception 'LOGIN_REQUIRED';
  end if;
  if not exists (select 1 from public.stores
    where id = p_store_id and status = 'approved') then
    raise exception 'STORE_NOT_AVAILABLE';
  end if;
  if p_delivery_address is null or
       char_length(trim(p_delivery_address)) not between 8 and 300 or
       p_phone is null or char_length(trim(p_phone)) not between 8 and 25 or
       p_notes is null or char_length(p_notes) > 400 then
    raise exception 'INVALID_DELIVERY_DETAILS';
  end if;
  if p_items is null or jsonb_typeof(p_items) <> 'array'
       or jsonb_array_length(p_items) not between 1 and 20 then
    raise exception 'INVALID_ITEMS';
  end if;

  insert into public.orders
    (buyer_id, store_id, delivery_address, phone, notes, total_iqd)
  values
    (v_user, p_store_id, trim(p_delivery_address), trim(p_phone),
      trim(p_notes), 0)
  returning id into v_order;

  for v_item in select value from jsonb_array_elements(p_items) loop
    if jsonb_typeof(v_item) <> 'object' then
      raise exception 'INVALID_ITEM';
    end if;
    v_id := (v_item ->> 'product_id')::uuid;
    v_quantity := (v_item ->> 'quantity')::integer;
    if v_id is null or v_quantity is null or
         v_quantity not between 1 and 20 or v_id = any(v_seen) then
      raise exception 'INVALID_OR_DUPLICATE_ITEM';
    end if;
    v_seen := array_append(v_seen, v_id);
    select * into v_product from public.products
      where id = v_id and store_id = p_store_id and is_active = true
      for update;
    if not found then
      raise exception 'PRODUCT_UNAVAILABLE';
    end if;
    if v_product.stock_quantity < v_quantity then
      raise exception 'OUT_OF_STOCK';
    end if;
    update public.products
      set stock_quantity = stock_quantity - v_quantity where id = v_id;
    insert into public.order_items
      (order_id, product_id, product_name, unit_price_iqd,
        quantity, line_total_iqd)
    values
      (v_order, v_id, v_product.name, v_product.price_iqd,
        v_quantity, v_product.price_iqd::bigint * v_quantity);
    v_total := v_total + v_product.price_iqd::bigint * v_quantity;
  end loop;
  update public.orders set total_iqd = v_total where id = v_order;
  return v_order;
end;
$$;

-- Rejected/cancelled orders restore inventory exactly once. No direct
-- order status update is granted to client roles.
create or replace function public.change_cash_order_status(
  p_order_id uuid, p_new_status text
) returns text
language plpgsql security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
  v_order public.orders%rowtype;
  v_owner uuid;
begin
  if v_user is null then raise exception 'LOGIN_REQUIRED'; end if;
  select * into v_order from public.orders where id = p_order_id for update;
  if not found then raise exception 'ORDER_NOT_FOUND'; end if;
  select owner_id into v_owner from public.stores where id = v_order.store_id;
  if v_user = v_order.buyer_id then
    if not (v_order.status = 'placed' and p_new_status = 'cancelled') then
      raise exception 'INVALID_BUYER_TRANSITION';
    end if;
  elsif v_user = v_owner then
    if not (
      (v_order.status = 'placed' and p_new_status in ('accepted', 'rejected')) or
      (v_order.status = 'accepted' and p_new_status = 'preparing') or
      (v_order.status = 'preparing' and p_new_status = 'ready')
    ) then
      raise exception 'INVALID_MERCHANT_TRANSITION';
    end if;
  else
    raise exception 'PERMISSION_DENIED';
  end if;
  if p_new_status in ('cancelled', 'rejected') then
    update public.products p
      set stock_quantity = p.stock_quantity + i.quantity
      from public.order_items i
      where i.order_id = v_order.id and p.id = i.product_id;
  end if;
  update public.orders set status = p_new_status,
    updated_at = now() where id = v_order.id;
  return p_new_status;
end;
$$;

revoke all on function public.place_cash_order(uuid,jsonb,text,text,text)
  from public, anon, authenticated;
grant execute on function public.place_cash_order(uuid,jsonb,text,text,text)
  to authenticated;
revoke all on function public.change_cash_order_status(uuid,text)
  from public, anon, authenticated;
grant execute on function public.change_cash_order_status(uuid,text)
  to authenticated;
