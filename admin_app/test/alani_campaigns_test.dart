import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shitreed_admin/alani_campaign_admin_page.dart';

void main(){
  testWidgets('Admin offers page disables publishing without secure database',(tester)async{
    await tester.pumpWidget(const MaterialApp(home:AlAniCampaignAdminPage()));
    await tester.pumpAndSettle();
    expect(find.text('شريط العروض المؤقتة'),findsOneWidget);
    expect(find.byType(FloatingActionButton),findsNothing);
  });
}
