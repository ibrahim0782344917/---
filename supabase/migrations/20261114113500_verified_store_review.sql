-- Production-ready store review boundary for Shitreed.
-- No existing store is auto-approved. No customer/order rows are modified.
-- Administrator access is read from auth.users.raw_app_meta_data, which only
-- the trusted Supabase Admin API/service role can edit (not a user profile).
create table if not exists public.store_review_audit (
  id uuid primary key default gen_random_uuid(),
  store_id uuid not null references public.stores(id) on delete restrict,
  admin_id uuid not null references auth.users(id) on delete restrict,
  old_status text not null,
  new_status text not null check (new_status in ('approved','suspended','pending')),
  reason text not null check (char_length(reason) between 20 and 1000),
  reviewed_at timestamptz not null default now()
);

create index if not exists store_review_audit_store_date_idx
  on public.store_review_audit (store_id, reviewed_at desc);
create index if not exists store_review_audit_admin_date_idx
  on public.store_review_audit (admin_id, reviewed_at desc);

alter table public.store_review_audit enable row level security;
revoke all on public.store_review_audit from public, anon, authenticated;

-- All exposed procedures verify the administrator in trusted SERVER-SIDE
-- auth.users metadata, not editable user_metadata or a client-supplied flag.
create or replace function public.shitreed_is_admin()
returns boolean
language sql stable security definer
set search_path = ''
as $$
  select (select auth.uid()) is not null
    and exists (
      select 1 from auth.users u
       where u.id = (select auth.uid())
         and u.raw_app_meta_data ->> 'shitreed_role' = 'admin'
    );
$$;

revoke all on function public.shitreed_is_admin() from public, anon, authenticated;
grant execute on function public.shitreed_is_admin() to authenticated;

create or replace function public.shitreed_pending_store_reviews()
returns table (
  store_id uuid,
  store_name text,
  area text,
  category text,
  store_address text,
  store_phone text,
  applied_at timestamptz
)
language plpgsql stable security definer
set search_path = ''
as $$
begin
  if not public.shitreed_is_admin() then
    raise exception 'ADMIN_ACCESS_REQUIRED';
  end if;
  return query
  select s.id, s.name, s.area, s.category, s.address, s.phone, s.created_at
    from public.stores s
    where s.status = 'pending'
    order by s.created_at asc
    limit 100;
end;
$$;

revoke all on function public.shitreed_pending_store_reviews()
  from public, anon, authenticated;
grant execute on function public.shitreed_pending_store_reviews()
  to authenticated;

create or replace function public.shitreed_review_store(
  p_store_id uuid, p_decision text, p_reason text
) returns text
language plpgsql security definer
set search_path = ''
as $$
declare
  v_store public.stores%rowtype;
  v_admin uuid := auth.uid();
  v_new_status text;
begin
  if not public.shitreed_is_admin() or v_admin is null then
    raise exception 'ADMIN_ACCESS_REQUIRED';
  end if;
  if p_store_id is null or p_reason is null
     or char_length(btrim(p_reason)) not between 20 and 1000 then
    raise exception 'REASON_REQUIRED';
  end if;
  if p_decision not in ('approve', 'reject') then
    raise exception 'INVALID_REVIEW_DECISION';
  end if;

  select * into v_store from public.stores
    where id = p_store_id for update;
  if not found then
    raise exception 'STORE_NOT_FOUND';
  end if;
  if v_store.status <> 'pending' then
    raise exception 'STORE_NOT_PENDING';
  end if;
  -- The administrator must verify ownership and accuracy of the business
  -- outside this function before selecting Approve. No approval by default.
  if p_decision = 'approve' then
    if char_length(btrim(v_store.name)) < 2
       or char_length(btrim(v_store.area)) < 2
       or char_length(btrim(v_store.address)) < 8 then
      raise exception 'STORE_DETAILS_INCOMPLETE';
    end if;
    v_new_status := 'approved';
  else
    v_new_status := 'suspended';
  end if;

  update public.stores
     set status = v_new_status
   where id = v_store.id;

  insert into public.store_review_audit (
    store_id, admin_id, old_status, new_status, reason
  ) values (
    v_store.id, v_admin, v_store.status, v_new_status, btrim(p_reason)
  );
  return v_new_status;
end;
$$;

revoke all on function public.shitreed_review_store(uuid,text,text)
  from public, anon, authenticated;
grant execute on function public.shitreed_review_store(uuid,text,text)
  to authenticated;
