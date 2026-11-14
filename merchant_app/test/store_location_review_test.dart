import 'package:flutter_test/flutter_test.dart';
import 'package:shitreed_merchant/merchant/shop_location.dart';
import 'package:shitreed_merchant/admin/store_reviews_page.dart';

void main() {
  test('valid Baghdad shop pins reject null, incomplete or foreign positions', () {
    expect(isBaghdadShopLocation(33.3152, 44.3661), isTrue);
    expect(isBaghdadShopLocation(null, 44.3661), isFalse);
    expect(isBaghdadShopLocation(33.3152, null), isFalse);
    expect(isBaghdadShopLocation(35.0, 44.3661), isFalse);
    expect(isBaghdadShopLocation(double.nan, 44.3661), isFalse);
    expect(isBaghdadShopLocation(double.infinity, 44.3661), isFalse);
  });

  test('shop contact needs minimum seven numeric digits', () {
    expect(validShopPhone('0770 123 4567'), isTrue);
    expect(validShopPhone('+9647701234567'), isTrue);
    expect(validShopPhone('phone'), isFalse);
    expect(validShopPhone('1234'), isFalse);
  });

  test('only complete pending stores enable approval button', () {
    final complete = <String, dynamic>{
      'store_phone': '07701234567',
      'store_address': 'شارع فلسطين بغداد',
      'latitude': 33.3152,
      'longitude': 44.3661,
    };
    expect(storeReadyForApproval(complete), isTrue);
    expect(storeReadyForApproval({...complete, 'latitude': null}), isFalse);
    expect(storeReadyForApproval({...complete, 'store_phone': null}), isFalse);
    expect(storeReadyForApproval({...complete, 'store_address': ''}), isFalse);
  });
}
