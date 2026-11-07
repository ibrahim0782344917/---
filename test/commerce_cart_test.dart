import 'package:flutter_test/flutter_test.dart';
import 'package:shitreed_customer/backend/marketplace_backend.dart';
import 'package:shitreed_customer/commerce/commerce_service.dart';

void main() {
  setUp(() => CommerceCart.instance.clear());
  tearDown(() => CommerceCart.instance.clear());

  test('live cart does not mix stores or exceed available stock', () {
    const a = MarketplaceProduct(
      id: 'first', storeId: 'shop-1', name: 'Product A',
      priceIqd: 12500, stockQuantity: 2,
    );
    const b = MarketplaceProduct(
      id: 'second', storeId: 'shop-2', name: 'Product B',
      priceIqd: 1000, stockQuantity: 5,
    );

    expect(CommerceCart.instance.add(a), isTrue);
    expect(CommerceCart.instance.add(a), isTrue);
    expect(CommerceCart.instance.add(a), isFalse);
    expect(CommerceCart.instance.add(b), isFalse);
    expect(CommerceCart.instance.count, 2);
    expect(CommerceCart.instance.totalIqd, 25000);
    CommerceCart.instance.subtract(a);
    expect(CommerceCart.instance.count, 1);
    CommerceCart.instance.clear();
    expect(CommerceCart.instance.add(b), isTrue);
    expect(CommerceCart.instance.storeId, 'shop-2');
  });

  test('out-of-stock product cannot be put in live cart', () {
    const empty = MarketplaceProduct(
      id: 'sold-out', storeId: 'shop-1', name: 'Sold out',
      priceIqd: 200, stockQuantity: 0,
    );
    expect(CommerceCart.instance.add(empty), isFalse);
    expect(CommerceCart.instance.items, isEmpty);
  });
}
