import 'package:flutter_test/flutter_test.dart';
import 'package:shitreed_merchant/reports/merchant_reports.dart';

Map<String,dynamic> row(String id,String status,int total,int fee) =>
  {'id':id,'status':status,'total_iqd':total,'delivery_fee_iqd':fee};

void main(){
  test('open commitments split merchandise and fees; exclude cancellations',(){
    final result=summarizeMerchantOrders([],[
      row('a','placed',55000,5000),
      row('b','ready',30000,0),
      row('c','cancelled',20000,0),
      row('d','rejected',10000,0),
      row('e','delivered',15000,5000),
      row('f','out_for_delivery',25000,5000),
    ]);
    expect(result.openGoodsIqd,100000);
    expect(result.openDeliveryIqd,10000);
    expect(result.openOrderTotalIqd,110000);
    expect(result.deliveredOrderTotalIqd,15000);
    expect(result.deliveredOrders,1);
    expect(result.cancelledOrRejected,2);
    expect(result.outForDeliveryOrders,1);
    expect(result.totalOrderValueIqd,125000);
  });
  test('unknown status and invalid fee fail closed',(){
    expect(()=>summarizeMerchantOrders([], [row('a','unknown',10000,0)]),throwsStateError);
    expect(()=>summarizeMerchantOrders([], [row('a','placed',1000,5000)]),throwsStateError);
  });
  test('duplicate order and missing fee fail closed',(){
    expect(()=>summarizeMerchantOrders([], [row('a','placed',10000,0),row('a','ready',10000,0)]),throwsStateError);
    expect(()=>summarizeMerchantOrders([], [{'id':'a','status':'placed','total_iqd':10000}]),throwsStateError);
  });
  test('limited sample flag does not imply full accounting',(){
    final result=summarizeMerchantOrders([],[],limitedSample:true);
    expect(result.limitedSample,isTrue);
    expect(result.openOrderTotalIqd,0);
  });
}
