import 'package:flutter_test/flutter_test.dart';
import 'package:shitreed_admin/admin_api.dart';
import 'package:shitreed_admin/alani_store_api.dart';
import 'package:shitreed_admin/alani_dashboard_filters.dart';

void main() {
  test('one Admin checks platform permissions before opening the store', () {
    expect(AdminAccess.canOpenAlAni('super_admin'),isTrue);
    expect(AdminAccess.canOpenAlAni('operations'),isTrue);
    expect(AdminAccess.canOpenAlAni('support'),isFalse);
    expect(AdminAccess.canOpenAlAni('viewer'),isFalse);
    expect(AdminAccess.canOpenAlAni(null),isFalse);
  });

  test('owner-scoped order status transitions remain narrow', () {
    expect(AlAniAdminApi.nextStatuses('placed'),['accepted','rejected']);
    expect(AlAniAdminApi.nextStatuses('accepted'),['preparing']);
    expect(AlAniAdminApi.nextStatuses('preparing'),['ready']);
    expect(AlAniAdminApi.nextStatuses('ready'),isEmpty);
  });

  test('shop product filters do not expose hidden items by default', () {
    final products=<Map<String,dynamic>>[
      {'name':'عسل','stock_quantity':0,'is_active':false},
      {'name':'زيت زيتون','stock_quantity':5,'is_active':true},
      {'name':'زيت حبة','stock_quantity':20,'is_active':true},
    ];
    expect(AlAniAdminFilters.products(products,inventory:'out').length,1);
    expect(AlAniAdminFilters.products(products,inventory:'low').length,2);
    expect(AlAniAdminFilters.products(products,search:'زيت').length,2);
    expect(AlAniAdminFilters.products(products,inventory:'hidden').length,1);
  });
}
