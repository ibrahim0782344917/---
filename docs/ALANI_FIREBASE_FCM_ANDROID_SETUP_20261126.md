# Firebase Cloud Messaging — Al-Ani Android production pilot
26 November 2026. Preparation only; no Firebase account connected and no notification sent.

## Android registration
Use one approved Firebase project dedicated to this store. Register the three current pilot IDs exactly:
- com.ibrahimalani.shitreed_customer.livepilot
- com.ibrahimalani.shitreed_merchant.livepilot
- com.ibrahimalani.shitreed_admin.livepilot

The signed release IDs omit .livepilot; verify Play package IDs before registering those.
Download the respective Android client google-services.json files. Keep separate copies, named customer, merchant and admin. Do not provide service-account private keys in chat, Git, or client apps.

## Configuration validation
scripts/validate_alani_firebase_configs.py checks package match, distinct app IDs, one project identity, client key presence and rejects service-account files. Its --self-test uses only synthetic config values. It does not validate ownership, network or FCM delivery.

## Integration gates
1. Register apps in Firebase console and enable Cloud Messaging. Follow https://firebase.google.com/docs/flutter/setup and https://firebase.google.com/docs/cloud-messaging/flutter/get-started. Android projects are generated during CI; integrate config after the final applicationId is set. Use FlutterFire CLI / Google Services Gradle plugin for the generated projects and pin compatible plugin dependencies with resolved lockfiles. No production build dependencies changed by this preparation.
2. Disable auto-init and analytics collection before explicit opt-in. Request Android 13+ notification permission; initialize only after valid configuration. Use top-level background handler with @pragma('vm:entry-point'), route taps to authorized screens, support onTokenRefresh, revoke registration before sign-out and on opt-out. Do not trust push payload as authority for any order or money operation.
3. Private, scoped registration of device tokens: user and application binding, account-change revocation, stale token cleanup, no public token listings. Store sender credentials exclusively server-side (prefer managed identity or secret manager). No registration or send API activated yet.
4. Server-derived recipient selection for order updates, support, and staff events; deduplication, retries with backoff, opt-in preferences, no private content or phone/address in lock-screen text. No broad unauthenticated send endpoint; no client-selected arbitrary recipient.
5. Test isolated synthetic accounts and actual Android foreground/background/terminated delivery. Verify denied permissions, logout/account switch, invalid token, duplicate delivery, and locked-screen privacy. Force-stopped Android apps must be reopened before receiving messages again. Only enable production sends once tests pass.
6. Existing production order and support notification inbox remains independent of FCM. No changes to checkout or financial data.

Official background guidance: https://firebase.google.com/docs/cloud-messaging/flutter/receive-messages
Console: https://console.firebase.google.com/
