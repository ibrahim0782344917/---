import 'package:flutter_test/flutter_test.dart';
import 'package:shitreed_customer/commerce/checkout_request_token.dart';

void main() {
  const cart = [
    (productId: 'alpha', quantity: 2),
    (productId: 'beta', quantity: 1),
  ];

  test('retry with identical order uses same key', () {
    var issued = 0;
    final token = CheckoutRequestToken(
      idGenerator: () => 'test-key-${++issued}',
    );
    final first = token.forOrder(
      storeId: 'shop-1', items: cart,
      deliveryAddress: 'الغزالية بغداد - شارع ١',
      phone: '07700000000', notes: 'قرب المدرسة',
    );
    final retry = token.forOrder(
      storeId: 'shop-1', items: cart.reversed,
      deliveryAddress: ' الغزالية بغداد - شارع ١ ',
      phone: '07700000000', notes: 'قرب المدرسة',
    );
    expect(retry, first);
    expect(issued, 1);
  });

  test('changes to cart, address, phone, or notes create new key', () {
    var issued = 0;
    final token = CheckoutRequestToken(
      idGenerator: () => 'test-key-${++issued}',
    );
    String request({
      List<({String productId, int quantity})> items = cart,
      String address = 'بغداد - عنوان منزل واضح',
      String phone = '07700000000',
      String notes = '',
    }) => token.forOrder(
      storeId: 'shop-1', items: items,
      deliveryAddress: address, phone: phone, notes: notes,
    );

    final original = request();
    expect(request(), original);
    expect(request(items: [(productId: 'alpha', quantity: 3)]),
      isNot(original));
    expect(request(address: 'عنوان آخر في بغداد'), 'test-key-3');
    expect(request(phone: '07800000000'), 'test-key-4');
    expect(request(notes: 'اتصل قبل التوصيل'), 'test-key-5');
    token.reset();
    expect(request(), 'test-key-6');
  });

  test('default request token is a valid UUID version 4', () {
    final id = CheckoutRequestToken().forOrder(
      storeId: 'shop-1', items: cart,
      deliveryAddress: 'بغداد - منطقة ١',
      phone: '07700000000', notes: '',
    );
    expect(id, matches(RegExp(
      r'^[a-f0-9]{8}-[a-f0-9]{4}-4[a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$',
    )));
  });
}
