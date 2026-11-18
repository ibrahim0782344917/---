import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shitreed_customer/main.dart';

void main() {
  testWidgets('welcome opens Al-Ani store and menu shows return policy',
      (tester) async {
    await tester.pumpWidget(const ShitreedApp());
    await tester.pumpAndSettle();
    expect(find.text('أهلاً وسهلاً بكم'), findsOneWidget);
    expect(find.text('الدخول إلى المتجر'), findsOneWidget);
    await tester.tap(find.text('الدخول إلى المتجر'));
    await tester.pumpAndSettle();
    expect(find.text('من الطبيعة إلى بيتك'), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);
    await tester.tap(find.byTooltip('Open navigation menu'));
    await tester.pumpAndSettle();
    expect(find.text('سياسة الاسترجاع'), findsOneWidget);
    expect(find.text('طلب استرجاع'), findsOneWidget);
  });
}
