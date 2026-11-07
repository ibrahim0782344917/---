import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shitreed_merchant/main.dart';
import 'package:shitreed_merchant/shared/merchant_widgets.dart';

void main() {
  test('formats Iraqi dinar amounts consistently', () {
    expect(priceText(1250000), '1,250,000 د.ع');
    expect(priceText(500), '500 د.ع');
  });

  testWidgets('merchant app without backend gives a safe setup message',
      (tester) async {
    await tester.pumpWidget(const ShitreedMerchantApp());
    expect(find.byType(MaterialApp), findsOneWidget);
    expect(find.textContaining('تطبيق شتريد تاجر يحتاج اتصال Supabase'),
      findsOneWidget);
  });
}
