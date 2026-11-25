import 'package:flutter_test/flutter_test.dart';
import 'package:shitreed_customer/alani/alani_delivery_tracking.dart';

void main() {
  test('delivery is disabled outside explicitly approved build', () {
    expect(AlAniDeliveryGate.enabled, isFalse);
    expect(AlAniDeliveryGate.storeId,
        '25091ca2-c0da-416c-b634-81b188ee66be');
  });

  test('buyer sees each supported delivery stage', () {
    expect(AlAniDeliveryStages.label('ready'), contains('المندوب'));
    expect(AlAniDeliveryStages.label('out_for_delivery'), contains('خرج'));
    expect(AlAniDeliveryStages.label('delivered'), contains('التسليم'));
    expect(AlAniDeliveryStages.label('cancelled'), contains('إلغاء'));
  });
}
