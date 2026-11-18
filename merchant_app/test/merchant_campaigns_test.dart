import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shitreed_merchant/marketing/merchant_campaigns_page.dart';

void main(){
  testWidgets('unapproved campaign backend never claims enabled publishing',(tester)async{
    await tester.pumpWidget(const MaterialApp(home:MerchantCampaignsPage(
      storeId:'00000000-0000-4000-8000-000000000000',storeName:'محل اختبار')));
    await tester.pumpAndSettle();
    expect(find.text('شريط العروض المؤقتة'),findsOneWidget);
    expect(find.textContaining('نظام العروض قيد التجهيز'),findsWidgets);
    expect(find.byType(FloatingActionButton),findsNothing);
  });
}
