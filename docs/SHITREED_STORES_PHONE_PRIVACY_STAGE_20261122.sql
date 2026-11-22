-- STAGING ONLY. Must be rehearsed on isolated PG and all consumers updated
-- before live migration. This closes public REST access to stores.phone.
begin;
revoke select on public.stores from anon,authenticated;
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
commit;
