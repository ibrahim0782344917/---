import 'package:flutter/material.dart';
import 'package:shitreed_merchant/commerce/commerce_service.dart';
import 'package:shitreed_merchant/merchant/merchant_dashboard.dart';
import 'package:shitreed_merchant/merchant/merchant_settings_pages.dart';
import 'package:shitreed_merchant/reports/merchant_reports.dart';
import 'package:shitreed_merchant/marketing/merchant_campaigns_page.dart';
import 'package:shitreed_merchant/support/alani_support_chat.dart';
import 'package:shitreed_merchant/delivery/alani_delivery_pages.dart';
import 'package:shitreed_merchant/shared/merchant_widgets.dart';

/// Only owner-owned stores are loaded through CommerceService.myStores().
/// All writes still depend on Supabase RLS; no arbitrary store id is accepted.
class MerchantControlCenter extends StatefulWidget {
  const MerchantControlCenter({super.key});

  @override
  State<MerchantControlCenter> createState() => _MerchantControlCenterState();
}

class _MerchantControlCenterState extends State<MerchantControlCenter> {
  late Future<List<Map<String,dynamic>>> _stores;
  String _search = '';

  @override
  void initState() {
    super.initState();
    _stores = CommerceService.myStores();
  }

  Future<void> _reload() async {
    final pending=CommerceService.myStores();
    setState(()=>_stores=pending);
    try { await pending; } catch (_) { /* Rendered by FutureBuilder */ }
  }

  Future<void> _open(Widget page) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder:(_)=>page));
    if (mounted) await _reload();
  }

  Widget _action(String label,IconData icon,VoidCallback tap) =>
    OutlinedButton.icon(
      onPressed:tap,icon:Icon(icon,size:18),
      label:Text(label,style:const TextStyle(fontSize:12)),
    );

  Widget _storeCard(Map<String,dynamic> store) {
    final id=store['id']?.toString()??'';
    final name=store['name']?.toString()??'المتجر';
    final approved=store['status']=='approved';
    final isAlAni=id=='25091ca2-c0da-416c-b634-81b188ee66be';
    return Card(
      color:Colors.white,
      margin:const EdgeInsets.only(bottom:12),
      child:Padding(
        padding:const EdgeInsets.all(15),
        child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
          Row(children:[
            const CircleAvatar(
              backgroundColor:Color(0xFFE4FAED),
              child:Icon(Icons.storefront_outlined,color:merchantPurple)),
            const SizedBox(width:11),
            Expanded(child:Column(
              crossAxisAlignment:CrossAxisAlignment.start,children:[
                Text(name,style:const TextStyle(
                  fontSize:17,fontWeight:FontWeight.w900)),
                Text(approved?'متجر معتمد':'قيد المراجعة',
                  style:TextStyle(fontSize:12,
                    color:approved?const Color(0xFF087A46):Colors.orange)),
              ])),
          ]),
          const SizedBox(height:12),
          Text(store['area']?.toString()??'',
            style:const TextStyle(fontSize:12,color:Colors.black54)),
          if(isAlAni) ...[
            const SizedBox(height:9),
            const DecoratedBox(
              decoration:BoxDecoration(
                color:Color(0xFFECFBF1),
                borderRadius:BorderRadius.all(Radius.circular(10))),
              child:Padding(
                padding:EdgeInsets.all(12),
                child:Text('سياسة السيد إبراهيم العاني: الدفع نقداً عند الاستلام، '
                  'التوصيل ٥٬٠٠٠ د.ع، والرجوع الاختياري ٥٬٠٠٠ د.ع. '
                  'لا تُفرض رسوم خطأ المتجر على المنتج المكسور.',
                  style:TextStyle(height:1.6,fontSize:12)),
              ),
            ),
          ],
          const SizedBox(height:13),
          Wrap(spacing:7,runSpacing:7,children:[
            _action('معلومات المتجر',Icons.settings_outlined,
              ()=>_open(MerchantStoreSettingsPage(store:store))),
            _action('المنتجات والمخزون',Icons.inventory_2_outlined,
              ()=>_open(MerchantProductsPage(storeId:id,storeName:name))),
            _action('طلبات المتجر',Icons.receipt_long_outlined,
              ()=>_open(MerchantOrdersPage(storeId:id))),
            _action('العروض المؤقتة',Icons.campaign_outlined,
              ()=>_open(MerchantCampaignsPage(storeId:id,storeName:name))),
            if(isAlAni && AlAniMerchantDeliveryGate.enabled)
              _action('إدارة المندوبين والتوصيل',Icons.local_shipping_outlined,
                ()=>_open(AlAniMerchantDeliveryPage(storeId:id))),
            if(isAlAni && AlAniSupportFeature.enabled)
              _action('رسائل العملاء',Icons.chat_bubble_outline,
                ()=>_open(const AlAniSupportInboxPage())),
          ]),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:const Text('مركز إدارة متاجري'),actions:[
      IconButton(onPressed:_reload,
        tooltip:'تحديث المتاجر',icon:const Icon(Icons.refresh)),
    ]),
    body:RefreshIndicator(onRefresh:_reload,
      child:ListView(
        padding:const EdgeInsets.all(16),
        physics:const AlwaysScrollableScrollPhysics(),
        children:[
          Container(
            padding:const EdgeInsets.all(20),
            decoration:BoxDecoration(
              borderRadius:BorderRadius.circular(20),
              gradient:const LinearGradient(
                colors:[merchantDark,merchantPurple])),
            child:const Column(
              crossAxisAlignment:CrossAxisAlignment.start,children:[
                Icon(Icons.admin_panel_settings_outlined,
                  color:Colors.white,size:35),
                SizedBox(height:8),
                Text('إدارة المحل من مكان واحد',style:TextStyle(
                  fontWeight:FontWeight.w900,fontSize:21,color:Colors.white)),
                SizedBox(height:7),
                Text('منتجاتك ومخزونك وطلباتك وبيانات محلك فقط. '
                  'حساب التاجر لا يمنح صلاحية إدارة الزبائن أو الرصيد.',
                  style:TextStyle(color:Colors.white,height:1.6)),
              ]),
          ),
          const SizedBox(height:20),
          TextField(
            decoration:const InputDecoration(
              labelText:'البحث في متاجري',
              prefixIcon:Icon(Icons.search),
              border:OutlineInputBorder()),
            onChanged:(value)=>setState(()=>_search=value.trim().toLowerCase()),
          ),
          const SizedBox(height:13),
          FutureBuilder<List<Map<String,dynamic>>>(
            future:_stores,builder:(context,snapshot){
              if(snapshot.connectionState!=ConnectionState.done){
                return const Padding(
                  padding:EdgeInsets.all(35),
                  child:Center(child:CircularProgressIndicator()));
              }
              if(snapshot.hasError){
                return const Card(child:Padding(padding:EdgeInsets.all(18),
                  child:Text('تعذر تحميل متاجرك. تحقق من الاتصال وحساب التاجر.')));
              }
              final rows=(snapshot.data??[]).where((s)=>
                (s['name']??'').toString().toLowerCase().contains(_search)).toList();
              if(rows.isEmpty){
                return const Card(child:Padding(padding:EdgeInsets.all(18),
                  child:Text('لا توجد متاجر مطابقة لحسابك وبحثك.')));
              }
              return Column(children:[
                for(final store in rows)_storeCard(store),
              ]);
            },
          ),
          const SizedBox(height:10),
          ListTile(
            leading:const Icon(Icons.assessment_outlined,color:merchantPurple),
            title:const Text('تقارير متاجري'),
            subtitle:const Text('أرقام طلبات حقيقية، لا تعني مبالغ محصّلة'),
            trailing:const Icon(Icons.chevron_left),
            onTap:()=>_open(const MerchantReportsPage()),
          ),
        ],
      ),
    ),
  );
}