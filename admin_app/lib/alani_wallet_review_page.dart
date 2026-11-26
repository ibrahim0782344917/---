import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'admin_api.dart';

/// Only the server-authorized super admin may list submitted proofs.
/// No action here credits funds or approves a transfer as settled.
class AlAniWalletReviewPage extends StatefulWidget {
  const AlAniWalletReviewPage({super.key});
  @override
  State<AlAniWalletReviewPage> createState()=>_AlAniWalletReviewPageState();
}
class _AlAniWalletReviewPageState extends State<AlAniWalletReviewPage> {
  final db=Supabase.instance.client;
  late final String? actor;
  StreamSubscription<AuthState>? subscription;
  bool loading=true,working=false,sessionChanged=false;
  String? error;
  List<Map<String,dynamic>> rows=[];
  bool get sameActor=>!sessionChanged&&actor!=null&&actor==db.auth.currentUser?.id;
  @override
  void initState(){
    super.initState();
    actor=db.auth.currentUser?.id;
    subscription=db.auth.onAuthStateChange.listen((_){
      if(mounted&&db.auth.currentUser?.id!=actor){
        setState((){sessionChanged=true;rows=[];error='تغيّر الحساب. أعد فتح الصفحة.';});
      }
    });
    unawaited(load());
  }
  @override
  void dispose(){subscription?.cancel();super.dispose();}
  Future<void> load()async{
    if(!mounted||!sameActor)return;
    setState((){loading=true;error=null;});
    try{
      if(await AdminApi.currentRole()!='super_admin')throw StateError('SUPER_ADMIN_REQUIRED');
      if(!mounted||!sameActor)return;
      final raw=await db.rpc('alani_wallet_admin_requests');
      if(mounted&&sameActor)setState(()=>rows=(raw as List).map((r)=>Map<String,dynamic>.from(r as Map)).toList());
    }catch(_){if(mounted)setState((){rows=[];error='تعذر الوصول إلى إثباتات التحويل. تحقق من الصلاحية والاتصال.';});}
    finally{if(mounted)setState(()=>loading=false);}
  }
  Future<void> preview(Map<String,dynamic> row)async{
    if(working||!sameActor)return;
    final path=row['proof_object_path']?.toString()??'';
    if(!path.endsWith('.jpg')&&!path.endsWith('.png')){
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('معاينة PDF غير متاحة في هذا الإصدار.')));
      return;
    }
    setState(()=>working=true);
    try{
      if(await AdminApi.currentRole()!='super_admin')throw StateError('SUPER_ADMIN_REQUIRED');
      if(!sameActor||!mounted)return;
      final Uint8List bytes=await db.storage.from('alani-wallet-proof-private').download(path);
      if(!sameActor||!mounted)return;
      if(bytes.isEmpty||bytes.length>5242880)throw StateError('INVALID_PROOF');
      await showDialog<void>(context:context,builder:(context)=>AlertDialog(
        title:const Text('معاينة إثبات خاص'),
        content:SizedBox(width:360,child:SingleChildScrollView(child:Image.memory(bytes,errorBuilder:(context,error,stackTrace)=>const Text('تعذرت معاينة الصورة.')))),
        actions:[TextButton(onPressed:()=>Navigator.pop(context),child:const Text('إغلاق'))]));
    }catch(_){if(mounted&&sameActor)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('المعاينة غير متاحة أو ليست لديك صلاحية قراءة الملف.')));}
    finally{if(mounted)setState(()=>working=false);}
  }
  Future<void> review(Map<String,dynamic> row,String decision)async{
    if(working||!sameActor)return;
    String reason='';
    final ok=await showDialog<bool>(context:context,builder:(context)=>AlertDialog(
      title:const Text('تسجيل قرار المراجعة'),
      content:Column(mainAxisSize:MainAxisSize.min,children:[
        const Text('هذا القرار لا يؤكد وصول الأموال ولا يضيف رصيداً.'),
        TextField(maxLength:1000,minLines:2,maxLines:4,onChanged:(v)=>reason=v,decoration:const InputDecoration(labelText:'السبب (12 حرفاً على الأقل)')),
      ]),
      actions:[TextButton(onPressed:()=>Navigator.pop(context,false),child:const Text('إلغاء')),
        FilledButton(onPressed:()=>Navigator.pop(context,true),child:const Text('تسجيل'))]));
    if(ok!=true||!mounted||!sameActor||working)return;
    if(reason.trim().length<12){ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('اكتب سبباً واضحاً للمراجعة.')));return;}
    setState(()=>working=true);
    try{
      if(await AdminApi.currentRole()!='super_admin')throw StateError('SUPER_ADMIN_REQUIRED');
      if(!mounted||!sameActor)return;
      await db.rpc('alani_wallet_admin_review',params:{'p_id':row['id'],'p_decision':decision,'p_reason':reason.trim()});
      if(mounted&&sameActor)await load();
    }catch(_){if(mounted&&sameActor)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('لم يسجل القرار؛ تحقق من تفعيل صلاحية المراجعة.')));}
    finally{if(mounted)setState(()=>working=false);}
  }
  String label(dynamic s)=>switch(s){
    'submitted'=>'بانتظار المراجعة','under_review'=>'قيد المراجعة','needs_information'=>'معلومات إضافية','rejected'=>'مرفوض','externally_verified'=>'تحويل مؤكد خارجياً، ليس رصيداً',_=>'غير معروف'};
  @override
  Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:const Text('مراجعة إثباتات التحويل'),actions:[IconButton(onPressed:working?null:load,tooltip:'تحديث',icon:const Icon(Icons.refresh))]),
    body:!sameActor?const Center(child:Text('الجلسة غير متاحة.')):ListView(padding:const EdgeInsets.all(16),children:[
      Card(child:ListTile(leading:const Icon(Icons.shield_outlined),title:const Text('إثبات التحويل لا يساوي رصيداً'),
        subtitle:const Text('التحقق من وصول الأموال لدى الجهة المعتمدة مستقل عن مراجعة الإيصال. إصدار الرصيد المالي مغلق.'))),
      if(loading||working)const LinearProgressIndicator(),
      if(error!=null)ListTile(title:Text(error!)),
      if(!loading&&error==null&&rows.isEmpty)const ListTile(title:Text('لا توجد إثباتات تحويل مرسلة.')),
      for(final row in rows)Card(child:Padding(padding:const EdgeInsets.all(16),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Text('${row['amount_iqd']} د.ع',style:Theme.of(context).textTheme.titleLarge),
        Text(label(row['status'])),Text('الجهة: ${row['provider_code']}'),
        Text('مرجع معلن: ${row['declared_reference']}'),Text('تاريخ الإرسال: ${row['submitted_at']}'),
        const SizedBox(height:10),
        OutlinedButton.icon(onPressed:working?null:()=>preview(row),icon:const Icon(Icons.visibility_outlined),label:const Text('معاينة الإثبات')),
        if(row['status']!='rejected'&&row['status']!='externally_verified')Wrap(spacing:8,runSpacing:8,children:[
          OutlinedButton(onPressed:working?null:()=>review(row,'under_review'),child:const Text('قيد المراجعة')),
          OutlinedButton(onPressed:working?null:()=>review(row,'needs_information'),child:const Text('طلب معلومات')),
          OutlinedButton(onPressed:working?null:()=>review(row,'rejected'),child:const Text('رفض')),
        ]),
      ]))),
    ]));
}
