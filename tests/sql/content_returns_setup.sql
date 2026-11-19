-- Supplemental disposable fixture for media and returns RLS tests.
create table auth.users (id uuid primary key);
insert into auth.users(id) values
 ('11111111-1111-4111-8111-111111111111'),
 ('99999999-9999-4999-8999-999999999999'),
 ('88888888-8888-4888-8888-888888888888'),
 ('77777777-7777-4777-8777-777777777777');
grant usage on schema auth to anon,authenticated;
grant execute on function auth.uid() to anon,authenticated;
grant select on public.stores to anon,authenticated;
grant select on public.orders to authenticated;
