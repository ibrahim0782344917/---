SET LOCAL lock_timeout = '3s';
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
 if not exists (select 1 from auth.sessions s where s.user_id=actor and s.id::text=(auth.jwt()->>'session_id') and (s.not_after is null or s.not_after>pg_catalog.now()) and s.aal::text='aal2') then
   raise exception 'SESSION_EXPIRED';
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
 if not exists (select 1 from auth.sessions s where s.user_id=actor and s.id::text=(auth.jwt()->>'session_id') and (s.not_after is null or s.not_after>pg_catalog.now()) and s.aal::text='aal2') then
   raise exception 'SESSION_EXPIRED';
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
 if not exists (select 1 from auth.sessions s where s.user_id=actor and s.id::text=(auth.jwt()->>'session_id') and (s.not_after is null or s.not_after>pg_catalog.now()) and s.aal::text='aal2') then
   raise exception 'SESSION_EXPIRED';
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
CREATE OR REPLACE FUNCTION public.shitreed_customer_deletion_preflight()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_user uuid := (select auth.uid());
  v_open bigint;
  v_total bigint;
  v_owned bigint;
begin
  if v_user is null then raise exception 'LOGIN_REQUIRED'; end if;
 if not exists (select 1 from auth.sessions s where s.user_id=v_user and s.id::text=(auth.jwt()->>'session_id') and (s.not_after is null or s.not_after>pg_catalog.now())) then
   raise exception 'SESSION_EXPIRED';
 end if;
  select
    count(*) filter (where status not in ('cancelled','rejected','delivered')),
    count(*)
  into v_open,v_total
  from public.orders
  where buyer_id=v_user;
  select count(*) into v_owned from public.stores where owner_id=v_user;
  -- Retained order history, administrative audits, support tickets,
  -- open disputes, merchant access and financial balances require separate
  -- legal and operational checks. Never advertise automatic deletion.
  return pg_catalog.jsonb_build_object(
    'open_orders', v_open,
    'historical_orders', v_total,
    'owned_stores', v_owned,
    'manual_review_required', true,
    'can_delete_immediately', false
  );
end;
$function$
;
CREATE OR REPLACE FUNCTION public.shitreed_customer_request_deletion(p_reason text DEFAULT ''::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_user uuid := auth.uid();
  v_request uuid;
begin
  if v_user is null then raise exception 'LOGIN_REQUIRED'; end if;
 if not exists (select 1 from auth.sessions s where s.user_id=v_user and s.id::text=(auth.jwt()->>'session_id') and (s.not_after is null or s.not_after>pg_catalog.now())) then
   raise exception 'SESSION_EXPIRED';
 end if;
  if p_reason is null or char_length(btrim(p_reason)) > 500 then
    raise exception 'INVALID_DELETION_REASON';
  end if;
  -- Serialize parallel requests from the same identity and avoid duplicate rows.
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('deletion:' || v_user::text, 19391)
  );

  select id into v_request
  from public.customer_deletion_requests
  where user_id = v_user and status in ('pending','processing')
  order by requested_at desc limit 1;

  if v_request is null then
    insert into public.customer_deletion_requests(user_id,reason)
    values(v_user,btrim(p_reason))
    returning id into v_request;
  end if;
  return v_request;
end;
$function$
;
