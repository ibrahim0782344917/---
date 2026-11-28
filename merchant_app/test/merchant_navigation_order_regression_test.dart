import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shitreed_merchant/navigation/merchant_shell.dart';
import 'package:shitreed_merchant/merchant/merchant_dashboard.dart';

void main() {
  testWidgets('only active merchant tab mounts and switching does not throw', (tester) async {
    final built = <int>[];
    await tester.pumpWidget(MaterialApp(home: MerchantShellPage(
      pageBuilder: (index, navigate) {
        built.add(index);
        return Scaffold(body: Center(child: Text('tab-$index')));
      },
    )));
    await tester.pumpAndSettle();
    expect(built.toSet(), {0});
    for (final entry in [(3, 'الطلبات'), (4, 'حسابي'), (0, 'الرئيسية')]) {
      await tester.tap(find.widgetWithText(NavigationDestination, entry.$2));
      await tester.pumpAndSettle();
      expect(find.text('tab-${entry.$1}'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
    expect(find.text('tab-3', skipOffstage: false), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('independent customer order accepts prepares and becomes ready', (tester) async {
    var status = 'placed';
    final changes = <String>[];
    await tester.pumpWidget(MaterialApp(home: MerchantOrdersPage(
      storeId: 'fixture-store', merchantUserId: 'merchant',
      loadOrders: (_) async => [{
        'id': 'fixture-order-id', 'buyer_id': 'customer', 'status': status,
        'total_iqd': 40000, 'delivery_fee_iqd': 5000,
        'phone': '00000000000', 'delivery_address': 'Fixture address', 'notes': '',
      }],
      changeStatus: (_, next) async {
        changes.add(next);
        status = next;
        return next;
      },
    )));
    await tester.pumpAndSettle();
    for (final label in ['قبول الطلب', 'بدء التحضير', 'جاهز للتسليم']) {
      final target = find.widgetWithText(FilledButton, label);
      await tester.ensureVisible(target);
      await tester.tap(target);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
    expect(changes, ['accepted', 'preparing', 'ready']);
    expect(find.text('الحالة: ready'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
