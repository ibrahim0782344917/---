-- Authoritative lifetime XP total, independent of UI history pagination.
-- SECURITY INVOKER uses the caller's authenticated RLS; no user can write XP.
create or replace function public.shitreed_my_xp_total()
returns bigint
language sql stable security invoker set search_path=''
as $$
 select coalesce(sum(points),0)::bigint
 from public.shitreed_xp_events
 where user_id=(select auth.uid());
$$;
revoke all on function public.shitreed_my_xp_total() from public,anon;
grant execute on function public.shitreed_my_xp_total() to authenticated;
