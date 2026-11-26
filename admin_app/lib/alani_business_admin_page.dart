import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AlAniBusinessAdminPage extends StatefulWidget {
  const AlAniBusinessAdminPage({super.key});
  static const enabled=bool.fromEnvironment('ALANI_BUSINESS_TEST_ENABLED') &&
    String.fromEnvironment('SUPABASE_URL')=='https://tgvdwotbrnhcoykuxdpr.supabase.co';
  @override
  State<AlAniBusinessAdminPage> createState()=>_AlAniBusinessAdminPageState();
}
class _AlAniBusinessAdminPageState extends State<AlAniBusinessAdminPage>{
  late Future<Map<String,dynamic>> _data;
  Future<Map<String,dynamic>> _load()async{
    if(!AlAniBusinessAdminPage.enabled)throw StateError('TEST_ONLY');
    final result=Map<String,dynamic>.from(await Supabase.instance.client.rpc('alani_admin_business_overview_test') as Map);
    result['accounting']=await Supabase.instance.client.rpc('alani_accounting_overview_test');
    return result;
  }
  @override
  void initState(){super.initState();_data=_load();}
  void _refresh()=>setState(()=>_data=_load());
  @override
  Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:const Text('التقارير التجارية للإدارة — TEST'),actions:[IconButton(onPressed:_refresh,icon:const Icon(Icons.refresh))]),
    body:FutureBuilder<Map<String,dynamic>>(future:_data,builder:(context,snap){
      if(snap.connectionState!=ConnectionState.done)return const Center(child:CircularProgressIndicator());
      if(snap.hasError||!snap.hasData)return Center(child:TextButton(onPressed:_refresh,child:const Text('تعذر التحميل، تحقق من الصلاحية')));
      final data=snap.data!;
      final acct=Map<String,dynamic>.from(data['accounting'] as Map);
      final ops=Map<String,dynamic>.from(data['operations'] as Map),debt=Map<String,dynamic>.from(data['debts'] as Map),
        trial=Map<String,dynamic>.from(acct['trial_balance'] as Map),margin=Map<String,dynamic>.from(data['pos_margin'] as Map);
      Widget amount(String title,Object? value)=>ListTile(title:Text(title),trailing:Text(value==null?'غير متاح':'$value د.ع'));
      return ListView(padding:const EdgeInsets.all(16),children:[
        const Text('تقارير TEST وليست أرصدة حقيقية أو حسابات نهائية.'),
        amount('المشتريات',ops['purchases_iqd']),amount('المصاريف',ops['expenses_iqd']),
        amount('الديون المتبقية',debt['balance_iqd']),
        amount('مبيعات POS السابقة (منتج واحد)',ops['pos_sales_iqd']),
        const Divider(),const Text('الفواتير متعددة المنتجات'),
        amount('المبيعات',margin['sales_iqd']),amount('المرتجعات',margin['returns_iqd']),
        amount('صافي المبيعات',margin['net_sales_iqd']),amount('التكلفة المقدرة',margin['estimated_cost_iqd']),
        amount('هامش الربح الإجمالي المقدر',margin['estimated_gross_margin_iqd']),
        const Text('طريقة آخر تكلفة شراء مسجلة. لا يشمل المصاريف أو الطلبات الإلكترونية أو المبيعات السابقة. ليس صافي الربح.'),
        const Divider(),const Text('ميزان المراجعة الموسع — يشمل فواتير POS الجديدة'),
        amount('المدين',trial['debit_iqd']),amount('الدائن',trial['credit_iqd']),
        amount('النتيجة التشغيلية التقديرية المحدودة',acct['limited_estimated_result_iqd']),
        const Text('لا يشمل تكاليف جميع القنوات أو الفروقات غير المقيمة. لا يمثل صافي ربح نهائياً.'),
      ]);
    }));
}
