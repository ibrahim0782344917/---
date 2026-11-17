-- FIXED DRAFT, NOT APPLIED TO PRODUCTION.
-- Google Places (New) proxy must have strict per-minute and daily caps.
-- Do not enable paid Google Places without project quotas, budget alarms,
-- restricted API credentials and a successful authorized review.
create schema if not exists private_places;
revoke all on schema private_places from public, anon, authenticated;

create table if not exists private_places.google_places_request_limits (
  bucket text primary key,
  requests integer not null default 1 check (requests between 1 and 100),
  window_started_at timestamptz not null default now()
);
alter table private_places.google_places_request_limits enable row level security;
revoke all on private_places.google_places_request_limits
  from public, anon, authenticated;

create index if not exists google_places_request_limits_retention_idx
  on private_places.google_places_request_limits(window_started_at);

create or replace function public.try_consume_google_places_budget(
  p_bucket text
) returns boolean
language plpgsql
security definer
set search_path = ''
as $function$
declare
  was_allowed boolean := false;
  current_day text := to_char(now() at time zone 'UTC', 'YYYY-MM-DD');
begin
  -- Bucket must be a server-generated SHA-256 hex digest. The Edge Function
  -- hashes the request bucket with a secret salt. No raw IPs stored.
  if p_bucket is null or p_bucket !~ '^[0-9a-f]{64}$' then
    return false;
  end if;

  -- Limit an IP bucket to 8 requests per 60 seconds (DB row locked via UPSERT).
  insert into private_places.google_places_request_limits as guard
    (bucket, requests, window_started_at)
  values (p_bucket, 1, now())
  on conflict (bucket) do update
    set requests = case
      when guard.window_started_at < now() - interval '1 minute'
        then 1 else guard.requests + 1 end,
        window_started_at = case
      when guard.window_started_at < now() - interval '1 minute'
        then now() else guard.window_started_at end
    where guard.window_started_at < now() - interval '1 minute'
      or guard.requests < 8
    returning true into was_allowed;
  if not coalesce(was_allowed, false) then
    return false;
  end if;

  -- Hard cap: 100 billable Nearby Search requests per UTC day total,
  -- independent of easily spoofed/missing x-forwarded-for headers.
  was_allowed := false;
  insert into private_places.google_places_request_limits as daily
    (bucket, requests, window_started_at)
  values ('daily:' || current_day, 1, now())
  on conflict (bucket) do update
    set requests = daily.requests + 1
    where daily.requests < 100
    returning true into was_allowed;
  return coalesce(was_allowed, false);
end;
$function$;

revoke all on function public.try_consume_google_places_budget(text)
  from public, anon, authenticated;
grant execute on function public.try_consume_google_places_budget(text)
  to service_role;

-- Operator follow-up: an authorized, scheduled retention cleanup should delete
-- hash buckets after at most 30 days; not activated until the plan is approved.
