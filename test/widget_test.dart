import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shitreed_customer/main.dart';

void main() {
  testWidgets('Al-Ani storefront is primary app route with catalog', (tester) async {
    await tester.pumpWidget(const ShitreedApp());
    await tester.pumpAndSettle();
    expect(find.text('السيد إبراهيم العاني'), findsOneWidget);
    expect(find.text('من الطبيعة إلى بيتك'), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byTooltip('خرائط Google'), findsOneWidget);
    await tester.tap(find.text('المتجر').last);
    await tester.pumpAndSettle();
    expect(find.text('الزيوت والأعشاب والمنتجات'), findsOneWidget);
  });
}
