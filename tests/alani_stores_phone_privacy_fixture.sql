create role anon nologin;
create role authenticated nologin;
create schema auth;
create function auth.uid() returns uuid language sql stable
  as $x$ select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid $x$;
grant usage on schema auth to anon,authenticated;
grant execute on function auth.uid() to anon,authenticated;
create table public.stores (
 id uuid primary key,
 owner_id uuid not null,
 name text not null,
 area text not null,
 category text not null,
 address text not null,
 phone text,
 latitude double precision,
 longitude double precision,
 status text not null,
 created_at timestamptz not null default now(),
 description text not null default '',
 opening_hours text not null default '',
 logo_url text
);
insert into public.stores(id,owner_id,name,area,category,address,phone,status)
values
 ('25091ca2-c0da-416c-b634-81b188ee66be',
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
  'متجر العاني','بغداد','أعشاب','الغزالية','07700000000','approved'),
 ('22222222-2222-4222-8222-222222222222',
  'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
  'متجر آخر','بغداد','أغذية','الكاظمية','07711111111','approved');
alter table public.stores enable row level security;
create policy public_approved_stores on public.stores for select
  to anon,authenticated using (status='approved');
create policy owner_shops on public.stores for select
  to authenticated using (owner_id=(select auth.uid()));
grant select on public.stores to anon,authenticated;
