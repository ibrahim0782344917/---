-- Disposable PostgreSQL only. Synthetic staff account and minimal authorization.
CREATE SCHEMA private_checkout;
CREATE PUBLICATION supabase_realtime;
CREATE TABLE public.shitreed_admin_staff(user_id uuid PRIMARY KEY REFERENCES auth.users(id),staff_role text NOT NULL,enabled boolean NOT NULL);
INSERT INTO public.shitreed_admin_staff VALUES('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb','support',true);
CREATE FUNCTION public.shitreed_admin_role() RETURNS text LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO '' AS $f$
SELECT CASE WHEN public.shitreed_is_admin() THEN 'super_admin' ELSE (SELECT staff_role FROM public.shitreed_admin_staff WHERE user_id=auth.uid() AND enabled) END
$f$;
REVOKE ALL ON FUNCTION public.shitreed_admin_role() FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.shitreed_admin_role() TO authenticated;
