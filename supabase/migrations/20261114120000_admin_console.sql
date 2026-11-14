-- Shitreed administrator console. Apply only after verified_store_review.
-- Not applied automatically by this pull request; review/test on staging first.
-- Staff roles are server-side only, never sourced from raw_user_meta_data.
create table if not exists public.shitreed_admin_staff (
  user_id uuid primary key references auth.users(id) on delete restrict,
  staff_role text not null check (staff_role in
    ('operations', 'merchant_reviewer', 'catalog_manager', 'support', 'viewer')),
  enabled boolean not null default true,
  assigned_by uuid not null references auth.users(id) on delete restrict,
  updated_at timestamptz not null default now()
);

create table if not exists public.shitreed_admin_activity (
  id bigint generated always as identity primary key,
  actor_id uuid not null references auth.users(id) on delete restrict,
  section text not null,
  entity_id uuid,
  action text not null,
  before_state text,
  after_state text,
  reason text not null check (char_length(reason) between 12 and 1000),
  created_at timestamptz not null default now()
);
create index if not exists shitreed_admin_activity_created_idx
  on public.shitreed_admin_activity(created_at desc);
create index if not exists shitreed_admin_activity_actor_idx
  on public.shitreed_admin_activity(actor_id, created_at desc);
alter table public.shitreed_admin_staff enable row level security;
alter table public.shitreed_admin_activity enable row level security;
revoke all on public.shitreed_admin_staff, public.shitreed_admin_activity
  from public, anon, authenticated;
revoke all on sequence public.shitreed_admin_activity_id_seq
  from public, anon, authenticated;

-- Only trusted Auth app metadata can bootstrap the first super administrator.
-- Non-super administrators are assigned through the audited RPC below.
create or replace function public.shitreed_admin_role()
returns text language plpgsql stable security definer
set search_path = ''
as $$
declare v_uid uuid := (select auth.uid());
declare v_role text;
begin
  if v_uid is null then return null; end if;
  if exists (
    select 1 from auth.users u
    where u.id = v_uid
      and u.raw_app_meta_data ->> 'shitreed_role' = 'admin'
  ) then
    return 'super_admin';
  end if;
  select s.staff_role into v_role from public.shitreed_admin_staff s
    where s.user_id = v_uid and s.enabled = true;
  return v_role;
end;
$$;
revoke all on function public.shitreed_admin_role() from public, anon, authenticated;
grant execute on function public.shitreed_admin_role() to authenticated;

create or replace function public.shitreed_admin_dashboard()
returns jsonb language plpgsql stable security definer
set search_path = ''
as $$
declare
  v_role text := public.shitreed_admin_role();
begin
  if v_role is null then raise exception 'ADMIN_ACCESS_REQUIRED'; end if;
  return jsonb_build_object(
    'stores', (select count(*) from public.stores),
    'pending_stores', (select count(*) from public.stores where status = 'pending'),
    'approved_stores', (select count(*) from public.stores where status = 'approved'),
    'products', (select count(*) from public.products),
    'active_products', (select count(*) from public.products where is_active = true),
    'orders', (select count(*) from public.orders),
    'open_orders', (select count(*) from public.orders
      where status in ('placed','accepted','preparing','ready')),
    'order_value_iqd', (select coalesce(sum(total_iqd),0) from public.orders
      where status not in ('cancelled','rejected')),
    'customers', (select count(*) from public.customer_profiles)
  );
end;
$$;
revoke all on function public.shitreed_admin_dashboard()
  from public, anon, authenticated;
grant execute on function public.shitreed_admin_dashboard() to authenticated;

-- Explicit branches avoid SQL string concatenation and arbitrary table reads.
-- Only necessary fields are projected; order contact details are support-only.
create or replace function public.shitreed_admin_rows(
  p_section text, p_limit integer default 30, p_offset integer default 0
) returns jsonb language plpgsql stable security definer
set search_path = ''
as $$
declare
  v_role text := public.shitreed_admin_role();
  v_items jsonb := '[]'::jsonb;
begin
  if v_role is null then raise exception 'ADMIN_ACCESS_REQUIRED'; end if;
  if p_limit not between 1 and 100 or p_offset < 0 or p_offset > 100000 then
    raise exception 'INVALID_PAGINATION';
  end if;
  if p_section = 'stores' then
    select coalesce(jsonb_agg(to_jsonb(x)), '[]'::jsonb) into v_items
    from (
      select id, owner_id, name, area, category, address, phone,
        status, latitude, longitude, created_at from public.stores
      order by created_at desc, id limit p_limit offset p_offset
    ) x;
  elsif p_section = 'products' then
    select coalesce(jsonb_agg(to_jsonb(x)), '[]'::jsonb) into v_items
    from (
      select id, store_id, name, price_iqd, stock_quantity,
        is_active, created_at from public.products
      order by created_at desc, id limit p_limit offset p_offset
    ) x;
  elsif p_section = 'orders' and
    v_role in ('super_admin','operations','support') then
    select coalesce(jsonb_agg(to_jsonb(x)), '[]'::jsonb) into v_items
    from (
      select id, buyer_id, store_id, status, payment_method, total_iqd,
        delivery_address, phone, created_at, updated_at from public.orders
      order by created_at desc, id limit p_limit offset p_offset
    ) x;
  elsif p_section = 'customers' and
    v_role in ('super_admin','operations','support') then
    select coalesce(jsonb_agg(to_jsonb(x)), '[]'::jsonb) into v_items
    from (
      select id, display_name, created_at from public.customer_profiles
      order by created_at desc, id limit p_limit offset p_offset
    ) x;
  elsif p_section = 'staff' and v_role = 'super_admin' then
    select coalesce(jsonb_agg(to_jsonb(x)), '[]'::jsonb) into v_items
    from (
      select user_id, staff_role, enabled, assigned_by, updated_at
      from public.shitreed_admin_staff
      order by updated_at desc, user_id limit p_limit offset p_offset
    ) x;
  elsif p_section = 'audit' and v_role in ('super_admin','operations') then
    select coalesce(jsonb_agg(to_jsonb(x)), '[]'::jsonb) into v_items
    from (
      select id, actor_id, section, entity_id, action, before_state,
        after_state, reason, created_at from public.shitreed_admin_activity
      order by created_at desc, id desc limit p_limit offset p_offset
    ) x;
  else
    raise exception 'SECTION_NOT_ALLOWED';
  end if;
  return jsonb_build_object('items', v_items, 'limit', p_limit, 'offset', p_offset);
end;
$$;
revoke all on function public.shitreed_admin_rows(text,integer,integer)
  from public, anon, authenticated;
grant execute on function public.shitreed_admin_rows(text,integer,integer)
  to authenticated;

-- Soft moderation only: no destructive customer, store or order deletion.
-- Inventory is restored once under the same order lock used by merchant RPCs.
create or replace function public.shitreed_admin_change(
  p_section text, p_id uuid, p_action text, p_reason text
) returns text language plpgsql security definer
set search_path = ''
as $$
declare
  v_role text := public.shitreed_admin_role();
  v_actor uuid := auth.uid();
  v_store public.stores%rowtype;
  v_product public.products%rowtype;
  v_order public.orders%rowtype;
  v_old text;
  v_next text;
begin
  if v_role is null then raise exception 'ADMIN_ACCESS_REQUIRED'; end if;
  if p_id is null or p_reason is null or
     char_length(btrim(p_reason)) not between 12 and 1000 then
    raise exception 'VALID_REASON_REQUIRED';
  end if;
  if p_section = 'stores' and v_role in
    ('super_admin','operations','merchant_reviewer') then
    select * into v_store from public.stores where id = p_id for update;
    if not found then raise exception 'STORE_NOT_FOUND'; end if;
    v_old := v_store.status;
    if p_action = 'approve' and v_old = 'pending' then
      if char_length(btrim(v_store.address)) < 8 then
        raise exception 'STORE_DETAILS_INCOMPLETE';
      end if;
      v_next := 'approved';
    elsif p_action = 'suspend' and v_old = 'approved' then
      v_next := 'suspended';
    elsif p_action = 'reopen' and v_old = 'suspended' then
      v_next := 'pending';
    else
      raise exception 'INVALID_STORE_TRANSITION';
    end if;
    update public.stores set status = v_next where id = p_id;
  elsif p_section = 'products' and v_role in
    ('super_admin','operations','catalog_manager') then
    select * into v_product from public.products where id = p_id for update;
    if not found then raise exception 'PRODUCT_NOT_FOUND'; end if;
    v_old := case when v_product.is_active then 'active' else 'inactive' end;
    if p_action = 'disable' and v_product.is_active then
      v_next := 'inactive';
      update public.products set is_active = false where id = p_id;
    elsif p_action = 'enable' and not v_product.is_active then
      if not exists (select 1 from public.stores s
        where s.id = v_product.store_id and s.status = 'approved') then
        raise exception 'STORE_NOT_APPROVED';
      end if;
      v_next := 'active';
      update public.products set is_active = true where id = p_id;
    else
      raise exception 'INVALID_PRODUCT_TRANSITION';
    end if;
  elsif p_section = 'orders' and v_role in
    ('super_admin','operations','support') then
    select * into v_order from public.orders where id = p_id for update;
    if not found then raise exception 'ORDER_NOT_FOUND'; end if;
    v_old := v_order.status;
    if p_action = 'accept' and v_old = 'placed' then
      v_next := 'accepted';
    elsif p_action = 'prepare' and v_old = 'accepted' then
      v_next := 'preparing';
    elsif p_action = 'ready' and v_old = 'preparing' then
      v_next := 'ready';
    elsif p_action = 'reject' and v_old = 'placed' then
      v_next := 'rejected';
    elsif p_action = 'cancel' and v_old in ('placed','accepted','preparing') then
      v_next := 'cancelled';
    else
      raise exception 'INVALID_ORDER_TRANSITION';
    end if;
    if v_next in ('cancelled','rejected') then
      update public.products p
        set stock_quantity = p.stock_quantity + i.quantity
        from public.order_items i
        where i.order_id = p_id and i.product_id = p.id;
    end if;
    update public.orders set status = v_next, updated_at = now()
      where id = p_id;
  else
    raise exception 'ACTION_NOT_ALLOWED';
  end if;
  insert into public.shitreed_admin_activity
    (actor_id, section, entity_id, action, before_state, after_state, reason)
    values (v_actor, p_section, p_id, p_action, v_old, v_next, btrim(p_reason));
  return v_next;
end;
$$;
revoke all on function public.shitreed_admin_change(text,uuid,text,text)
  from public, anon, authenticated;
grant execute on function public.shitreed_admin_change(text,uuid,text,text)
  to authenticated;

-- Bootstrap super admins cannot be changed here: change their trusted
-- app_metadata in the Supabase dashboard using a privileged service session.
create or replace function public.shitreed_admin_set_staff(
  p_user_id uuid, p_role text, p_enabled boolean, p_reason text
) returns text language plpgsql security definer
set search_path = ''
as $$
declare v_old text;
declare v_next text;
begin
  if public.shitreed_admin_role() is distinct from 'super_admin' then
    raise exception 'SUPER_ADMIN_REQUIRED';
  end if;
  if p_user_id is null or p_user_id = auth.uid() then
    raise exception 'INVALID_STAFF_MEMBER';
  end if;
  if p_role not in
     ('operations','merchant_reviewer','catalog_manager','support','viewer')
     or p_enabled is null or p_reason is null or
     char_length(btrim(p_reason)) not between 12 and 1000 then
    raise exception 'INVALID_STAFF_ASSIGNMENT';
  end if;
  if not exists (select 1 from auth.users where id = p_user_id) then
    raise exception 'USER_NOT_FOUND';
  end if;
  if exists (select 1 from auth.users u where u.id = p_user_id
    and u.raw_app_meta_data ->> 'shitreed_role' = 'admin') then
    raise exception 'BOOTSTRAP_ADMIN_CANNOT_BE_CHANGED_HERE';
  end if;
  select staff_role || ':' || enabled::text into v_old
    from public.shitreed_admin_staff where user_id = p_user_id for update;
  insert into public.shitreed_admin_staff
    (user_id, staff_role, enabled, assigned_by, updated_at)
  values (p_user_id, p_role, p_enabled, auth.uid(), now())
  on conflict (user_id) do update
    set staff_role = excluded.staff_role,
        enabled = excluded.enabled,
        assigned_by = excluded.assigned_by,
        updated_at = now();
  v_next := p_role || ':' || p_enabled::text;
  insert into public.shitreed_admin_activity
    (actor_id, section, entity_id, action, before_state, after_state, reason)
    values (auth.uid(), 'staff', p_user_id, 'set_staff', v_old, v_next,
      btrim(p_reason));
  return v_next;
end;
$$;
revoke all on function public.shitreed_admin_set_staff(uuid,text,boolean,text)
  from public, anon, authenticated;
grant execute on function public.shitreed_admin_set_staff(uuid,text,boolean,text)
  to authenticated;
