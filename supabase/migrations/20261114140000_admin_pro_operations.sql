-- Shitreed Admin Pro: searchable operations, order detail, safe inventory/price controls.
-- All RPCs authenticate against trusted server-side role data; no direct table grants.
create or replace function public.shitreed_admin_search(
  p_section text, p_search text default '', p_filter text default '',
  p_limit integer default 25, p_offset integer default 0
) returns jsonb language plpgsql stable security definer
set search_path = ''
as $$
declare
  v_role text := public.shitreed_admin_role();
  v_search text := btrim(coalesce(p_search,''));
  v_filter text := coalesce(p_filter,'');
  v_total bigint := 0;
  v_items jsonb := '[]'::jsonb;
begin
  if v_role is null then raise exception 'ADMIN_ACCESS_REQUIRED'; end if;
  if p_limit is null or p_limit not between 1 and 50
     or p_offset is null or p_offset not between 0 and 100000
     or char_length(v_search)>80 or char_length(v_filter)>30 then
    raise exception 'INVALID_SEARCH_ARGUMENTS';
  end if;
  if p_section = 'stores' then
    if v_filter not in ('','pending','approved','suspended') then
      raise exception 'INVALID_FILTER';
    end if;
    with matched as (
      select id,owner_id,name,area,category,address,phone,status,
        latitude,longitude,created_at
      from public.stores
      where (v_filter='' or status=v_filter)
        and (v_search='' or name ilike '%'||v_search||'%'
          or area ilike '%'||v_search||'%'
          or category ilike '%'||v_search||'%'
          or id::text ilike '%'||v_search||'%')
    ), page as (
      select * from matched order by created_at desc,id
      limit p_limit offset p_offset
    )
    select (select count(*) from matched),
      coalesce((select jsonb_agg(to_jsonb(page)) from page),'[]'::jsonb)
    into v_total,v_items;
  elsif p_section = 'products' then
    if v_filter not in ('','active','inactive') then
      raise exception 'INVALID_FILTER';
    end if;
    with matched as (
      select id,store_id,name,price_iqd,stock_quantity,is_active,created_at,
        image_url from public.products
      where (v_filter='' or
        (v_filter='active' and is_active=true) or
        (v_filter='inactive' and is_active=false))
        and (v_search='' or name ilike '%'||v_search||'%'
          or id::text ilike '%'||v_search||'%'
          or store_id::text ilike '%'||v_search||'%')
    ), page as (
      select * from matched order by created_at desc,id
      limit p_limit offset p_offset
    )
    select (select count(*) from matched),
      coalesce((select jsonb_agg(to_jsonb(page)) from page),'[]'::jsonb)
    into v_total,v_items;
  elsif p_section='orders' and v_role in
    ('super_admin','operations','support') then
    if v_filter not in
      ('','placed','accepted','preparing','ready','rejected','cancelled') then
      raise exception 'INVALID_FILTER';
    end if;
    with matched as (
      select id,buyer_id,store_id,status,payment_method,total_iqd,
        delivery_address,phone,created_at,updated_at from public.orders
      where (v_filter='' or status=v_filter)
        and (v_search='' or id::text ilike '%'||v_search||'%'
          or store_id::text ilike '%'||v_search||'%'
          or buyer_id::text ilike '%'||v_search||'%'
          or phone ilike '%'||v_search||'%')
    ), page as (
      select * from matched order by created_at desc,id
      limit p_limit offset p_offset
    )
    select (select count(*) from matched),
      coalesce((select jsonb_agg(to_jsonb(page)) from page),'[]'::jsonb)
    into v_total,v_items;
  elsif p_section='customers' and v_role in
    ('super_admin','operations','support') then
    if v_filter<>'' then raise exception 'INVALID_FILTER'; end if;
    with matched as (
      select id,display_name,created_at from public.customer_profiles
      where (v_search='' or display_name ilike '%'||v_search||'%'
        or id::text ilike '%'||v_search||'%')
    ), page as (
      select * from matched order by created_at desc,id
      limit p_limit offset p_offset
    )
    select (select count(*) from matched),
      coalesce((select jsonb_agg(to_jsonb(page)) from page),'[]'::jsonb)
    into v_total,v_items;
  elsif p_section='staff' and v_role='super_admin' then
    if v_filter not in ('','enabled','disabled') then
      raise exception 'INVALID_FILTER';
    end if;
    with matched as (
      select user_id,staff_role,enabled,assigned_by,updated_at
      from public.shitreed_admin_staff
      where (v_filter='' or
        (v_filter='enabled' and enabled=true) or
        (v_filter='disabled' and enabled=false))
        and (v_search='' or user_id::text ilike '%'||v_search||'%'
          or staff_role ilike '%'||v_search||'%')
    ), page as (
      select * from matched order by updated_at desc,user_id
      limit p_limit offset p_offset
    )
    select (select count(*) from matched),
      coalesce((select jsonb_agg(to_jsonb(page)) from page),'[]'::jsonb)
    into v_total,v_items;
  elsif p_section='audit' and v_role in
    ('super_admin','operations') then
    if v_filter not in ('','stores','products','orders','staff','inventory','pricing') then
      raise exception 'INVALID_FILTER';
    end if;
    with matched as (
      select id,actor_id,section,entity_id,action,before_state,
        after_state,reason,created_at
      from public.shitreed_admin_activity
      where (v_filter='' or section=v_filter)
        and (v_search='' or action ilike '%'||v_search||'%'
          or reason ilike '%'||v_search||'%'
          or actor_id::text ilike '%'||v_search||'%')
    ), page as (
      select * from matched order by created_at desc,id desc
      limit p_limit offset p_offset
    )
    select (select count(*) from matched),
      coalesce((select jsonb_agg(to_jsonb(page)) from page),'[]'::jsonb)
    into v_total,v_items;
  else
    raise exception 'SECTION_NOT_ALLOWED';
  end if;
  return jsonb_build_object('items',v_items,'total',v_total,
    'limit',p_limit,'offset',p_offset);
end;
$$;
revoke all on function public.shitreed_admin_search(text,text,text,integer,integer)
  from public,anon,authenticated;
grant execute on function public.shitreed_admin_search(text,text,text,integer,integer)
  to authenticated;

create or replace function public.shitreed_admin_insights()
returns jsonb language plpgsql stable security definer set search_path=''
as $$
declare
 v_role text := public.shitreed_admin_role();
 v_day date;
 v_count bigint;
 v_value bigint;
 v_points jsonb := '[]'::jsonb;
begin
 if v_role is null then raise exception 'ADMIN_ACCESS_REQUIRED'; end if;
 for v_day in select (current_date - n)::date from generate_series(6,0,-1) n loop
   select count(*),coalesce(sum(total_iqd) filter
      (where status not in ('cancelled','rejected')),0)
   into v_count,v_value from public.orders
   where created_at >= v_day::timestamptz
     and created_at < (v_day+1)::timestamptz;
   v_points := v_points || jsonb_build_array(jsonb_build_object(
     'date',v_day::text,'orders',v_count,'order_value_iqd',v_value));
 end loop;
 return jsonb_build_object('daily',v_points,
   'notice','Order value is NOT collected payments or net revenue');
end;
$$;
revoke all on function public.shitreed_admin_insights()
  from public,anon,authenticated;
grant execute on function public.shitreed_admin_insights() to authenticated;

create or replace function public.shitreed_admin_order_detail(p_order_id uuid)
returns jsonb language plpgsql stable security definer set search_path=''
as $$
declare
 v_role text := public.shitreed_admin_role();
 v_order jsonb;
begin
 if v_role not in ('super_admin','operations','support') or v_role is null
   then raise exception 'ADMIN_ACCESS_REQUIRED'; end if;
 if p_order_id is null then raise exception 'INVALID_ORDER_ID'; end if;
 select to_jsonb(o) into v_order from (
   select id,buyer_id,store_id,status,payment_method,total_iqd,
     delivery_address,phone,notes,created_at,updated_at
   from public.orders where id=p_order_id
 ) o;
 if v_order is null then raise exception 'ORDER_NOT_FOUND'; end if;
 return jsonb_build_object('order',v_order,
  'items',coalesce((select jsonb_agg(to_jsonb(i) order by i.product_name)
    from (select product_id,product_name,unit_price_iqd,quantity,line_total_iqd
      from public.order_items where order_id=p_order_id) i),'[]'::jsonb),
  'history',coalesce((select jsonb_agg(to_jsonb(h) order by h.changed_at)
    from (select old_status,new_status,changed_by,changed_at
      from public.order_status_history where order_id=p_order_id) h),'[]'::jsonb));
end;
$$;
revoke all on function public.shitreed_admin_order_detail(uuid)
  from public,anon,authenticated;
grant execute on function public.shitreed_admin_order_detail(uuid) to authenticated;

create or replace function public.shitreed_admin_inventory_adjust(
  p_product_id uuid,p_delta integer,p_reason text
) returns integer language plpgsql security definer set search_path=''
as $$
declare
 v_role text := public.shitreed_admin_role();
 v_product public.products%rowtype;
 v_new bigint;
begin
 if v_role not in ('super_admin','operations','catalog_manager')
   or v_role is null then raise exception 'ADMIN_ACCESS_REQUIRED'; end if;
 if p_product_id is null or p_delta is null or p_delta=0
   or p_delta not between -10000 and 10000 or p_reason is null
   or char_length(btrim(p_reason)) not between 20 and 1000 then
   raise exception 'INVALID_INVENTORY_ADJUSTMENT';
 end if;
 select * into v_product from public.products
   where id=p_product_id for update;
 if not found then raise exception 'PRODUCT_NOT_FOUND'; end if;
 v_new := v_product.stock_quantity::bigint + p_delta::bigint;
 if v_new < 0 or v_new > 10000000 then
   raise exception 'INVENTORY_OUT_OF_RANGE'; end if;
 update public.products set stock_quantity=v_new::integer
  where id=p_product_id;
 insert into public.shitreed_admin_activity
   (actor_id,section,entity_id,action,before_state,after_state,reason)
 values (auth.uid(),'inventory',p_product_id,'adjust',
   v_product.stock_quantity::text,v_new::text,btrim(p_reason));
 return v_new::integer;
end;
$$;
revoke all on function public.shitreed_admin_inventory_adjust(uuid,integer,text)
  from public,anon,authenticated;
grant execute on function public.shitreed_admin_inventory_adjust(uuid,integer,text)
  to authenticated;

create or replace function public.shitreed_admin_price_update(
  p_product_id uuid,p_price_iqd integer,p_reason text
) returns integer language plpgsql security definer set search_path=''
as $$
declare
 v_role text := public.shitreed_admin_role();
 v_product public.products%rowtype;
begin
 if v_role not in ('super_admin','operations','catalog_manager')
   or v_role is null then raise exception 'ADMIN_ACCESS_REQUIRED'; end if;
 if p_product_id is null or p_price_iqd is null
   or p_price_iqd not between 0 and 100000000
   or p_reason is null or char_length(btrim(p_reason)) not between 20 and 1000
   then raise exception 'INVALID_PRICE_UPDATE'; end if;
 select * into v_product from public.products where id=p_product_id for update;
 if not found then raise exception 'PRODUCT_NOT_FOUND'; end if;
 if v_product.price_iqd = p_price_iqd then
   raise exception 'PRICE_UNCHANGED'; end if;
 update public.products set price_iqd=p_price_iqd where id=p_product_id;
 insert into public.shitreed_admin_activity
   (actor_id,section,entity_id,action,before_state,after_state,reason)
 values (auth.uid(),'pricing',p_product_id,'set_price',
   v_product.price_iqd::text,p_price_iqd::text,btrim(p_reason));
 return p_price_iqd;
end;
$$;
revoke all on function public.shitreed_admin_price_update(uuid,integer,text)
  from public,anon,authenticated;
grant execute on function public.shitreed_admin_price_update(uuid,integer,text)
  to authenticated;

-- Exact email lookup, never a listing of all Supabase Auth emails.
create or replace function public.shitreed_admin_find_user(p_email text)
returns jsonb language plpgsql stable security definer set search_path=''
as $$
declare v_result jsonb;
begin
 if public.shitreed_admin_role() is distinct from 'super_admin'
   then raise exception 'SUPER_ADMIN_REQUIRED'; end if;
 if p_email is null or length(btrim(p_email)) not between 5 and 254
   or strpos(p_email,'@')=0 then raise exception 'INVALID_EMAIL'; end if;
 select jsonb_build_object('id',u.id,'email',u.email)
 into v_result from auth.users u
 where lower(u.email)=lower(btrim(p_email)) limit 1;
 return v_result;
end;
$$;
revoke all on function public.shitreed_admin_find_user(text)
  from public,anon,authenticated;
grant execute on function public.shitreed_admin_find_user(text)
  to authenticated;

-- Add explicit rejection from pending alongside existing approvals.
-- Reuses both review audit and admin activity logging in one transaction.
 no destructive customer, store or order deletion.
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
    if char_length(btrim(p_reason)) < 20 then
      raise exception 'STORE_REVIEW_REASON_TOO_SHORT';
    end if;
    select * into v_store from public.stores where id = p_id for update;
    if not found then raise exception 'STORE_NOT_FOUND'; end if;
    v_old := v_store.status;
    if p_action = 'approve' and v_old = 'pending' then
      if char_length(btrim(v_store.address)) < 8 then
        raise exception 'STORE_DETAILS_INCOMPLETE';
      end if;
      v_next := 'approved';
    elsif p_action = 'reject' and v_old = 'pending' then
      v_next := 'suspended';
    elsif p_action = 'suspend' and v_old = 'approved' then
      v_next := 'suspended';
    elsif p_action = 'reopen' and v_old = 'suspended' then
      v_next := 'pending';
    else
      raise exception 'INVALID_STORE_TRANSITION';
    end if;
    update public.stores set status = v_next where id = p_id;
    -- Keep the established store-review audit alongside the admin activity log.
    insert into public.store_review_audit
      (store_id, admin_id, old_status, new_status, reason)
    values (p_id, v_actor, v_old, v_next, btrim(p_reason));
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


