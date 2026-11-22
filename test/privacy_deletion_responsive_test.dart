// ignore_for_file: prefer_interpolation_to_compose_strings
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shitreed_customer/account/customer_delete_account_page.dart';
import 'package:shitreed_customer/main.dart';

class _FakeDeletionRepository implements CustomerDeletionRepository {
  int submissions = 0;
  String? lastReason;
  final requests = <Map<String, dynamic>>[];

  @override
  Future<String> requestDeletion(String reason) async {
    submissions++;
    lastReason = reason.trim();
    requests.add({
      'id': 'aaaaaaaa-aaaa-4aaa-aaaa-aaaaaaaaaaaa',
      'status': 'pending',
      'requested_at': '2026-11-22T10:00:00Z',
    });
    return 'aaaaaaaa-aaaa-4aaa-aaaa-aaaaaaaaaaaa';
  }

  @override
  Future<List<Map<String, dynamic>>> myRequests() async =>
      List<Map<String, dynamic>>.from(requests);
}

void main() {
  testWidgets('deletion request needs explicit confirmation and does not erase',
      (tester) async {
    final service = _FakeDeletionRepository();
    await tester.pumpWidget(MaterialApp(
      home: CustomerDeleteAccountPage(repository: service),
    ));
    await tester.pumpAndSettle();

    final submit = find.widgetWithText(FilledButton, 'إرسال طلب حذف حسابي');
    expect(tester.widget<FilledButton>(submit).onPressed, isNull);
    await tester.ensureVisible(find.byType(CheckboxListTile));
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pump();
    expect(tester.widget<FilledButton>(submit).onPressed, isNotNull);
    await tester.tap(submit);
    await tester.pumpAndSettle();
    expect(service.submissions, 1);
    expect(service.requests.single['status'], 'pending');
    expect(find.textContaining('الحساب لم يُحذف بعد'), findsOneWidget);
  });

  for (final size in [
    const Size(320, 640),
    const Size(360, 740),
    const Size(393, 852),
    const Size(600, 960),
    const Size(800, 1200),
  ]) {
    testWidgets('delete-account form lays out on ' + size.width.toString() +
        'px screen', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(MaterialApp(
        home: CustomerDeleteAccountPage(
          repository: _FakeDeletionRepository(),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text('طلب حذف حساب الزبون'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.widgetWithText(FilledButton, 'إرسال طلب حذف حسابي'),
        130,
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('marketplace opens safely on ' + size.width.toString() +
        'px screen', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(const ShitreedApp());
      await tester.pumpAndSettle();
      expect(find.text('ابدأ الآن'), findsOneWidget);
      await tester.tap(find.text('ابدأ الآن'));
      await tester.pumpAndSettle();
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
