SET LOCAL lock_timeout='3s';
CREATE FUNCTION public.shitreed_verified_admin_role()
RETURNS text LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=''
AS $fn$
BEGIN
 IF auth.uid() IS NULL OR auth.jwt()->>'aal' IS DISTINCT FROM 'aal2' THEN RETURN NULL; END IF;
 IF NOT EXISTS(SELECT 1 FROM auth.sessions s WHERE s.user_id=auth.uid() AND s.id::text=auth.jwt()->>'session_id' AND s.aal::text='aal2' AND (s.not_after IS NULL OR s.not_after>now())) THEN RETURN NULL; END IF;
 RETURN public.shitreed_admin_role();
END;
$fn$;
REVOKE ALL ON FUNCTION public.shitreed_verified_admin_role() FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.shitreed_verified_admin_role() TO authenticated;
CREATE FUNCTION public.alani_avatar_live_session()
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=''
AS $fn$
 SELECT auth.uid() IS NOT NULL AND EXISTS(SELECT 1 FROM auth.sessions s WHERE s.user_id=auth.uid() AND s.id::text=auth.jwt()->>'session_id' AND (s.not_after IS NULL OR s.not_after>now()));
$fn$;
REVOKE ALL ON FUNCTION public.alani_avatar_live_session() FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.alani_avatar_live_session() TO authenticated;
CREATE POLICY alani_avatar_live_session_select ON storage.objects AS RESTRICTIVE FOR SELECT TO authenticated
 USING(bucket_id<>'shitreed-avatars' OR (SELECT public.alani_avatar_live_session()));
CREATE POLICY alani_avatar_live_session_insert ON storage.objects AS RESTRICTIVE FOR INSERT TO authenticated
 WITH CHECK(bucket_id<>'shitreed-avatars' OR (SELECT public.alani_avatar_live_session()));
CREATE POLICY alani_avatar_live_session_update ON storage.objects AS RESTRICTIVE FOR UPDATE TO authenticated
 USING(bucket_id<>'shitreed-avatars' OR (SELECT public.alani_avatar_live_session()))
 WITH CHECK(bucket_id<>'shitreed-avatars' OR (SELECT public.alani_avatar_live_session()));
CREATE POLICY alani_avatar_guest_private ON storage.objects AS RESTRICTIVE FOR ALL TO anon
 USING(bucket_id<>'shitreed-avatars') WITH CHECK(bucket_id<>'shitreed-avatars');

CREATE OR REPLACE FUNCTION public.alani_can_moderate(p_publication_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
select (select auth.uid()) is not null and exists(
 select 1 from public.alani_publications p
 join public.stores s on s.id=p.store_id
 where p.id=p_publication_id and p.store_id='25091ca2-c0da-416c-b634-81b188ee66be'::uuid
 and (s.owner_id=(select auth.uid()) or COALESCE(public.shitreed_verified_admin_role()='super_admin',false)
 or exists(select 1 from public.alani_content_staff sf
 where sf.store_id=s.id and sf.user_id=(select auth.uid())
 and sf.role in ('editor','moderator')))
);
$function$;

CREATE OR REPLACE FUNCTION public.alani_dispatch_delivery(p_order_id uuid, p_courier_id uuid)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
 v_actor uuid:=(SELECT auth.uid());
 v_order public.orders%ROWTYPE;
BEGIN
 IF v_actor IS NULL THEN RAISE EXCEPTION 'LOGIN_REQUIRED'; END IF;
 IF NOT EXISTS (SELECT 1 FROM auth.sessions s WHERE s.user_id=v_actor AND s.id::text=(auth.jwt()->>'session_id') AND (s.not_after IS NULL OR s.not_after>now())) THEN RAISE EXCEPTION 'SESSION_EXPIRED'; END IF;
 SELECT * INTO v_order FROM public.orders o
  WHERE o.id=p_order_id FOR UPDATE;
 IF NOT FOUND OR v_order.store_id <>
  '25091ca2-c0da-416c-b634-81b188ee66be'::uuid
 THEN RAISE EXCEPTION 'ORDER_NOT_FOUND'; END IF;
 IF NOT EXISTS(
  SELECT 1 FROM public.stores s WHERE s.id=v_order.store_id
   AND s.status='approved' AND
   (s.owner_id=v_actor OR COALESCE(public.shitreed_verified_admin_role()='super_admin',false)))
 THEN RAISE EXCEPTION 'PERMISSION_DENIED'; END IF;
 IF v_order.status<>'ready' THEN RAISE EXCEPTION 'ORDER_NOT_READY'; END IF;
 IF p_courier_id IS NULL OR p_courier_id=v_order.buyer_id THEN RAISE EXCEPTION 'INVALID_COURIER'; END IF;
 PERFORM 1 FROM public.alani_delivery_couriers c WHERE c.store_id=v_order.store_id AND c.courier_id=p_courier_id FOR UPDATE;
 IF NOT FOUND OR NOT EXISTS(
   SELECT 1 FROM public.alani_delivery_couriers c
   WHERE c.store_id=v_order.store_id AND c.courier_id=p_courier_id
     AND c.enabled=true)
 THEN RAISE EXCEPTION 'COURIER_NOT_APPROVED'; END IF;
 INSERT INTO public.alani_delivery_jobs(
   order_id,store_id,courier_id,dispatched_by)
 VALUES(p_order_id,v_order.store_id,p_courier_id,v_actor);
 UPDATE public.orders SET
   status='out_for_delivery',updated_at=now()
 WHERE id=p_order_id;
 RETURN 'out_for_delivery';
END $function$;

CREATE OR REPLACE FUNCTION public.alani_evidence_access(p_name text, p_write boolean)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE a uuid:=auth.uid(); k text; target uuid;
BEGIN
 IF a IS NULL OR p_write IS NULL OR p_name IS NULL OR p_name !~ '^(delivery|return)/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/proof[.]jpg$' THEN RETURN false; END IF;
 IF NOT EXISTS(SELECT 1 FROM auth.sessions s WHERE s.user_id=a AND s.id::text=auth.jwt()->>'session_id' AND (s.not_after IS NULL OR s.not_after>now())) THEN RETURN false; END IF;
 k:=split_part(p_name,'/',1); target:=split_part(p_name,'/',2)::uuid;
 IF k='delivery' THEN
  RETURN EXISTS(SELECT 1 FROM public.orders o JOIN public.alani_delivery_jobs j ON j.order_id=o.id JOIN public.stores s ON s.id=o.store_id
   WHERE o.id=target AND o.store_id='25091ca2-c0da-416c-b634-81b188ee66be'::uuid AND
   CASE WHEN p_write THEN o.status='out_for_delivery' AND j.picked_up_at IS NOT NULL AND j.courier_id=a AND EXISTS(SELECT 1 FROM public.alani_delivery_couriers c WHERE c.store_id=o.store_id AND c.courier_id=a AND c.enabled)
   ELSE o.buyer_id=a OR s.owner_id=a OR public.shitreed_verified_admin_role()='super_admin' OR (o.status='out_for_delivery' AND j.courier_id=a AND EXISTS(SELECT 1 FROM public.alani_delivery_couriers c WHERE c.store_id=o.store_id AND c.courier_id=a AND c.enabled)) END);
 ELSE
  RETURN EXISTS(SELECT 1 FROM public.alani_return_requests r JOIN public.stores s ON s.id=r.store_id
   WHERE r.id=target AND r.store_id='25091ca2-c0da-416c-b634-81b188ee66be'::uuid AND
   CASE WHEN p_write THEN r.customer_id=a AND r.status IN ('submitted','reviewing') AND r.reason IN ('damaged','wrong_item','defective','delivery_issue')
   ELSE r.customer_id=a OR s.owner_id=a OR public.shitreed_verified_admin_role()='super_admin' END);
 END IF;
END $function$;

CREATE OR REPLACE FUNCTION public.alani_list_delivery_couriers()
 RETURNS TABLE(courier_id uuid, enabled boolean, active_jobs bigint)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
 v_actor uuid:=(SELECT auth.uid());
 v_store constant uuid:='25091ca2-c0da-416c-b634-81b188ee66be'::uuid;
BEGIN
 IF v_actor IS NULL THEN RAISE EXCEPTION 'LOGIN_REQUIRED'; END IF;
 IF NOT EXISTS (SELECT 1 FROM auth.sessions s WHERE s.user_id=v_actor AND s.id::text=(auth.jwt()->>'session_id') AND (s.not_after IS NULL OR s.not_after>now())) THEN RAISE EXCEPTION 'SESSION_EXPIRED'; END IF;
 IF NOT EXISTS(
   SELECT 1 FROM public.stores s WHERE s.id=v_store
     AND (s.owner_id=v_actor OR COALESCE(public.shitreed_verified_admin_role()='super_admin',false)))
 THEN RAISE EXCEPTION 'STORE_PERMISSION_DENIED'; END IF;
 RETURN QUERY SELECT c.courier_id,c.enabled,
  (SELECT count(*) FROM public.alani_delivery_jobs j
     JOIN public.orders o ON o.id=j.order_id
     WHERE j.courier_id=c.courier_id AND o.status='out_for_delivery')
   FROM public.alani_delivery_couriers c
   WHERE c.store_id=v_store ORDER BY c.added_at DESC LIMIT 100;
END $function$;

CREATE OR REPLACE FUNCTION public.alani_mark_support_read(p_thread_id uuid, p_last_seen_message_id uuid)
 RETURNS timestamp with time zone
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_actor uuid := (SELECT auth.uid());
  v_customer uuid;
  v_store uuid;
  v_message_time timestamptz;
  v_saved_at timestamptz;
BEGIN
  IF v_actor IS NULL THEN RAISE EXCEPTION 'LOGIN_REQUIRED'; END IF;
  IF p_thread_id IS NULL OR p_last_seen_message_id IS NULL
  THEN RAISE EXCEPTION 'INVALID_READ_ACK'; END IF;
  SELECT customer_id,store_id INTO v_customer,v_store
    FROM public.alani_support_threads WHERE id=p_thread_id;
  IF v_customer IS NULL THEN RAISE EXCEPTION 'THREAD_NOT_FOUND'; END IF;
  IF v_customer<>v_actor AND NOT EXISTS (
      SELECT 1 FROM public.stores s
      WHERE s.id=v_store AND s.owner_id=v_actor
    ) AND NOT COALESCE(public.shitreed_verified_admin_role() IN ('super_admin','operations','support'),false)
  THEN RAISE EXCEPTION 'PERMISSION_DENIED'; END IF;
  SELECT m.created_at INTO v_message_time
    FROM public.alani_support_messages m
    WHERE m.id=p_last_seen_message_id AND m.thread_id=p_thread_id;
  IF v_message_time IS NULL THEN RAISE EXCEPTION 'MESSAGE_NOT_IN_THREAD'; END IF;

  INSERT INTO public.alani_support_read_receipts (
    thread_id,user_id,last_read_at
  ) VALUES (p_thread_id,v_actor,v_message_time)
  ON CONFLICT (thread_id,user_id) DO UPDATE SET
    last_read_at=GREATEST(
      public.alani_support_read_receipts.last_read_at,
      EXCLUDED.last_read_at),
    updated_at=now()
  RETURNING last_read_at INTO v_saved_at;
  RETURN v_saved_at;
END $function$;

CREATE OR REPLACE FUNCTION public.alani_order_delivery_status(p_order_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE v_actor uuid:=(SELECT auth.uid());v_order public.orders%ROWTYPE;
 v_job public.alani_delivery_jobs%ROWTYPE;
BEGIN
 IF v_actor IS NULL THEN RAISE EXCEPTION 'LOGIN_REQUIRED'; END IF;
 IF NOT EXISTS (SELECT 1 FROM auth.sessions s WHERE s.user_id=v_actor AND s.id::text=(auth.jwt()->>'session_id') AND (s.not_after IS NULL OR s.not_after>now())) THEN RAISE EXCEPTION 'SESSION_EXPIRED'; END IF;
 SELECT * INTO v_order FROM public.orders WHERE id=p_order_id;
 IF NOT FOUND OR v_order.store_id<>
  '25091ca2-c0da-416c-b634-81b188ee66be'::uuid
 THEN RAISE EXCEPTION 'ORDER_NOT_FOUND'; END IF;
 SELECT * INTO v_job FROM public.alani_delivery_jobs WHERE order_id=p_order_id;
 IF v_order.buyer_id<>v_actor AND NOT EXISTS(
  SELECT 1 FROM public.stores s
   WHERE s.id=v_order.store_id AND s.owner_id=v_actor)
  AND NOT EXISTS (SELECT 1 FROM public.alani_delivery_couriers c WHERE c.store_id=v_job.store_id AND c.courier_id=v_actor AND c.enabled AND v_job.courier_id=v_actor)
  AND NOT COALESCE(public.shitreed_verified_admin_role()='super_admin',false)
 THEN RAISE EXCEPTION 'PERMISSION_DENIED'; END IF;
 RETURN jsonb_build_object(
  'order_id',v_order.id,'status',v_order.status,
  'assigned',v_job.order_id IS NOT NULL,
  'dispatched_at',v_job.dispatched_at,
  'picked_up_at',v_job.picked_up_at,
  'delivered_at',v_job.delivered_at,
  'proof_method',v_job.proof_method,
  'delivery_fee_iqd',v_order.delivery_fee_iqd);
END $function$;

CREATE OR REPLACE FUNCTION public.alani_owner_delivery_jobs()
 RETURNS TABLE(order_id uuid, courier_id uuid, status text, dispatched_at timestamp with time zone, picked_up_at timestamp with time zone, delivered_at timestamp with time zone)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE v_actor uuid:=(SELECT auth.uid());
BEGIN
 IF v_actor IS NULL THEN RAISE EXCEPTION 'LOGIN_REQUIRED'; END IF;
 IF NOT EXISTS (SELECT 1 FROM auth.sessions s WHERE s.user_id=v_actor AND s.id::text=(auth.jwt()->>'session_id') AND (s.not_after IS NULL OR s.not_after>now())) THEN RAISE EXCEPTION 'SESSION_EXPIRED'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.stores s
  WHERE s.id='25091ca2-c0da-416c-b634-81b188ee66be'::uuid AND
  (s.owner_id=v_actor OR COALESCE(public.shitreed_verified_admin_role()='super_admin',false)))
 THEN RAISE EXCEPTION 'STORE_PERMISSION_DENIED'; END IF;
 RETURN QUERY SELECT j.order_id,j.courier_id,o.status,
  j.dispatched_at,j.picked_up_at,j.delivered_at
 FROM public.alani_delivery_jobs j
 JOIN public.orders o ON o.id=j.order_id
 ORDER BY j.dispatched_at DESC LIMIT 100;
END $function$;

CREATE OR REPLACE FUNCTION public.alani_plan_return_resolution(p_request_id uuid, p_kind text, p_amount_iqd bigint, p_outbound_fee_iqd bigint, p_return_fee_iqd bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE a uuid:=auth.uid(); r public.alani_return_requests%rowtype; o public.orders%rowtype;
BEGIN
 IF a IS NULL THEN RAISE EXCEPTION 'LOGIN_REQUIRED'; END IF;
 IF NOT EXISTS(SELECT 1 FROM auth.sessions s WHERE s.user_id=a AND s.id::text=auth.jwt()->>'session_id' AND (s.not_after IS NULL OR s.not_after>now())) THEN RAISE EXCEPTION 'SESSION_EXPIRED'; END IF;
 SELECT * INTO r FROM public.alani_return_requests WHERE id=p_request_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'RETURN_NOT_FOUND'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.stores s WHERE s.id=r.store_id AND (s.owner_id=a OR COALESCE(public.shitreed_verified_admin_role()='super_admin',false))) THEN RAISE EXCEPTION 'PERMISSION_DENIED'; END IF;
 IF r.status<>'approved' THEN RAISE EXCEPTION 'RETURN_NOT_APPROVED'; END IF;
 SELECT * INTO o FROM public.orders WHERE id=r.order_id AND store_id=r.store_id AND status='delivered';
 IF NOT FOUND THEN RAISE EXCEPTION 'ORDER_NOT_DELIVERED'; END IF;
 IF p_kind IS NULL OR p_kind NOT IN ('refund','replacement','compensation','no_payment') OR p_amount_iqd IS NULL OR p_amount_iqd NOT BETWEEN 0 AND o.total_iqd OR p_outbound_fee_iqd IS NULL OR p_outbound_fee_iqd NOT IN (0,5000) OR p_return_fee_iqd IS NULL OR p_return_fee_iqd NOT IN (0,5000) OR (p_kind IN ('replacement','no_payment') AND p_amount_iqd<>0) OR (p_kind IN ('refund','compensation') AND p_amount_iqd=0) OR (r.reason<>'change_mind' AND (p_outbound_fee_iqd<>0 OR p_return_fee_iqd<>0)) THEN RAISE EXCEPTION 'INVALID_RESOLUTION_PLAN'; END IF;
 UPDATE public.alani_return_requests SET resolution_kind=p_kind,planned_amount_iqd=p_amount_iqd,planned_outbound_fee_iqd=p_outbound_fee_iqd,planned_return_fee_iqd=p_return_fee_iqd,updated_at=now() WHERE id=r.id;
 RETURN jsonb_build_object('kind',p_kind,'planned_amount_iqd',p_amount_iqd,'outbound_fee_iqd',p_outbound_fee_iqd,'return_fee_iqd',p_return_fee_iqd,'payment_executed',false);
END;
$function$;

CREATE OR REPLACE FUNCTION public.alani_publish_reviewed(p_id uuid, p_publish boolean)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_user uuid:=(select auth.uid());
 v_store constant uuid:='25091ca2-c0da-416c-b634-81b188ee66be'::uuid;
begin
 if v_user is null or p_publish is null then raise exception 'BAD_REQUEST'; end if;
 if not (exists(select 1 from public.stores where id=v_store and owner_id=v_user)
 or COALESCE(public.shitreed_verified_admin_role()='super_admin',false) or exists(
 select 1 from public.alani_content_staff where store_id=v_store
 and user_id=v_user and role='editor'))
 then raise exception 'PUBLISH_DENIED'; end if;
 update public.alani_publications set
 status=case when p_publish then 'published' else 'draft' end,
 published_at=case when p_publish then now() else null end,
 updated_at=now()
 where id=p_id and store_id=v_store;
 if not found then raise exception 'NO_PUBLICATION'; end if;
 insert into public.alani_moderation_audit(publication_id,actor_id,target_id,action)
 values(p_id,v_user,p_id,case when p_publish then 'publish' else 'unpublish' end);
end $function$;

CREATE OR REPLACE FUNCTION public.alani_review_return(p_request_id uuid, p_new_status text, p_note text)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_actor uuid := (select auth.uid());
  v_request public.alani_return_requests%rowtype;
  v_owner uuid;
begin
  if v_actor is null then raise exception 'LOGIN_REQUIRED'; end if;
 IF NOT EXISTS (SELECT 1 FROM auth.sessions s WHERE s.user_id=v_actor AND s.id::text=(auth.jwt()->>'session_id') AND (s.not_after IS NULL OR s.not_after>now())) THEN RAISE EXCEPTION 'SESSION_EXPIRED'; END IF;
  if p_note is null or char_length(pg_catalog.btrim(p_note)) not between 10 and 1000
    then raise exception 'INVALID_REVIEW_NOTE'; end if;
  select * into v_request from public.alani_return_requests
    where id=p_request_id for update;
  if not found then raise exception 'RETURN_NOT_FOUND'; end if;
  select owner_id into v_owner from public.stores where id=v_request.store_id;
  if (v_owner is distinct from v_actor and not COALESCE(public.shitreed_verified_admin_role()='super_admin',false)) or
     v_request.store_id<>'25091ca2-c0da-416c-b634-81b188ee66be'::uuid
    then raise exception 'PERMISSION_DENIED'; end if;
  if p_new_status is null or not (
    (v_request.status='submitted' and p_new_status in ('reviewing','declined')) or
    (v_request.status='reviewing' and p_new_status in ('approved','declined')) or
    (v_request.status='approved' and p_new_status='resolved')
  ) then raise exception 'INVALID_RETURN_TRANSITION'; end if;
  if p_new_status='resolved' and v_request.resolution_kind is null then raise exception 'RESOLUTION_PLAN_REQUIRED'; end if;
  update public.alani_return_requests
    set status=p_new_status,resolution_note=pg_catalog.btrim(p_note),updated_at=now()
    where id=v_request.id;
  insert into public.alani_return_status_history(return_id,old_status,new_status,changed_by)
    values (v_request.id,v_request.status,p_new_status,v_actor);
  return p_new_status;
end
$function$;

CREATE OR REPLACE FUNCTION public.alani_save_writer_draft(p_id uuid, p_kind text, p_title text, p_body text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_user uuid:=(select auth.uid());v_id uuid;
 v_store constant uuid:='25091ca2-c0da-416c-b634-81b188ee66be'::uuid;
 v_owner boolean;
begin
 if v_user is null then raise exception 'LOGIN_REQUIRED'; end if;
 v_owner:=exists(select 1 from public.stores where id=v_store and owner_id=v_user)
 or COALESCE(public.shitreed_verified_admin_role()='super_admin',false);
 if not v_owner and not exists(select 1 from public.alani_content_staff
 where store_id=v_store and user_id=v_user and role in ('writer','editor'))
 then raise exception 'AUTHOR_DENIED'; end if;
 if p_kind not in ('video','article','recipe','post') or p_kind is null
 or p_title is null or char_length(pg_catalog.btrim(p_title)) not between 3 and 180
 or p_body is null or char_length(p_body)>10000 then raise exception 'BAD_DRAFT'; end if;
 if p_id is null then
 insert into public.alani_publications(store_id,kind,title,body,status,created_by)
 values(v_store,p_kind,pg_catalog.btrim(p_title),p_body,'draft',v_user)
 returning id into v_id;
 else
 update public.alani_publications set kind=p_kind,title=pg_catalog.btrim(p_title),
 body=p_body,updated_at=now() where id=p_id and store_id=v_store and status='draft'
 and (created_by=v_user or v_owner or exists(
 select 1 from public.alani_content_staff where store_id=v_store
 and user_id=v_user and role='editor')) returning id into v_id;
 if v_id is null then raise exception 'DRAFT_PERMISSION_DENIED'; end if;
 end if;
 return v_id;
end $function$;

CREATE OR REPLACE FUNCTION public.alani_send_support_message(p_thread_id uuid, p_body text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
 v_actor uuid:=(SELECT auth.uid());
 v_thread public.alani_support_threads%ROWTYPE;
 v_id uuid;
BEGIN
 IF v_actor IS NULL THEN RAISE EXCEPTION 'LOGIN_REQUIRED'; END IF;
 IF p_thread_id IS NULL OR p_body IS NULL
  OR char_length(btrim(p_body)) NOT BETWEEN 1 AND 1500
 THEN RAISE EXCEPTION 'INVALID_MESSAGE'; END IF;
 SELECT * INTO v_thread FROM public.alani_support_threads
 WHERE id=p_thread_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'THREAD_NOT_FOUND'; END IF;
 IF v_thread.customer_id<>v_actor AND
  NOT EXISTS(SELECT 1 FROM public.stores s
    WHERE s.id=v_thread.store_id AND s.owner_id=v_actor)
  AND NOT COALESCE(public.shitreed_verified_admin_role() IN ('super_admin','operations','support'),false)
 THEN RAISE EXCEPTION 'PERMISSION_DENIED'; END IF;
 IF (SELECT count(*) FROM public.alani_support_messages
      WHERE thread_id=p_thread_id AND sender_id=v_actor
        AND created_at>now()-interval '1 minute')>=12
 THEN RAISE EXCEPTION 'RATE_LIMIT'; END IF;
 INSERT INTO public.alani_support_messages(thread_id,sender_id,body)
 VALUES(p_thread_id,v_actor,btrim(p_body)) RETURNING id INTO v_id;
 UPDATE public.alani_support_threads SET updated_at=now() WHERE id=p_thread_id;
 RETURN v_id;
END $function$;

CREATE OR REPLACE FUNCTION public.alani_set_content_staff(p_user_id uuid, p_role text, p_enabled boolean)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_user uuid:=(select auth.uid());
 v_store constant uuid:='25091ca2-c0da-416c-b634-81b188ee66be'::uuid;
begin
 if v_user is null or not(
 exists(select 1 from public.stores where id=v_store and owner_id=v_user)
 or COALESCE(public.shitreed_verified_admin_role()='super_admin',false)) then raise exception 'STAFF_DENIED'; end if;
 if p_user_id is null or p_enabled is null
 or (p_enabled and (p_role is null or p_role not in ('writer','editor','moderator')))
 then raise exception 'BAD_STAFF_ROLE'; end if;
 if p_enabled then
 insert into public.alani_content_staff(store_id,user_id,role,granted_by)
 values(v_store,p_user_id,p_role,v_user)
 on conflict(store_id,user_id) do update
 set role=excluded.role,granted_by=excluded.granted_by;
 else
 delete from public.alani_content_staff where store_id=v_store and user_id=p_user_id;
 end if;
 insert into public.alani_moderation_audit(publication_id,actor_id,target_id,action)
 values(null,v_user,p_user_id,case when p_enabled then 'role:'||p_role else 'role:revoked' end);
end $function$;

CREATE OR REPLACE FUNCTION public.alani_set_delivery_courier(p_courier_id uuid, p_enabled boolean)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
 v_actor uuid := (SELECT auth.uid());
 v_store constant uuid:='25091ca2-c0da-416c-b634-81b188ee66be'::uuid;
BEGIN
 IF v_actor IS NULL THEN RAISE EXCEPTION 'LOGIN_REQUIRED'; END IF;
 IF NOT EXISTS (SELECT 1 FROM auth.sessions s WHERE s.user_id=v_actor AND s.id::text=(auth.jwt()->>'session_id') AND (s.not_after IS NULL OR s.not_after>now())) THEN RAISE EXCEPTION 'SESSION_EXPIRED'; END IF;
 IF NOT EXISTS (SELECT 1 FROM public.stores s
     WHERE s.id=v_store AND s.status='approved'
       AND (s.owner_id=v_actor OR COALESCE(public.shitreed_verified_admin_role()='super_admin',false)))
 THEN RAISE EXCEPTION 'STORE_PERMISSION_DENIED'; END IF;
 IF p_courier_id IS NULL OR p_enabled IS NULL OR
    NOT EXISTS (SELECT 1 FROM auth.users u WHERE u.id=p_courier_id)
 THEN RAISE EXCEPTION 'COURIER_ACCOUNT_NOT_FOUND'; END IF;
 PERFORM 1 FROM public.alani_delivery_couriers c WHERE c.store_id=v_store AND c.courier_id=p_courier_id FOR UPDATE;
 IF NOT p_enabled AND EXISTS(
   SELECT 1 FROM public.alani_delivery_jobs j
   JOIN public.orders o ON o.id=j.order_id
   WHERE j.courier_id=p_courier_id AND o.status='out_for_delivery'
 ) THEN RAISE EXCEPTION 'COURIER_HAS_ACTIVE_DELIVERIES'; END IF;
 INSERT INTO public.alani_delivery_couriers(
   store_id,courier_id,enabled,added_by)
 VALUES(v_store,p_courier_id,p_enabled,v_actor)
 ON CONFLICT (store_id,courier_id) DO UPDATE SET
  enabled=EXCLUDED.enabled, updated_at=now();
 RETURN p_enabled;
END $function$;

CREATE OR REPLACE FUNCTION public.alani_support_presence_ping(p_thread_id uuid, p_typing boolean)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE v_actor uuid:=(SELECT auth.uid()); v_now timestamptz:=clock_timestamp();
BEGIN
 IF v_actor IS NULL OR p_typing IS NULL THEN RAISE EXCEPTION 'LOGIN_REQUIRED'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.alani_support_threads t JOIN public.stores s ON s.id=t.store_id WHERE t.id=p_thread_id AND s.status='approved' AND
 (t.customer_id=v_actor OR s.owner_id=v_actor OR COALESCE(public.shitreed_verified_admin_role() IN ('super_admin','operations','support'),false))) THEN RAISE EXCEPTION 'PERMISSION_DENIED'; END IF;
 INSERT INTO private_checkout.alani_support_presence(thread_id,user_id,last_seen_at,typing_until)
 VALUES(p_thread_id,v_actor,v_now,CASE WHEN p_typing THEN v_now+interval '12 seconds' END)
 ON CONFLICT(thread_id,user_id) DO UPDATE SET last_seen_at=excluded.last_seen_at,typing_until=excluded.typing_until
 WHERE private_checkout.alani_support_presence.last_seen_at<=v_now-interval '2 seconds';
 RETURN true;
END $function$;

CREATE OR REPLACE FUNCTION public.alani_support_presence_read(p_thread_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE v_actor uuid:=(SELECT auth.uid()); v_customer uuid; v_owner uuid; v_seen timestamptz; v_typing boolean; v_read timestamptz;
BEGIN
 IF v_actor IS NULL THEN RAISE EXCEPTION 'LOGIN_REQUIRED'; END IF;
 SELECT t.customer_id,s.owner_id INTO v_customer,v_owner FROM public.alani_support_threads t JOIN public.stores s ON s.id=t.store_id WHERE t.id=p_thread_id AND s.status='approved';
 IF v_customer IS NULL OR (v_customer<>v_actor AND v_owner IS DISTINCT FROM v_actor AND NOT COALESCE(public.shitreed_verified_admin_role() IN ('super_admin','operations','support'),false)) THEN RAISE EXCEPTION 'PERMISSION_DENIED'; END IF;
 -- Customer sees only aggregate authorized team activity; staff see only the customer.
 SELECT max(p.last_seen_at),coalesce(bool_or(p.typing_until>now()),false) INTO v_seen,v_typing
 FROM private_checkout.alani_support_presence p
 WHERE p.thread_id=p_thread_id AND
 ((v_actor<>v_customer AND p.user_id=v_customer) OR
 (v_actor=v_customer AND p.user_id<>v_customer AND (p.user_id=v_owner OR EXISTS(SELECT 1 FROM auth.users u WHERE u.id=p.user_id AND u.raw_app_meta_data->>'shitreed_role'='admin') OR EXISTS(SELECT 1 FROM public.shitreed_admin_staff a WHERE a.user_id=p.user_id AND a.enabled AND a.staff_role IN ('operations','support')))));
 SELECT max(r.last_read_at) INTO v_read FROM public.alani_support_read_receipts r
 WHERE r.thread_id=p_thread_id AND
 ((v_actor<>v_customer AND r.user_id=v_customer) OR
 (v_actor=v_customer AND r.user_id<>v_customer AND (r.user_id=v_owner OR EXISTS(SELECT 1 FROM auth.users u WHERE u.id=r.user_id AND u.raw_app_meta_data->>'shitreed_role'='admin') OR EXISTS(SELECT 1 FROM public.shitreed_admin_staff a WHERE a.user_id=r.user_id AND a.enabled AND a.staff_role IN ('operations','support')))));
 RETURN jsonb_build_object('online',COALESCE(v_seen>now()-interval '45 seconds',false),'typing',v_typing,'last_seen_at',CASE WHEN v_seen>now()-interval '7 days' THEN date_trunc('minute',v_seen) END,'peer_read_at',v_read);
END $function$;

CREATE OR REPLACE FUNCTION public.alani_support_unread_counts()
 RETURNS TABLE(thread_id uuid, unread_count bigint)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE v_actor uuid := (SELECT auth.uid());
BEGIN
  IF v_actor IS NULL THEN RAISE EXCEPTION 'LOGIN_REQUIRED'; END IF;
  RETURN QUERY
    SELECT t.id,(
      SELECT count(*)
      FROM public.alani_support_messages m
      WHERE m.thread_id=t.id AND m.sender_id<>v_actor
        AND m.created_at>COALESCE(r.last_read_at,'-infinity'::timestamptz)
    )
    FROM public.alani_support_threads t
    LEFT JOIN public.alani_support_read_receipts r
      ON r.thread_id=t.id AND r.user_id=v_actor
    WHERE t.customer_id=v_actor
      OR EXISTS (
        SELECT 1 FROM public.stores s
        WHERE s.id=t.store_id AND s.owner_id=v_actor
      )
      OR COALESCE(public.shitreed_verified_admin_role() IN ('super_admin','operations','support'),false)
    ORDER BY t.updated_at DESC
    LIMIT 100;
END $function$;

CREATE OR REPLACE FUNCTION public.alani_wallet_admin_requests()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE result jsonb;
BEGIN
 IF auth.uid() IS NULL OR public.shitreed_verified_admin_role() IS DISTINCT FROM 'super_admin' THEN RAISE EXCEPTION 'SUPER_ADMIN_REQUIRED'; END IF;
 SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY x.submitted_at DESC),'[]'::jsonb) INTO result
 FROM (SELECT r.id,r.amount_iqd,r.provider_code,r.declared_reference,r.proof_object_path,r.submitted_at,
 coalesce((SELECT v.decision FROM private_checkout.alani_wallet_topup_reviews v WHERE v.request_id=r.id ORDER BY v.created_at DESC,v.id DESC LIMIT 1),'submitted') AS status
 FROM private_checkout.alani_wallet_topup_requests r WHERE r.submitted_at IS NOT NULL ORDER BY r.submitted_at DESC LIMIT 50) x;
 RETURN result;
END $function$;

CREATE OR REPLACE FUNCTION public.alani_wallet_admin_review(p_id uuid, p_decision text, p_reason text)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE a uuid:=auth.uid(); r private_checkout.alani_wallet_topup_requests%ROWTYPE; previous text;
BEGIN
 IF a IS NULL OR public.shitreed_verified_admin_role() IS DISTINCT FROM 'super_admin' THEN RAISE EXCEPTION 'SUPER_ADMIN_REQUIRED'; END IF;
 IF p_decision IS NULL OR p_decision NOT IN ('under_review','needs_information','rejected') OR p_reason IS NULL OR char_length(btrim(p_reason)) NOT BETWEEN 12 AND 1000 THEN RAISE EXCEPTION 'INVALID_REVIEW'; END IF;
 SELECT * INTO r FROM private_checkout.alani_wallet_topup_requests WHERE id=p_id AND submitted_at IS NOT NULL FOR UPDATE;
 IF NOT FOUND OR r.user_id=a THEN RAISE EXCEPTION 'REQUEST_NOT_FOUND_OR_SELF_REVIEW'; END IF;
 SELECT v.decision INTO previous FROM private_checkout.alani_wallet_topup_reviews v WHERE v.request_id=r.id ORDER BY v.created_at DESC,v.id DESC LIMIT 1;
 IF previous IN ('rejected','externally_verified') THEN RAISE EXCEPTION 'REVIEW_FINAL'; END IF;
 IF previous=p_decision THEN RETURN previous; END IF;
 INSERT INTO private_checkout.alani_wallet_topup_reviews(request_id,reviewer_id,decision,reason) VALUES(r.id,a,p_decision,btrim(p_reason));
 RETURN p_decision;
END $function$;

CREATE OR REPLACE FUNCTION public.alani_wallet_proof_access(p_path text, p_write boolean)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE a uuid:=auth.uid(); r private_checkout.alani_wallet_topup_requests%ROWTYPE;
BEGIN
 IF a IS NULL OR p_write IS NULL OR p_path IS NULL THEN RETURN false; END IF;
 SELECT * INTO r FROM private_checkout.alani_wallet_topup_requests WHERE proof_object_path=p_path;
 IF NOT FOUND THEN RETURN false; END IF;
 IF p_write THEN RETURN r.user_id=a AND r.submitted_at IS NULL AND coalesce((public.alani_wallet_status()->>'intake_enabled')::boolean,false)
 AND EXISTS(SELECT 1 FROM private_checkout.alani_wallet_allowed_providers WHERE code=r.provider_code AND enabled); END IF;
 RETURN r.user_id=a OR (r.submitted_at IS NOT NULL AND public.shitreed_verified_admin_role() IS NOT DISTINCT FROM 'super_admin');
END $function$;

CREATE OR REPLACE FUNCTION public.shitreed_admin_change(p_section text, p_id uuid, p_action text, p_reason text)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_role text := public.shitreed_verified_admin_role();
  v_actor uuid := auth.uid();
  v_store public.stores%rowtype;
  v_product public.products%rowtype;
  v_order public.orders%rowtype;
  v_old text;
  v_next text;
begin
  if v_role is null then raise exception 'ADMIN_ACCESS_REQUIRED'; end if;
  if p_id is null or p_reason is null or
     char_length(btrim(p_reason)) not between 12 and 1000 then
    raise exception 'VALID_REASON_REQUIRED';
  end if;
  if p_section = 'stores' and v_role in
    ('super_admin','operations','merchant_reviewer') then
    if char_length(btrim(p_reason)) < 20 then
      raise exception 'STORE_REVIEW_REASON_TOO_SHORT';
    end if;
    select * into v_store from public.stores where id = p_id for update;
    if not found then raise exception 'STORE_NOT_FOUND'; end if;
    v_old := v_store.status;
    if p_action = 'approve' and v_old = 'pending' then
      if char_length(btrim(v_store.address)) < 8 then
        raise exception 'STORE_DETAILS_INCOMPLETE';
      end if;
      v_next := 'approved';
    elsif p_action = 'reject' and v_old = 'pending' then
      v_next := 'suspended';
    elsif p_action = 'suspend' and v_old = 'approved' then
      v_next := 'suspended';
    elsif p_action = 'reopen' and v_old = 'suspended' then
      v_next := 'pending';
    else
      raise exception 'INVALID_STORE_TRANSITION';
    end if;
    update public.stores set status = v_next where id = p_id;
    -- Keep the established store-review audit alongside the admin activity log.
    insert into public.store_review_audit
      (store_id, admin_id, old_status, new_status, reason)
    values (p_id, v_actor, v_old, v_next, btrim(p_reason));
  elsif p_section = 'products' and v_role in
    ('super_admin','operations','catalog_manager') then
    select * into v_product from public.products where id = p_id for update;
    if not found then raise exception 'PRODUCT_NOT_FOUND'; end if;
    v_old := case when v_product.is_active then 'active' else 'inactive' end;
    if p_action = 'disable' and v_product.is_active then
      v_next := 'inactive';
      update public.products set is_active = false where id = p_id;
    elsif p_action = 'enable' and not v_product.is_active then
      if not exists (select 1 from public.stores s
        where s.id = v_product.store_id and s.status = 'approved') then
        raise exception 'STORE_NOT_APPROVED';
      end if;
      v_next := 'active';
      update public.products set is_active = true where id = p_id;
    else
      raise exception 'INVALID_PRODUCT_TRANSITION';
    end if;
  elsif p_section = 'orders' and v_role in
    ('super_admin','operations','support') then
    select * into v_order from public.orders where id = p_id for update;
    if not found then raise exception 'ORDER_NOT_FOUND'; end if;
    v_old := v_order.status;
    if p_action = 'accept' and v_old = 'placed' then
      v_next := 'accepted';
    elsif p_action = 'prepare' and v_old = 'accepted' then
      v_next := 'preparing';
    elsif p_action = 'ready' and v_old = 'preparing' then
      v_next := 'ready';
    elsif p_action = 'reject' and v_old = 'placed' then
      v_next := 'rejected';
    elsif p_action = 'cancel' and v_old in ('placed','accepted','preparing') then
      v_next := 'cancelled';
    else
      raise exception 'INVALID_ORDER_TRANSITION';
    end if;
    if v_next in ('cancelled','rejected') then
      update public.products p
        set stock_quantity = p.stock_quantity + i.quantity
        from public.order_items i
        where i.order_id = p_id and i.product_id = p.id;
    end if;
    update public.orders set status = v_next, updated_at = now()
      where id = p_id;
  else
    raise exception 'ACTION_NOT_ALLOWED';
  end if;
  insert into public.shitreed_admin_activity
    (actor_id, section, entity_id, action, before_state, after_state, reason)
    values (v_actor, p_section, p_id, p_action, v_old, v_next, btrim(p_reason));
  return v_next;
end;
$function$;

CREATE OR REPLACE FUNCTION public.shitreed_admin_dashboard()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_role text := public.shitreed_verified_admin_role();
begin
  if v_role is null then raise exception 'ADMIN_ACCESS_REQUIRED'; end if;
  return jsonb_build_object(
    'stores', (select count(*) from public.stores),
    'pending_stores', (select count(*) from public.stores where status = 'pending'),
    'approved_stores', (select count(*) from public.stores where status = 'approved'),
    'products', (select count(*) from public.products),
    'active_products', (select count(*) from public.products where is_active = true),
    'orders', (select count(*) from public.orders),
    'open_orders', (select count(*) from public.orders
      where status in ('placed','accepted','preparing','ready')),
    'order_value_iqd', (select coalesce(sum(total_iqd),0) from public.orders
      where status not in ('cancelled','rejected')),
    'customers', (select count(*) from public.customer_profiles)
  );
end;
$function$;

CREATE OR REPLACE FUNCTION public.shitreed_admin_find_user(p_email text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_result jsonb;
begin
 if public.shitreed_verified_admin_role() is distinct from 'super_admin'
   then raise exception 'SUPER_ADMIN_REQUIRED'; end if;
 if p_email is null or length(btrim(p_email)) not between 5 and 254
   or strpos(p_email,'@')=0 then raise exception 'INVALID_EMAIL'; end if;
 select jsonb_build_object('id',u.id,'email',u.email)
 into v_result from auth.users u
 where lower(u.email)=lower(btrim(p_email)) limit 1;
 return v_result;
end;
$function$;

CREATE OR REPLACE FUNCTION public.shitreed_admin_insights()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
 v_role text := public.shitreed_verified_admin_role();
 v_day date;
 v_count bigint;
 v_value bigint;
 v_points jsonb := '[]'::jsonb;
begin
 if v_role is null then raise exception 'ADMIN_ACCESS_REQUIRED'; end if;
 for v_day in select (current_date - n)::date from generate_series(6,0,-1) n loop
   select count(*),coalesce(sum(total_iqd) filter
      (where status not in ('cancelled','rejected')),0)
   into v_count,v_value from public.orders
   where created_at >= v_day::timestamptz
     and created_at < (v_day+1)::timestamptz;
   v_points := v_points || jsonb_build_array(jsonb_build_object(
     'date',v_day::text,'orders',v_count,'order_value_iqd',v_value));
 end loop;
 return jsonb_build_object('daily',v_points,
   'notice','Order value is NOT collected payments or net revenue');
end;
$function$;

CREATE OR REPLACE FUNCTION public.shitreed_admin_inventory_adjust(p_product_id uuid, p_delta integer, p_reason text)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
 v_role text := public.shitreed_verified_admin_role();
 v_product public.products%rowtype;
 v_new bigint;
begin
 if v_role not in ('super_admin','operations','catalog_manager')
   or v_role is null then raise exception 'ADMIN_ACCESS_REQUIRED'; end if;
 if p_product_id is null or p_delta is null or p_delta=0
   or p_delta not between -10000 and 10000 or p_reason is null
   or char_length(btrim(p_reason)) not between 20 and 1000 then
   raise exception 'INVALID_INVENTORY_ADJUSTMENT';
 end if;
 select * into v_product from public.products
   where id=p_product_id for update;
 if not found then raise exception 'PRODUCT_NOT_FOUND'; end if;
 v_new := v_product.stock_quantity::bigint + p_delta::bigint;
 if v_new < 0 or v_new > 10000000 then
   raise exception 'INVENTORY_OUT_OF_RANGE'; end if;
 update public.products set stock_quantity=v_new::integer
  where id=p_product_id;
 insert into public.shitreed_admin_activity
   (actor_id,section,entity_id,action,before_state,after_state,reason)
 values (auth.uid(),'inventory',p_product_id,'adjust',
   v_product.stock_quantity::text,v_new::text,btrim(p_reason));
 return v_new::integer;
end;
$function$;

CREATE OR REPLACE FUNCTION public.shitreed_admin_order_detail(p_order_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
 v_role text := public.shitreed_verified_admin_role();
 v_order jsonb;
begin
 if v_role not in ('super_admin','operations','support') or v_role is null
   then raise exception 'ADMIN_ACCESS_REQUIRED'; end if;
 if p_order_id is null then raise exception 'INVALID_ORDER_ID'; end if;
 select to_jsonb(o) into v_order from (
   select id,buyer_id,store_id,status,payment_method,total_iqd,
     delivery_address,phone,notes,created_at,updated_at
   from public.orders where id=p_order_id
 ) o;
 if v_order is null then raise exception 'ORDER_NOT_FOUND'; end if;
 return jsonb_build_object('order',v_order,
  'items',coalesce((select jsonb_agg(to_jsonb(i) order by i.product_name)
    from (select product_id,product_name,unit_price_iqd,quantity,line_total_iqd
      from public.order_items where order_id=p_order_id) i),'[]'::jsonb),
  'history',coalesce((select jsonb_agg(to_jsonb(h) order by h.changed_at)
    from (select old_status,new_status,changed_by,changed_at
      from public.order_status_history where order_id=p_order_id) h),'[]'::jsonb));
end;
$function$;

CREATE OR REPLACE FUNCTION public.shitreed_admin_price_update(p_product_id uuid, p_price_iqd integer, p_reason text)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
 v_role text := public.shitreed_verified_admin_role();
 v_product public.products%rowtype;
begin
 if v_role not in ('super_admin','operations','catalog_manager')
   or v_role is null then raise exception 'ADMIN_ACCESS_REQUIRED'; end if;
 if p_product_id is null or p_price_iqd is null
   or p_price_iqd not between 0 and 100000000
   or p_reason is null or char_length(btrim(p_reason)) not between 20 and 1000
   then raise exception 'INVALID_PRICE_UPDATE'; end if;
 select * into v_product from public.products where id=p_product_id for update;
 if not found then raise exception 'PRODUCT_NOT_FOUND'; end if;
 if v_product.price_iqd = p_price_iqd then
   raise exception 'PRICE_UNCHANGED'; end if;
 update public.products set price_iqd=p_price_iqd where id=p_product_id;
 insert into public.shitreed_admin_activity
   (actor_id,section,entity_id,action,before_state,after_state,reason)
 values (auth.uid(),'pricing',p_product_id,'set_price',
   v_product.price_iqd::text,p_price_iqd::text,btrim(p_reason));
 return p_price_iqd;
end;
$function$;

CREATE OR REPLACE FUNCTION public.shitreed_admin_rows(p_section text, p_limit integer DEFAULT 30, p_offset integer DEFAULT 0)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_role text := public.shitreed_verified_admin_role();
  v_items jsonb := '[]'::jsonb;
begin
  if v_role is null then raise exception 'ADMIN_ACCESS_REQUIRED'; end if;
  if p_limit is null or p_offset is null or p_limit not between 1 and 100 or p_offset < 0 or p_offset > 100000 then
    raise exception 'INVALID_PAGINATION';
  end if;
  if p_section = 'stores' then
    select coalesce(jsonb_agg(to_jsonb(x)), '[]'::jsonb) into v_items
    from (
      select id, owner_id, name, area, category, address, phone,
        status, latitude, longitude, created_at from public.stores
      order by created_at desc, id limit p_limit offset p_offset
    ) x;
  elsif p_section = 'products' then
    select coalesce(jsonb_agg(to_jsonb(x)), '[]'::jsonb) into v_items
    from (
      select id, store_id, name, price_iqd, stock_quantity,
        is_active, created_at from public.products
      order by created_at desc, id limit p_limit offset p_offset
    ) x;
  elsif p_section = 'orders' and
    v_role in ('super_admin','operations','support') then
    select coalesce(jsonb_agg(to_jsonb(x)), '[]'::jsonb) into v_items
    from (
      select id, buyer_id, store_id, status, payment_method, total_iqd,
        delivery_address, phone, created_at, updated_at from public.orders
      order by created_at desc, id limit p_limit offset p_offset
    ) x;
  elsif p_section = 'customers' and
    v_role in ('super_admin','operations','support') then
    select coalesce(jsonb_agg(to_jsonb(x)), '[]'::jsonb) into v_items
    from (
      select id, display_name, created_at from public.customer_profiles
      order by created_at desc, id limit p_limit offset p_offset
    ) x;
  elsif p_section = 'staff' and v_role = 'super_admin' then
    select coalesce(jsonb_agg(to_jsonb(x)), '[]'::jsonb) into v_items
    from (
      select user_id, staff_role, enabled, assigned_by, updated_at
      from public.shitreed_admin_staff
      order by updated_at desc, user_id limit p_limit offset p_offset
    ) x;
  elsif p_section = 'audit' and v_role in ('super_admin','operations') then
    select coalesce(jsonb_agg(to_jsonb(x)), '[]'::jsonb) into v_items
    from (
      select id, actor_id, section, entity_id, action, before_state,
        after_state, reason, created_at from public.shitreed_admin_activity
      order by created_at desc, id desc limit p_limit offset p_offset
    ) x;
  else
    raise exception 'SECTION_NOT_ALLOWED';
  end if;
  return jsonb_build_object('items', v_items, 'limit', p_limit, 'offset', p_offset);
end;
$function$;

CREATE OR REPLACE FUNCTION public.shitreed_admin_search(p_section text, p_search text DEFAULT ''::text, p_filter text DEFAULT ''::text, p_limit integer DEFAULT 25, p_offset integer DEFAULT 0)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_role text := public.shitreed_verified_admin_role();
  v_search text := btrim(coalesce(p_search,''));
  v_filter text := coalesce(p_filter,'');
  v_total bigint := 0;
  v_items jsonb := '[]'::jsonb;
begin
  if v_role is null then raise exception 'ADMIN_ACCESS_REQUIRED'; end if;
  if p_limit is null or p_limit not between 1 and 50
     or p_offset is null or p_offset not between 0 and 100000
     or char_length(v_search)>80 or char_length(v_filter)>30 then
    raise exception 'INVALID_SEARCH_ARGUMENTS';
  end if;
  if p_section = 'stores' then
    if v_filter not in ('','pending','approved','suspended') then
      raise exception 'INVALID_FILTER';
    end if;
    with matched as (
      select id,owner_id,name,area,category,address,phone,status,
        latitude,longitude,created_at
      from public.stores
      where (v_filter='' or status=v_filter)
        and (v_search='' or name ilike '%'||v_search||'%'
          or area ilike '%'||v_search||'%'
          or category ilike '%'||v_search||'%'
          or id::text ilike '%'||v_search||'%')
    ), page as (
      select * from matched order by created_at desc,id
      limit p_limit offset p_offset
    )
    select (select count(*) from matched),
      coalesce((select jsonb_agg(to_jsonb(page)) from page),'[]'::jsonb)
    into v_total,v_items;
  elsif p_section = 'products' then
    if v_filter not in ('','active','inactive') then
      raise exception 'INVALID_FILTER';
    end if;
    with matched as (
      select id,store_id,name,price_iqd,stock_quantity,is_active,created_at,
        image_url from public.products
      where (v_filter='' or
        (v_filter='active' and is_active=true) or
        (v_filter='inactive' and is_active=false))
        and (v_search='' or name ilike '%'||v_search||'%'
          or id::text ilike '%'||v_search||'%'
          or store_id::text ilike '%'||v_search||'%')
    ), page as (
      select * from matched order by created_at desc,id
      limit p_limit offset p_offset
    )
    select (select count(*) from matched),
      coalesce((select jsonb_agg(to_jsonb(page)) from page),'[]'::jsonb)
    into v_total,v_items;
  elsif p_section='orders' and v_role in
    ('super_admin','operations','support') then
    if v_filter not in
      ('','placed','accepted','preparing','ready','rejected','cancelled') then
      raise exception 'INVALID_FILTER';
    end if;
    with matched as (
      select id,buyer_id,store_id,status,payment_method,total_iqd,
        delivery_address,phone,created_at,updated_at from public.orders
      where (v_filter='' or status=v_filter)
        and (v_search='' or id::text ilike '%'||v_search||'%'
          or store_id::text ilike '%'||v_search||'%'
          or buyer_id::text ilike '%'||v_search||'%'
          or phone ilike '%'||v_search||'%')
    ), page as (
      select * from matched order by created_at desc,id
      limit p_limit offset p_offset
    )
    select (select count(*) from matched),
      coalesce((select jsonb_agg(to_jsonb(page)) from page),'[]'::jsonb)
    into v_total,v_items;
  elsif p_section='customers' and v_role in
    ('super_admin','operations','support') then
    if v_filter<>'' then raise exception 'INVALID_FILTER'; end if;
    with matched as (
      select id,display_name,created_at from public.customer_profiles
      where (v_search='' or display_name ilike '%'||v_search||'%'
        or id::text ilike '%'||v_search||'%')
    ), page as (
      select * from matched order by created_at desc,id
      limit p_limit offset p_offset
    )
    select (select count(*) from matched),
      coalesce((select jsonb_agg(to_jsonb(page)) from page),'[]'::jsonb)
    into v_total,v_items;
  elsif p_section='staff' and v_role='super_admin' then
    if v_filter not in ('','enabled','disabled') then
      raise exception 'INVALID_FILTER';
    end if;
    with matched as (
      select user_id,staff_role,enabled,assigned_by,updated_at
      from public.shitreed_admin_staff
      where (v_filter='' or
        (v_filter='enabled' and enabled=true) or
        (v_filter='disabled' and enabled=false))
        and (v_search='' or user_id::text ilike '%'||v_search||'%'
          or staff_role ilike '%'||v_search||'%')
    ), page as (
      select * from matched order by updated_at desc,user_id
      limit p_limit offset p_offset
    )
    select (select count(*) from matched),
      coalesce((select jsonb_agg(to_jsonb(page)) from page),'[]'::jsonb)
    into v_total,v_items;
  elsif p_section='audit' and v_role in
    ('super_admin','operations') then
    if v_filter not in ('','stores','products','orders','staff','inventory','pricing') then
      raise exception 'INVALID_FILTER';
    end if;
    with matched as (
      select id,actor_id,section,entity_id,action,before_state,
        after_state,reason,created_at
      from public.shitreed_admin_activity
      where (v_filter='' or section=v_filter)
        and (v_search='' or action ilike '%'||v_search||'%'
          or reason ilike '%'||v_search||'%'
          or actor_id::text ilike '%'||v_search||'%')
    ), page as (
      select * from matched order by created_at desc,id desc
      limit p_limit offset p_offset
    )
    select (select count(*) from matched),
      coalesce((select jsonb_agg(to_jsonb(page)) from page),'[]'::jsonb)
    into v_total,v_items;
  else
    raise exception 'SECTION_NOT_ALLOWED';
  end if;
  return jsonb_build_object('items',v_items,'total',v_total,
    'limit',p_limit,'offset',p_offset);
end;
$function$;

CREATE OR REPLACE FUNCTION public.shitreed_admin_set_staff(p_user_id uuid, p_role text, p_enabled boolean, p_reason text)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_old text;
        v_next text;
begin
  if public.shitreed_verified_admin_role() is distinct from 'super_admin' then
    raise exception 'SUPER_ADMIN_REQUIRED';
  end if;
  if p_user_id is null or p_user_id = auth.uid() then
    raise exception 'INVALID_STAFF_MEMBER';
  end if;
  if p_role is null or p_role not in
     ('operations','merchant_reviewer','catalog_manager','support','viewer')
     or p_enabled is null or p_reason is null or
     char_length(btrim(p_reason)) not between 12 and 1000 then
    raise exception 'INVALID_STAFF_ASSIGNMENT';
  end if;
  if not exists (select 1 from auth.users where id = p_user_id) then
    raise exception 'USER_NOT_FOUND';
  end if;
  if exists (select 1 from auth.users u where u.id = p_user_id
    and u.raw_app_meta_data ->> 'shitreed_role' = 'admin') then
    raise exception 'BOOTSTRAP_ADMIN_CANNOT_BE_CHANGED_HERE';
  end if;
  select staff_role || ':' || enabled::text into v_old
    from public.shitreed_admin_staff where user_id = p_user_id for update;
  insert into public.shitreed_admin_staff
    (user_id, staff_role, enabled, assigned_by, updated_at)
  values (p_user_id, p_role, p_enabled, auth.uid(), now())
  on conflict (user_id) do update
    set staff_role = excluded.staff_role,
        enabled = excluded.enabled,
        assigned_by = excluded.assigned_by,
        updated_at = now();
  v_next := p_role || ':' || p_enabled::text;
  insert into public.shitreed_admin_activity
    (actor_id, section, entity_id, action, before_state, after_state, reason)
    values (auth.uid(), 'staff', p_user_id, 'set_staff', v_old, v_next,
      btrim(p_reason));
  return v_next;
end;
$function$;

CREATE OR REPLACE FUNCTION public.shitreed_pending_store_reviews()
 RETURNS TABLE(store_id uuid, store_name text, area text, category text, store_address text, store_phone text, applied_at timestamp with time zone)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if not COALESCE(public.shitreed_verified_admin_role()='super_admin',false) then
    raise exception 'ADMIN_ACCESS_REQUIRED';
  end if;
  return query
  select s.id, s.name, s.area, s.category, s.address, s.phone, s.created_at
    from public.stores s
    where s.status = 'pending'
    order by s.created_at asc
    limit 100;
end;
$function$;

CREATE OR REPLACE FUNCTION public.shitreed_review_store(p_store_id uuid, p_decision text, p_reason text)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_store public.stores%rowtype;
  v_admin uuid := auth.uid();
  v_new_status text;
begin
  if not COALESCE(public.shitreed_verified_admin_role()='super_admin',false) or v_admin is null then
    raise exception 'ADMIN_ACCESS_REQUIRED';
  end if;
  if p_store_id is null or p_reason is null
     or char_length(btrim(p_reason)) not between 20 and 1000 then
    raise exception 'REASON_REQUIRED';
  end if;
  if p_decision is null or p_decision not in ('approve', 'reject') then
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
$function$;
ALTER POLICY alani_staff_read ON public.alani_content_staff USING (user_id=auth.uid() OR EXISTS(SELECT 1 FROM public.stores s WHERE s.id=alani_content_staff.store_id AND s.owner_id=auth.uid()) OR COALESCE(public.shitreed_verified_admin_role()='super_admin',false));
ALTER POLICY alani_audit_moderator ON public.alani_moderation_audit USING (public.alani_can_moderate(publication_id) OR (publication_id IS NULL AND (COALESCE(public.shitreed_verified_admin_role()='super_admin',false) OR EXISTS(SELECT 1 FROM public.stores s WHERE s.id='25091ca2-c0da-416c-b634-81b188ee66be'::uuid AND s.owner_id=auth.uid()))));
ALTER POLICY alani_returns_read_participant ON public.alani_return_requests USING (customer_id=auth.uid() OR EXISTS(SELECT 1 FROM public.stores s WHERE s.id=alani_return_requests.store_id AND s.owner_id=auth.uid()) OR COALESCE(public.shitreed_verified_admin_role()='super_admin',false));
ALTER POLICY alani_support_thread_participants ON public.alani_support_threads USING (customer_id=auth.uid() OR EXISTS(SELECT 1 FROM public.stores s WHERE s.id=alani_support_threads.store_id AND s.owner_id=auth.uid()) OR COALESCE(public.shitreed_verified_admin_role() IN ('super_admin','operations','support'),false));