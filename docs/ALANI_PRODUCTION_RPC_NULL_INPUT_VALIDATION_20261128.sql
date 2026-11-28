SET LOCAL lock_timeout = '3s';
CREATE OR REPLACE FUNCTION public.alani_set_content_staff(p_user_id uuid, p_role text, p_enabled boolean)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_user uuid:=(select auth.uid());
 v_store constant uuid:='25091ca2-c0da-416c-b634-81b188ee66be'::uuid;
begin
 if v_user is null or not(
 exists(select 1 from public.stores where id=v_store and owner_id=v_user)
 or public.shitreed_is_admin()) then raise exception 'STAFF_DENIED'; end if;
 if p_user_id is null or p_enabled is null
 or (p_enabled and (p_role is null or p_role not in ('writer','editor','moderator')))
 then raise exception 'BAD_STAFF_ROLE'; end if;
 if p_enabled then
 insert into public.alani_content_staff(store_id,user_id,role,granted_by)
 values(v_store,p_user_id,p_role,v_user)
 on conflict(store_id,user_id) do update
 set role=excluded.role,granted_by=excluded.granted_by;
 else
 delete from public.alani_content_staff where store_id=v_store and user_id=p_user_id;
 end if;
 insert into public.alani_moderation_audit(publication_id,actor_id,target_id,action)
 values(null,v_user,p_user_id,case when p_enabled then 'role:'||p_role else 'role:revoked' end);
end $function$
;
CREATE OR REPLACE FUNCTION public.change_cash_order_status(p_order_id uuid, p_new_status text)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_user uuid := auth.uid();
  v_order public.orders%rowtype;
  v_owner uuid;
begin
  if v_user is null then raise exception 'LOGIN_REQUIRED'; end if;
  if p_new_status is null then raise exception 'INVALID_STATUS'; end if;
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
$function$
;
CREATE OR REPLACE FUNCTION public.shitreed_admin_rows(p_section text, p_limit integer DEFAULT 30, p_offset integer DEFAULT 0)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_role text := public.shitreed_admin_role();
  v_items jsonb := '[]'::jsonb;
begin
  if v_role is null then raise exception 'ADMIN_ACCESS_REQUIRED'; end if;
  if p_limit is null or p_offset is null or p_limit not between 1 and 100 or p_offset < 0 or p_offset > 100000 then
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
$function$
;
CREATE OR REPLACE FUNCTION public.shitreed_admin_set_badge(p_user_id uuid, p_badge_kind text, p_label text, p_icon text, p_enabled boolean, p_reason text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare actor uuid := (select auth.uid());
begin
 if actor is null or public.shitreed_admin_role() is distinct from 'super_admin' then
   raise exception 'PERMISSION_DENIED';
 end if;
 if (auth.jwt()->>'aal') is distinct from 'aal2' then
  raise exception 'MFA_REQUIRED';
 end if;
 if p_user_id is null or p_enabled is null or p_badge_kind is null or p_badge_kind not in
 ('verified_identity','verified_merchant','gold','king','merchant_pro','custom')
 or char_length(btrim(coalesce(p_label,''))) not between 2 and 80
 or char_length(coalesce(p_icon,'')) not between 1 and 10
 or char_length(btrim(coalesce(p_reason,''))) not between 12 and 500 then
   raise exception 'INVALID_BADGE_REQUEST';
 end if;
 if p_enabled then
   insert into public.shitreed_user_badges
    (user_id,badge_kind,label,icon,reason,granted_by,active)
   values(p_user_id,p_badge_kind,btrim(p_label),p_icon,btrim(p_reason),actor,true)
   on conflict(user_id,badge_kind,label) do update set
    active=true,icon=excluded.icon,reason=excluded.reason,
    granted_by=excluded.granted_by,granted_at=now(),expires_at=null;
 else
   update public.shitreed_user_badges set active=false
    where user_id=p_user_id and badge_kind=p_badge_kind and label=btrim(p_label);
 end if;
 insert into public.shitreed_profile_admin_audit(actor_id,target_user_id,action,reason)
 values(actor,p_user_id,case when p_enabled then 'badge_granted' else 'badge_revoked' end,btrim(p_reason));
 return true;
end;
$function$
;
CREATE OR REPLACE FUNCTION public.shitreed_admin_set_level_threshold(p_level integer, p_min_xp integer, p_reason text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare old_min int; previous_min int; next_min int; actor uuid := (select auth.uid());
begin
 if actor is null or public.shitreed_admin_role() is distinct from 'super_admin' then
  raise exception 'PERMISSION_DENIED';
 end if;
 if (auth.jwt()->>'aal') is distinct from 'aal2' then
  raise exception 'MFA_REQUIRED';
 end if;
 if p_level is null or p_min_xp is null or p_level not between 2 and 100 or p_min_xp<1 or
   char_length(btrim(coalesce(p_reason,'')))<12 then
  raise exception 'INVALID_LEVEL_REQUEST';
 end if;
 select min_xp into previous_min from public.shitreed_level_thresholds where level=p_level-1;
 select min_xp into next_min from public.shitreed_level_thresholds where level=p_level+1;
 if previous_min is null or p_min_xp<=previous_min or
    (next_min is not null and p_min_xp>=next_min) then
  raise exception 'LEVEL_THRESHOLD_OUT_OF_ORDER';
 end if;
 select min_xp into old_min from public.shitreed_level_thresholds where level=p_level;
 update public.shitreed_level_thresholds set min_xp=p_min_xp where level=p_level;
 insert into public.shitreed_profile_admin_audit(actor_id,action,reason)
 values(actor,'level_threshold_change',
    btrim(p_reason)||' (level '||p_level||', old '||old_min||', new '||p_min_xp||')');
 return true;
end;
$function$
;
CREATE OR REPLACE FUNCTION public.shitreed_admin_set_xp_rule(p_event_type text, p_points integer, p_enabled boolean, p_reason text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare actor uuid := (select auth.uid());
begin
 if actor is null or public.shitreed_admin_role() is distinct from 'super_admin' then
   raise exception 'PERMISSION_DENIED';
 end if;
 if (auth.jwt()->>'aal') is distinct from 'aal2' then
   raise exception 'MFA_REQUIRED';
 end if;
 if p_event_type is null or p_points is null or p_points not between 0 and 1000 or
   p_enabled is null or
   char_length(btrim(coalesce(p_reason,''))) not between 12 and 500 then
   raise exception 'INVALID_RULE_CHANGE';
 end if;
 update public.shitreed_xp_rules
   set points=p_points,enabled=p_enabled,updated_at=now()
   where event_type=p_event_type;
 if not found then raise exception 'UNKNOWN_XP_RULE'; end if;
 insert into public.shitreed_profile_admin_audit(actor_id,action,reason)
 values(actor,'xp_rule_changed',
 btrim(p_reason)||' (rule '||p_event_type||', points '||p_points||
 ', enabled '||p_enabled||')');
 return true;
end;
$function$
;
CREATE OR REPLACE FUNCTION public.shitreed_review_store(p_store_id uuid, p_decision text, p_reason text)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_store public.stores%rowtype;
  v_admin uuid := auth.uid();
  v_new_status text;
begin
  if not public.shitreed_is_admin() or v_admin is null then
    raise exception 'ADMIN_ACCESS_REQUIRED';
  end if;
  if p_store_id is null or p_reason is null
     or char_length(btrim(p_reason)) not between 20 and 1000 then
    raise exception 'REASON_REQUIRED';
  end if;
  if p_decision is null or p_decision not in ('approve', 'reject') then
    raise exception 'INVALID_REVIEW_DECISION';
  end if;

  select * into v_store from public.stores
    where id = p_store_id for update;
  if not found then
    raise exception 'STORE_NOT_FOUND';
  end if;
  if v_store.status <> 'pending' then
    raise exception 'STORE_NOT_PENDING';
  end if;
  -- The administrator must verify ownership and accuracy of the business
  -- outside this function before selecting Approve. No approval by default.
  if p_decision = 'approve' then
    if char_length(btrim(v_store.name)) < 2
       or char_length(btrim(v_store.area)) < 2
       or char_length(btrim(v_store.address)) < 8 then
      raise exception 'STORE_DETAILS_INCOMPLETE';
    end if;
    v_new_status := 'approved';
  else
    v_new_status := 'suspended';
  end if;

  update public.stores
     set status = v_new_status
   where id = v_store.id;

  insert into public.store_review_audit (
    store_id, admin_id, old_status, new_status, reason
  ) values (
    v_store.id, v_admin, v_store.status, v_new_status, btrim(p_reason)
  );
  return v_new_status;
end;
$function$
;
