import 'package:flutter/material.dart';
import 'package:shitreed_customer/alani/alani_premium_widgets.dart';
import 'package:shitreed_customer/alani/alani_customer_extras.dart';
import 'package:shitreed_customer/backend/marketplace_backend.dart';
import 'package:shitreed_customer/commerce/commerce_service.dart';
import 'package:shitreed_customer/commerce/customer_commerce_pages.dart';

const _green = Color(0xFF1C503B);

/// Customer product details use the same stock and server-side checkout
/// procedures as Shitreed. No client-supplied price reaches an order.
class AlAniProductDetailsPage extends StatelessWidget {
  final MarketplaceProduct product;
  const AlAniProductDetailsPage({super.key, required this.product});

  void _addToCart(BuildContext context) {
    final added = CommerceCart.instance.add(product);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(added
          ? 'تمت إضافة المنتج إلى السلة'
          : 'تعذرت الإضافة؛ تحقق من المخزون أو المنتجات الموجودة بالسلة.'),
    ));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Theme.of(context).scaffoldBackgroundColor,
    appBar: AppBar(title: const Text('تفاصيل المنتج'), actions: [
      if (AlAniCustomerExtras.enabled && MarketplaceBackend.currentUser != null)
        IconButton(icon: const Icon(Icons.favorite_border), tooltip: 'حفظ في المفضلة', onPressed: () async {
          try {
            await AlAniCustomerExtras.call('alani_set_favorite_test', {'p_product_id': product.id, 'p_saved': true});
            if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم الحفظ في المفضلة.')));
          } catch (_) {
            if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تعذر حفظ المنتج.')));
          }
        }),
    ]),
    body: SafeArea(child: ListView(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 24),
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: SizedBox(
            height: 280,
            child: product.imageUrl != null &&
                    product.imageUrl!.startsWith('https://')
                ? Image.network(product.imageUrl!, fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) =>
                      const Icon(Icons.eco_outlined, color: _green, size: 90))
                : const ColoredBox(color: Color(0xFFE6EFE7),
                    child: Center(child: Icon(Icons.eco_outlined,
                      color: _green, size: 90))),
          ),
        ),
        const SizedBox(height: 22),
        AlAniSectionBanner(icon:Icons.eco_outlined,title:product.name,
          subtitle:product.stockQuantity > 0
            ? 'متوفر في المخزون: ${product.stockQuantity}' : 'غير متوفر حالياً',
          detail:priceText(product.priceIqd)),
        const SizedBox(height: 18),
        const AlAniSectionTitle('وصف المنتج',icon:Icons.description_outlined),
        const SizedBox(height: 8),
        Card(child:Padding(padding:const EdgeInsets.all(16),
          child:SelectableText(product.description.isEmpty
            ? 'لم يُضف صاحب المتجر وصفاً لهذا المنتج بعد.' : product.description,
            style:const TextStyle(height:1.6,fontSize:15)))),
        const SizedBox(height: 22),
        Text('السعر النهائي ورسوم التوصيل يتم تأكيدهما '
          'عند إتمام الطلب. معلومات المنتجات لا تمثل نصيحة طبية.',
          style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
        if (AlAniCustomerExtras.enabled && MarketplaceBackend.currentUser != null)
          OutlinedButton.icon(icon:const Icon(Icons.calendar_month_outlined),
            label:const Text('تفضيل شراء شهري'),
            onPressed:() async {
              final accepted=await showDialog<bool>(context:context,builder:(ctx)=>AlertDialog(
                title:const Text('تسجيل تفضيل شهري'),
                content:const Text('حفظ وحدة واحدة من المنتج للمراجعة الشهرية. لا ينشئ طلباً ولا يخصم أي مبلغ تلقائياً.'),
                actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('إلغاء')),
                  FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('حفظ'))],
              ));
              if(accepted!=true || !context.mounted)return;
              try{
                await AlAniCustomerExtras.call('alani_set_subscription_test',{'p_product_id':product.id,'p_quantity':1,'p_active':true});
                if(context.mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('تم حفظ التفضيل الشهري.')));
              }catch(_){if(context.mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('تعذر حفظ التفضيل.')));}
            }),
        const SizedBox(height: 14),
        FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: _green,
            padding: const EdgeInsets.symmetric(vertical: 15),
          ),
          onPressed: product.stockQuantity > 0
              ? () => _addToCart(context) : null,
          icon: const Icon(Icons.add_shopping_cart_outlined),
          label: const Text('إضافة إلى السلة'),
        ),
      ],
    )),
  );
}
