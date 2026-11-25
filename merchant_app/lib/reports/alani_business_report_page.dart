import 'package:flutter/material.dart';
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
    return Map<String,dynamic>.from(data as Map);
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
        const Text('تعرض هذه الصفحة التقرير فقط. إدخال العمليات يحتاج واجهات مستقلة واختبارات إضافية.'),
      ]);
    }),
  );
}
