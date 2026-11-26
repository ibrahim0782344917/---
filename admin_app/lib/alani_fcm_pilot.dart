import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// FCM device diagnostics only. No account-targeted sending or private payloads.
@pragma('vm:entry-point')
Future<void> alaniFirebaseBackground(RemoteMessage message) async {
  if(Firebase.apps.isEmpty) await Firebase.initializeApp();
  // Android handles notification payload display. Never trust data payloads
  // to change an order, balance, account or navigate to unauthorized content.
}

abstract final class AlAniFcmPilot {
  static const configured=bool.fromEnvironment('ALANI_FCM_CLIENT_ENABLED',defaultValue:false)
    && String.fromEnvironment('SUPABASE_URL')=='https://tgvdwotbrnhcoykuxdpr.supabase.co';
  static bool ready=false;
  static Future<void> initialize()async{
    if(!configured||kIsWeb||defaultTargetPlatform!=TargetPlatform.android)return;
    try{
      final app=await Firebase.initializeApp().timeout(const Duration(seconds:8));
      if(app.options.projectId!='alani-store-e3dc9')return;
      FirebaseMessaging.onBackgroundMessage(alaniFirebaseBackground);
      ready=true;
    }catch(_){ready=false;}
  }
}

class AlAniFcmSettingsPage extends StatefulWidget {
  const AlAniFcmSettingsPage({super.key});
  @override
  State<AlAniFcmSettingsPage> createState()=>_AlAniFcmSettingsPageState();
}
class _AlAniFcmSettingsPageState extends State<AlAniFcmSettingsPage>{
  bool busy=false;
  String? _token;
  String? _challengeId;
  static const _kind='admin';
  String _status='لم يُطلب إذن الإشعارات في هذه الصفحة.';
  StreamSubscription<RemoteMessage>? _messages;
  StreamSubscription<String>? _refresh;
  @override
  void initState(){
    super.initState();
    if(!AlAniFcmPilot.ready)return;
    _messages=FirebaseMessaging.onMessage.listen((message) async {
      if(message.data['kind']=='device_challenge'){
        final id=message.data['challenge_id'];
        final nonce=message.data['nonce'];
        if(id is! String || nonce is! String || id!=_challengeId) return;
        try{
          final result=await Supabase.instance.client.rpc('alani_fcm_confirm_device_test',
            params:{'p_id':id,'p_nonce':nonce});
          if(mounted && _challengeId==id)setState((){
            if(result==true)_challengeId=null;
            _status=result==true?'تم توثيق الجهاز لهذا الحساب.':'تعذر التحقق من الجهاز.';
          });
        }catch(_){if(mounted)setState(()=>_status='تعذر توثيق الجهاز.');}
        return;
      }
      if(mounted)setState(()=>_status='استُقبل إشعار في التطبيق المفتوح.');
    });
    _refresh=FirebaseMessaging.instance.onTokenRefresh.listen((token){
      if(mounted&&_token!=null)setState(()=>_token=token);
    });
  }
  @override
  void dispose(){_messages?.cancel();_refresh?.cancel();_token=null;super.dispose();}
  Future<void> _enable()async{
    if(busy||!AlAniFcmPilot.ready)return;
    setState(()=>busy=true);
    try{
      final fcm=FirebaseMessaging.instance;
      final settings=await fcm.requestPermission(alert:true,badge:true,sound:true);
      if(settings.authorizationStatus!=AuthorizationStatus.authorized&&
        settings.authorizationStatus!=AuthorizationStatus.provisional){
        await fcm.setAutoInitEnabled(false);
        await fcm.deleteToken();
        if(mounted)setState((){_token=null;_status='لم يُمنح إذن الإشعارات.';});
        return;
      }
      // User explicitly opted into a device-only test, not customer messaging.
      await fcm.setAutoInitEnabled(true);
      final token=await fcm.getToken().timeout(const Duration(seconds:15));
      if(mounted)setState((){_token=token;_status=token==null?'لم يصل رمز الجهاز بعد.':'رمز الجهاز جاهز لاختبار Firebase من اللوحة الخاصة.';});
    }catch(_){
      if(mounted)setState((){_token=null;_status='تعذر تأكيد التسجيل؛ تحقق من الاتصال وإعدادات Firebase.';});
    }finally{if(mounted)setState(()=>busy=false);}
  }
  Future<void> _requestRegistration() async {
    if(busy || _token==null || !AlAniFcmPilot.ready)return;
    setState(()=>busy=true);
    try{
      final db=Supabase.instance.client;
      if(db.auth.currentUser==null)throw StateError('Login required');
      final id=await db.rpc('alani_fcm_request_device_test',
        params:{'p_kind':_kind,'p_token':_token});
      if(mounted)setState((){
        _challengeId=id.toString();
        _status='طلب التسجيل قيد التحقق. أبق هذه الصفحة مفتوحة؛ إرسال رمز التحقق يحتاج خادم TEST مفعلاً.';
      });
    }catch(_){if(mounted)setState(()=>_status='التسجيل غير متاح. يلزم حساب اختباري مصرح له.');}
    finally{if(mounted)setState(()=>busy=false);}
  }
  Future<void> _disable()async{
    if(busy||!AlAniFcmPilot.ready)return;
    setState(()=>busy=true);
    try{
      final fcm=FirebaseMessaging.instance;
      if(Supabase.instance.client.auth.currentUser!=null){
        await Supabase.instance.client.rpc('alani_fcm_revoke_device_test',params:{'p_kind':_kind});
      }
      await fcm.setAutoInitEnabled(false);
      await fcm.deleteToken();
      if(mounted)setState((){_token=null;_challengeId=null;_status='تم إلغاء رمز تسجيل الجهاز.';});
    }catch(_){if(mounted)setState(()=>_status='لم نتأكد من إلغاء التسجيل. أوقف إذن الإشعارات من إعدادات Android وأعد المحاولة.');}
    finally{if(mounted)setState(()=>busy=false);}
  }
  @override
  Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:const Text('إشعارات Firebase')),
    body:ListView(padding:const EdgeInsets.all(16),children:[
      Card(child:ListTile(
        leading:const Icon(Icons.notifications_outlined),
        title:Text(AlAniFcmPilot.ready?'إعداد Firebase موجود':'Firebase غير مفعّل في هذه النسخة'),
        subtitle:const Text('اختبار خاص على TEST. التسجيل يحتاج حساباً مصرحاً وإثبات ملكية الجهاز؛ الإرسال التلقائي غير مفعّل.'))),
      Text(_status),
      if(busy)const LinearProgressIndicator(),
      if(AlAniFcmPilot.ready)...[
        FilledButton(onPressed:busy?null:_enable,child:const Text('السماح بالإشعارات وتجهيز رمز الاختبار')),
        if(_token!=null) FilledButton.tonal(
          onPressed:busy?null:_requestRegistration,child:const Text('طلب ربط الجهاز بحسابي — TEST')),
        if(_token!=null)OutlinedButton.icon(
          onPressed:busy?null:()async{
            final token=_token;
            if(token==null)return;
            await Clipboard.setData(ClipboardData(text:token));
            if(context.mounted)ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content:Text('انسخ الرمز فقط إلى لوحة Firebase الخاصة بك. لا تنشره.')));
          },icon:const Icon(Icons.copy),label:const Text('نسخ رمز الجهاز للاختبار')),
        OutlinedButton(onPressed:busy?null:_disable,child:const Text('إلغاء تسجيل الجهاز')),
      ],
    ]));
}
