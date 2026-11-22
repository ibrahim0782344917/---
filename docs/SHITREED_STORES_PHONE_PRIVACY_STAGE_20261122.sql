-- STAGING ONLY. Must be rehearsed on isolated PG and all consumers updated
-- before live migration. This closes public REST access to stores.phone.
begin;
revoke select on public.stores from public,anon,authenticated;
-- Production has a separate authenticated column-level SELECT grant on phone;
-- table-level REVOKE does NOT revoke that grant. Remove it explicitly.
revoke select (phone) on public.stores from public,anon,authenticated;
grant select (
  id,owner_id,name,area,category,address,latitude,longitude,status,
  created_at,description,opening_hours,logo_url
) on public.stores to anon,authenticated;

-- Secure narrow phone retrieval; callers can ONLY read shops they own.
create or replace function public.shitreed_my_store_contacts()
returns table(store_id uuid,phone text)
language sql stable security definer set search_path=''
as $contacts$
  select s.id,s.phone from public.stores s
  where s.owner_id = (select auth.uid())
$contacts$;
revoke all on function public.shitreed_my_store_contacts()
  from public,anon,authenticated;
grant execute on function public.shitreed_my_store_contacts()
  to authenticated;
-- Fail the entire transaction if a public role can still read the phone field.
do $assert_no_phone$
begin
  if has_column_privilege('anon','public.stores','phone','SELECT') or
     has_column_privilege('authenticated','public.stores','phone','SELECT') then
    raise exception 'STORE_PHONE_SELECT_STILL_EXPOSED';
  end if;
  if not has_column_privilege('anon','public.stores','name','SELECT') or
     not has_column_privilege('authenticated','public.stores','id','SELECT') then
    raise exception 'PUBLIC_STORE_METADATA_BROKEN';
  end if;
end
$assert_no_phone$;
commit;
