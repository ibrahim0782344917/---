-- Independent, non-destructive quota guard for Google Places requests.
-- Google place names/addresses/locations are NOT saved to the database.
create table if not exists public.google_places_request_limits (
  bucket text primary key,
  requests integer not null default 1,
  window_started_at timestamptz not null default now()
);
alter table public.google_places_request_limits enable row level security;
revoke all on public.google_places_request_limits from public, anon, authenticated;

create or replace function public.try_consume_google_places_budget(
  p_bucket text
) returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  was_allowed boolean := false;
begin
  if char_length(p_bucket) <> 64 then
    return false;
  end if;
  insert into public.google_places_request_limits as guard
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
  return coalesce(was_allowed, false);
end;
$$;
revoke all on function public.try_consume_google_places_budget(text)
  from public, anon, authenticated;
grant execute on function public.try_consume_google_places_budget(text)
  to service_role;
