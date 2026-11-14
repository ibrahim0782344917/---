import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shitreed_admin/admin_pro_features.dart';
import 'package:shitreed_admin/admin_api.dart';

void main() {
  testWidgets('dashboard chart renders real zero-valued days', (tester) async {
    final days = <Map<String, dynamic>>[
      {'date':'2026-11-08','orders':0},
      {'date':'2026-11-09','orders':0},
      {'date':'2026-11-10','orders':0},
      {'date':'2026-11-11','orders':0},
      {'date':'2026-11-12','orders':0},
      {'date':'2026-11-13','orders':0},
      {'date':'2026-11-14','orders':0},
    ];
    await tester.pumpWidget(MaterialApp(home:
      Scaffold(body: WeeklyOrdersChart(daily: days))));
    expect(find.text('حركة الطلبات خلال 7 أيام'), findsOneWidget);
    expect(find.text('11-14'), findsOneWidget);
    expect(find.text('11-08'), findsOneWidget);
    expect(find.text('0'), findsNWidgets(7));
  });

  test('staff roles are checked on client as a convenience only', () {
    expect(AdminAccess.sectionsFor('viewer'), isNot(contains('orders')));
    expect(AdminAccess.sectionsFor('support'), contains('orders'));
    expect(AdminAccess.canChange('viewer','products'), isFalse);
    expect(AdminAccess.canChange('catalog_manager','products'), isTrue);
    expect(AdminAccess.canChange('catalog_manager','orders'), isFalse);
    expect(AdminAccess.sectionsFor('super_admin'), contains('audit'));
  });

  test('result pages carry server-provided totals', () {
    const page = AdminPage(items: [], total: 12);
    expect(page.items, isEmpty);
    expect(page.total, 12);
  });
}
