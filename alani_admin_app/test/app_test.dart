import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:alani_admin_app/main.dart';
import 'package:alani_admin_app/api.dart';

import 'package:alani_admin_app/dashboard_filters.dart';
void main() {
  test('filters low stock and out-of-stock accurately', () {
    final products = <Map<String, dynamic>>[
      {'name':'عسل أصلي','description':'عسل طبيعي','stock_quantity':0,'is_active':true},
      {'name':'زيت حبة البركة','description':'زيت طبيعي','stock_quantity':3,'is_active':true},
      {'name':'أعشاب','description':'خلطة','stock_quantity':25,'is_active':false},
    ];
    expect(AlAniAdminFilters.products(products,inventory:'low').length,2);
    expect(AlAniAdminFilters.products(products,inventory:'out').length,1);
    expect(AlAniAdminFilters.products(products,inventory:'hidden').length,1);
    expect(AlAniAdminFilters.products(products,search:'زيت').single['stock_quantity'],3);
  });

  test('order searches are scoped to the loaded data', () {
    final orders = <Map<String, dynamic>>[
      {'id':'order01','status':'placed','delivery_address':'الغزالية'},
      {'id':'order02','status':'ready','delivery_address':'المنصور'},
    ];
    expect(AlAniAdminFilters.orders(orders,status:'placed').length,1);
    expect(AlAniAdminFilters.orders(orders,search:'المنصور').single['id'],'order02');
  });

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
