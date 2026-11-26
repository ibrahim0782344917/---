import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AlAniPeriodReportPage extends StatefulWidget {
  const AlAniPeriodReportPage({super.key});
  static const enabled=bool.fromEnvironment('ALANI_BUSINESS_TEST_ENABLED') &&
    String.fromEnvironment('SUPABASE_URL')=='https://tgvdwotbrnhcoykuxdpr.supabase.co';
  @override
  State<AlAniPeriodReportPage> createState()=>_AlAniPeriodReportPageState();
}
class _AlAniPeriodReportPageState extends State<AlAniPeriodReportPage>{
  String _period='day';
  DateTime _day=DateTime.now().toUtc().add(const Duration(hours:3));
  late final String? _actor;
  late Future<List<dynamic>> _data;
  SupabaseClient get _db=>Supabase.instance.client;
  bool get _allowed=>AlAniPeriodReportPage.enabled&&_actor!=null&&_db.auth.currentUser?.id==_actor;
  String get _date=>'${_day.year}-${_day.month.toString().padLeft(2,'0')}-${_day.day.toString().padLeft(2,'0')}';
  @override
  void initState(){super.initState();_actor=_db.auth.currentUser?.id;_data=_load();}
  Future<List<dynamic>> _load()async{
    if(!_allowed)throw StateError('TEST_ONLY');
    return Future.wait<dynamic>([
      _db.rpc('alani_period_report_test',params:{'p_period':_period,'p_day':_date}),
      _db.rpc('alani_stock_valuation_test'),
    ]);
  }
  void _refresh()=>setState(()=>_data=_load());
  Future<void> _pick()async{
    final day=await showDatePicker(context:context,initialDate:DateTime(_day.year,_day.month,_day.day),firstDate:DateTime(2000),lastDate:DateTime(2100,12,31));
    if(day!=null&&mounted){_day=day;_refresh();}
  }
  Widget _amount(String label,Object? value)=>ListTile(title:Text(label),trailing:Text(value==null?'غير متاح':'$value د.ع'));
  @override
  Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:const Text('التقارير حسب الفترة — TEST'),actions:[IconButton(onPressed:_refresh,icon:const Icon(Icons.refresh))]),body:ListView(padding:const EdgeInsets.all(16),children:[
    DropdownButtonFormField<String>(initialValue:_period,items:const [
      DropdownMenuItem(value:'day',child:Text('يومي')),DropdownMenuItem(value:'month',child:Text('شهري')),DropdownMenuItem(value:'year',child:Text('سنوي'))],
      onChanged:(v){if(v!=null){_period=v;_refresh();}},decoration:const InputDecoration(labelText:'نوع الفترة')),
    OutlinedButton(onPressed:_pick,child:Text('التاريخ: $_date')),
    FutureBuilder<List<dynamic>>(future:_data,builder:(context,s){
      if(s.connectionState!=ConnectionState.done)return const LinearProgressIndicator();
      if(!_allowed||s.hasError||!s.hasData)return const Text('تعذر تحميل التقرير أو تغير الحساب.');
      final p=Map<String,dynamic>.from(s.data![0] as Map),v=Map<String,dynamic>.from(s.data![1] as Map);
      return Column(children:[
        Text('من ${p['start_day']} حتى قبل ${p['end_day_exclusive']} — توقيت بغداد'),
        _amount('مبيعات الفواتير الجديدة',p['pos_sales_iqd']),_amount('المرتجعات',p['pos_returns_iqd']),
        _amount('صافي المبيعات',p['pos_net_sales_iqd']),_amount('تكلفة المبيعات المقدرة',p['pos_estimated_cost_iqd']),
        _amount('المصاريف',p['expenses_iqd']),_amount('المشتريات',p['purchases_iqd']),
        _amount('مبيعات POS القديمة',p['legacy_pos_sales_iqd']),_amount('تحصيل الطلبات المسجل',p['cod_settlement_iqd']),
        _amount('استرجاع الطلبات المسجل',p['cod_refund_iqd']),
        _amount('نتيجة تشغيلية محدودة',p['limited_result_iqd']),
        const Text('النتيجة ليست صافي ربح شامل؛ تحجب عند نقص التكلفة أو وجود قنوات غير مقيمة.'),
        const Divider(),const Text('قيمة المخزون الحالية (ليست تاريخ الفترة)'),
        _amount('القيمة المعروفة المقدرة',v['known_value_iqd']),_amount('القيمة الإجمالية المقدرة',v['complete_estimated_value_iqd']),
        Text('منتجات بتكلفة غير معروفة: ${v['missing_cost_products']}'),
        const Text('آخر تكلفة شراء، لا FIFO ولا متوسط مرجح.'),
        for(final r in (v['items'] as List))ListTile(title:Text(r['name'].toString()),subtitle:Text('كمية: ${r['stock_quantity']}'),trailing:Text(r['estimated_value_iqd']?.toString()??'غير مقيم')),
      ]);
    }),
  ]));
}
