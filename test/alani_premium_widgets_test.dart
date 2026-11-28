import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shitreed_customer/alani/alani_design_system.dart';
import 'package:shitreed_customer/alani/alani_premium_widgets.dart';
void main(){
  for(final brightness in Brightness.values){
    testWidgets('shared components fit narrow RTL and large text in $brightness',(tester)async{
      tester.view.physicalSize=const Size(320,640);
      tester.view.devicePixelRatio=1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(MaterialApp(theme:AlAniDesignSystem.theme(brightness:brightness),
        home:const Scaffold(body:Directionality(textDirection:TextDirection.rtl,
          child:MediaQuery(data:MediaQueryData(textScaler:TextScaler.linear(1.5)),child:
            SingleChildScrollView(child:Column(children:[
              AlAniSectionBanner(icon:Icons.shopping_bag,title:'سلة السيد إبراهيم العاني',
                subtitle:'الدفع عند الاستلام والتوصيل',detail:'٥٬٠٠٠ د.ع'),
              AlAniSectionTitle('تفاصيل الطلب',icon:Icons.receipt_long),
              AlAniEmptyState(icon:Icons.notifications_off_outlined,message:'لا توجد إشعارات طلبات.'),
            ])))))));
      expect(tester.takeException(),isNull);
      expect(find.text('سلة السيد إبراهيم العاني'),findsOneWidget);
      expect(find.text('٥٬٠٠٠ د.ع'),findsOneWidget);
    });
  }
}
