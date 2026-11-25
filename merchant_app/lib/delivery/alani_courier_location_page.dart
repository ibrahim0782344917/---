import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Consent-based, foreground-only sharing. No background service or history.
class AlAniCourierLocationPage extends StatefulWidget {
  const AlAniCourierLocationPage({super.key,required this.orderId});
  final String orderId;
  static const enabled =
      bool.fromEnvironment('ALANI_COURIER_GPS_TEST_ENABLED',defaultValue:false) &&
      String.fromEnvironment('SUPABASE_URL')=='https://tgvdwotbrnhcoykuxdpr.supabase.co';
  @override
  State<AlAniCourierLocationPage> createState()=>_AlAniCourierLocationPageState();
}
class _AlAniCourierLocationPageState extends State<AlAniCourierLocationPage> with WidgetsBindingObserver {
  Timer? _timer;
  Future<void>? _pending;
  bool _sharing=false;
  bool _starting=false;
  bool _stopping=false;
  String? _actor;
  String _message='المشاركة متوقفة.';
  SupabaseClient get _db=>Supabase.instance.client;
  @override
  void initState(){super.initState();WidgetsBinding.instance.addObserver(this);}
  bool get _foreground=>WidgetsBinding.instance.lifecycleState==AppLifecycleState.resumed;
  Future<void> _start() async {
    if(!AlAniCourierLocationPage.enabled || _sharing || _starting || _stopping)return;
    setState(()=>_starting=true);
    try{
      final consent=await showDialog<bool>(context:context,builder:(ctx)=>AlertDialog(
        title:const Text('مشاركة موقع التوصيل'),
        content:const Text('سيُرسل موقعك الحالي لصاحب هذا الطلب فقط أثناء التوصيل، كل 15 ثانية ما دامت هذه الشاشة مفتوحة. تستطيع إيقاف المشاركة في أي وقت. لا تعمل في الخلفية.'),
        actions:[
          TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('رفض')),
          FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('أوافق')),
        ],
      ));
      if(consent!=true || !mounted)return;
      if(!await Geolocator.isLocationServiceEnabled())throw StateError('GPS_DISABLED');
      var permission=await Geolocator.checkPermission();
      if(permission==LocationPermission.denied)permission=await Geolocator.requestPermission();
      if(permission!=LocationPermission.whileInUse && permission!=LocationPermission.always)throw StateError('GPS_PERMISSION');
      if(!mounted || !_foreground)return;
      _actor=_db.auth.currentUser?.id;
      if(_actor==null)throw StateError('LOGIN_REQUIRED');
      setState((){_sharing=true;_message='جاري الحصول على الموقع…';});
      _tick();
      _timer=Timer.periodic(const Duration(seconds:15),(_)=>_tick());
    }catch(_){if(mounted)setState(()=>_message='تعذر تشغيل الموقع. تحقق من الصلاحية وخدمة الموقع.');}
    finally{if(mounted)setState(()=>_starting=false);}
  }
  void _tick(){
    if(!_sharing || !_foreground || _pending!=null || !mounted)return;
    _pending=_send().whenComplete(()=>_pending=null);
  }
  Future<void> _send() async {
    try{
      final pos=await Geolocator.getCurrentPosition(locationSettings:const LocationSettings(
        accuracy:LocationAccuracy.high,timeLimit:Duration(seconds:12)));
      if(!_sharing || !_foreground || !mounted || _db.auth.currentUser?.id!=_actor)return;
      final result=await _db.rpc('alani_publish_location_test',params:{
        'p_order_id':widget.orderId,'p_lat':pos.latitude,'p_lon':pos.longitude,
        'p_accuracy_m':pos.accuracy,'p_consent':true,
      });
      if(mounted && _sharing)setState(()=>_message=result=='published'?'تم تحديث الموقع.':'بانتظار تحديث الموقع.');
    }catch(_){
      if(mounted && _sharing)setState(()=>_message='تعذر تحديث الموقع. يمكن إيقاف المشاركة وإعادة المحاولة.');
    }
  }
  Future<void> _stop({bool disposing=false}) async {
    if(!_sharing || _stopping)return;
    _sharing=false;_stopping=true;_timer?.cancel();_timer=null;
    if(!disposing && mounted)setState(()=>_message='جاري إيقاف المشاركة…');
    try{
      await _pending;
      if(_actor!=null && _db.auth.currentUser?.id==_actor){
        await _db.rpc('alani_publish_location_test',params:{
          'p_order_id':widget.orderId,'p_lat':null,'p_lon':null,'p_accuracy_m':null,'p_consent':false,
        });
      }
      _message='المشاركة متوقفة.';
    }catch(_){_message='توقف الإرسال؛ الموقع السابق ينتهي خلال 90 ثانية إذا تعذر حذفه فوراً.';}
    finally{_stopping=false;_actor=null;if(!disposing && mounted)setState((){});}
  }
  @override
  void didChangeAppLifecycleState(AppLifecycleState state){
    if(state!=AppLifecycleState.resumed && _sharing)unawaited(_stop());
  }
  @override
  void dispose(){
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    if(_sharing)unawaited(_stop(disposing:true));
    super.dispose();
  }
  @override
  Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:const Text('مشاركة موقع التوصيل — TEST')),
    body:ListView(padding:const EdgeInsets.all(20),children:[
      const Text('مشاركة اختيارية لصاحب الطلب فقط. لا يتم حفظ سجل مسار، ويُحجب الموقع بعد انتهاء التوصيل.'),
      const SizedBox(height:16),Text(_message),
      if(_sharing) FilledButton(onPressed:()=>_stop(),child:const Text('إيقاف المشاركة'))
      else FilledButton(onPressed:!AlAniCourierLocationPage.enabled || _starting || _stopping?null:_start,child:const Text('مشاركة موقعي')),
    ]));
}
