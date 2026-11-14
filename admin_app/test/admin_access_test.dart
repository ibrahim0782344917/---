import 'package:flutter_test/flutter_test.dart';
import 'package:shitreed_admin/admin_api.dart';

void main() {
  test('unassigned accounts do not receive admin sections', () {
    expect(AdminAccess.sectionsFor(null), isEmpty);
    expect(AdminAccess.sectionsFor('customer'), isEmpty);
    expect(AdminAccess.canChange('viewer', 'stores'), isFalse);
  });

  test('merchant reviewer cannot alter products or orders', () {
    expect(AdminAccess.canChange('merchant_reviewer', 'stores'), isTrue);
    expect(AdminAccess.canChange('merchant_reviewer', 'products'), isFalse);
    expect(AdminAccess.canChange('merchant_reviewer', 'orders'), isFalse);
    expect(AdminAccess.sectionsFor('merchant_reviewer'), contains('stores'));
  });

  test('support can manage orders but not products', () {
    expect(AdminAccess.canChange('support', 'orders'), isTrue);
    expect(AdminAccess.canChange('support', 'products'), isFalse);
    expect(AdminAccess.sectionsFor('support'), isNot(contains('staff')));
  });

  test('only super administrator sees staff section', () {
    expect(AdminAccess.sectionsFor('super_admin'), contains('staff'));
    expect(AdminAccess.sectionsFor('operations'), isNot(contains('staff')));
  });

  test('staff assignment needs a syntactically valid UUID', () {
    expect(AdminAccess.isUuid('1234'), isFalse);
    expect(AdminAccess.isUuid('00000000-0000-4000-8000-000000000000'), isTrue);
  });
}
