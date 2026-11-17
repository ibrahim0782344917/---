-- Require AAL2 MFA for sensitive gamification administration.
create or replace function public.shitreed_admin_set_level_threshold(
 p_level integer,p_min_xp integer,p_reason text
) returns boolean
language plpgsql security definer set search_path=''
as $$
declare old_min int; previous_min int; next_min int; actor uuid := (select auth.uid());
begin
 if actor is null or public.shitreed_admin_role() is distinct from 'super_admin' then
  raise exception 'PERMISSION_DENIED';
 end if;
 if (auth.jwt()->>'aal') is distinct from 'aal2' then
  raise exception 'MFA_REQUIRED';
 end if;
 if p_level not between 2 and 100 or p_min_xp<1 or
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
$$;
revoke all on function public.shitreed_admin_set_level_threshold(integer,integer,text)
 from public,anon;
grant execute on function public.shitreed_admin_set_level_threshold(integer,integer,text)
 to authenticated;

create or replace function public.shitreed_admin_set_badge(
 p_user_id uuid,p_badge_kind text,p_label text,p_icon text,
 p_enabled boolean,p_reason text
) returns boolean
language plpgsql security definer set search_path=''
as $$
declare actor uuid := (select auth.uid());
begin
 if actor is null or public.shitreed_admin_role() is distinct from 'super_admin' then
   raise exception 'PERMISSION_DENIED';
 end if;
 if (auth.jwt()->>'aal') is distinct from 'aal2' then
  raise exception 'MFA_REQUIRED';
 end if;
 if p_user_id is null or p_badge_kind not in
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
$$;
revoke all on function public.shitreed_admin_set_badge(uuid,text,text,text,boolean,text)
 from public,anon;
grant execute on function public.shitreed_admin_set_badge(uuid,text,text,text,boolean,text)
 to authenticated;



-- XP rules apply prospectively. Points are issued only by verified server events,
-- not by this RPC or by the shopper/merchant mobile clients.
create or replace function public.shitreed_admin_set_xp_rule(
 p_event_type text, p_points integer, p_enabled boolean, p_reason text
) returns boolean
language plpgsql security definer set search_path=''
as $$
declare actor uuid := (select auth.uid());
begin
 if actor is null or public.shitreed_admin_role() is distinct from 'super_admin' then
   raise exception 'PERMISSION_DENIED';
 end if;
 if (auth.jwt()->>'aal') is distinct from 'aal2' then
   raise exception 'MFA_REQUIRED';
 end if;
 if p_event_type is null or p_points not between 0 and 1000 or
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
$$;
revoke all on function public.shitreed_admin_set_xp_rule(text,integer,boolean,text)
 from public,anon;
grant execute on function public.shitreed_admin_set_xp_rule(text,integer,boolean,text)
 to authenticated;
