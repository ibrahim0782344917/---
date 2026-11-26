import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'admin_api.dart';

/// Read-only readiness: a schema or permission is not a completed feature.
/// This page cannot activate payments or modify production settings.
class AlAniReleaseReadinessPage extends StatefulWidget {
  const AlAniReleaseReadinessPage({super.key});
  @override
  State<AlAniReleaseReadinessPage> createState()=>_AlAniReleaseReadinessPageState();
}
class _AlAniReleaseReadinessPageState extends State<AlAniReleaseReadinessPage> {
  late final String? _actor;
  StreamSubscription<AuthState>? _auth;
  bool _changed=false,_loading=true;
  Map<String,dynamic>? _state;
  String? _error;
  bool get _sameActor=>!_changed&&_actor!=null&&AdminApi.client.auth.currentUser?.id==_actor;
  @override
  void initState(){
    super.initState();_actor=AdminApi.client.auth.currentUser?.id;
    _auth=AdminApi.client.auth.onAuthStateChange.listen((_){
      if(mounted&&AdminApi.client.auth.currentUser?.id!=_actor)setState((){
        _changed=true;_state=null;_loading=false;_error=null;
      });
    });
    unawaited(_load());
  }
  @override
  void dispose(){_auth?.cancel();super.dispose();}
  Future<void> _load()async{
    if(!mounted||!_sameActor)return;
    setState((){_state=null;_error=null;_loading=true;});
    try{
      if(await AdminApi.currentRole()!='super_admin')throw StateError('SUPER_ADMIN_REQUIRED');
      if(!mounted||!_sameActor)return;
      final response=await AdminApi.client.rpc('alani_admin_release_readiness');
      if(mounted&&_sameActor)setState(()=>_state=Map<String,dynamic>.from(response as Map));
    }catch(_){if(mounted&&_sameActor)setState(()=>_error='تعذر التحقق من جاهزية الأنظمة.');}
    finally{if(mounted)setState(()=>_loading=false);}
  }
  Widget _row(String label,String key,String positive,String negative){
    final enabled=_state?[key]==true;
    return Card(child:ListTile(
      leading:Icon(enabled?Icons.check_circle_outline:Icons.pending_outlined,
        color:enabled?Theme.of(context).colorScheme.primary:Theme.of(context).colorScheme.onSurfaceVariant),
      title:Text(label),subtitle:Text(enabled?positive:negative),
    ));
  }
  @override
  Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:const Text('جاهزية أنظمة الإنتاج'),
      actions:[IconButton(tooltip:'تحديث',onPressed:_loading?null:_load,icon:const Icon(Icons.refresh))]),
    body:!_sameActor?const Center(child:Text('أعد فتح الصفحة بحساب المدير المعتمد.')):
      _loading?const Center(child:CircularProgressIndicator()):
      _error!=null?Center(child:Text(_error!)):
      _state==null?const Center(child:Text('لم تُسترجع بيانات الجاهزية.')):
      ListView(padding:const EdgeInsets.all(16),children:[
        const Card(child:ListTile(leading:Icon(Icons.info_outline),
          title:Text('فحص مباشر للخادم — قراءة فقط'),
          subtitle:Text('توفر البنية والصلاحيات لا يثبت نجاح تجربة الهاتف، ولا يسمح هذا الفحص بتفعيل أموال أو تغيير طلبات.'))),
        _row('الشراء','checkout_ready','بوابة الشراء جاهزة','بوابة الشراء غير جاهزة'),
        _row('بنية الدردشة','chat_schema','البنية موجودة','البنية غير موجودة'),
        _row('صلاحيات الدردشة','chat_api_enabled','واجهة الدردشة مفتوحة للمخوّلين','واجهة الدردشة مغلقة'),
        _row('استقبال إثباتات التحويل','wallet_intake_enabled','بوابة استقبال الإثباتات مفتوحة','بوابة الاستقبال مغلقة'),
        _row('الرصيد المالي','wallet_credit_enabled','بوابة الرصيد مفتوحة','الرصيد المالي غير مفعّل'),
        _row('جهات اتصال الزبائن القدامى','legacy_schema','البنية الخاصة موجودة؛ لا يثبت الاستيراد','البنية الخاصة غير موجودة'),
        _row('التوصيل','delivery_schema','بنية التوصيل موجودة؛ يلزم اختبار التشغيل','البنية غير موجودة'),
        _row('الاسترجاع','return_schema','بنية الاسترجاع موجودة؛ يلزم اختبار التشغيل','البنية غير موجودة'),
        _row('العروض','campaign_schema','بنية العروض موجودة؛ يلزم اختبار التشغيل','البنية غير موجودة'),
        _row('الكاشير','pos_schema','بنية الكاشير موجودة؛ يلزم اختبار التشغيل','البنية غير موجودة'),
        Card(child:ListTile(title:const Text('مزودو الدفع المتاحون للشحن'),trailing:Text('${_state!['enabled_provider_count']??'—'}'))),
        Card(child:ListTile(title:const Text('الجداول العامة دون RLS'),trailing:Text('${_state!['public_tables_missing_rls']??'—'}'))),
      ]),
  );
}
