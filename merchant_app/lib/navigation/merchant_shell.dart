// ignore_for_file: curly_braces_in_flow_control_structures
import 'package:flutter/material.dart';
import 'package:shitreed_merchant/account/merchant_account_page.dart';
import 'package:shitreed_merchant/commerce/commerce_service.dart';
import 'package:shitreed_merchant/merchant/merchant_dashboard.dart';
import 'package:shitreed_merchant/reports/merchant_reports.dart';
import 'package:shitreed_merchant/shared/merchant_widgets.dart';

class MerchantShellPage extends StatefulWidget {
  const MerchantShellPage({super.key});
  @override
  State<MerchantShellPage> createState()=>_MerchantShellPageState();
}

class _MerchantShellPageState extends State<MerchantShellPage> {
  int _tab=0;
  @override
  Widget build(BuildContext context) => Scaffold(
    body:IndexedStack(index:_tab,children:[
      MerchantOverviewPage(
        onNavigate:(index)=>setState((){_tab=index;}),
      ),
      const MerchantDashboardPage(),
      const MerchantResourceIndexPage(products:true),
      const MerchantResourceIndexPage(products:false),
      const MerchantAccountPage(),
    ]),
    bottomNavigationBar:NavigationBar(
      height:77,
      selectedIndex:_tab,
      onDestinationSelected:(value)=>setState((){_tab=value;}),
      labelBehavior:NavigationDestinationLabelBehavior.alwaysShow,
      destinations:const [
        NavigationDestination(icon:Icon(Icons.home_outlined),
          selectedIcon:Icon(Icons.home),label:'الرئيسية'),
        NavigationDestination(icon:Icon(Icons.storefront_outlined),
          selectedIcon:Icon(Icons.storefront),label:'متاجري'),
        NavigationDestination(icon:Icon(Icons.inventory_2_outlined),
          selectedIcon:Icon(Icons.inventory_2),label:'المنتجات'),
        NavigationDestination(icon:Icon(Icons.receipt_long_outlined),
          selectedIcon:Icon(Icons.receipt_long),label:'الطلبات'),
        NavigationDestination(icon:Icon(Icons.person_outline),
          selectedIcon:Icon(Icons.person),label:'حسابي'),
      ],
    ),
  );
}

class MerchantOverviewPage extends StatefulWidget {
  const MerchantOverviewPage({super.key,required this.onNavigate});
  final ValueChanged<int> onNavigate;
  @override
  State<MerchantOverviewPage> createState()=>_MerchantOverviewPageState();
}

class _MerchantOverviewPageState extends State<MerchantOverviewPage> {
  late Future<MerchantReport> _report;
  @override
  void initState(){super.initState();_report=loadMerchantReport();}
  Future<void> _refresh() async {
    final result=loadMerchantReport();
    setState((){_report=result;});
    await result;
  }

  Widget _metric(String name,String count,IconData icon) => Container(
    width:159,
    padding:const EdgeInsets.all(15),
    decoration:BoxDecoration(
      color:Colors.white,
      borderRadius:BorderRadius.circular(18),
      border:Border.all(color:const Color(0xFFE7DAF8))),
    child:Column(
      crossAxisAlignment:CrossAxisAlignment.start,
      children:[
        Icon(icon,color:merchantPurple,size:28),
        const SizedBox(height:7),
        Text(count,style:const TextStyle(
          color:merchantDark,fontWeight:FontWeight.w900,
          fontSize:22)),
        Text(name,style:const TextStyle(
          fontSize:12,color:Colors.black54)),
      ],
    ),
  );

  Widget _action(String title,String subtitle,
      IconData icon,int tab) => Card(
    color:Colors.white,
    child:ListTile(
      leading:CircleAvatar(backgroundColor:const Color(0xFFF1E6FD),
        child:Icon(icon,color:merchantPurple)),
      title:Text(title,style:const TextStyle(
        fontWeight:FontWeight.w800)),
      subtitle:Text(subtitle,
        style:const TextStyle(fontSize:12)),
      trailing:const Icon(Icons.chevron_left),
      onTap:()=>widget.onNavigate(tab),
    ),
  );

  @override
  Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:const Text('الرئيسية • شتريد تاجر')),
    body:SafeArea(child:RefreshIndicator(
      onRefresh:_refresh,
      child:ListView(
        physics:const AlwaysScrollableScrollPhysics(),
        padding:const EdgeInsets.all(16),children:[
          Container(
            padding:const EdgeInsets.all(20),
            decoration:BoxDecoration(
              borderRadius:BorderRadius.circular(23),
              gradient:const LinearGradient(colors:[
                merchantDark,merchantPurple,
              ])),
            child:const Row(children:[
              Icon(Icons.storefront_rounded,
                size:64,color:merchantOrange),
              SizedBox(width:13),
              Expanded(child:Column(
                crossAxisAlignment:CrossAxisAlignment.start,
                children:[
                  Text('هلا بيك في شتريد تاجر',style:TextStyle(
                    color:Colors.white,fontWeight:FontWeight.w900,
                    fontSize:22)),
                  Text('ادخل المنتجات، تابع الطلبات '
                    'وطوّر محلك من موبايلك',
                    style:TextStyle(color:Colors.white70)),
                ],
              )),
            ]),
          ),
          const SizedBox(height:20),
          const Text('ملخّص متاجري',style:TextStyle(
            color:merchantDark,fontSize:21,fontWeight:FontWeight.w900)),
          const SizedBox(height:11),
          FutureBuilder<MerchantReport>(
            future:_report,
            builder:(context,snap){
              if(snap.connectionState!=ConnectionState.done){
                return const Center(child:Padding(
                  padding:EdgeInsets.all(24),
                  child:CircularProgressIndicator()));
              }
              if(snap.hasError){
                return const Text('تعذّر تحميل الملخص. اسحب للتحديث.');
              }
              final v=snap.data!;
              return Column(
                crossAxisAlignment:CrossAxisAlignment.stretch,
                children:[
                  Wrap(spacing:11,runSpacing:11,children:[
                    _metric('محلاتي',v.stores.toString(),
                      Icons.storefront_outlined),
                    _metric('قيد المراجعة',
                      v.pendingApprovalStores.toString(),
                      Icons.hourglass_empty),
                    _metric('طلبات جديدة',
                      v.placedOrders.toString(),
                      Icons.markunread_outlined),
                    _metric('طلبات قيد التحضير',
                      v.preparingOrders.toString(),
                      Icons.inventory_outlined),
                  ]),
                  const SizedBox(height:13),
                  if(v.pendingApprovalStores>0)
                    Container(
                      padding:const EdgeInsets.all(13),
                      decoration:BoxDecoration(
                        color:const Color(0xFFFFF3E6),
                        borderRadius:BorderRadius.circular(15)),
                      child:const Text('عندك محل بانتظار موافقة الإدارة. '
                        'ما يظهر للزبائن إلا بعد التحقق من ملكيته.',
                        style:TextStyle(color:Color(0xFF844600))),
                    ),
                ],
              );
            },
          ),
          const SizedBox(height:23),
          const Text('إدارة سريعة',style:TextStyle(
            color:merchantDark,fontSize:21,fontWeight:FontWeight.w900)),
          const SizedBox(height:10),
          _action('إدارة المحلات','إضافة محلك وتعديل أوقات الدوام', 
            Icons.storefront_outlined,1),
          _action('المنتجات والمخزون','أضف الأسعار والصور وتابع الكميات',
            Icons.inventory_2_outlined,2),
          _action('الطلبات الجديدة','اقبل، جهّز، وتابع حالة الطلب',
            Icons.receipt_long_outlined,3),
          _action('الحساب والدعم','الخصوصية والشروط والمساعدة',
            Icons.support_agent_outlined,4),
          const SizedBox(height:18),
          const Text('ملاحظة: الإحصائيات تعبّر عن طلبات مسجلة '
            'وليست أرباحاً نقدية محصّلة.',
            textAlign:TextAlign.center,
            style:TextStyle(color:Colors.black54,fontSize:12)),
        ],
      ))),
  );
}

class MerchantResourceIndexPage extends StatefulWidget {
  const MerchantResourceIndexPage({super.key,required this.products});
  final bool products;
  @override
  State<MerchantResourceIndexPage> createState()=>_MerchantResourceIndexPageState();
}
class _MerchantResourceIndexPageState
    extends State<MerchantResourceIndexPage> {
  late Future<List<Map<String,dynamic>>> _stores;
  @override
  void initState(){super.initState();_stores=CommerceService.myStores();}
  Future<void> _refresh() async {
    final result=CommerceService.myStores();
    setState((){_stores=result;});
    await result;
  }
  @override
  Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:Text(widget.products
      ? 'المنتجات والمخزون':'طلبات المتاجر')),
    body:SafeArea(child:RefreshIndicator(
      onRefresh:_refresh,
      child:ListView(
        physics:const AlwaysScrollableScrollPhysics(),
        padding:const EdgeInsets.all(16),children:[
          Text(widget.products
            ? 'اختر المحل لإدارة المنتجات':'اختر المحل لعرض الطلبات',
            style:const TextStyle(color:merchantDark,
              fontSize:21,fontWeight:FontWeight.w900)),
          const SizedBox(height:8),
          const Text('المنتجات والطلبات مرتبطة '
            'بمتجرك المحفوظ في قاعدة البيانات.',
            style:TextStyle(color:Colors.black54)),
          const SizedBox(height:12),
          FutureBuilder<List<Map<String,dynamic>>>(
            future:_stores,
            builder:(context,snap){
              if(snap.connectionState!=ConnectionState.done){
                return const Center(child:CircularProgressIndicator());
              }
              if(snap.hasError)return const Text(
                'تعذّر تحميل قائمة المتاجر.');
              final stores=snap.data??[];
              if(stores.isEmpty)return const Padding(
                padding:EdgeInsets.all(30),
                child:Text('ما عندك محل مسجل بعد. '
                  'افتح «متاجري» وسجّل أول محل.',
                  textAlign:TextAlign.center));
              return Column(children:[
                for(final store in stores)Card(color:Colors.white,
                  child:ListTile(
                    leading:const CircleAvatar(
                      backgroundColor:Color(0xFFEFE5FC),
                      child:Icon(Icons.storefront,
                        color:merchantPurple)),
                    title:Text(store['name'] as String? ?? '',
                      style:const TextStyle(
                        fontWeight:FontWeight.w900)),
                    subtitle:Text(store['status']=='approved'
                      ? 'متجر معتمد'
                      : 'بانتظار مراجعة الإدارة'),
                    trailing:const Icon(Icons.chevron_left),
                    onTap:(){
                      final id=store['id'] as String;
                      final page=widget.products
                        ? MerchantProductsPage(
                            storeId:id,
                            storeName:store['name'] as String)
                        : MerchantOrdersPage(storeId:id);
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(builder:(_)=>page));
                    },
                  )),
              ]);
            },
          ),
        ]))),
  );
}
