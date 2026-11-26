import 'package:flutter_test/flutter_test.dart';
import 'package:shitreed_customer/alani/alani_checkout_readiness.dart';

void main() {
  const valid = <String, dynamic>{
    'checkoutEnabled': true,
    'deliveryFeeIqd': 5000,
    'storeId': AlAniCheckoutReadiness.storeId,
    'paymentMethod': 'cash_on_delivery',
  };
  test('client builds are locked until deliberately approved', () {
    expect(AlAniCheckoutReadiness.clientApproved, isFalse);
    expect(AlAniCheckoutReadiness.directProductionPilot, isFalse);
  });
  test('server checkout gate is fail closed', () {
    expect(AlAniCheckoutReadiness.validConfig(valid), isTrue);
    expect(AlAniCheckoutReadiness.validConfig(
      {...valid, 'checkoutEnabled': false}), isFalse);
    expect(AlAniCheckoutReadiness.validConfig(
      {...valid, 'deliveryFeeIqd': 0}), isFalse);
    expect(AlAniCheckoutReadiness.validConfig(
      {...valid, 'deliveryFeeIqd': 10000}), isFalse);
    expect(AlAniCheckoutReadiness.validConfig(
      {...valid, 'storeId': 'another-shop'}), isFalse);
    expect(AlAniCheckoutReadiness.validConfig(
      {...valid, 'paymentMethod': 'credit_card'}), isFalse);
  });
}
