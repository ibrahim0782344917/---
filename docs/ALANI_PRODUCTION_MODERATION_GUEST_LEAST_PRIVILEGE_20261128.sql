-- Production migration applied 2026-11-28: alani_production_moderation_guest_least_privilege_20261128
-- Restrict moderation helper to signed-in users, preserve public published comments.
ALTER POLICY alani_comments_read ON public.alani_post_comments TO authenticated;
CREATE POLICY alani_comments_public_read ON public.alani_post_comments FOR SELECT TO anon
USING (status = 'approved' AND EXISTS (SELECT 1 FROM public.alani_publications p JOIN public.stores s ON s.id=p.store_id WHERE p.id=alani_post_comments.publication_id AND p.status='published' AND s.status='approved'));
REVOKE EXECUTE ON FUNCTION public.alani_can_moderate(uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.alani_can_moderate(uuid) TO authenticated;
-- Verified: anon moderation execute false; authenticated true; public aggregate retained.
-- Rollback (review before use):
-- GRANT EXECUTE ON FUNCTION public.alani_can_moderate(uuid) TO anon;
-- DROP POLICY alani_comments_public_read ON public.alani_post_comments;
-- ALTER POLICY alani_comments_read ON public.alani_post_comments TO anon, authenticated;
