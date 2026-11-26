import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'alani_pos_pdf.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

String posRequestKey(){
  final r=Random.secure(),b=List<int>.filled(16,0);
  for(var i=0;i<b.length;i++){b[i]=r.nextInt(256);}
  b[6]=(b[6]&15)|64;b[8]=(b[8]&63)|128;
  final s=b.map((v)=>v.toRadixString(16).padLeft(2,'0')).join();
  return '${s.substring(0,8)}-${s.substring(8,12)}-${s.substring(12,16)}-${s.substring(16,20)}-${s.substring(20)}';
}
class AlAniBarcodeCameraPage extends StatefulWidget{
  const AlAniBarcodeCameraPage({super.key});
  @override
  State<AlAniBarcodeCameraPage> createState()=>_AlAniBarcodeCameraPageState();
}
class _AlAniBarcodeCameraPageState extends State<AlAniBarcodeCameraPage>{
  bool _done=false;
  @override
  Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:const Text('مسح باركود المنتج')),
    body:MobileScanner(onDetect:(capture){
      if(_done||!mounted)return;
      for(final code in capture.barcodes){
        final value=code.rawValue;
        if(value!=null&&RegExp(r'^[0-9]{8,14}$').hasMatch(value)){
          _done=true;Navigator.pop(context,value);break;
        }
      }
    },errorBuilder:(context,error)=>const Center(child:Text('الكاميرا غير متاحة. ارجع للإدخال اليدوي.'))));
}
class AlAniPosInvoicePage extends StatefulWidget{
  const AlAniPosInvoicePage({super.key});
  static const enabled=bool.fromEnvironment('ALANI_POS_INVOICE_TEST_ENABLED') &&
    String.fromEnvironment('SUPABASE_URL')=='https://tgvdwotbrnhcoykuxdpr.supabase.co';
  @override
  State<AlAniPosInvoicePage> createState()=>_AlAniPosInvoicePageState();
}
class _AlAniPosInvoicePageState extends State<AlAniPosInvoicePage>{
  final _barcode=TextEditingController(),_qty=TextEditingController(text:'1');
  final _cart=<String,int>{};
  late final String? _actor;
  bool _busy=false;
  Map<String,dynamic>? _pending;
  String? _invoice;
  String _key=posRequestKey();
  SupabaseClient get _db=>Supabase.instance.client;
  bool get _allowed=>AlAniPosInvoicePage.enabled&&_actor!=null&&_db.auth.currentUser?.id==_actor;
  bool get _locked=>_busy||_pending!=null||_invoice!=null;
  @override
  void initState(){super.initState();_actor=_db.auth.currentUser?.id;}
  @override
  void dispose(){_barcode.dispose();_qty.dispose();super.dispose();}
  void _notice(String s){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(s)));}
  void _add(){
    if(_locked||!_allowed)return;
    final code=_barcode.text.trim(),n=int.tryParse(_qty.text.trim())??0;
    if(!RegExp(r'^[0-9]{8,14}$').hasMatch(code)||n<1||n+(_cart[code]??0)>20||(!_cart.containsKey(code)&&_cart.length>=20)){_notice('تحقق من الباركود والكمية.');return;}
    setState(()=>_cart[code]=(_cart[code]??0)+n);_barcode.clear();
  }
  Future<void> _scan()async{
    final code=await Navigator.of(context).push<String>(MaterialPageRoute(builder:(_)=>const AlAniBarcodeCameraPage()));
    if(mounted&&code!=null&&!_locked)_barcode.text=code;
  }
  Future<void> _submit()async{
    if(_busy||!_allowed||_invoice!=null||_cart.isEmpty)return;
    setState(()=>_busy=true);
    try{
      if(_pending==null){
        final items=[for(final e in _cart.entries){'barcode':e.key,'quantity':e.value}];
        final q=Map<String,dynamic>.from(await _db.rpc('alani_pos_cart_quote_test',params:{'p_items':items}) as Map);
        if(!mounted||!_allowed)return;
        final lines=(q['lines'] as List).map((e)=>Map<String,dynamic>.from(e as Map));
        final ok=await showDialog<bool>(context:context,builder:(ctx)=>AlertDialog(title:const Text('تأكيد فاتورة TEST'),
          content:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[
            for(final l in lines)Text('${l['name']} × ${l['quantity']} = ${l['total_iqd']} د.ع'),
            Text('الإجمالي: ${q['total_iqd']} د.ع'),const Text('لا تحصيل أموال حقيقية.')])),
          actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('رجوع')),FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('تسجيل'))]));
        if(ok!=true||!mounted||!_allowed)return;
        _pending={'p_key':_key,'p_items':items,'p_expected_total':q['total_iqd']};
      }
      final id=await _db.rpc('alani_pos_invoice_sale_test',params:_pending);
      if(mounted&&_allowed)setState(()=>_invoice=id.toString());
    }catch(_){_notice(_pending==null?'تعذر التسعير. راجع المخزون والباركود.':'النتيجة غير مؤكدة. أعد المحاولة بنفس الرقم والبيانات.');}
    finally{if(mounted)setState(()=>_busy=false);}
  }
  @override
  Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:const Text('كاشير متعدد المنتجات — TEST')),
    body:ListView(padding:const EdgeInsets.all(16),children:[
      const Text('سجل فاتورة اختبار فقط. احتفظ برقمها قبل التأكيد.'),
      SelectableText(_key),TextButton(onPressed:()=>Clipboard.setData(ClipboardData(text:_key)),child:const Text('نسخ المرجع')),
      if(_invoice!=null)SelectableText('تم تسجيل الفاتورة: $_invoice'),
      if(_invoice==null)...[
        TextField(controller:_barcode,readOnly:_locked,keyboardType:TextInputType.number,decoration:InputDecoration(labelText:'الباركود',suffixIcon:IconButton(onPressed:_locked||!_allowed?null:_scan,icon:const Icon(Icons.qr_code_scanner)))),
        TextField(controller:_qty,readOnly:_locked,keyboardType:TextInputType.number,decoration:const InputDecoration(labelText:'الكمية')),
        OutlinedButton(onPressed:_locked?null:_add,child:const Text('إضافة إلى الفاتورة')),
        for(final e in _cart.entries)ListTile(title:Text(e.key),subtitle:Text('الكمية: ${e.value}'),trailing:IconButton(onPressed:_locked?null:()=>setState(()=>_cart.remove(e.key)),icon:const Icon(Icons.delete_outline))),
        FilledButton(onPressed:_busy||!_allowed||_cart.isEmpty?null:_submit,child:Text(_pending==null?'عرض السعر والتأكيد':'إعادة نفس المحاولة')),
      ],
      if(_busy)const LinearProgressIndicator(),
    ]));
}
class AlAniPosHistoryPage extends StatefulWidget{
  const AlAniPosHistoryPage({super.key});
  @override
  State<AlAniPosHistoryPage> createState()=>_AlAniPosHistoryPageState();
}
class _AlAniPosHistoryPageState extends State<AlAniPosHistoryPage>{
  late Future<List<dynamic>> _data;
  SupabaseClient get _db=>Supabase.instance.client;
  Future<List<dynamic>> _load()async{
    if(!AlAniPosInvoicePage.enabled)throw StateError('TEST_ONLY');
    return await _db.rpc('alani_pos_invoice_list_test') as List;
  }
  @override
  void initState(){super.initState();_data=_load();}
  void _refresh()=>setState(()=>_data=_load());
  @override
  Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:const Text('الفواتير والمرتجعات — TEST'),actions:[IconButton(onPressed:_refresh,icon:const Icon(Icons.refresh))]),
    body:FutureBuilder<List<dynamic>>(future:_data,builder:(context,snap){
      if(snap.connectionState!=ConnectionState.done)return const Center(child:CircularProgressIndicator());
      if(snap.hasError||!snap.hasData)return Center(child:TextButton(onPressed:_refresh,child:const Text('تعذر التحميل')));
      return ListView(children:[
        for(final raw in snap.data!) _invoiceCard(Map<String,dynamic>.from(raw as Map)),
      ]);
    }));
  Widget _invoiceCard(Map<String,dynamic> i){
    final lines=(i['lines'] as List).map((e)=>Map<String,dynamic>.from(e as Map)).toList();
    final text=['إيصال TEST غير ضريبي','فاتورة: ${i['id']}','${i['created_at']}',for(final l in lines)'${l['name']} × ${l['quantity']} @ ${l['unit_price_iqd']} د.ع — مرتجع: ${l['returned_qty']}','إجمالي أصلي: ${i['total_iqd']} د.ع'].join('\n');
    return Card(child:Column(children:[
      ListTile(title:Text('فاتورة ${i['total_iqd']} د.ع'),subtitle:SelectableText(i['id'].toString()),trailing:IconButton(tooltip:'نسخ الإيصال النصي',onPressed:()=>Clipboard.setData(ClipboardData(text:text)),icon:const Icon(Icons.copy))),
      Wrap(spacing:8,children:[
        TextButton.icon(icon:const Icon(Icons.print),label:const Text('طباعة PDF'),onPressed:()async{
          try{await AlAniPosPdf.printReceipt(i);}catch(_){if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('تعذر إعداد الطباعة. تحقق من الخط والاتصال وخدمة الطباعة.')));}
        }),
        TextButton.icon(icon:const Icon(Icons.picture_as_pdf),label:const Text('مشاركة PDF'),onPressed:()async{
          try{await AlAniPosPdf.shareReceipt(i);}catch(_){if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('تعذر إعداد PDF.')));}
        }),
      ]),
      for(final l in lines) ListTile(title:Text(l['name'].toString()),subtitle:Text('الكمية: ${l['quantity']} • المرتجع: ${l['returned_qty']}'),
        trailing:TextButton(onPressed:(l['quantity'] as num)>(l['returned_qty'] as num)?()async{
          await Navigator.of(context).push<void>(MaterialPageRoute(builder:(_)=>_PosReturnPage(invoice:i['id'] as String,line:l)));
          if(mounted)_refresh();
        }:null,child:const Text('إرجاع'))),
    ]));
  }
}
class _PosReturnPage extends StatefulWidget{
  const _PosReturnPage({required this.invoice,required this.line});
  final String invoice;
  final Map<String,dynamic> line;
  @override
  State<_PosReturnPage> createState()=>_PosReturnPageState();
}
class _PosReturnPageState extends State<_PosReturnPage>{
  final _qty=TextEditingController(text:'1'),_reason=TextEditingController();
  final _key=posRequestKey();
  bool _busy=false,_restock=false,_done=false;
  Map<String,dynamic>? _pending;
  late final String? _actor;
  @override
  void initState(){super.initState();_actor=Supabase.instance.client.auth.currentUser?.id;}
  @override
  void dispose(){_qty.dispose();_reason.dispose();super.dispose();}
  Future<void> _save()async{
    if(_busy||_done||!AlAniPosInvoicePage.enabled||_actor==null||_actor!=Supabase.instance.client.auth.currentUser?.id)return;
    final n=int.tryParse(_qty.text)??0;
    if(n<1||n>(widget.line['quantity'] as num)-(widget.line['returned_qty'] as num)||_reason.text.trim().length<3)return;
    setState(()=>_busy=true);
    try{
      _pending??={'p_key':_key,'p_invoice':widget.invoice,'p_product':widget.line['product_id'],'p_qty':n,'p_restock':_restock,'p_reason':_reason.text.trim()};
      await Supabase.instance.client.rpc('alani_pos_return_line_test',params:_pending);
      if(mounted)setState(()=>_done=true);
    }catch(_){if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('لم تتأكد العملية. أعد نفس المحاولة أو راجع الفاتورة.')));}
    finally{if(mounted)setState(()=>_busy=false);}
  }
  @override
  Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:const Text('تسجيل مرتجع — TEST')),body:ListView(padding:const EdgeInsets.all(16),children:[
    Text(widget.line['name'].toString()),SelectableText(_key),
    TextField(controller:_qty,readOnly:_pending!=null||_busy,keyboardType:TextInputType.number,decoration:const InputDecoration(labelText:'كمية الإرجاع')),
    TextField(controller:_reason,readOnly:_pending!=null||_busy,maxLength:200,decoration:const InputDecoration(labelText:'سبب الإرجاع')),
    SwitchListTile(title:const Text('إعادة المنتج الصالح للمخزون'),subtitle:const Text('لا تفعّل للمنتج التالف'),value:_restock,onChanged:_pending!=null||_busy?null:(v)=>setState(()=>_restock=v)),
    const Text('تسجيل رد مبلغ افتراضي فقط، لا تحويل نقدي.'),
    FilledButton(onPressed:_busy||_done?null:_save,child:Text(_done?'تم تسجيل المرتجع':'تأكيد المرتجع')),
  ]));
}
