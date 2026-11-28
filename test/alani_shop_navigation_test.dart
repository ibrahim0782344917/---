import 'package:flutter_test/flutter_test.dart';
import 'package:shitreed_customer/alani/alani_shop.dart';
void main(){
  test('new storefront tabs preserve existing catalog, videos and posts',(){
    expect([for(var i=0;i<5;i++) AlAniShopNavigation.tabFor(i)], [0,1,2,4,null]);
    expect([for(var i=0;i<5;i++) AlAniShopNavigation.selectedIndex(i)], [0,1,2,3,3]);
  });
}
