import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AlAniBundleManagePage extends StatefulWidget {
  const AlAniBundleManagePage({super.key});
  static const enabled=bool.fromEnvironment('ALANI_BUSINESS_TEST_ENABLED') &&
    String.fromEnvironment('SUPABASE_URL')=='https://tgvdwotbrnhcoykuxdpr.supabase.co';
  @override
  State<AlAniBundleManagePage> createState()=>_AlAniBundleManagePageState();
}
class _AlAniBundleManagePageState extends State<AlAniBundleManagePage>{
  late Future<List<dynamic>> _data;
  final _title=TextEditingController(),_price=TextEditingController(),_qty=TextEditingController(text:'1'),_days=TextEditingController(text:'7');
  final _items=<String,int>{};
  String? _selected;
  bool _free=false,_busy=false;
  late final String? _actor;
  SupabaseClient get _db=>Supabase.instance.client;
  bool get _allowed=>AlAniBundleManagePage.enabled&&_actor!=null&&_db.auth.currentUser?.id==_actor;
  @override
  void initState(){super.initState();_actor=_db.auth.currentUser?.id;_data=_load();}
  @override
  void dispose(){_title.dispose();_price.dispose();_qty.dispose();_days.dispose();super.dispose();}
  Future<List<dynamic>> _load()async{
    if(!_allowed)throw StateError('TEST_ONLY');
    return Future.wait<dynamic>([_db.rpc('alani_manage_bundles_list_test'),_db.rpc('alani_inventory_report_test',params:{'p_barcode':null})]);
  }
  void _refresh()=>setState(()=>_data=_load());
  void _notice(String s){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(s)));}
  Future<void> _save()async{
    if(_busy||!_allowed)return;
    final price=int.tryParse(_price.text),days=int.tryParse(_days.text);
    if(price==null||price<=0||days==null||days<1||days>90||_items.length<2||_title.text.trim().length<2){_notice('أدخل اسم الباقة وسعرها ومنتجين مختلفين ومدة من يوم إلى 90 يوماً.');return;}
    setState(()=>_busy=true);
    try{
      final now=DateTime.now().toUtc();
      await _db.rpc('alani_save_bundle_test',params:{
        'p_title':_title.text.trim(),'p_items':[for(final e in _items.entries){'product_id':e.key,'quantity':e.value}],
        'p_price_iqd':price,'p_free_delivery':_free,'p_starts_at':now.toIso8601String(),'p_ends_at':now.add(Duration(days:days)).toIso8601String()
      });
      if(mounted){_items.clear();_title.clear();_price.clear();_refresh();_notice('تم تسجيل الباقة في TEST.');}
    }catch(_){_notice('لم تتأكد نتيجة الحفظ. حدّث القائمة قبل إعادة الإنشاء.');}
    finally{if(mounted)setState(()=>_busy=false);}
  }
  Future<void> _toggle(String id,bool value)async{
    if(_busy||!_allowed)return;
    setState(()=>_busy=true);
    try{await _db.rpc('alani_bundle_enabled_test',params:{'p_bundle':id,'p_enabled':value});if(mounted)_refresh();}
    catch(_){_notice('تعذر تغيير الحالة.');}finally{if(mounted)setState(()=>_busy=false);}
  }
  @override
  Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:const Text('إدارة الباقات — TEST'),actions:[IconButton(onPressed:_busy?null:_refresh,icon:const Icon(Icons.refresh))]),
    body:FutureBuilder<List<dynamic>>(future:_data,builder:(context,snap){
      if(snap.connectionState!=ConnectionState.done)return const Center(child:CircularProgressIndicator());
      if(snap.hasError||!snap.hasData)return Center(child:TextButton(onPressed:_refresh,child:const Text('تعذر التحميل')));
      final bundles=(snap.data![0] as List).map((e)=>Map<String,dynamic>.from(e as Map));
      final products=(snap.data![1] as List).map((e)=>Map<String,dynamic>.from(e as Map)).toList();
      final names={for(final p in products)p['id'].toString():p['name'].toString()};
      return ListView(padding:const EdgeInsets.all(16),children:[
        const Text('إنشاء باقة جديدة للاختبار'),TextField(controller:_title,enabled:!_busy,decoration:const InputDecoration(labelText:'اسم الباقة')),
        DropdownButtonFormField<String>(initialValue:names.containsKey(_selected)?_selected:null,isExpanded:true,items:[for(final p in products)DropdownMenuItem(value:p['id'] as String,child:Text(p['name'].toString()))],onChanged:_busy?null:(v)=>setState(()=>_selected=v),decoration:const InputDecoration(labelText:'المنتج')),
        TextField(controller:_qty,enabled:!_busy,keyboardType:TextInputType.number,decoration:const InputDecoration(labelText:'الكمية')),
        OutlinedButton(onPressed:_busy?null:(){final id=_selected,n=int.tryParse(_qty.text)??0;if(id!=null&&n>=1&&n<=20&&(_items.containsKey(id)||_items.length<20))setState(()=>_items[id]=n);},child:const Text('إضافة/تعديل كمية المكون')),
        for(final e in _items.entries)ListTile(title:Text(names[e.key]??e.key),subtitle:Text('الكمية: ${e.value}'),trailing:IconButton(onPressed:_busy?null:()=>setState(()=>_items.remove(e.key)),icon:const Icon(Icons.delete_outline))),
        TextField(controller:_price,enabled:!_busy,keyboardType:TextInputType.number,decoration:const InputDecoration(labelText:'سعر الباقة بالدينار')),
        TextField(controller:_days,enabled:!_busy,keyboardType:TextInputType.number,decoration:const InputDecoration(labelText:'مدة العرض بالأيام')),
        SwitchListTile(title:const Text('توصيل مجاني'),value:_free,onChanged:_busy?null:(v)=>setState(()=>_free=v)),
        FilledButton(onPressed:_busy||!_allowed?null:_save,child:const Text('إنشاء باقة TEST')),
        const Divider(),const Text('الباقات المسجلة'),
        for(final b in bundles)SwitchListTile(title:Text(b['title'].toString()),subtitle:Text('${b['price_iqd']} د.ع • ينتهي: ${b['ends_at']}'),value:b['enabled']==true,onChanged:_busy||!_allowed?null:(v)=>_toggle(b['id'] as String,v)),
      ]);
    }));
}
