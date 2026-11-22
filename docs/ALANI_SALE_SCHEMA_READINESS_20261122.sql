-- Metadata-only and safe to call anonymously. Does not authorize opening
-- checkout by itself: the server AND app release flags must still agree.
-- Never creates orders or changes inventory; returns false until migration exists.
create or replace function public.shitreed_alani_checkout_schema_ready()
returns boolean
language sql stable security definer set search_path = ''
as $ready$
  select
    exists (
      select 1 from pg_catalog.pg_attribute a
      where a.attrelid='public.orders'::pg_catalog.regclass
        and a.attname='delivery_fee_iqd' and not a.attisdropped
    )
    and pg_catalog.to_regclass('private_checkout.web_checkout_requests') is not null
    and exists (
      select 1 from pg_catalog.pg_proc p
      where p.oid=pg_catalog.to_regprocedure(
        'public.place_alani_cash_order(jsonb,text,text,text,uuid,bigint)')
        and pg_catalog.has_function_privilege('authenticated',p.oid,'EXECUTE')
    );
$ready$;
revoke all on function public.shitreed_alani_checkout_schema_ready()
  from public,anon,authenticated;
grant execute on function public.shitreed_alani_checkout_schema_ready()
  to anon,authenticated;
