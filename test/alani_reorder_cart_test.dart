import 'package:flutter_test/flutter_test.dart';
import 'package:shitreed_customer/backend/marketplace_backend.dart';
import 'package:shitreed_customer/commerce/commerce_service.dart';

MarketplaceProduct product(String id,{int stock=4,String store='store-a'}) =>
    MarketplaceProduct(id:id,storeId:store,name:id,priceIqd:15000,stockQuantity:stock);
void main(){
  final cart=CommerceCart.instance;
  setUp(cart.clear);
  tearDown(cart.clear);
  test('reorder fills an empty cart with exact quantities',(){
    expect(cart.loadReorder([CommerceCartItem(product('a'),2),CommerceCartItem(product('b'),1)]),isTrue);
    expect(cart.count,3);
    expect(cart.totalIqd,45000);
  });
  test('reorder rejects insufficient stock atomically',(){
    expect(cart.loadReorder([CommerceCartItem(product('a'),1),CommerceCartItem(product('b',stock:0),1)]),isFalse);
    expect(cart.items,isEmpty);
  });
  test('reorder never overwrites existing cart',(){
    expect(cart.add(product('a')),isTrue);
    expect(cart.loadReorder([CommerceCartItem(product('b'),1)]),isFalse);
    expect(cart.items.single.product.id,'a');
  });
  test('reorder rejects duplicates and mixed stores',(){
    expect(cart.loadReorder([CommerceCartItem(product('a'),1),CommerceCartItem(product('a'),1)]),isFalse);
    expect(cart.loadReorder([CommerceCartItem(product('a'),1),CommerceCartItem(product('b',store:'store-b'),1)]),isFalse);
    expect(cart.items,isEmpty);
  });
}
