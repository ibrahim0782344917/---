-- Shitreed customer account-deletion REQUEST, not immediate erasure.
-- Existing public.customer_deletion_requests has RLS and a one-open-request index.
-- This fixes read access while keeping all direct client writes prohibited.
revoke all on public.customer_deletion_requests
  from public, anon, authenticated;
grant select on public.customer_deletion_requests to authenticated;

create or replace function public.shitreed_customer_request_deletion(
  p_reason text default ''
) returns uuid
language plpgsql security definer set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
  v_request uuid;
begin
  if v_user is null then raise exception 'LOGIN_REQUIRED'; end if;
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
$$;
revoke all on function public.shitreed_customer_request_deletion(text)
  from public,anon,authenticated;
grant execute on function public.shitreed_customer_request_deletion(text)
  to authenticated;

-- NO auth.users deletion here. Actual erasure requires identity verification,
-- review of unsettled orders & balances, retained-data policy, session revocation,
-- storage cleanup and server-side Admin API workflow.
