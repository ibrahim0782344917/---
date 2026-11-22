-- Disposable PostgreSQL fixture, synthetic identities.
create table auth.users (id uuid primary key);
insert into auth.users values
('11111111-1111-4111-8111-111111111111'),
('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'),
('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'),
('cccccccc-cccc-4ccc-8ccc-cccccccccccc'),
('dddddddd-dddd-4ddd-8ddd-dddddddddddd');
