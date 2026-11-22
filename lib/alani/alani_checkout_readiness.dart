import 'dart:convert';

import 'package:http/http.dart' as http;

/// Both app-side approval and trusted server readiness must be true.
/// GitHub debug builds default to no live checkout; a successful Flutter build
/// alone NEVER authorizes order placement. Network failure always locks checkout.
class AlAniCheckoutReadiness {
  const AlAniCheckoutReadiness._();

  static const bool clientApproved =
      bool.fromEnvironment('ALANI_CHECKOUT_ENABLED', defaultValue: false) &&
      bool.fromEnvironment('ALANI_DELIVERY_TOTALS_VERIFIED',
          defaultValue: false);

  // Release builds must explicitly set their approved API URL.
  static const String apiBase = String.fromEnvironment(
    'ALANI_API_BASE',
    defaultValue: 'https://alani-site-admin-staging.up.railway.app',
  );
  static const String storeId = '25091ca2-c0da-416c-b634-81b188ee66be';

  static bool validConfig(Map<String, dynamic> value) =>
      value['checkoutEnabled'] == true &&
      value['deliveryFeeIqd'] == 5000 &&
      value['storeId'] == storeId &&
      value['paymentMethod'] == 'cash_on_delivery';

  static Future<bool> checkServer({http.Client? client}) async {
    if (!clientApproved) return false;
    final uri = Uri.tryParse('$apiBase/api/config');
    if (uri == null || uri.scheme != 'https' || uri.userInfo.isNotEmpty ||
        uri.host.isEmpty) {
      return false;
    }
    final ownClient = client == null;
    final api = client ?? http.Client();
    try {
      // A public config endpoint must not need any credentials.
      // Do not cache success: an operator may disable sales mid-session.
      final result = await api.get(uri).timeout(const Duration(seconds: 8));
      if (result.statusCode != 200 || result.bodyBytes.length > 4096) {
        return false;
      }
      final decoded = jsonDecode(utf8.decode(result.bodyBytes));
      return decoded is Map<String, dynamic> && validConfig(decoded);
    } catch (_) {
      return false;
    } finally {
      if (ownClient) api.close();
    }
  }
}
