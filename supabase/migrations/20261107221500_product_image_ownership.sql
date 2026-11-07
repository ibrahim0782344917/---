-- Keep each merchant's product photography under its own store path.
-- This restriction does not delete photos or customer data.
alter table public.products add constraint products_image_belongs_to_store
  check (
    image_url is null or
    image_url like (
      'https://ltwncrewggdrjevakwpb.supabase.co/storage/v1/object/public/store-images/'
      || store_id::text || '/%'
    )
  );
