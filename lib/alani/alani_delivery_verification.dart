import 'package:supabase_flutter/supabase_flutter.dart';

/// A delivery-code flow restricted to the isolated TEST database.
/// It does not turn on real sales or production delivery.
abstract final class AlAniDeliveryFeature {
  static const enabled =
      bool.fromEnvironment('ALANI_DELIVERY_WORKFLOW_ENABLED',
          defaultValue: false) &&
      (String.fromEnvironment('SUPABASE_URL') ==
              'https://tgvdwotbrnhcoykuxdpr.supabase.co' ||
          bool.fromEnvironment('ALANI_DELIVERY_PRODUCTION_APPROVED',
              defaultValue: false));
}

abstract final class AlAniDeliveryVerification {
  static Future<Map<String, dynamic>> status(String orderId) async {
    final result = await Supabase.instance.client
        .rpc('alani_order_delivery_status',
            params: {'p_order_id': orderId});
    return Map<String, dynamic>.from(result as Map);
  }

  /// The buyer alone gets a six-digit code, only AFTER the courier pickup.
  /// The server stores only salted SHA256, with 15-minute expiry and
  /// five persisted courier guesses. Never log, cache, or upload the code.
  static Future<Map<String, dynamic>> issueCode(String orderId) async {
    final result = await Supabase.instance.client
        .rpc('alani_issue_delivery_pin',
            params: {'p_order_id': orderId});
    return Map<String, dynamic>.from(result as Map);
  }
}
