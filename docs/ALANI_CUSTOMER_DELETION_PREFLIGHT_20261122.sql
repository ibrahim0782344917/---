-- Read-only account deletion readiness. Never actually deletes a user.
-- A pending request must still be reviewed by a trusted operator.
-- No tables or rows are modified by this function.
create or replace function public.shitreed_customer_deletion_preflight()
returns jsonb
language plpgsql stable security definer set search_path = ''
as $preflight$
declare
  v_user uuid := (select auth.uid());
  v_open bigint;
  v_total bigint;
  v_owned bigint;
begin
  if v_user is null then raise exception 'LOGIN_REQUIRED'; end if;
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
$preflight$;
revoke all on function public.shitreed_customer_deletion_preflight()
  from public,anon,authenticated;
grant execute on function public.shitreed_customer_deletion_preflight()
  to authenticated;
