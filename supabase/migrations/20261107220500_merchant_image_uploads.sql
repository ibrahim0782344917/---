-- Public product photography. Reads are public; uploads are only by the
-- authenticated owner of the store whose UUID prefixes the object path.
insert into storage.buckets
  (id,name,public,file_size_limit,allowed_mime_types)
values ('store-images','store-images',true,5242880,
  array['image/jpeg','image/png','image/webp'])
on conflict (id) do nothing;

create policy "merchant uploads images only for owned store"
  on storage.objects for insert to authenticated
  with check (
    bucket_id = 'store-images'
    and exists (
      select 1 from public.stores s
      where s.id::text = (storage.foldername(name))[1]
        and s.owner_id = (select auth.uid())
    )
  );

alter table public.products add constraint products_image_source_allowed
  check (
    image_url is null or
    image_url like
      'https://ltwncrewggdrjevakwpb.supabase.co/storage/v1/object/public/store-images/%'
  );
