import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'alani_pos_invoice_page.dart' show posRequestKey;

class AlAniStockCountPage extends StatefulWidget {
  const AlAniStockCountPage({super.key,required this.product});
  final Map<String,dynamic> product;
  @override
  State<AlAniStockCountPage> createState()=>_AlAniStockCountPageState();
}
class _AlAniStockCountPageState extends State<AlAniStockCountPage>{
  final _qty=TextEditingController(),_reason=TextEditingController();
  final _key=posRequestKey();
  late final String? _actor;
  late Future<Map<String,dynamic>> _history;
  Map<String,dynamic>? _pending;
  bool _busy=false,_done=false;
  SupabaseClient get _db=>Supabase.instance.client;
  bool get _allowed=>const bool.fromEnvironment('ALANI_INVENTORY_TEST_ENABLED') &&
    const String.fromEnvironment('SUPABASE_URL')=='https://tgvdwotbrnhcoykuxdpr.supabase.co' &&
    _actor!=null&&_actor==_db.auth.currentUser?.id;
  @override
  void initState(){super.initState();_actor=_db.auth.currentUser?.id;_qty.text=widget.product['stock_quantity'].toString();_history=_load();}
  @override
  void dispose(){_qty.dispose();_reason.dispose();super.dispose();}
  Future<Map<String,dynamic>> _load()async{
    if(!_allowed)throw StateError('TEST_ONLY');
    return Map<String,dynamic>.from(await _db.rpc('alani_stock_history_test',params:{'p_product':widget.product['id']}) as Map);
  }
  void _notice(String s){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(s)));}
  Future<void> _save()async{
    if(_busy||_done||!_allowed)return;
    final count=int.tryParse(_qty.text.trim()),expected=(widget.product['stock_quantity'] as num).toInt();
    if(count==null||count<0||count>2147483647||_reason.text.trim().length<3||_reason.text.trim().length>200){_notice('تحقق من الكمية والسبب.');return;}
    setState(()=>_busy=true);
    try{
      if(_pending==null){
        final ok=await showDialog<bool>(context:context,builder:(ctx)=>AlertDialog(
          title:const Text('تأكيد تسوية جرد TEST'),
          content:Text('المخزون المسجل: $expected\nالعدد الفعلي: $count\nالفرق: ${count-expected}\nسيعدل مخزون الاختبار فقط.'),
          actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('رجوع')),FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('تأكيد'))]));
        if(ok!=true||!mounted||!_allowed)return;
        _pending={'p_key':_key,'p_product':widget.product['id'],'p_expected':expected,'p_counted':count,'p_reason':_reason.text.trim()};
      }
      await _db.rpc('alani_record_stock_count_test',params:_pending);
      if(mounted&&_allowed)setState((){_done=true;_history=_load();});
    }on PostgrestException catch(e){
      if(e.message=='STOCK_CHANGED_RECOUNT'){_notice('تغيّر المخزون منذ فتح الشاشة. ارجع وحدّث المنتج وأعد الجرد.');}
      else {_notice('تعذر تأكيد العملية. احتفظ بالمرجع وأعد نفس المحاولة.');}
    }catch(_){_notice('تعذر تأكيد العملية. احتفظ بالمرجع وأعد نفس المحاولة.');}
    finally{if(mounted)setState(()=>_busy=false);}
  }
  @override
  Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:const Text('الجرد وحركة المخزون — TEST')),body:ListView(padding:const EdgeInsets.all(16),children:[
    Text(widget.product['name'].toString(),style:const TextStyle(fontSize:20,fontWeight:FontWeight.bold)),
    Text('المخزون عند فتح الشاشة: ${widget.product['stock_quantity']}'),
    SelectableText(_key),TextButton(onPressed:()=>Clipboard.setData(ClipboardData(text:_key)),child:const Text('نسخ مرجع الجرد')),
    TextField(controller:_qty,readOnly:_busy||_pending!=null,keyboardType:TextInputType.number,decoration:const InputDecoration(labelText:'الكمية الفعلية المعدودة')),
    TextField(controller:_reason,readOnly:_busy||_pending!=null,maxLength:200,decoration:const InputDecoration(labelText:'سبب التسوية')),
    FilledButton(onPressed:_busy||_done||!_allowed?null:_save,child:Text(_done?'تم تسجيل الجرد':_pending==null?'مراجعة وتأكيد':'إعادة المحاولة نفسها')),
    const Divider(),const Text('آخر حركات المخزون منذ تفعيل سجل التدقيق'),
    FutureBuilder<Map<String,dynamic>>(future:_history,builder:(context,s){
      if(s.connectionState!=ConnectionState.done)return const LinearProgressIndicator();
      if(s.hasError||!s.hasData)return const Text('تعذر تحميل السجل.');
      final rows=s.data!['movements'] as List;
      final counts=s.data!['counts'] as List;
      return Column(children:[
        for(final r in rows)ListTile(title:Text('${r['before_qty']} ← ${r['after_qty']} (فرق ${r['delta']})'),subtitle:Text(r['changed_at'].toString())),
        const Divider(),const Text('تسويات الجرد'),
        for(final r in counts)ListTile(title:Text('${r['expected_qty']} ← ${r['counted_qty']}'),subtitle:Text('${r['reason']} • ${r['created_at']}')),
      ]);
    }),
  ]));
}
