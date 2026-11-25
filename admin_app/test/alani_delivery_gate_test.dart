import 'package:flutter_test/flutter_test.dart';
import 'package:shitreed_admin/alani_delivery_admin_page.dart';

void main() {
  test('admin courier oversight requires explicit approved environment', () {
    expect(AlAniAdminDeliveryGate.enabled, isFalse);
  });
}
