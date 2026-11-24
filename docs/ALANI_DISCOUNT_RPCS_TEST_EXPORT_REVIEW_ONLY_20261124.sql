-- REVIEW ONLY! Extracted from shitreed-test on 2026-11-24.
-- NEVER execute this file on production without verified backup/restore,
-- prerequisite tables/policies, full owner authorization review and integration tests.
-- Functions depend on public.shitreed_store_campaigns,
-- public.shitreed_campaign_items, public.orders.delivery_fee_iqd,
-- private_checkout.web_checkout_requests and approved store products.
-- SECURITY DEFINER functions must be audited for role and input safety.

-- alani_active_campaign_price
CREATE OR REPLACE FUNCTION public.alani_active_campaign_price(p_product_id uuid, p_regular_price_iqd integer)
 RETURNS integer
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
 SELECT LEAST(p_regular_price_iqd, COALESCE((
  SELECT min(ci.sale_price_iqd) FROM public.shitreed_campaign_items ci
  JOIN public.shitreed_store_campaigns c ON c.id=ci.campaign_id
  JOIN public.products p ON p.id=ci.product_id
  JOIN public.stores s ON s.id=p.store_id
  WHERE ci.product_id=p_product_id AND ci.sale_price_iqd>0
    AND ci.sale_price_iqd<p_regular_price_iqd
    AND c.store_id=p.store_id AND c.is_published
    AND c.starts_at<=now() AND c.ends_at>now()
    AND p.is_active AND s.status='approved'
 ),p_regular_price_iqd));
$function$;

-- alani_discount_quote
CREATE OR REPLACE FUNCTION public.alani_discount_quote(p_items jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
AS $function$
DECLARE v_item jsonb;v_id uuid;v_qty integer;v_seen uuid[]:=array[]::uuid[];
v_product public.products%rowtype;v_price integer;v_subtotal bigint:=0;
v_lines jsonb:='[]'::jsonb;v_store constant uuid:='25091ca2-c0da-416c-b634-81b188ee66be'::uuid;
BEGIN
IF p_items IS NULL OR pg_catalog.jsonb_typeof(p_items)<>'array'
OR pg_catalog.jsonb_array_length(p_items) NOT BETWEEN 1 AND 20
THEN RAISE EXCEPTION 'INVALID_ITEMS';END IF;
IF NOT EXISTS(SELECT 1 FROM public.stores WHERE id=v_store AND status='approved')
THEN RAISE EXCEPTION 'STORE_NOT_AVAILABLE';END IF;
FOR v_item IN SELECT value FROM pg_catalog.jsonb_array_elements(p_items) LOOP
IF pg_catalog.jsonb_typeof(v_item)<>'object'
  OR coalesce(v_item->>'product_id','') !~ '^[0-9a-fA-F-]{36}$'
  OR coalesce(v_item->>'quantity','') !~ '^[0-9]{1,2}$'
THEN RAISE EXCEPTION 'INVALID_ITEM';END IF;
v_id:=(v_item->>'product_id')::uuid;v_qty:=(v_item->>'quantity')::integer;
IF v_id=ANY(v_seen) OR v_qty NOT BETWEEN 1 AND 20
THEN RAISE EXCEPTION 'INVALID_OR_DUPLICATE_ITEM';END IF;
v_seen:=pg_catalog.array_append(v_seen,v_id);
SELECT * INTO v_product FROM public.products
 WHERE id=v_id AND store_id=v_store AND is_active=true;
IF NOT FOUND OR v_product.stock_quantity<v_qty
THEN RAISE EXCEPTION 'PRODUCT_UNAVAILABLE';END IF;
v_price:=public.alani_active_campaign_price(v_id,v_product.price_iqd);
v_subtotal:=v_subtotal+v_price::bigint*v_qty;
v_lines:=v_lines||pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object(
 'product_id',v_id,'product_name',v_product.name,'quantity',v_qty,
 'regular_price_iqd',v_product.price_iqd,'unit_price_iqd',v_price,
 'discount_pct', CASE WHEN v_price<v_product.price_iqd THEN
  round(100.0*(v_product.price_iqd-v_price)/v_product.price_iqd)::integer
 ELSE 0 END));
END LOOP;
RETURN pg_catalog.jsonb_build_object('subtotal_iqd',v_subtotal,
'delivery_fee_iqd',5000,'total_iqd',v_subtotal+5000,'lines',v_lines);
END $function$;

-- alani_save_campaign
CREATE OR REPLACE FUNCTION public.alani_save_campaign(p_id uuid, p_store_id uuid, p_title text, p_description text, p_image_url text, p_starts_at timestamp with time zone, p_ends_at timestamp with time zone, p_published boolean, p_items jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
 v_user uuid := (SELECT auth.uid());
 v_store uuid;
 v_campaign uuid;
 v_item jsonb;
 v_product uuid;
 v_sale integer;
 v_regular integer;
 v_seen uuid[]:=array[]::uuid[];
BEGIN
 IF v_user IS NULL THEN RAISE EXCEPTION 'LOGIN_REQUIRED'; END IF;
 IF p_store_id IS NULL OR NOT EXISTS(
  SELECT 1 FROM public.stores s WHERE s.id=p_store_id AND s.status='approved'
    AND (s.owner_id=v_user OR public.shitreed_is_admin())
 ) THEN RAISE EXCEPTION 'STORE_PERMISSION_DENIED'; END IF;
 IF p_title IS NULL OR char_length(btrim(p_title)) NOT BETWEEN 3 AND 100
 OR p_description IS NULL OR char_length(p_description)>600
 OR (p_image_url IS NOT NULL AND
   (char_length(p_image_url)>1024 OR p_image_url !~ '^https://[^[:space:]]+$'))
 OR p_starts_at IS NULL OR p_ends_at IS NULL
 OR p_ends_at<=p_starts_at OR p_ends_at>p_starts_at+interval '90 days'
 OR p_published IS NULL
 OR p_items IS NULL OR jsonb_typeof(p_items)<>'array'
 OR jsonb_array_length(p_items)>30
 THEN RAISE EXCEPTION 'INVALID_CAMPAIGN_DETAILS'; END IF;
 IF p_id IS NOT NULL THEN
   SELECT store_id INTO v_store FROM public.shitreed_store_campaigns
    WHERE id=p_id FOR UPDATE;
   IF v_store IS NULL OR v_store<>p_store_id
   THEN RAISE EXCEPTION 'CAMPAIGN_NOT_FOUND_OR_WRONG_STORE'; END IF;
   v_campaign:=p_id;
   UPDATE public.shitreed_store_campaigns
      SET title=btrim(p_title),description=p_description,image_url=p_image_url,
          starts_at=p_starts_at,ends_at=p_ends_at,is_published=false,
          product_id=NULL,updated_at=now()
     WHERE id=v_campaign;
 ELSE
   INSERT INTO public.shitreed_store_campaigns(
     store_id,created_by,title,description,image_url,starts_at,ends_at,is_published,product_id)
     VALUES(p_store_id,v_user,btrim(p_title),p_description,p_image_url,
           p_starts_at,p_ends_at,false,NULL)
     RETURNING id INTO v_campaign;
 END IF;
 DELETE FROM public.shitreed_campaign_items WHERE campaign_id=v_campaign;
 FOR v_item IN SELECT value FROM jsonb_array_elements(p_items) LOOP
   IF jsonb_typeof(v_item)<>'object'
    OR coalesce(v_item->>'product_id','') !~ '^[0-9a-fA-F-]{36}$'
    OR coalesce(v_item->>'sale_price_iqd','') !~ '^[0-9]{1,9}$'
   THEN RAISE EXCEPTION 'INVALID_DISCOUNT_ITEM'; END IF;
   v_product:=(v_item->>'product_id')::uuid;
   v_sale:=(v_item->>'sale_price_iqd')::integer;
   IF v_product=ANY(v_seen) THEN RAISE EXCEPTION 'DUPLICATE_DISCOUNT_PRODUCT'; END IF;
   v_seen:=array_append(v_seen,v_product);
   SELECT price_iqd INTO v_regular FROM public.products
    WHERE id=v_product AND store_id=p_store_id AND is_active FOR SHARE;
   IF v_regular IS NULL OR v_sale<=0 OR v_sale>=v_regular
   THEN RAISE EXCEPTION 'DISCOUNT_PRICE_MUST_BE_LOWER_THAN_CURRENT_PRICE'; END IF;
   INSERT INTO public.shitreed_campaign_items(campaign_id,product_id,sale_price_iqd)
     VALUES(v_campaign,v_product,v_sale);
 END LOOP;
 UPDATE public.shitreed_store_campaigns
    SET is_published=p_published,updated_at=now() WHERE id=v_campaign;
 RETURN v_campaign;
END $function$;

-- place_alani_cash_order
CREATE OR REPLACE FUNCTION public.place_alani_cash_order(p_items jsonb, p_delivery_address text, p_phone text, p_notes text, p_request_key uuid, p_expected_total_iqd bigint)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_user uuid := (select auth.uid());
  v_store constant uuid := '25091ca2-c0da-416c-b634-81b188ee66be'::uuid;
  v_fee constant bigint := 5000;
  v_order uuid;
  v_existing_hash text;
  v_hash text;
  v_item jsonb;
  v_product public.products%rowtype;
  v_id uuid;
  v_qty integer;
  v_effective_price integer;
  v_total bigint := 5000;
  v_seen uuid[] := array[]::uuid[];
begin
  if v_user is null then raise exception 'LOGIN_REQUIRED'; end if;
  if p_request_key is null then raise exception 'MISSING_REQUEST_KEY'; end if;
  if p_expected_total_iqd is null or
     p_expected_total_iqd < v_fee or p_expected_total_iqd > 100000000000
  then raise exception 'INVALID_TOTAL'; end if;
  if not exists (
    select 1 from public.stores where id = v_store and status = 'approved'
  ) then raise exception 'STORE_NOT_AVAILABLE'; end if;
  if p_delivery_address is null or
     char_length(pg_catalog.btrim(p_delivery_address)) not between 8 and 300
     or p_phone is null or
     char_length(pg_catalog.btrim(p_phone)) not between 8 and 25
     or p_notes is null or char_length(p_notes) > 400
  then raise exception 'INVALID_DELIVERY_DETAILS'; end if;
  if p_items is null or pg_catalog.jsonb_typeof(p_items) <> 'array'
     or pg_catalog.jsonb_array_length(p_items) not between 1 and 20
  then raise exception 'INVALID_ITEMS'; end if;

  v_hash := pg_catalog.md5(v_store::text || '|' || p_items::text ||
    '|' || pg_catalog.btrim(p_delivery_address) ||
    '|' || pg_catalog.btrim(p_phone) || '|' || p_notes ||
    '|' || p_expected_total_iqd::text || '|alani-cod-v1');

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(v_user::text || ':' || p_request_key::text,0)
  );
  select order_id,payload_hash into v_order,v_existing_hash
    from private_checkout.web_checkout_requests
    where buyer_id = v_user and request_key = p_request_key;
  if v_order is not null then
    if v_existing_hash <> v_hash then
      raise exception 'IDEMPOTENCY_PAYLOAD_MISMATCH';
    end if;
    return v_order;
  end if;

  -- Keep the price, inventory, shipping fee, and idempotency record
  -- in ONE database transaction. Any error rolls them all back.
  insert into public.orders(
    buyer_id,store_id,delivery_address,phone,notes,total_iqd,delivery_fee_iqd
  ) values (
    v_user,v_store,pg_catalog.btrim(p_delivery_address),
    pg_catalog.btrim(p_phone),pg_catalog.btrim(p_notes),0,v_fee
  ) returning id into v_order;

  for v_item in select value from pg_catalog.jsonb_array_elements(p_items) loop
    if pg_catalog.jsonb_typeof(v_item) <> 'object' then
      raise exception 'INVALID_ITEM'; end if;
    v_id := (v_item->>'product_id')::uuid;
    v_qty := (v_item->>'quantity')::integer;
    if v_id is null or v_qty is null or
       v_qty not between 1 and 20 or v_id = any(v_seen)
    then raise exception 'INVALID_OR_DUPLICATE_ITEM'; end if;
    v_seen := pg_catalog.array_append(v_seen,v_id);
    select * into v_product from public.products
      where id=v_id and store_id=v_store and is_active=true
      for update;
    if not found then raise exception 'PRODUCT_UNAVAILABLE'; end if;
    if v_product.stock_quantity < v_qty then
      raise exception 'OUT_OF_STOCK'; end if;
    v_effective_price := public.alani_active_campaign_price(v_id,v_product.price_iqd);
    update public.products
      set stock_quantity=stock_quantity-v_qty where id=v_id;
    insert into public.order_items(
      order_id,product_id,product_name,unit_price_iqd,
      quantity,line_total_iqd
    ) values (
      v_order,v_id,v_product.name,v_effective_price,
      v_qty,v_effective_price::bigint*v_qty
    );
    v_total := v_total + v_effective_price::bigint*v_qty;
  end loop;

  if v_total <> p_expected_total_iqd then
    raise exception 'ORDER_TOTAL_CHANGED'; end if;
  update public.orders set total_iqd=v_total where id=v_order;
  insert into private_checkout.web_checkout_requests(
    buyer_id,request_key,payload_hash,order_id
  ) values (v_user,p_request_key,v_hash,v_order);
  return v_order;
end;
$function$;

-- Permissions recorded from the isolated test implementation:
REVOKE ALL ON FUNCTION public.alani_active_campaign_price(uuid,integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.alani_active_campaign_price(uuid,integer) TO anon,authenticated;
REVOKE ALL ON FUNCTION public.alani_discount_quote(jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.alani_discount_quote(jsonb) TO anon,authenticated;
REVOKE ALL ON FUNCTION public.alani_save_campaign(uuid,uuid,text,text,text,timestamptz,timestamptz,boolean,jsonb) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.alani_save_campaign(uuid,uuid,text,text,text,timestamptz,timestamptz,boolean,jsonb) TO authenticated;
REVOKE ALL ON FUNCTION public.place_alani_cash_order(jsonb,text,text,text,uuid,bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.place_alani_cash_order(jsonb,text,text,text,uuid,bigint) TO authenticated;
