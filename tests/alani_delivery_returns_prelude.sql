-- Disposable PG fixture ONLY: never execute against live users.
create table auth.users(id uuid primary key);
insert into auth.users(id) values
 ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'),
 ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'),
 ('cccccccc-cccc-4ccc-8ccc-cccccccccccc'),
 ('dddddddd-dddd-4ddd-8ddd-dddddddddddd');

grant select on public.stores to authenticated;
alter table public.orders add constraint orders_status_check
  check (status in ('placed','accepted','preparing','ready','rejected','cancelled'));
create table public.order_status_history (
 id uuid primary key default gen_random_uuid(),
 order_id uuid not null references public.orders(id),
 old_status text,
 new_status text not null check
   (new_status in ('placed','accepted','preparing','ready','rejected','cancelled')),
 changed_by uuid,
 changed_at timestamptz not null default now()
);
create function public.test_log_status() returns trigger
 language plpgsql security definer set search_path='' as $log$
begin
 if new.status is distinct from old.status then
   insert into public.order_status_history(order_id,old_status,new_status,changed_by)
     values (new.id,old.status,new.status,auth.uid());
 end if;
 return new;
end
$log$;
create trigger log_status_change after update of status on public.orders
  for each row execute function public.test_log_status();
grant select on public.order_status_history to authenticated;
insert into public.orders(id,buyer_id,store_id,status,delivery_address,phone,total_iqd)
values
 ('f0000000-0000-4000-8000-000000000002',
  'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
  '25091ca2-c0da-416c-b634-81b188ee66be','ready','الغزالية، عنوان وهمي','07700000000',35000),
 ('f0000000-0000-4000-8000-000000000003',
  'dddddddd-dddd-4ddd-8ddd-dddddddddddd',
  '25091ca2-c0da-416c-b634-81b188ee66be','ready','الغزالية، عنوان وهمي','07700000000',24000),
 ('f0000000-0000-4000-8000-000000000004',
  'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
  '22222222-2222-4222-8222-222222222222','ready','الغزالية، عنوان وهمي','07700000000',12000);
