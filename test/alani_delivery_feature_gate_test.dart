import 'package:flutter_test/flutter_test.dart';
import 'package:shitreed_customer/alani/alani_delivery_verification.dart';

void main() {
  test('delivery handoff defaults to OFF without an explicit TEST flag', () {
    expect(AlAniDeliveryFeature.enabled, isFalse);
  });
}
