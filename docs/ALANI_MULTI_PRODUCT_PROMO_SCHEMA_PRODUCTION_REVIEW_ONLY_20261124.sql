-- REVIEW ONLY: EXACT TEST SHAPE, not applied to production. 
-- Requires verified backup restore, production change window, and manual audit.
-- Prerequisites: public.stores, public.products, auth.users, private_checkout
-- schema, public.shitreed_is_admin() and public.orders.delivery_fee_iqd.
BEGIN;
CREATE TABLE public.shitreed_store_campaigns (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 store_id uuid NOT NULL REFERENCES public.stores(id) ON DELETE CASCADE,
 product_id uuid REFERENCES public.products(id) ON DELETE SET NULL,
 created_by uuid NOT NULL REFERENCES auth.users(id),
 title text NOT NULL CHECK (char_length(btrim(title)) BETWEEN 3 AND 100),
 description text NOT NULL DEFAULT '' CHECK (char_length(description)<=600),
 image_url text CHECK (image_url IS NULL OR
   (char_length(image_url)<=1024 AND image_url~'^https://[^[:space:]]+$')),
 starts_at timestamptz NOT NULL,
 ends_at timestamptz NOT NULL,
 is_published boolean NOT NULL DEFAULT false,
 created_at timestamptz NOT NULL DEFAULT now(),
 updated_at timestamptz NOT NULL DEFAULT now(),
 CONSTRAINT campaign_window_valid CHECK
 (ends_at>starts_at AND ends_at<=starts_at+interval '90 days')
);
CREATE INDEX shitreed_campaigns_active_window_idx
 ON public.shitreed_store_campaigns(store_id,starts_at,ends_at)
 WHERE is_published;
CREATE INDEX shitreed_campaigns_product_fk_idx
 ON public.shitreed_store_campaigns(product_id) WHERE product_id IS NOT NULL;
CREATE TABLE public.shitreed_campaign_items (
 campaign_id uuid NOT NULL REFERENCES public.shitreed_store_campaigns(id)
  ON DELETE CASCADE,
 product_id uuid NOT NULL REFERENCES public.products(id) ON DELETE RESTRICT,
 sale_price_iqd integer NOT NULL CHECK(sale_price_iqd>0),
 created_at timestamptz NOT NULL DEFAULT now(),
 updated_at timestamptz NOT NULL DEFAULT now(),
 PRIMARY KEY(campaign_id,product_id)
);
CREATE INDEX shitreed_campaign_items_product_idx
 ON public.shitreed_campaign_items(product_id,campaign_id);

CREATE OR REPLACE FUNCTION private_checkout.validate_campaign_item()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
DECLARE c_store uuid; p_store uuid; p_price integer; p_active boolean;
BEGIN
  SELECT store_id INTO c_store FROM public.shitreed_store_campaigns
   WHERE id=NEW.campaign_id;
  SELECT store_id,price_iqd,is_active INTO p_store,p_price,p_active
    FROM public.products WHERE id=NEW.product_id;
  IF c_store IS NULL OR p_store IS NULL OR c_store <> p_store OR NOT p_active
     OR NEW.sale_price_iqd <= 0 OR NEW.sale_price_iqd >= p_price
  THEN RAISE EXCEPTION 'INVALID_CAMPAIGN_PRODUCT_OR_DISCOUNT'; END IF;
  NEW.updated_at=now();
  RETURN NEW;
END $function$;
CREATE TRIGGER campaign_item_validation
 BEFORE INSERT OR UPDATE ON public.shitreed_campaign_items
 FOR EACH ROW EXECUTE FUNCTION private_checkout.validate_campaign_item();
ALTER TABLE public.shitreed_store_campaigns ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.shitreed_campaign_items ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.shitreed_store_campaigns FROM PUBLIC,anon,authenticated;
REVOKE ALL ON public.shitreed_campaign_items FROM PUBLIC,anon,authenticated;
GRANT SELECT ON public.shitreed_store_campaigns TO anon,authenticated;
GRANT INSERT(store_id,product_id,created_by,title,description,image_url,
 starts_at,ends_at,is_published) ON public.shitreed_store_campaigns TO authenticated;
GRANT UPDATE(product_id,title,description,image_url,starts_at,ends_at,is_published)
 ON public.shitreed_store_campaigns TO authenticated;
GRANT SELECT ON public.shitreed_campaign_items TO anon,authenticated;
GRANT INSERT(campaign_id,product_id,sale_price_iqd)
 ON public.shitreed_campaign_items TO authenticated;
GRANT UPDATE(sale_price_iqd) ON public.shitreed_campaign_items TO authenticated;
GRANT DELETE ON public.shitreed_campaign_items TO authenticated;

CREATE POLICY campaign_item_live_read ON public.shitreed_campaign_items
 FOR SELECT TO anon,authenticated
 USING ((EXISTS ( SELECT 1
   FROM (shitreed_store_campaigns c
     JOIN products p ON ((p.id = shitreed_campaign_items.product_id)))
  WHERE ((c.id = shitreed_campaign_items.campaign_id) AND (c.store_id = p.store_id) AND c.is_published AND (c.starts_at <= now()) AND (c.ends_at > now()) AND p.is_active AND (p.price_iqd > shitreed_campaign_items.sale_price_iqd)))));

CREATE POLICY campaign_item_manager_delete ON public.shitreed_campaign_items
 FOR DELETE TO authenticated
 USING ((EXISTS ( SELECT 1
   FROM (shitreed_store_campaigns c
     JOIN stores s ON ((s.id = c.store_id)))
  WHERE ((c.id = shitreed_campaign_items.campaign_id) AND (s.status = 'approved'::text) AND ((s.owner_id = ( SELECT auth.uid() AS uid)) OR ( SELECT shitreed_is_admin() AS shitreed_is_admin))))));

CREATE POLICY campaign_item_manager_insert ON public.shitreed_campaign_items
 FOR INSERT TO authenticated
 WITH CHECK ((EXISTS ( SELECT 1
   FROM ((shitreed_store_campaigns c
     JOIN stores s ON ((s.id = c.store_id)))
     JOIN products p ON ((p.id = shitreed_campaign_items.product_id)))
  WHERE ((c.id = shitreed_campaign_items.campaign_id) AND (s.status = 'approved'::text) AND (p.store_id = s.id) AND p.is_active AND (p.price_iqd > shitreed_campaign_items.sale_price_iqd) AND ((s.owner_id = ( SELECT auth.uid() AS uid)) OR ( SELECT shitreed_is_admin() AS shitreed_is_admin))))));

CREATE POLICY campaign_item_manager_read ON public.shitreed_campaign_items
 FOR SELECT TO authenticated
 USING ((( SELECT shitreed_is_admin() AS shitreed_is_admin) OR (EXISTS ( SELECT 1
   FROM (shitreed_store_campaigns c
     JOIN stores s ON ((s.id = c.store_id)))
  WHERE ((c.id = shitreed_campaign_items.campaign_id) AND (s.owner_id = ( SELECT auth.uid() AS uid)))))));

CREATE POLICY campaign_item_manager_update ON public.shitreed_campaign_items
 FOR UPDATE TO authenticated
 USING ((EXISTS ( SELECT 1
   FROM (shitreed_store_campaigns c
     JOIN stores s ON ((s.id = c.store_id)))
  WHERE ((c.id = shitreed_campaign_items.campaign_id) AND (s.status = 'approved'::text) AND ((s.owner_id = ( SELECT auth.uid() AS uid)) OR ( SELECT shitreed_is_admin() AS shitreed_is_admin))))))
 WITH CHECK ((EXISTS ( SELECT 1
   FROM ((shitreed_store_campaigns c
     JOIN stores s ON ((s.id = c.store_id)))
     JOIN products p ON ((p.id = shitreed_campaign_items.product_id)))
  WHERE ((c.id = shitreed_campaign_items.campaign_id) AND (p.store_id = c.store_id) AND p.is_active AND (p.price_iqd > shitreed_campaign_items.sale_price_iqd) AND (s.status = 'approved'::text) AND ((s.owner_id = ( SELECT auth.uid() AS uid)) OR ( SELECT shitreed_is_admin() AS shitreed_is_admin))))));

CREATE POLICY shitreed_campaign_manager_insert ON public.shitreed_store_campaigns
 FOR INSERT TO authenticated
 WITH CHECK (((created_by = ( SELECT auth.uid() AS uid)) AND (EXISTS ( SELECT 1
   FROM stores s
  WHERE ((s.id = shitreed_store_campaigns.store_id) AND (s.status = 'approved'::text) AND ((s.owner_id = ( SELECT auth.uid() AS uid)) OR ( SELECT shitreed_is_admin() AS shitreed_is_admin))))) AND ((product_id IS NULL) OR (EXISTS ( SELECT 1
   FROM products p
  WHERE ((p.id = shitreed_store_campaigns.product_id) AND (p.store_id = shitreed_store_campaigns.store_id)))))));

CREATE POLICY shitreed_campaign_manager_read ON public.shitreed_store_campaigns
 FOR SELECT TO authenticated
 USING ((( SELECT shitreed_is_admin() AS shitreed_is_admin) OR (EXISTS ( SELECT 1
   FROM stores s
  WHERE ((s.id = shitreed_store_campaigns.store_id) AND (s.owner_id = ( SELECT auth.uid() AS uid)))))));

CREATE POLICY shitreed_campaign_manager_update ON public.shitreed_store_campaigns
 FOR UPDATE TO authenticated
 USING ((EXISTS ( SELECT 1
   FROM stores s
  WHERE ((s.id = shitreed_store_campaigns.store_id) AND (s.status = 'approved'::text) AND ((s.owner_id = ( SELECT auth.uid() AS uid)) OR ( SELECT shitreed_is_admin() AS shitreed_is_admin))))))
 WITH CHECK (((EXISTS ( SELECT 1
   FROM stores s
  WHERE ((s.id = shitreed_store_campaigns.store_id) AND (s.status = 'approved'::text) AND ((s.owner_id = ( SELECT auth.uid() AS uid)) OR ( SELECT shitreed_is_admin() AS shitreed_is_admin))))) AND ((product_id IS NULL) OR (EXISTS ( SELECT 1
   FROM products p
  WHERE ((p.id = shitreed_store_campaigns.product_id) AND (p.store_id = shitreed_store_campaigns.store_id)))))));

CREATE POLICY shitreed_campaign_public_live ON public.shitreed_store_campaigns
 FOR SELECT TO anon,authenticated
 USING ((is_published AND (starts_at <= now()) AND (ends_at > now()) AND (EXISTS ( SELECT 1
   FROM stores s
  WHERE ((s.id = shitreed_store_campaigns.store_id) AND (s.status = 'approved'::text)))) AND ((product_id IS NULL) OR (EXISTS ( SELECT 1
   FROM products p
  WHERE ((p.id = shitreed_store_campaigns.product_id) AND (p.store_id = shitreed_store_campaigns.store_id) AND p.is_active))))));
COMMIT;
