\set ON_ERROR_STOP on

-- Minimal isolated fixture: never connected to live Supabase.
create role anon;
create role authenticated;
create schema auth;

create table auth.users (
  id uuid primary key,
  raw_app_meta_data jsonb not null default '{}'::jsonb
);
create function auth.uid() returns uuid
  language sql stable as $$
    select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid
  $$;
create table public.stores (
  id uuid primary key,
  owner_id uuid not null references auth.users(id),
  name text not null,
  area text not null,
  category text not null,
  address text not null,
  phone text,
  latitude double precision,
  longitude double precision,
  status text not null default 'pending',
  created_at timestamptz not null default now()
);

\ir ../migrations/20261114113500_verified_store_review.sql
\ir ../migrations/20261114125000_verified_store_geo_contact.sql

insert into auth.users (id, raw_app_meta_data) values
('10000000-0000-4000-8000-000000000001',
  '{"shitreed_role":"admin"}'::jsonb),
('10000000-0000-4000-8000-000000000002', '{}'::jsonb),
('10000000-0000-4000-8000-000000000003', '{}'::jsonb);

insert into public.stores (id, owner_id, name, area, category, address)
values (
'20000000-0000-4000-8000-000000000001',
'10000000-0000-4000-8000-000000000002',
'محل اختبار','المنصور','متاجر','عنوان كامل في بغداد'
);

select set_config('request.jwt.claim.sub',
  '10000000-0000-4000-8000-000000000001',false);

do $test$
declare
  listed_count integer;
  review_state text;
  audit_count integer;
  error_state text;
begin
  select count(*) into listed_count
    from public.shitreed_pending_store_reviews_v2();
  if listed_count <> 1 then
    raise exception 'Admin cannot see pending stores';
  end if;

  begin
    perform public.shitreed_review_store(
      '20000000-0000-4000-8000-000000000001',
      'approve','لقد تحققت من تفاصيل ملكية هذا المحل والمعلومات');
    raise exception 'SHOULD_REJECT_INCOMPLETE';
  exception when others then
    if sqlerrm <> 'STORE_CONTACT_REQUIRED' then
      raise exception 'Expected contact error but got %', sqlerrm;
    end if;
  end;

  update public.stores set phone = '07701234567'
    where id = '20000000-0000-4000-8000-000000000001';

  begin
    perform public.shitreed_review_store(
      '20000000-0000-4000-8000-000000000001',
      'approve','لقد تحققت من تفاصيل ملكية هذا المحل والمعلومات');
    raise exception 'SHOULD_REJECT_MISSING_PIN';
  exception when others then
    if sqlerrm <> 'STORE_MAP_PIN_REQUIRED' then
      raise exception 'Expected pin error but got %', sqlerrm;
    end if;
  end;

  update public.stores set latitude = 33.3152, longitude = 44.3661
    where id = '20000000-0000-4000-8000-000000000001';
  review_state := public.shitreed_review_store(
      '20000000-0000-4000-8000-000000000001',
      'approve','لقد تحققت من تفاصيل ملكية هذا المحل والمعلومات');
  if review_state <> 'approved' then
    raise exception 'Ready store not approved';
  end if;
  select count(*) into audit_count from public.store_review_audit;
  if audit_count <> 1 then
    raise exception 'Review audit was not written';
  end if;

  begin
    update public.stores set longitude = null
      where id = '20000000-0000-4000-8000-000000000001';
    raise exception 'SHOULD_REJECT_REMOVING_PIN';
  exception when others then
    if sqlerrm <> 'STORE_MAP_PIN_REQUIRED' then
      raise exception 'Expected pinned store protection: %', sqlerrm;
    end if;
  end;

  if has_function_privilege('anon',
    'public.shitreed_pending_store_reviews_v2()', 'EXECUTE') then
    raise exception 'Untrusted anonymous role can read pending stores';
  end if;

  raise notice 'Admin can approve only complete Baghdad store; audit and pin protected';
end
$test$;

select set_config('request.jwt.claim.sub',
  '10000000-0000-4000-8000-000000000003',false);

do $test$
begin
  begin
    perform public.shitreed_pending_store_reviews_v2();
    raise exception 'SHOULD_REJECT_NON_ADMIN';
  exception when others then
    if sqlerrm <> 'ADMIN_ACCESS_REQUIRED' then
      raise exception 'Non-admin can see pending stores: %', sqlerrm;
    end if;
  end;
  raise notice 'Non-admin cannot view pending store details';
end
$test$;
