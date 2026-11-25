-- Disposable PostgreSQL CI fixture only: all identities and orders are synthetic.
CREATE ROLE anon NOLOGIN;
CREATE ROLE authenticated NOLOGIN;
CREATE SCHEMA auth;
CREATE SCHEMA extensions;
CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA extensions;
CREATE TABLE auth.users (
 id uuid PRIMARY KEY,
 raw_app_meta_data jsonb NOT NULL DEFAULT '{}'::jsonb
);
CREATE FUNCTION auth.uid() RETURNS uuid LANGUAGE sql STABLE AS $$
 SELECT nullif(current_setting('request.jwt.claim.sub',true),'')::uuid
$$;
GRANT USAGE ON SCHEMA auth TO anon,authenticated;
GRANT USAGE ON SCHEMA extensions TO authenticated;
GRANT USAGE ON SCHEMA public TO anon,authenticated;
GRANT EXECUTE ON FUNCTION auth.uid() TO anon,authenticated;
INSERT INTO auth.users(id,raw_app_meta_data) VALUES
 ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','{}'),
 ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb','{}'),
 ('cccccccc-cccc-4ccc-8ccc-cccccccccccc','{}'),
 ('dddddddd-dddd-4ddd-8ddd-dddddddddddd','{}'),
 ('eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee','{"shitreed_role":"admin"}');
CREATE TABLE public.stores (
 id uuid PRIMARY KEY,owner_id uuid NOT NULL REFERENCES auth.users(id),
 status text NOT NULL CHECK(status IN('approved','pending','suspended'))
);
INSERT INTO public.stores(id,owner_id,status) VALUES
 ('25091ca2-c0da-416c-b634-81b188ee66be',
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','approved');
CREATE TABLE public.orders (
 id uuid PRIMARY KEY, buyer_id uuid NOT NULL REFERENCES auth.users(id),
 store_id uuid NOT NULL REFERENCES public.stores(id),
 status text NOT NULL DEFAULT 'placed',
 delivery_address text NOT NULL DEFAULT 'Baghdad synthetic street 10',
 payment_method text NOT NULL DEFAULT 'cash_on_delivery',
 total_iqd bigint NOT NULL DEFAULT 25000,
 delivery_fee_iqd bigint NOT NULL DEFAULT 5000,
 delivered_at timestamptz,
 updated_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.orders ADD CONSTRAINT orders_status_check CHECK
 (status IN ('placed','accepted','preparing','ready',
            'delivered','rejected','cancelled'));
CREATE TABLE public.order_status_history (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 order_id uuid NOT NULL REFERENCES public.orders(id),
 old_status text,new_status text NOT NULL,
 changed_by uuid,
 changed_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.order_status_history
 ADD CONSTRAINT order_status_history_new_status_check CHECK
 (new_status IN ('placed','accepted','preparing','ready',
               'delivered','rejected','cancelled'));
CREATE FUNCTION public.synthetic_log_order_status()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
 IF NEW.status IS DISTINCT FROM OLD.status THEN
  INSERT INTO public.order_status_history(order_id,old_status,new_status,changed_by)
   VALUES(NEW.id,OLD.status,NEW.status,auth.uid());
 END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER synthetic_order_audit AFTER UPDATE ON public.orders
 FOR EACH ROW EXECUTE FUNCTION public.synthetic_log_order_status();

CREATE FUNCTION public.shitreed_is_admin()
 RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER
 SET search_path TO '' AS $$
 SELECT (SELECT auth.uid()) IS NOT NULL AND EXISTS(
 SELECT 1 FROM auth.users u WHERE u.id=(SELECT auth.uid())
  AND u.raw_app_meta_data->>'shitreed_role'='admin');
$$;
REVOKE ALL ON FUNCTION public.shitreed_is_admin() FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.shitreed_is_admin() TO authenticated;
INSERT INTO public.orders(id,buyer_id,store_id,status) VALUES
 ('11111111-1111-4111-8111-111111111111',
  'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
  '25091ca2-c0da-416c-b634-81b188ee66be','ready'),
 ('22222222-2222-4222-8222-222222222222',
  'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
  '25091ca2-c0da-416c-b634-81b188ee66be','ready');
