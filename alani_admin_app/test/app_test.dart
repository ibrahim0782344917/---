import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:alani_admin_app/main.dart';
import 'package:alani_admin_app/api.dart';

void main() {
  test('order transitions respect server-side flow', () {
    expect(AlAniAdminApi.nextStatuses('placed'), ['accepted','rejected']);
    expect(AlAniAdminApi.nextStatuses('accepted'), ['preparing']);
    expect(AlAniAdminApi.nextStatuses('preparing'), ['ready']);
    expect(AlAniAdminApi.nextStatuses('ready'), isEmpty);
  });

  testWidgets('app starts with private merchant-owner sign in', (tester) async {
    await tester.pumpWidget(const AlAniAdminApp());
    await tester.pumpAndSettle();
    expect(find.text('السيد إبراهيم العاني'), findsOneWidget);
    expect(find.text('دخول مالك المتجر'), findsOneWidget);
    expect(find.byType(TextField), findsNWidgets(2));
  });
}
