-- Only verified Baghdad businesses with contact details and a usable pin
-- can become publicly visible. Existing pending stores stay untouched.
-- This uses an INVOKER trigger (not a new public privileged RPC).
create or replace function public.shitreed_validate_approved_store()
returns trigger language plpgsql
set search_path = ''
as $$
begin
  if new.status = 'approved' then
    if new.name is null or char_length(btrim(new.name)) < 2 or
       new.area is null or char_length(btrim(new.area)) < 2 or
       new.address is null or char_length(btrim(new.address)) < 8 then
      raise exception 'STORE_DETAILS_INCOMPLETE';
    end if;
    if new.phone is null or
       char_length(btrim(new.phone)) not between 8 and 30 or
       char_length(pg_catalog.regexp_replace(new.phone, '[^0-9]', '', 'g')) < 7 then
      raise exception 'STORE_CONTACT_REQUIRED';
    end if;
    if new.latitude is null or new.longitude is null or
       new.latitude not between 32.8 and 33.9 or
       new.longitude not between 43.6 and 45.2 or
       not pg_catalog.isfinite(new.latitude) or
       not pg_catalog.isfinite(new.longitude) then
      raise exception 'STORE_MAP_PIN_REQUIRED';
    end if;
  end if;
  return new;
end;
$$;

revoke all on function public.shitreed_validate_approved_store()
  from public, anon, authenticated;

drop trigger if exists shitreed_approved_store_requires_contact_pin
  on public.stores;
create trigger shitreed_approved_store_requires_contact_pin
  before insert or update on public.stores
  for each row execute function public.shitreed_validate_approved_store();

-- V2 keeps old RPC available to older Admin clients. The new admin interface
-- can see pin readiness without any direct access to pending store rows.
create or replace function public.shitreed_pending_store_reviews_v2()
returns table (
  store_id uuid,
  store_name text,
  area text,
  category text,
  store_address text,
  store_phone text,
  latitude double precision,
  longitude double precision,
  applied_at timestamptz
)
language plpgsql stable security definer
set search_path = ''
as $$
begin
  if not public.shitreed_is_admin() then
    raise exception 'ADMIN_ACCESS_REQUIRED';
  end if;
  return query
  select s.id, s.name, s.area, s.category, s.address, s.phone,
    s.latitude, s.longitude, s.created_at
  from public.stores s
  where s.status = 'pending'
  order by s.created_at asc limit 100;
end;
$$;

revoke all on function public.shitreed_pending_store_reviews_v2()
  from public, anon, authenticated;
grant execute on function public.shitreed_pending_store_reviews_v2()
  to authenticated;

comment on function public.shitreed_pending_store_reviews_v2()
  is 'Admin-only pending merchants including location readiness';
