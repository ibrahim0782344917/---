import 'package:flutter_test/flutter_test.dart';
import 'package:shitreed_customer/main.dart';

void main() {
  testWidgets('Baghdad map tab is reachable without a Google API key',
      (tester) async {
    await tester.pumpWidget(const ShitreedApp());
    await tester.tap(find.text('ابدأ الآن'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('الخريطة'));
    await tester.pumpAndSettle();

    expect(find.text('خريطة شتريد • بغداد'), findsOneWidget);
    expect(find.text('افتح خريطة بغداد في Google'), findsOneWidget);
    expect(find.text('خريطة شتريد • بغداد'), findsOneWidget);
  });
}
