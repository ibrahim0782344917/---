-- Activation for Al-Ani store-owned MP4 uploads and reels.
-- Separate additive migration; verify on staging before production.
-- Public reads are intentional for marketing videos. An unpublished asset
-- is not discoverable in the feed, but its URL can be shared if leaked.
begin;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('alani-reels', 'alani-reels', true, 41943040, array['video/mp4'])
on conflict (id) do nothing;

-- Fail closed if a bucket with this name was already created privately or
-- with unrelated security settings. Do not silently weaken existing buckets.
do $reels$
begin
  if not exists (
    select 1 from storage.buckets where id = 'alani-reels'
    and public is true and file_size_limit = 41943040
    and allowed_mime_types = array['video/mp4']
  ) then
    raise exception 'alani-reels bucket has unexpected configuration';
  end if;
end
$reels$;

create policy alani_reels_owner_upload on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'alani-reels'
    and (storage.foldername(name))[1] =
      '25091ca2-c0da-416c-b634-81b188ee66be'
    and (storage.foldername(name))[2] = (select auth.uid())::text
    and storage.extension(name) = 'mp4'
    and exists (
      select 1 from public.stores s
      where s.id = '25091ca2-c0da-416c-b634-81b188ee66be'::uuid
      and s.owner_id = (select auth.uid()) and s.status = 'approved'
    )
  );

create policy alani_reels_owner_manage_read on storage.objects
  for select to authenticated
  using (
    bucket_id = 'alani-reels'
    and (storage.foldername(name))[1] =
      '25091ca2-c0da-416c-b634-81b188ee66be'
    and (storage.foldername(name))[2] = (select auth.uid())::text
    and exists (
      select 1 from public.stores s
      where s.id = '25091ca2-c0da-416c-b634-81b188ee66be'::uuid
      and s.owner_id = (select auth.uid())
    )
  );

create policy alani_reels_owner_delete on storage.objects
  for delete to authenticated
  using (
    bucket_id = 'alani-reels'
    and (storage.foldername(name))[1] =
      '25091ca2-c0da-416c-b634-81b188ee66be'
    and (storage.foldername(name))[2] = (select auth.uid())::text
    and exists (
      select 1 from public.stores s
      where s.id = '25091ca2-c0da-416c-b634-81b188ee66be'::uuid
      and s.owner_id = (select auth.uid())
    )
  );

commit;
