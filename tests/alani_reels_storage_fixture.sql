-- Disposable PostgreSQL ONLY. Mimic the Supabase Storage permission surface.
create role anon nologin;
create role authenticated nologin;
create schema auth;
create function auth.uid() returns uuid language sql stable as $uid$
  select nullif(current_setting('request.jwt.claim.sub', true),'')::uuid
$uid$;
grant usage on schema auth to authenticated, anon;
grant execute on function auth.uid() to authenticated, anon;

create table public.stores (id uuid primary key, owner_id uuid, status text);
insert into public.stores values
  ('25091ca2-c0da-416c-b634-81b188ee66be',
   '11111111-1111-4111-8111-111111111111','approved'),
  ('22222222-2222-4222-8222-222222222222',
   '22222222-2222-4222-8222-222222222222','approved');
grant select on public.stores to authenticated, anon;

create schema storage;
create table storage.buckets (
  id text primary key,
  name text not null,
  public boolean default false,
  file_size_limit bigint,
  allowed_mime_types text[]
);
create table storage.objects (
  id uuid primary key default gen_random_uuid(),
  bucket_id text references storage.buckets(id),
  name text not null
);
create function storage.foldername(n text) returns text[]
  language sql immutable as $folder$
  select case when position('/' in n) > 0
    then string_to_array(regexp_replace(n,'/[^/]*$',''),'/')
    else array[]::text[] end
$folder$;
create function storage.extension(n text) returns text
  language sql immutable as $extension$
  select lower(regexp_replace(n, '^.*\.', ''))
$extension$;
grant usage on schema storage to authenticated, anon;
grant select, insert, delete, update on storage.objects to authenticated;
alter table storage.objects enable row level security;
