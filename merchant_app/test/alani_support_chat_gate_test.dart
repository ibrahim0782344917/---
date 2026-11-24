import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shitreed_merchant/support/alani_support_chat.dart';

void main() {
  test('Support chat fails closed outside explicitly approved test build', () {
    expect(AlAniSupportFeature.enabled, isFalse);
    expect(AlAniSupportFeature.storeId,
      '25091ca2-c0da-416c-b634-81b188ee66be');
  });
  testWidgets('Staff inbox cannot expose user messages when chat disabled',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: AlAniSupportInboxPage()));
    await tester.pumpAndSettle();
    expect(find.text('محادثات العملاء غير مفعّلة على الإنتاج.'),
      findsOneWidget);
    expect(find.byType(ListTile), findsNothing);
  });
}
