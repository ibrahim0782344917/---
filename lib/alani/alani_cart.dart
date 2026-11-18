import 'package:flutter/material.dart';
import 'package:shitreed_customer/commerce/commerce_service.dart';
import 'package:shitreed_customer/commerce/customer_commerce_pages.dart';
import 'alani_pages.dart';

const _green=Color(0xFF01BE5F);
const _ink=Color(0xFF173E2A);

/// This flavor must NOT take payments/orders until the server computes the
/// 5,000 IQD delivery charge authoritatively. Existing Shitreed checkout
/// stays untouched; no client total is submitted to the server.
class AlAniCartPage extends StatelessWidget {
  const AlAniCartPage({super.key});

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation:CommerceCart.instance,
    builder:(context,_) {
      final cart=CommerceCart.instance;
      final items=cart.items;
      return ListView(
        padding:const EdgeInsets.all(17),
        children:[
          const Text('سلة السيد إبراهيم العاني',
            style:TextStyle(fontSize:23,fontWeight:FontWeight.w900,color:_ink)),
          const SizedBox(height:7),
          const Text('الدفع نقداً عند الاستلام. '
            'أجور التوصيل ٥٬٠٠٠ دينار عراقي.',
            style:TextStyle(fontSize:13)),
          const SizedBox(height:15),
          if(items.isEmpty)const Padding(
            padding:EdgeInsets.all(33),
            child:Center(child:Text('السلة فارغة. اختر من منتجات متجرنا.'))),
          for(final item in items) Card(color:Colors.white,child:ListTile(
            title:Text(item.product.name),
            subtitle:Text(priceText(item.product.priceIqd)),
            trailing:Wrap(crossAxisAlignment:WrapCrossAlignment.center,
              spacing:0,children:[
              IconButton(
                tooltip:'تقليل الكمية',
                onPressed:()=>cart.subtract(item.product),
                icon:const Icon(Icons.remove_circle_outline)),
              Text(item.quantity.toString()),
              IconButton(
                tooltip:'زيادة الكمية',
                onPressed:()=>cart.add(item.product),
                icon:const Icon(Icons.add_circle_outline)),
            ]),
          )),
          if(items.isNotEmpty) ...[
            OutlinedButton.icon(
              onPressed:cart.clear,
              icon:const Icon(Icons.remove_shopping_cart_outlined),
              label:const Text('إفراغ السلة')),
            const SizedBox(height:15),
            ListTile(title:const Text('مجموع المنتجات'),
              trailing:Text(priceText(cart.totalIqd))),
            const ListTile(title:Text('أجور التوصيل'),
              trailing:Text('٥٬٠٠٠ د.ع')),
            ListTile(
              title:const Text('الإجمالي المتوقع مع التوصيل',
                style:TextStyle(fontWeight:FontWeight.bold)),
              trailing:Text(priceText(cart.totalIqd+5000),
                style:const TextStyle(fontWeight:FontWeight.w900,color:_green)),
            ),
            const Card(
              color:Color(0xFFFFF0D9),
              child:Padding(
                padding:EdgeInsets.all(16),
                child:Text('تأكيد الطلب قيد التجهيز: '
                  'لم يُحدّث الخادم بعد لإضافة رسوم التوصيل وتدقيقها. '
                  'لن نرسل طلباً قبل إكمال ربط الرسوم.',
                  style:TextStyle(height:1.7)),
              ),
            ),
            const SizedBox(height:8),
            const FilledButton.icon(
              onPressed:null,
              icon:Icon(Icons.lock_outline),
              label:Text('الطلب عند الاستلام غير متاح بعد'),
            ),
            TextButton(
              onPressed:()=>Navigator.push(context,MaterialPageRoute<void>(
                builder:(_)=>const AlAniInfoPage(type:'payments'))),
              child:const Text('اقرأ سياسة الدفع والتوصيل'),
            ),
          ],
        ],
      );
    },
  );
}