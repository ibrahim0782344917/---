import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shitreed_customer/main.dart';

void main() {
  testWidgets('welcome opens customer marketplace', (tester) async {
    await tester.pumpWidget(const ShitreedApp());
    expect(find.text('ابدأ الآن'), findsOneWidget);
    await tester.tap(find.text('ابدأ الآن'));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.shopping_bag_rounded), findsOneWidget);
    expect(find.text('متاجر من مناطق بغداد'), findsOneWidget);
  });
}
