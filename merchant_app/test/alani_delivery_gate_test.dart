import 'package:flutter_test/flutter_test.dart';
import 'package:shitreed_merchant/delivery/alani_delivery_pages.dart';

void main() {
  test('delivery controls are fail closed outside approved builds', () {
    expect(AlAniMerchantDeliveryGate.enabled, isFalse);
    expect(AlAniMerchantDeliveryGate.storeId,
      '25091ca2-c0da-416c-b634-81b188ee66be');
  });
}
