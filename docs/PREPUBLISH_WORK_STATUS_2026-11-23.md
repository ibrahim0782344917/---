# Shitreed — pre-publish implementation checkpoint (23 Nov 2026)

**Hard stop: NO PRODUCTION CHANGES, NO RELEASE SIGNING, NO GOOGLE PLAY PUBLISH, NO LIVE PAYMENTS.**
Design is deliberately left open for the project owner to request revisions.

## Completed and checked in `shitreed-test`
- Database restore baseline: 28 public tables, 44 foreign keys, 42 prior RLS policies.
- Test identities: first account designated admin; second merchant; third spare. First test user's `app_metadata.shitreed_role` is now `admin`, never assign that role via user-editable metadata.
- One-time 5,000 IQD COD delivery charge: stored in `orders.delivery_fee_iqd`; final total calculated in `place_cash_order` on server. Historical orders retain zero shipping amount. Rollback test: 10,000 IQD items + 5,000 IQD delivery = 15,000 IQD.
- Caller-based authorization: 26 privileged SECURITY DEFINER RPCs restricted from `anon`; verified none callable by anon.
- Buyer receipt acknowledgment from `ready` to `delivered`; return-request table, buyer/merchant RLS, and admin review RPC; no refunds or wallet transfers. Test transaction checked workflow then rolled back.
- Store phone fields remain restricted to `anon` and `authenticated`; existing store listing queries explicitly select safe public fields.

## Code updates in review branch
- Cart shows subtotal, delivery, grand total.
- Client order history adds receipt confirmation and an explicit return-request form.
- New delivery quote unit tests.
- Offline debug APK and `flutter test` CI; no signing or deploy.

## Remaining acceptance blockers (must NOT mark as complete)
1. Connected Android APK test on physical phones with independent customer, merchant, admin accounts; offline debug is not the connected app.
2. Audit all remaining SECURITY DEFINER RPCs, protect password and API credentials, test permission boundaries through a real Supabase JWT.
3. Import 4,952 sanitized/approved legacy customer contacts to an isolated, access-controlled staging table, after handling 48 review records; never create Auth accounts or financial orders automatically.
4. Complete return policies (time windows, disputed decisions, delivery evidence, manual payout), real courier workflow and 5,000 IQD delivery UX review.
5. Finish publication management (videos/articles/recipes), rights-cleared video upload/storage, chat/notifications/FCM, account deletion, admin UI, separate merchant app, wallet and points ledger.
6. Payment-provider sandbox and licensed banking integration review — DO NOT ENABLE live payments.
7. End-to-end testing, accessibility, dark/RTL, Google Maps/Places API key restrictions, release key backup, signed AAB; pause all design and Play store tasks pending user instructions.

## Known cautions
- Existing production database has not received the new test-only SQL patch; this branch must not be merged/deployed before a versioned migration and coordinated rollout.
- Test-only SQL scripts are under `supabase/patches/` and should be reconciled with official migrations.
- Legacy contact source is sensitive and is not proof of consent to marketing.
- Finance refunds/returns are manual review records, NOT actual settlements.

## Historical contact staging (separate from authentication)
- Test-only `private_legacy` schema is installed. No `anon` or `authenticated` privileges.
- All 48 flagged records have been copied into the protected `private_legacy.review_queue` with `pending` status. Compared every source field to the original workbook using an aggregate hash; all match.
- Import SQL has been created locally for the separate 4,952 ready contacts, but **not yet executed in Supabase**; staging count remains 0 until a private SQL upload through Termux, with operator-supplied test credentials. This personal-data SQL file must never be committed to GitHub or exposed publicly.
- Source name quality: 4,418 rows use the literal placeholder «لا», 46 «لا يوجد», and one «0» in the ready dataset; these are **unverified names**, not actual names, and must not become Auth identities.
- 48 review reasons: 27 shared-phone flags, 13 missing names, 9 non-standard primary phones (categories overlap). No automatic merge, notification or financial-order creation.
