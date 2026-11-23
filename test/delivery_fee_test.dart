import 'package:flutter_test/flutter_test.dart';
import 'package:shitreed_customer/backend/marketplace_backend.dart';
import 'package:shitreed_customer/commerce/commerce_service.dart';

void main() {
  test('empty cart never charges delivery', () {
    final cart = CommerceCart.instance;
    cart.clear();
    expect(cart.totalWithDeliveryIqd, 0);
  });

  test('cart quote adds 5,000 IQD once per order', () {
    final cart = CommerceCart.instance;
    cart.clear();
    const product = MarketplaceProduct(
      id: 'test-product', storeId: 'test-store', name: 'Test product',
      priceIqd: 10000, stockQuantity: 3,
    );
    expect(cart.add(product), isTrue);
    expect(cart.totalIqd, 10000);
    expect(cart.totalWithDeliveryIqd, 15000);
    expect(cart.add(product), isTrue);
    expect(cart.totalIqd, 20000);
    expect(cart.totalWithDeliveryIqd, 25000);
    cart.clear();
    expect(cart.totalWithDeliveryIqd, 0);
  });
}
