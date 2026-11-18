-- Iraqi OpenStreetMap directory, distinct from registered merchants and sales.
-- Data attribution: © OpenStreetMap contributors, ODbL 1.0.
create table if not exists public.shitreed_osm_directory (
  osm_id text primary key check (osm_id ~ '^(node|way|relation)/[1-9][0-9]{0,17}$'),
  name text not null check (char_length(btrim(name)) between 2 and 150),
  category text not null default 'محل أو خدمة',
  address text not null default 'العراق',
  latitude double precision not null check (latitude between 29 and 37.7),
  longitude double precision not null check (longitude between 38.5 and 48.9),
  source text not null default 'OpenStreetMap' check (source='OpenStreetMap'),
  imported_at timestamptz not null default now()
);
create index if not exists shitreed_osm_directory_coordinates
  on public.shitreed_osm_directory(latitude,longitude);
alter table public.shitreed_osm_directory enable row level security;
revoke all on public.shitreed_osm_directory from public, anon, authenticated;
grant select (osm_id,name,category,address,latitude,longitude,source,imported_at)
 on public.shitreed_osm_directory to anon, authenticated;
drop policy if exists "Public discover OSM directory" on public.shitreed_osm_directory;
create policy "Public discover OSM directory" on public.shitreed_osm_directory
 for select to anon, authenticated using (true);
-- Only trusted server/SQL administration may import ODbL data.
-- Never assume an OSM listing means Shitreed merchant verification.
