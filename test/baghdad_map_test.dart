import 'package:flutter_test/flutter_test.dart';
import 'package:shitreed_customer/main.dart';

void main() {
  testWidgets('Iraq discovery tab works without Google Maps credentials',
      (tester) async {
    await tester.pumpWidget(const ShitreedApp());
    await tester.tap(find.text('ابدأ الآن'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('الخريطة'));
    await tester.pumpAndSettle();

    expect(find.text('خريطة محلات العراق'), findsOneWidget);
    expect(find.text('خريطة الإنتاج تحتاج مزود خرائط'), findsOneWidget);
    expect(find.text('فتح خريطة بغداد الخارجية'), findsOneWidget);
    expect(find.textContaining('Google Maps API'), findsNothing);
  });
}
