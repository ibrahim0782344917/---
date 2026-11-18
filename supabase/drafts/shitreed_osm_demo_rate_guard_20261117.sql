-- Shitreed OSM Discovery: separate, strictly limited PREVIEW endpoint.
-- This migration never touches existing products, stores, orders or Google integrations.
create schema if not exists private_osm;
revoke all on schema private_osm from public,anon,authenticated;
create table if not exists private_osm.request_buckets (
  bucket text primary key,
  requests integer not null default 1 check (requests between 1 and 80),
  window_started_at timestamptz not null default now()
);
alter table private_osm.request_buckets enable row level security;
revoke all on private_osm.request_buckets from public,anon,authenticated;
create index if not exists osm_request_buckets_cleanup
  on private_osm.request_buckets(window_started_at);

create or replace function public.try_consume_shitreed_osm_quota(
  p_bucket text
) returns boolean
language plpgsql
security definer
set search_path=''
as $$
declare
  minute_allowed boolean := false;
  daily_allowed boolean := false;
  day_bucket text := 'day:' || to_char(now() at time zone 'UTC','YYYY-MM-DD');
begin
  if p_bucket is null or p_bucket !~ '^[0-9a-f]{64}$' then return false; end if;
  -- Hash bucket: max 5 searches each minute from the same network.
  insert into private_osm.request_buckets as b(bucket,requests,window_started_at)
    values(p_bucket,1,now())
    on conflict(bucket) do update
      set requests=case when b.window_started_at < now()-interval '1 minute'
        then 1 else b.requests+1 end,
          window_started_at=case when b.window_started_at < now()-interval '1 minute'
        then now() else b.window_started_at end
    where b.window_started_at < now()-interval '1 minute' or b.requests < 5
    returning true into minute_allowed;
  if not coalesce(minute_allowed,false) then return false; end if;
  -- Global cap for the whole demo: 80 upstream Overpass queries/day.
  insert into private_osm.request_buckets as b(bucket,requests,window_started_at)
    values(day_bucket,1,now())
    on conflict(bucket) do update set requests=b.requests+1
      where b.requests < 80
    returning true into daily_allowed;
  return coalesce(daily_allowed,false);
end;
$$;
revoke all on function public.try_consume_shitreed_osm_quota(text)
  from public,anon,authenticated;
grant execute on function public.try_consume_shitreed_osm_quota(text)
  to service_role;
-- Planned maintenance: delete buckets older than 7 days using authorized maintenance.
