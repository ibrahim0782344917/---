-- REVIEW ONLY: do not run against production before verified backup/restore.
-- Buyer-confirmed Al-Ani delivery and owner-controlled return requests.
begin;
alter table public.orders drop constraint if exists orders_status_check;
alter table public.orders add constraint orders_status_check
  check (status in ('placed','accepted','preparing','ready','delivered','rejected','cancelled'));
alter table public.order_status_history drop constraint if exists order_status_history_new_status_check;
alter table public.order_status_history add constraint order_status_history_new_status_check
  check (new_status in ('placed','accepted','preparing','ready','delivered','rejected','cancelled'));

create or replace function public.alani_confirm_received(p_order_id uuid)
returns text language plpgsql security definer set search_path = ''
as $receive$
declare
  v_actor uuid := (select auth.uid());
  v_order public.orders%rowtype;
begin
  if v_actor is null then raise exception 'LOGIN_REQUIRED'; end if;
  select * into v_order from public.orders where id=p_order_id for update;
  if not found or v_order.store_id<>'25091ca2-c0da-416c-b634-81b188ee66be'::uuid
    then raise exception 'ORDER_NOT_FOUND'; end if;
  if v_order.buyer_id<>v_actor then raise exception 'PERMISSION_DENIED'; end if;
  if v_order.status='delivered' then return 'delivered'; end if;
  if v_order.status<>'ready' then raise exception 'INVALID_DELIVERY_STATE'; end if;
  update public.orders set status='delivered',updated_at=now() where id=p_order_id;
  return 'delivered';
end
$receive$;
revoke all on function public.alani_confirm_received(uuid) from public,anon,authenticated;
grant execute on function public.alani_confirm_received(uuid) to authenticated;

create table if not exists public.alani_return_requests (
  id uuid primary key default gen_random_uuid(),
  store_id uuid not null references public.stores(id) on delete restrict,
  order_id uuid not null references public.orders(id) on delete restrict,
  customer_id uuid not null references auth.users(id) on delete restrict,
  reason text not null check (reason in ('change_mind','damaged','wrong_item','defective','delivery_issue')),
  details text not null check (char_length(details) between 15 and 2000),
  status text not null default 'submitted' check
    (status in ('submitted','reviewing','approved','declined','resolved')),
  resolution_note text not null default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create unique index if not exists alani_active_return_once_idx
  on public.alani_return_requests(customer_id,order_id)
  where status in ('submitted','reviewing','approved');
create index if not exists alani_return_store_idx on public.alani_return_requests(store_id,created_at desc);
alter table public.alani_return_requests enable row level security;
revoke all on public.alani_return_requests from public,anon,authenticated;
grant select on public.alani_return_requests to authenticated;
create policy alani_returns_read_participant on public.alani_return_requests
  for select to authenticated using (
    customer_id=(select auth.uid()) or exists (
      select 1 from public.stores s where s.id=store_id
        and s.owner_id=(select auth.uid())
    )
  );

create table if not exists public.alani_return_status_history (
  id uuid primary key default gen_random_uuid(),
  return_id uuid not null references public.alani_return_requests(id) on delete restrict,
  old_status text,
  new_status text not null,
  changed_by uuid references auth.users(id) on delete set null,
  changed_at timestamptz not null default now()
);
create index if not exists alani_return_events_idx
  on public.alani_return_status_history(return_id,changed_at);
alter table public.alani_return_status_history enable row level security;
revoke all on public.alani_return_status_history from public,anon,authenticated;
grant select on public.alani_return_status_history to authenticated;
create policy alani_return_events_participant
  on public.alani_return_status_history for select to authenticated using (
    exists (select 1 from public.alani_return_requests r
      where r.id=return_id and (
        r.customer_id=(select auth.uid()) or exists (
          select 1 from public.stores s where s.id=r.store_id
            and s.owner_id=(select auth.uid())
        )
      )
    )
  );

create or replace function public.alani_request_return(
  p_order_id uuid,p_reason text,p_details text
) returns uuid language plpgsql security definer set search_path=''
as $request$
declare
  v_actor uuid := (select auth.uid());
  v_order public.orders%rowtype;
  v_id uuid;
begin
  if v_actor is null then raise exception 'LOGIN_REQUIRED'; end if;
  if p_reason is null or
    p_reason not in ('change_mind','damaged','wrong_item','defective','delivery_issue')
    or p_details is null or char_length(pg_catalog.btrim(p_details)) not between 15 and 2000
    then raise exception 'INVALID_RETURN_DETAILS'; end if;
  select * into v_order from public.orders where id=p_order_id for update;
  if not found or v_order.store_id<>'25091ca2-c0da-416c-b634-81b188ee66be'::uuid
    then raise exception 'ORDER_NOT_FOUND'; end if;
  if v_order.buyer_id<>v_actor then raise exception 'PERMISSION_DENIED'; end if;
  if v_order.status<>'delivered' then raise exception 'RETURN_REQUIRES_DELIVERY'; end if;
  select id into v_id from public.alani_return_requests
    where order_id=p_order_id and customer_id=v_actor
      and status in ('submitted','reviewing','approved')
    order by created_at desc limit 1;
  if v_id is not null then return v_id; end if;
  insert into public.alani_return_requests(store_id,order_id,customer_id,reason,details)
  values (v_order.store_id,v_order.id,v_actor,p_reason,pg_catalog.btrim(p_details))
  returning id into v_id;
  insert into public.alani_return_status_history(return_id,old_status,new_status,changed_by)
    values (v_id,null,'submitted',v_actor);
  return v_id;
end
$request$;
revoke all on function public.alani_request_return(uuid,text,text) from public,anon,authenticated;
grant execute on function public.alani_request_return(uuid,text,text) to authenticated;

create or replace function public.alani_review_return(
  p_request_id uuid,p_new_status text,p_note text
) returns text language plpgsql security definer set search_path=''
as $review$
declare
  v_actor uuid := (select auth.uid());
  v_request public.alani_return_requests%rowtype;
  v_owner uuid;
begin
  if v_actor is null then raise exception 'LOGIN_REQUIRED'; end if;
  if p_note is null or char_length(pg_catalog.btrim(p_note)) not between 10 and 1000
    then raise exception 'INVALID_REVIEW_NOTE'; end if;
  select * into v_request from public.alani_return_requests
    where id=p_request_id for update;
  if not found then raise exception 'RETURN_NOT_FOUND'; end if;
  select owner_id into v_owner from public.stores where id=v_request.store_id;
  if v_owner is distinct from v_actor or
     v_request.store_id<>'25091ca2-c0da-416c-b634-81b188ee66be'::uuid
    then raise exception 'PERMISSION_DENIED'; end if;
  if not (
    (v_request.status='submitted' and p_new_status in ('reviewing','declined')) or
    (v_request.status='reviewing' and p_new_status in ('approved','declined')) or
    (v_request.status='approved' and p_new_status='resolved')
  ) then raise exception 'INVALID_RETURN_TRANSITION'; end if;
  update public.alani_return_requests
    set status=p_new_status,resolution_note=pg_catalog.btrim(p_note),updated_at=now()
    where id=v_request.id;
  insert into public.alani_return_status_history(return_id,old_status,new_status,changed_by)
    values (v_request.id,v_request.status,p_new_status,v_actor);
  return p_new_status;
end
$review$;
revoke all on function public.alani_review_return(uuid,text,text) from public,anon,authenticated;
grant execute on function public.alani_review_return(uuid,text,text) to authenticated;
commit;
