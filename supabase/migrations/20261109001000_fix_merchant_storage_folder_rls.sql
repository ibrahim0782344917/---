-- Fix merchant photo upload RLS; previous policy resolved bare "name" to
-- public.stores.name inside EXISTS instead of storage.objects.name.
-- Keep INSERT limited to store-images and authenticated store owners.
drop policy if exists "merchant uploads images only for owned store"
  on storage.objects;

create policy "merchant uploads images only for owned store"
  on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'store-images'
    and exists (
      select 1
      from public.stores merchant_store
      where merchant_store.id::text =
        split_part(storage.objects.name, '/', 1)
        and merchant_store.owner_id = (select auth.uid())
    )
  );
