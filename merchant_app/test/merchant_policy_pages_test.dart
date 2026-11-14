import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shitreed_merchant/account/merchant_legal_pages.dart';
import 'package:shitreed_merchant/main.dart';

void main(){
  testWidgets('privacy text is accessible without merchant login',
    (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home:MerchantLegalPage(title:'سياسة الخصوصية',
          sections:merchantPrivacySections)));
      expect(find.text('سياسة الخصوصية'),findsWidgets);
      expect(find.text('بيانات الحساب والمتاجر'),findsOneWidget);
      expect(find.byType(Scrollable),findsWidgets);
  });

  testWidgets('merchant terms explain cash on delivery',
    (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home:MerchantLegalPage(title:'الشروط',
          sections:merchantTermsSections)));
      expect(find.text('المبيعات'),findsOneWidget);
  });

  testWidgets('auth app stays safe if runtime Supabase is not configured',
    (tester) async {
      await tester.pumpWidget(const ShitreedMerchantApp());
      expect(find.textContaining('يحتاج اتصال Supabase'),findsOneWidget);
  });
}
