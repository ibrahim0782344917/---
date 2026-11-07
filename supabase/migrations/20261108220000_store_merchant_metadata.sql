-- Add non-destructive merchant storefront metadata, without changing orders.
alter table public.stores
  add column if not exists description text not null default ''
    check (char_length(description) <= 1000);
alter table public.stores
  add column if not exists opening_hours text not null default ''
    check (char_length(opening_hours) <= 250);
alter table public.stores
  add column if not exists logo_url text;

-- Store logos must be uploaded to the owner's existing Storage RLS folder.
alter table public.stores add constraint stores_logo_belongs_to_store
  check (
    logo_url is null or
    logo_url like (
      'https://ltwncrewggdrjevakwpb.supabase.co/storage/v1/object/public/store-images/'
      || id::text || '/%'
    )
  );

grant insert (description, opening_hours, logo_url)
  on public.stores to authenticated;
grant update (description, opening_hours, logo_url)
  on public.stores to authenticated;
