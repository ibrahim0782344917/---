import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shitreed_customer/alani/alani_customer_extras.dart';
import 'package:shitreed_customer/alani/alani_checkout_readiness.dart';

class AlAniBundleCheckoutPage extends StatefulWidget {
  const AlAniBundleCheckoutPage({super.key,required this.quote});
  final Map<String,dynamic> quote;
  static const enabled=AlAniCustomerExtras.enabled && AlAniCheckoutReadiness.testMode &&
      bool.fromEnvironment('ALANI_BUNDLE_CHECKOUT_TEST_ENABLED',defaultValue:false);
  @override
  State<AlAniBundleCheckoutPage> createState()=>_AlAniBundleCheckoutPageState();
}
class _AlAniBundleCheckoutPageState extends State<AlAniBundleCheckoutPage>{
  final _address=TextEditingController(),_phone=TextEditingController(),_notes=TextEditingController(),_reference=TextEditingController();
  final _form=GlobalKey<FormState>();
  Map<String,dynamic>? _pending;
  bool _busy=false;
  String? _order;
  late final String? _actor;
  static String _uuid(){
    final r=Random.secure();
    final b=List<int>.generate(16,(_)=>r.nextInt(256));
    b[6]=(b[6]&15)|64;b[8]=(b[8]&63)|128;
    final s=b.map((v)=>v.toRadixString(16).padLeft(2,'0')).join();
    return '${s.substring(0,8)}-${s.substring(8,12)}-${s.substring(12,16)}-${s.substring(16,20)}-${s.substring(20)}';
  }
  @override
  void initState(){super.initState();_actor=AlAniCustomerExtras.db.auth.currentUser?.id;_reference.text=_uuid();}
  @override
  void dispose(){_address.dispose();_phone.dispose();_notes.dispose();_reference.dispose();super.dispose();}
  bool get _allowed=>AlAniBundleCheckoutPage.enabled && _actor!=null && AlAniCustomerExtras.db.auth.currentUser?.id==_actor;
  void _notice(String text){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(text)));}
  Future<void> _submit()async{
    if(_busy||!_allowed||_order!=null)return;
    if(_pending==null){
      if(!_form.currentState!.validate())return;
      final ok=await showDialog<bool>(context:context,builder:(ctx)=>AlertDialog(title:const Text('تأكيد طلب TEST'),
        content:Text('المجموع: ${widget.quote['total_iqd']} د.ع، الدفع عند الاستلام تجريبي فقط. احتفظ برقم المحاولة قبل الإرسال.'),
        actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('إلغاء')),FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('تأكيد'))]));
      if(ok!=true||!mounted||!_allowed||_busy)return;
      _pending={'p_bundle_id':widget.quote['bundle_id'],'p_request_key':_reference.text.trim(),
        'p_expected_total_iqd':(widget.quote['total_iqd'] as num).toInt(),'p_address':_address.text.trim(),'p_phone':_phone.text.trim(),'p_notes':_notes.text.trim()};
    }
    setState(()=>_busy=true);
    try{
      if(!await AlAniCheckoutReadiness.checkServer()||!_allowed)throw StateError('TEST_NOT_READY');
      final id=await AlAniCustomerExtras.call('alani_place_bundle_test',_pending);
      if(mounted&&_allowed)setState(()=>_order=id.toString());
    }catch(_){_notice('لم تتأكد النتيجة. افحص رقم المحاولة أو أعد المحاولة بنفس البيانات والرقم. لا تنشئ طلباً جديداً للتكرار.');}
    finally{if(mounted)setState(()=>_busy=false);}
  }
  Future<void> _lookup()async{
    if(_busy||!_allowed||!RegExp(r'^[0-9a-fA-F-]{36}$').hasMatch(_reference.text.trim()))return;
    setState(()=>_busy=true);
    try{
      final id=await AlAniCustomerExtras.call('alani_bundle_order_lookup_test',{'p_key':_reference.text.trim()});
      if(mounted&&_allowed){if(id!=null)setState(()=>_order=id.toString());else _notice('لا يوجد طلب مؤكد بهذا الرقم حالياً.');}
    }catch(_){_notice('تعذر التحقق من الطلب.');}
    finally{if(mounted)setState(()=>_busy=false);}
  }
  @override
  Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:const Text('شراء الباقة — TEST')),
    body:Form(key:_form,child:ListView(padding:const EdgeInsets.all(16),children:[
      Text(widget.quote['title'].toString(),style:const TextStyle(fontSize:20,fontWeight:FontWeight.bold)),
      Text('التوصيل: ${widget.quote['delivery_fee_iqd']} د.ع • الإجمالي: ${widget.quote['total_iqd']} د.ع'),
      const Text('طلب في قاعدة الاختبار فقط. لا دفع حقيقي. انسخ رقم المحاولة واحتفظ به للبحث بعد انقطاع الاتصال.'),
      TextFormField(controller:_reference,readOnly:_pending!=null||_busy||_order!=null,decoration:const InputDecoration(labelText:'رقم المحاولة'),validator:(v)=>RegExp(r'^[0-9a-fA-F-]{36}$').hasMatch(v??'')?null:'رقم غير صالح'),
      TextButton.icon(onPressed:()=>Clipboard.setData(ClipboardData(text:_reference.text)),icon:const Icon(Icons.copy),label:const Text('نسخ رقم المحاولة')),
      TextButton(onPressed:_busy?null:_lookup,child:const Text('التحقق من طلب سابق بهذا الرقم')),
      if(_order!=null) SelectableText('تم تسجيل الطلب في TEST: $_order')
      else ...[
        TextFormField(controller:_address,readOnly:_pending!=null||_busy,decoration:const InputDecoration(labelText:'عنوان التوصيل'),validator:(v)=>(v?.trim().length??0)>=8&&(v?.trim().length??0)<=300?null:'العنوان 8–300 حرف'),
        TextFormField(controller:_phone,readOnly:_pending!=null||_busy,keyboardType:TextInputType.phone,decoration:const InputDecoration(labelText:'هاتف التوصيل'),validator:(v)=>(v?.trim().length??0)>=8&&(v?.trim().length??0)<=25?null:'الهاتف 8–25 حرف'),
        TextFormField(controller:_notes,readOnly:_pending!=null||_busy,maxLength:400,decoration:const InputDecoration(labelText:'ملاحظات')),
        FilledButton(onPressed:_busy||!_allowed?null:_submit,child:Text(_pending==null?'تأكيد شراء تجريبي':'إعادة المحاولة نفسها')),
      ],
      if(_busy)const LinearProgressIndicator(),
    ])));
}
