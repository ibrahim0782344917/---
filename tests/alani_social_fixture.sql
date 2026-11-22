create role anon nologin;
create role authenticated nologin;
create schema auth;
create table auth.users(id uuid primary key);
create function auth.uid() returns uuid language sql stable as $$
select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
grant usage on schema auth to anon,authenticated;
grant execute on function auth.uid() to anon,authenticated;
insert into auth.users values
 ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'),
 ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'),
 ('cccccccc-cccc-4ccc-8ccc-cccccccccccc');
create table public.stores(id uuid primary key,owner_id uuid not null,status text not null);
insert into public.stores values ('25091ca2-c0da-416c-b634-81b188ee66be',
 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','approved');
create table public.alani_publications(
 id uuid primary key default gen_random_uuid(),
 store_id uuid not null references public.stores(id),
 kind text not null,title text not null,body text not null default '',
 status text not null default 'draft',
 published_at timestamptz,updated_at timestamptz default now()
);
insert into public.alani_publications(id,store_id,kind,title,status) values
('11111111-1111-4111-8111-111111111111','25091ca2-c0da-416c-b634-81b188ee66be',
 'video','عسل أصلي','published');
create function public.shitreed_is_admin() returns boolean language sql stable as $x$select false$x$;
grant select on public.alani_publications,public.stores to anon,authenticated;
alter table public.alani_publications enable row level security;
alter table public.stores enable row level security;
create policy published on public.alani_publications for select to anon,authenticated
using(status='published' or exists(select 1 from public.stores s
 where s.id=store_id and s.owner_id=auth.uid()));
create policy stores_public on public.stores for select to anon,authenticated
using(status='approved');
