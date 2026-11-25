import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// An individual operation with a visible retry key. No automatic payments.
class AlAniBusinessEntryPage extends StatefulWidget {
  const AlAniBusinessEntryPage({super.key,required this.mode});
  final String mode;
  @override
  State<AlAniBusinessEntryPage> createState()=>_AlAniBusinessEntryPageState();
}
class _AlAniBusinessEntryPageState extends State<AlAniBusinessEntryPage>{
  final _key=TextEditingController(),_a=TextEditingController(),_b=TextEditingController();
  final _form=GlobalKey<FormState>();
  bool _credit=false,_busy=false,_done=false;
  String? _supplier,_product,_purchase;
  late final String? _actor;
  late Future<List<dynamic>> _data;
  Map<String,dynamic>? _pending;
  String? _rpc;
  SupabaseClient get _db=>Supabase.instance.client;
  bool get _allowed=>const bool.fromEnvironment('ALANI_BUSINESS_TEST_ENABLED') &&
      const String.fromEnvironment('SUPABASE_URL')=='https://tgvdwotbrnhcoykuxdpr.supabase.co' &&
      _actor!=null && _db.auth.currentUser?.id==_actor;
  bool get _locked=>_busy||_pending!=null||_done;
  String _uuid(){
    final r=Random.secure();final b=List<int>.generate(16,(_)=>r.nextInt(256));
    b[6]=(b[6]&15)|64;b[8]=(b[8]&63)|128;
    final s=b.map((v)=>v.toRadixString(16).padLeft(2,'0')).join();
    return '${s.substring(0,8)}-${s.substring(8,12)}-${s.substring(12,16)}-${s.substring(16,20)}-${s.substring(20)}';
  }
  @override
  void initState(){super.initState();_actor=_db.auth.currentUser?.id;_key.text=_uuid();_data=_load();}
  @override
  void dispose(){_key.dispose();_a.dispose();_b.dispose();super.dispose();}
  Future<List<dynamic>> _load()async{
    if(!_allowed)throw StateError('TEST_ONLY');
    return Future.wait<dynamic>([
      _db.rpc('alani_business_report_test'),
      _db.rpc('alani_inventory_report_test',params:{'p_barcode':null}),
      _db.rpc('alani_debt_report_test'),
    ]);
  }
  void _notice(String s){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(s)));}
  int _int(TextEditingController c)=>int.tryParse(c.text.trim())??-1;
  Future<void> _submit()async{
    if(_busy||_done||!_allowed)return;
    setState(()=>_busy=true);
    try{
      if(_pending==null){
        if(!_form.currentState!.validate())return;
        final key=_key.text.trim();
        Map<String,dynamic> args;
        String rpc,summary;
        switch(widget.mode){
          case 'supplier':
            rpc='alani_save_supplier_key_test';args={'p_key':key,'p_name':_a.text.trim()};summary='إضافة مورد: ${_a.text.trim()}';break;
          case 'purchase':
            if(_supplier==null||_product==null||_int(_a)<1||_int(_b)<1)throw StateError('INVALID_INPUT');
            rpc='alani_receive_purchase_test';args={'p_key':key,'p_supplier':_supplier,'p_product':_product,'p_qty':_int(_a),'p_cost':_int(_b),'p_credit':_credit};
            summary='استلام ${_int(_a)} وحدة، الإجمالي ${_int(_a)*_int(_b)} د.ع. ${_credit?"آجل":"غير آجل"}';break;
          case 'pos':
            final q=Map<String,dynamic>.from(await _db.rpc('alani_pos_quote_test',params:{'p_barcode':_a.text.trim(),'p_qty':_int(_b)}) as Map);
            rpc='alani_pos_sale_test';args={'p_key':key,'p_barcode':_a.text.trim(),'p_qty':_int(_b),'p_expected_total':q['total_iqd']};
            summary='بيع ${q['name']} × ${q['quantity']}، المجموع ${q['total_iqd']} د.ع';break;
          case 'debt':
            if(_purchase==null||_int(_a)<1)throw StateError('INVALID_INPUT');
            rpc='alani_record_debt_payment_test';args={'p_key':key,'p_purchase':_purchase,'p_amount':_int(_a)};
            summary='تسجيل سداد دين ${_int(_a)} د.ع (محاكاة)';break;
          case 'expense':
            rpc='alani_record_expense_test';args={'p_key':key,'p_description':_a.text.trim(),'p_amount':_int(_b)};
            summary='مصروف ${_a.text.trim()} بقيمة ${_int(_b)} د.ع';break;
          default:throw StateError('INVALID_MODE');
        }
        if(!mounted||!_allowed)return;
        final ok=await showDialog<bool>(context:context,builder:(ctx)=>AlertDialog(
          title:const Text('تأكيد عملية TEST'),content:Text('$summary\nلا تحويل أموال. احتفظ برقم العملية.'),
          actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('إلغاء')),FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('تأكيد'))]));
        if(ok!=true||!mounted||!_allowed)return;
        _rpc=rpc;_pending=args;
      }
      final result=await _db.rpc(_rpc!,params:_pending);
      if(mounted&&_allowed)setState(()=>_done=true);
      _notice('حفظت العملية في TEST: $result');
    }catch(_){_notice(_pending==null?'تحقق من البيانات والصلاحية والمخزون.':'النتيجة غير مؤكدة. أعد المحاولة بنفس الرقم والبيانات، أو راجع التقرير.');}
    finally{if(mounted)setState(()=>_busy=false);}
  }
  Widget _field(TextEditingController c,String label,{bool numeric=false})=>TextFormField(controller:c,readOnly:_locked,
    keyboardType:numeric?TextInputType.number:TextInputType.text,decoration:InputDecoration(labelText:label),
    validator:(v)=>v==null||v.trim().isEmpty||(numeric&&(int.tryParse(v.trim())??-1)<1)?'قيمة غير صالحة':null);
  Widget _select(String label,String? selected,List<DropdownMenuItem<String>> items,ValueChanged<String?> change)=>DropdownButtonFormField<String>(
    initialValue:selected,items:items,onChanged:_locked?null:change,decoration:InputDecoration(labelText:label),isExpanded:true,
    validator:(v)=>v==null?'اختر قيمة':null);
  @override
  Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:const Text('إدخال عملية — TEST')),
    body:FutureBuilder<List<dynamic>>(future:_data,builder:(context,snapshot){
      if(snapshot.connectionState!=ConnectionState.done)return const Center(child:CircularProgressIndicator());
      if(snapshot.hasError||!snapshot.hasData)return const Center(child:Text('تعذر تحميل بيانات العمليات.'));
      final report=Map<String,dynamic>.from(snapshot.data![0] as Map);
      final products=(snapshot.data![1] as List).map((e)=>Map<String,dynamic>.from(e as Map)).toList();
      final debt=Map<String,dynamic>.from(snapshot.data![2] as Map);
      final suppliers=(report['suppliers'] as List).map((e)=>Map<String,dynamic>.from(e as Map)).where((e)=>e['active']==true);
      final purchases=(debt['items'] as List).map((e)=>Map<String,dynamic>.from(e as Map)).where((e)=>(e['balance_iqd'] as num)>0);
      return Form(key:_form,child:ListView(padding:const EdgeInsets.all(16),children:[
        const Text('عمليات اختبار فقط. انسخ رقم العملية قبل التأكيد. لا تغيره عند إعادة المحاولة.'),
        TextFormField(controller:_key,readOnly:_locked,decoration:const InputDecoration(labelText:'رقم العملية'),
          validator:(v)=>RegExp(r'^[0-9a-fA-F-]{36}$').hasMatch(v??'')?null:'رقم غير صالح'),
        TextButton.icon(onPressed:()=>Clipboard.setData(ClipboardData(text:_key.text)),icon:const Icon(Icons.copy),label:const Text('نسخ رقم العملية')),
        if(widget.mode=='supplier')_field(_a,'اسم المورد'),
        if(widget.mode=='purchase')...[
          _select('المورد',_supplier,[for(final s in suppliers)DropdownMenuItem(value:s['id'] as String,child:Text(s['name'].toString()))],(v)=>setState(()=>_supplier=v)),
          _select('المنتج',_product,[for(final p in products)DropdownMenuItem(value:p['id'] as String,child:Text(p['name'].toString()))],(v)=>setState(()=>_product=v)),
          _field(_a,'الكمية',numeric:true),_field(_b,'تكلفة الوحدة بالدينار',numeric:true),
          SwitchListTile(title:const Text('شراء آجل'),value:_credit,onChanged:_locked?null:(v)=>setState(()=>_credit=v)),
        ],
        if(widget.mode=='pos')...[_field(_a,'رقم الباركود'),_field(_b,'الكمية',numeric:true)],
        if(widget.mode=='expense')...[_field(_a,'وصف المصروف'),_field(_b,'المبلغ بالدينار',numeric:true)],
        if(widget.mode=='debt')...[
          _select('المشتريات الآجلة',_purchase,[for(final p in purchases)DropdownMenuItem(value:p['purchase_key'] as String,child:Text('${p['supplier']} — ${p['balance_iqd']} د.ع'))],(v)=>setState(()=>_purchase=v)),
          _field(_a,'مبلغ السداد بالدينار',numeric:true),
        ],
        if(_done)const Text('تم حفظ العملية. ارجع للتقرير لتحديث الأرقام.')
        else FilledButton(onPressed:_busy||!_allowed?null:_submit,child:Text(_pending==null?'مراجعة وتأكيد':'إعادة المحاولة نفسها')),
        if(_busy)const LinearProgressIndicator(),
      ]));
    }));
}
