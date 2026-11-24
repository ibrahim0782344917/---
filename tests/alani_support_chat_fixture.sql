-- All accounts and orders below are synthetic local CI data.
CREATE ROLE anon NOLOGIN;
CREATE ROLE authenticated NOLOGIN;
CREATE SCHEMA auth;
CREATE TABLE auth.users (
 id uuid PRIMARY KEY,
 raw_app_meta_data jsonb NOT NULL DEFAULT '{}'::jsonb
);
CREATE FUNCTION auth.uid() RETURNS uuid LANGUAGE sql STABLE
AS $$ SELECT nullif(current_setting('request.jwt.claim.sub',true),'')::uuid $$;
GRANT USAGE ON SCHEMA auth TO anon,authenticated;
GRANT EXECUTE ON FUNCTION auth.uid() TO anon,authenticated;
GRANT USAGE ON SCHEMA public TO anon,authenticated;
INSERT INTO auth.users(id,raw_app_meta_data) VALUES
 ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','{}'),
 ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb','{}'),
 ('cccccccc-cccc-4ccc-8ccc-cccccccccccc','{}'),
 ('dddddddd-dddd-4ddd-8ddd-dddddddddddd','{}'),
 ('eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee','{"shitreed_role":"admin"}');
CREATE TABLE public.stores (
 id uuid PRIMARY KEY,
 owner_id uuid NOT NULL REFERENCES auth.users(id),
 status text NOT NULL
);
INSERT INTO public.stores(id,owner_id,status) VALUES
 ('25091ca2-c0da-416c-b634-81b188ee66be',
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','approved');
GRANT SELECT ON public.stores TO authenticated;
CREATE FUNCTION public.shitreed_is_admin() RETURNS boolean
LANGUAGE sql SECURITY DEFINER STABLE SET search_path TO '' AS $$
 SELECT (SELECT auth.uid()) IS NOT NULL AND EXISTS(
  SELECT 1 FROM auth.users u WHERE u.id=(SELECT auth.uid())
   AND u.raw_app_meta_data->>'shitreed_role'='admin')
$$;
REVOKE ALL ON FUNCTION public.shitreed_is_admin() FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.shitreed_is_admin() TO authenticated;
