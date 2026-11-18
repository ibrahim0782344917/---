import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shitreed_customer/main.dart';

void main() {
  testWidgets('Al-Ani keeps map access after welcome without map credentials',
      (tester) async {
    await tester.pumpWidget(const ShitreedApp());
    await tester.pumpAndSettle();
    await tester.tap(find.text('الدخول إلى المتجر'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('خرائط Google'), findsOneWidget);
    expect(find.byIcon(Icons.map_outlined), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);
  });
}
