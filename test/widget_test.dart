import 'package:flutter_test/flutter_test.dart';
import 'package:shitreed_customer/main.dart';

void main() {
  testWidgets('customer home renders', (tester) async {
    await tester.pumpWidget(const ShitreedApp());
    expect(find.text('شتريد اليوم؟'), findsOneWidget);
  });
}
