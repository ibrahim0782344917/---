import 'package:flutter_test/flutter_test.dart';
import 'package:shitreed_merchant/commerce/merchant_order_rules.dart';

void main() {
  group('merchant order role boundaries', () {
    test('shop owner cannot treat own purchase as independent merchant sale', () {
      expect(MerchantOrderRules.isSelfPurchase(
        buyerId: 'owner-1', merchantUserId: 'owner-1'), isTrue);
    });

    test('a separate customer can place orders for the merchant to process', () {
      expect(MerchantOrderRules.isSelfPurchase(
        buyerId: 'customer-2', merchantUserId: 'owner-1'), isFalse);
    });

    test('missing identity does not bypass server authorization', () {
      expect(MerchantOrderRules.isSelfPurchase(
        buyerId: null, merchantUserId: 'owner-1'), isFalse);
      expect(MerchantOrderRules.isSelfPurchase(
        buyerId: 'customer-2', merchantUserId: null), isFalse);
    });

    test('error messages explain expected role restrictions safely', () {
      expect(
        MerchantOrderRules.friendlyStatusError('INVALID_BUYER_TRANSITION'),
        contains('حساب زبون منفصل'),
      );
      expect(
        MerchantOrderRules.friendlyStatusError('PERMISSION_DENIED'),
        contains('صلاحية'),
      );
      expect(
        MerchantOrderRules.friendlyStatusError('internal stack: token sensitive'),
        isNot(contains('token sensitive')),
      );
    });
  });
}
