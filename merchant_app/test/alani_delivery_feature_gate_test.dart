import 'package:flutter_test/flutter_test.dart';
import 'package:shitreed_merchant/delivery/alani_delivery_page.dart';

void main() {
  test('delivery dispatch and courier screens default to OFF', () {
    expect(AlAniDeliveryFeature.enabled, isFalse);
    expect(AlAniDeliveryFeature.storeId,
        '25091ca2-c0da-416c-b634-81b188ee66be');
  });
}
