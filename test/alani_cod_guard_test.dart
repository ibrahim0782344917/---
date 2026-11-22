import 'package:flutter_test/flutter_test.dart';
import 'package:shitreed_customer/commerce/commerce_service.dart';

void main() {
  test('legacy Al-Ani checkout reports that fee-confirming cart is required', () {
    expect(checkoutFailureText('ALANI_USE_VERIFIED_CHECKOUT'),
      contains('٥٬٠٠٠'));
  });

  test('changed price does not pretend an order succeeded', () {
    expect(checkoutFailureText('ORDER_TOTAL_CHANGED'), contains('تغيّر سعر'));
  });

  test('retry conflict explains to review orders first', () {
    expect(checkoutFailureText('IDEMPOTENCY_PAYLOAD_MISMATCH'),
      contains('راجع طلباتك'));
  });

  test('backend messages never expose raw SQL details', () {
    final text=checkoutFailureText('syntax error at or near SELECT');
    expect(text, isNot(contains('SELECT')));
  });
}
