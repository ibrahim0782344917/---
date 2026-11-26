import 'package:flutter/material.dart';
import 'alani_business_entry_page.dart';
import 'alani_pos_invoice_page.dart';
import 'alani_bundle_manage_page.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AlAniBusinessReportPage extends StatefulWidget {
  const AlAniBusinessReportPage({super.key});
  static const enabled=bool.fromEnvironment('ALANI_BUSINESS_TEST_ENABLED',defaultValue:false) &&
      String.fromEnvironment('SUPABASE_URL')=='https://tgvdwotbrnhcoykuxdpr.supabase.co';
  @override
  State<AlAniBusinessReportPage> createState()=>_AlAniBusinessReportPageState();
}
class _AlAniBusinessReportPageState extends State<AlAniBusinessReportPage>{
  late Future<Map<String,dynamic>> _report;
  @override
  void initState(){super.initState();_report=_load();}
  Future<Map<String,dynamic>> _load()async{
    if(!AlAniBusinessReportPage.enabled)throw StateError('TEST_ONLY');
    final data=await Supabase.instance.client.rpc('alani_business_report_test');
    final report=Map<String,dynamic>.from(data as Map);
    final debt=await Supabase.instance.client.rpc('alani_debt_report_test');
    report['debt']=debt;
    report['trial_balance']=await Supabase.instance.client.rpc('alani_operational_trial_balance_test');
    if(AlAniPosInvoicePage.enabled) report['pos_margin']=await Supabase.instance.client.rpc('alani_pos_margin_test');
    return report;
  }
  void _refresh()=>setState(()=>_report=_load());
  @override
  Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:const Text('العمليات التجارية — TEST'),actions:[
      IconButton(onPressed:_refresh,icon:const Icon(Icons.refresh),tooltip:'تحديث')]),
    body:FutureBuilder<Map<String,dynamic>>(future:_report,builder:(context,snapshot){
      if(snapshot.connectionState!=ConnectionState.done)return const Center(child:CircularProgressIndicator());
      if(snapshot.hasError||!snapshot.hasData)return Center(child:TextButton(onPressed:_refresh,child:const Text('تعذر تحميل التقرير، تحقق من الصلاحية')));
      final data=snapshot.data!;
      final debt=Map<String,dynamic>.from(data['debt'] as Map);
      final trial=Map<String,dynamic>.from(data['trial_balance'] as Map);
      final suppliers=(data['suppliers'] as List? ?? []).map((e)=>Map<String,dynamic>.from(e as Map));
      return ListView(padding:const EdgeInsets.all(16),children:[
        const Text('سجلات تشغيلية تجريبية؛ ليست أرباحاً أو تسوية محاسبية أو إثبات تحويل أموال.'),
        for(final entry in const {
          'purchases_iqd':'إجمالي المشتريات المسجلة',
          'credit_purchases_iqd':'المشتريات الآجلة المسجلة (ليس رصيد دين متبقياً)',
          'pos_sales_iqd':'مبيعات نقاط البيع المسجلة',
          'expenses_iqd':'المصاريف المسجلة',
        }.entries)
          Card(child:ListTile(title:Text(entry.value),trailing:Text('${data[entry.key]??0} د.ع'))),
        const SizedBox(height:16),
        Text('الموردون: ${data['supplier_count']??0}',style:const TextStyle(fontWeight:FontWeight.bold)),
        for(final supplier in suppliers)
          ListTile(title:Text(supplier['name'].toString()),subtitle:Text(supplier['active']==true?'نشط':'متوقف')),
        Card(child:ListTile(title:const Text('الديون المتبقية'),trailing:Text('${debt['balance_iqd']} د.ع'),subtitle:Text('السداد المسجل: ${debt['paid_iqd']} د.ع'))),
        for(final entry in const {'supplier':'إضافة مورد','purchase':'استلام مشتريات','pos':'بيع بالباركود','debt':'تسجيل سداد دين','expense':'تسجيل مصروف'}.entries)
          Card(child:ListTile(title:Text(entry.value),leading:const Icon(Icons.add_circle_outline),onTap:()async{
            await Navigator.of(context).push<void>(MaterialPageRoute(builder:(_)=>AlAniBusinessEntryPage(mode:entry.key)));
            if(mounted)_refresh();
          })),
        Card(child:Column(children:[
          const ListTile(title:Text('ميزان المراجعة التشغيلي — TEST'),subtitle:Text('لا يشمل تكلفة المبيعات أو الطلبات الإلكترونية. ليس تقرير أرباح.')),
          ListTile(title:const Text('إجمالي المدين'),trailing:Text('${trial['debit_iqd']} د.ع')),
          ListTile(title:const Text('إجمالي الدائن'),trailing:Text('${trial['credit_iqd']} د.ع')),
          ListTile(title:Text(trial['balanced']==true?'القيود متوازنة':'القيود غير متوازنة')),
        ])),
        if(AlAniPosInvoicePage.enabled)...[
          Card(child:ListTile(title:const Text('كاشير متعدد المنتجات'),leading:const Icon(Icons.qr_code_scanner),onTap:()async{
            await Navigator.of(context).push<void>(MaterialPageRoute(builder:(_)=>const AlAniPosInvoicePage()));
            if(mounted)_refresh();
          })),
          Card(child:ListTile(title:const Text('الفواتير والمرتجعات'),leading:const Icon(Icons.receipt_long_outlined),onTap:()async{
            await Navigator.of(context).push<void>(MaterialPageRoute(builder:(_)=>const AlAniPosHistoryPage()));
            if(mounted)_refresh();
          })),
          if(data['pos_margin'] is Map)
            Card(child:ListTile(title:const Text('هامش الربح الإجمالي المقدر للفواتير الجديدة'),subtitle:const Text('لا يشمل المصاريف أو الطلبات الإلكترونية'),trailing:Text((data['pos_margin'] as Map)['estimated_gross_margin_iqd']?.toString()??'تكلفة غير متاحة'))),
        ],
        if(AlAniBundleManagePage.enabled)
          Card(child:ListTile(title:const Text('إدارة الباقات'),leading:const Icon(Icons.local_offer_outlined),onTap:()async{
            await Navigator.of(context).push<void>(MaterialPageRoute(builder:(_)=>const AlAniBundleManagePage()));
            if(mounted)_refresh();
          })),
        const Text('السداد والمبيعات في TEST سجلات تشغيلية فقط، لا تحويل أموال.'),
      ]);
    }),
  );
}
