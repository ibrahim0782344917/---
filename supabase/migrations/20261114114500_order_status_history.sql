-- Append-only order history for Shitreed COD orders.
-- Existing orders and merchant inventory are untouched by this migration.
create table if not exists public.order_status_history (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders(id) on delete restrict,
  old_status text,
  new_status text not null check (
    new_status in (
      'placed','accepted','preparing','ready','rejected','cancelled'
    )
  ),
  changed_by uuid references auth.users(id) on delete set null,
  changed_at timestamptz not null default now()
);

create index if not exists order_status_history_order_date_idx
  on public.order_status_history(order_id, changed_at asc);

alter table public.order_status_history enable row level security;
revoke all on public.order_status_history from public, anon, authenticated;
grant select on public.order_status_history to authenticated;

create policy "order participants see status history"
  on public.order_status_history
  for select to authenticated
  using (
    exists (
      select 1 from public.orders o
      where o.id = order_status_history.order_id
    )
  );

create or replace function public.shitreed_log_order_status()
returns trigger
language plpgsql security definer
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    insert into public.order_status_history(
      order_id, old_status, new_status, changed_by
    ) values (
      new.id, null, new.status, auth.uid()
    );
  elsif new.status is distinct from old.status then
    insert into public.order_status_history(
      order_id, old_status, new_status, changed_by
    ) values (
      new.id, old.status, new.status, auth.uid()
    );
  end if;
  return new;
end;
$$;

revoke all on function public.shitreed_log_order_status()
  from public, anon, authenticated;

create trigger shitreed_order_status_history
  after insert or update of status on public.orders
  for each row
  execute function public.shitreed_log_order_status();
