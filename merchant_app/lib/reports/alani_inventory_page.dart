import 'package:flutter/material.dart';
import 'alani_stock_count_page.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AlAniInventoryPage extends StatefulWidget {
  const AlAniInventoryPage({super.key});
  static const enabled=bool.fromEnvironment('ALANI_INVENTORY_TEST_ENABLED',defaultValue:false) &&
    String.fromEnvironment('SUPABASE_URL')=='https://tgvdwotbrnhcoykuxdpr.supabase.co';
  @override
  State<AlAniInventoryPage> createState()=>_AlAniInventoryPageState();
}
class _AlAniInventoryPageState extends State<AlAniInventoryPage>{
  final _barcode=TextEditingController();
  late Future<List<dynamic>> _data;
  bool _busy=false;
  @override
  void initState(){super.initState();_data=_load();}
  @override
  void dispose(){_barcode.dispose();super.dispose();}
  Future<List<dynamic>> _load()async{
    if(!AlAniInventoryPage.enabled)throw StateError('TEST_ONLY');
    final code=_barcode.text.trim();
    return await Supabase.instance.client.rpc('alani_inventory_report_test',params:{'p_barcode':code.isEmpty?null:code}) as List;
  }
  void _reload()=>setState(()=>_data=_load());
  Future<void> _edit(Map<String,dynamic> row)async{
    if(_busy)return;
    var code=row['barcode']?.toString()??'';
    var threshold=row['low_stock_threshold'].toString();
    final ok=await showDialog<bool>(context:context,builder:(ctx)=>AlertDialog(
      title:const Text('إعدادات الجرد'),
      content:Column(mainAxisSize:MainAxisSize.min,children:[
        TextFormField(initialValue:code,keyboardType:TextInputType.number,onChanged:(v)=>code=v.trim(),decoration:const InputDecoration(labelText:'الباركود (8–14 رقماً)')),
        TextFormField(initialValue:threshold,keyboardType:TextInputType.number,onChanged:(v)=>threshold=v.trim(),decoration:const InputDecoration(labelText:'حد المخزون المنخفض')),
      ]),
      actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('إلغاء')),FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('حفظ'))],
    ));
    if(ok!=true||!mounted||_busy)return;
    final limit=int.tryParse(threshold);
    if(limit==null||limit<0||limit>100000||(code.isNotEmpty&&!RegExp(r'^[0-9]{8,14}$').hasMatch(code))){
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('القيم المدخلة غير صالحة.')));return;
    }
    setState(()=>_busy=true);
    try{
      await Supabase.instance.client.rpc('alani_set_inventory_settings_test',params:{'p_product_id':row['id'],'p_barcode':code.isEmpty?null:code,'p_threshold':limit});
      if(mounted)_reload();
    }catch(_){if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('تعذر الحفظ. تحقق من الصلاحية وعدم تكرار الباركود.')));}
    finally{if(mounted)setState(()=>_busy=false);}
  }
  @override
  Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:const Text('المخزون والجرد — TEST'),actions:[IconButton(onPressed:_busy?null:_reload,icon:const Icon(Icons.refresh))]),
    body:Column(children:[
      Padding(padding:const EdgeInsets.all(12),child:TextField(controller:_barcode,keyboardType:TextInputType.number,decoration:InputDecoration(labelText:'بحث برقم الباركود',suffixIcon:IconButton(onPressed:_busy?null:_reload,icon:const Icon(Icons.search))),onSubmitted:(_)=>_reload())),
      const Padding(padding:EdgeInsets.all(8),child:Text('تقدير نفاد المخزون من مبيعات آخر 30 يوماً؛ ليس ضماناً ولا نموذج ذكاء اصطناعي.')),
      Expanded(child:FutureBuilder<List<dynamic>>(future:_data,builder:(context,snapshot){
        if(snapshot.connectionState!=ConnectionState.done)return const Center(child:CircularProgressIndicator());
        if(snapshot.hasError)return Center(child:TextButton(onPressed:_reload,child:const Text('تعذر تحميل التقرير، تحقق من الصلاحية أو الباركود')));
        final rows=snapshot.data??[];
        if(rows.isEmpty)return const Center(child:Text('لا توجد نتائج.'));
        return ListView.builder(itemCount:rows.length,itemBuilder:(context,i){
          final row=Map<String,dynamic>.from(rows[i] as Map);
          final days=row['estimated_days_remaining'];
          return Card(child:ListTile(
            leading:Icon(row['low_stock']==true?Icons.warning_amber:Icons.inventory_2_outlined),
            title:Text(row['name'].toString()),
            subtitle:Text('المخزون: ${row['stock_quantity']} • مبيعات 30 يوماً: ${row['sold_30d']}\nأيام متوقعة: ${days??"بيانات غير كافية"}\nالباركود: ${row['barcode']??"غير محدد"}'),
            onTap:_busy?null:()async{await Navigator.of(context).push<void>(MaterialPageRoute(builder:(_)=>AlAniStockCountPage(product:row)));if(mounted)_reload();},
            trailing:IconButton(onPressed:_busy?null:()=>_edit(row),icon:const Icon(Icons.edit),tooltip:'إعدادات الجرد'),
          ));
        });
      })),
    ]));
}
