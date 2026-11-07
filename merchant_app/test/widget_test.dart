import 'package:flutter_test/flutter_test.dart';
import 'package:shitreed_merchant/main.dart';

void main() {
  testWidgets('merchant app launches safely without runtime credentials',
      (tester) async {
    await tester.pumpWidget(const ShitreedMerchantApp());
    expect(find.textContaining('يحتاج اتصال Supabase'), findsOneWidget);
  });
}
