import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'alani_customer_extras.dart';
import 'alani_notification_preferences_page.dart';
import 'alani_support_chat.dart';

class AlAniOrderNotificationsPage extends StatefulWidget {
  const AlAniOrderNotificationsPage({super.key});
  @override
  State<AlAniOrderNotificationsPage> createState() => _AlAniOrderNotificationsPageState();
}

class _AlAniOrderNotificationsPageState extends State<AlAniOrderNotificationsPage> {
  late Future<List<dynamic>> _items;
  bool _busy = false;
  late final String? _actor;
  StreamSubscription<dynamic>? _authChanges;
  static const _production=String.fromEnvironment('SUPABASE_URL')=='https://ltwncrewggdrjevakwpb.supabase.co';
  bool _sessionChanged=false;
  Timer? _poller;
  bool _refreshing=false;
  bool get _sameActor=>!_sessionChanged&&_actor!=null&&_actor==AlAniCustomerExtras.db.auth.currentUser?.id;
  @override
  void initState() {
    super.initState();_actor=AlAniCustomerExtras.db.auth.currentUser?.id;_items=_load();
    _authChanges=AlAniCustomerExtras.db.auth.onAuthStateChange.listen((_){
      if(mounted&&!_sameActor){
        _poller?.cancel();
        setState((){_sessionChanged=true;_items=Future.value(<dynamic>[[],[],null]);});
      }
    });
    if(_production)_poller=Timer.periodic(const Duration(seconds:15),(_){
      if(mounted&&_sameActor&&!_busy&&!_refreshing&&WidgetsBinding.instance.lifecycleState==AppLifecycleState.resumed&&ModalRoute.of(context)?.isCurrent==true)_refresh();
    });
  }
  @override
  void dispose(){_poller?.cancel();_authChanges?.cancel();super.dispose();}
  Future<List<dynamic>> _load()async{
    if(!_sameActor)return <dynamic>[[],[],null];
    if(_production){
      _refreshing=true;
      try{
        final db=AlAniCustomerExtras.db;
        final rows=await db.rpc('alani_order_notifications');
        if(!mounted||!_sameActor)return <dynamic>[[],[],null];
        final raw=await db.rpc('alani_my_favorites');
        if(!mounted||!_sameActor)return <dynamic>[[],[],null];
        final alerts=<Map<String,dynamic>>[];
        for(final x in raw as List){
          final item=Map<String,dynamic>.from(x as Map);
          if(item['price_dropped']==true)alerts.add({...item,'kind':'price_drop'});
          if(item['restocked']==true)alerts.add({...item,'kind':'restocked'});
        }
        int? unread;
        if(AlAniSupportFeature.enabled){
          try{
            final counts=await db.rpc('alani_support_unread_counts');
            if(!mounted||!_sameActor)return <dynamic>[[],[],null];
            unread=(counts as List).fold<int>(0,(sum,row)=>sum+((row as Map)['unread_count'] as num).toInt());
          }catch(_){unread=null;}
        }
        return <dynamic>[rows,alerts,unread];
      }finally{_refreshing=false;}
    }
    return Future.wait<dynamic>([
      AlAniCustomerExtras.call('alani_order_notifications_test'),
      AlAniCustomerExtras.call('alani_customer_alerts_test'),
    ]);
  }
  void _refresh(){if(mounted&&_sameActor&&!_refreshing)setState(()=>_items=_load());}
  Future<void> _read(String id) async {
    if (_busy || !_sameActor) return;
    setState(() => _busy = true);
    try {
      if(_production){
        await AlAniCustomerExtras.db.rpc('alani_read_notification',params:{'p_event_id':id});
      }else{
        await AlAniCustomerExtras.call('alani_read_notification_test', {'p_event_id':id});
      }
      if (mounted&&_sameActor) _refresh();
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content:Text('تعذر تسجيل القراءة.')));
    } finally { if (mounted) setState(() => _busy = false); }
  }
  String _label(dynamic status) => switch (status) {
    'placed' => 'طلب جديد',
    'accepted' => 'تم قبول طلبك',
    'preparing' => 'طلبك قيد التجهيز',
    'ready' => 'طلبك جاهز',
    'out_for_delivery' => 'خرج طلبك للتوصيل',
    'delivered' => 'تم تسليم طلبك',
    'cancelled' => 'تم إلغاء الطلب',
    'rejected' => 'تم رفض الطلب',
    _ => 'تحديث الطلب',
  };
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar:AppBar(title:Text(_production?'مركز الإشعارات':'مركز الإشعارات — TEST'),
      actions:[IconButton(onPressed:_busy?null:_refresh,icon:const Icon(Icons.refresh)),IconButton(tooltip:'تفضيلات الإشعارات',onPressed:_sameActor?()=>Navigator.of(context).push<void>(MaterialPageRoute(builder:(_)=>const AlAniNotificationPreferencesPage())):null,icon:const Icon(Icons.settings))]),
    body:FutureBuilder<List<dynamic>>(future:_items,builder:(context,snapshot) {
      if(!_sameActor)return const Center(child:Text('أغلق الصفحة وأعد فتحها بالحساب الحالي.'));
      if (snapshot.connectionState!=ConnectionState.done&&!snapshot.hasData) return const Center(child:CircularProgressIndicator());
      if (snapshot.hasError) return Center(child:TextButton(onPressed:_refresh,child:const Text('تعذر التحميل، أعد المحاولة')));
      if(!_sameActor)return const Center(child:Text('أغلق الصفحة وأعد فتحها بالحساب الحالي.'));
      final data=snapshot.data ?? <dynamic>[[],[]];
      final rows=(data[0] as List).map((e)=>Map<String,dynamic>.from(e as Map));
      final alerts=(data[1] as List).map((e)=>Map<String,dynamic>.from(e as Map));
      return ListView(children:[
        if(_production&&AlAniSupportFeature.enabled)ListTile(
          leading:const Icon(Icons.support_agent),
          title:const Text('رسائل فريق الدعم'),
          subtitle:Text(data.length<3||data[2]==null?'تعذر التحقق من عدد الرسائل': 'غير مقروءة: ${data[2]}'),
          onTap:()async{
            await Navigator.of(context).push<void>(MaterialPageRoute(builder:(_)=>const AlAniCustomerSupportPage()));
            if(mounted&&_sameActor)_refresh();
          }),
        const ListTile(title:Text('تنبيهات المنتجات والاشتراكات'),subtitle:Text('تُحدّث عند فتح الصفحة أو التحديث؛ لا إشعارات دفع خارجية ولا شراء تلقائي.')),
        if(alerts.isEmpty)const ListTile(title:Text('لا توجد تنبيهات جديدة للعرض.')),
        for(final a in alerts)ListTile(
          leading:const Icon(Icons.notifications_outlined),
          title:Text(switch(a['kind']){'price_drop'=>'انخفاض السعر','restocked'=>'عاد المنتج للمخزون','monthly_review'=>'حان موعد مراجعة الاشتراك',_=>'تنبيه'}),
          subtitle:Text(a['name'].toString()+(a['price_iqd']!=null?' • ${a['price_iqd']} د.ع':''))),
        const Divider(),const ListTile(title:Text('إشعارات الطلبات')),
        if(rows.isEmpty)const ListTile(title:Text('لا توجد إشعارات طلبات.')),
        for(final row in rows) ListTile(
          leading:Icon(row['is_read']==true?Icons.notifications_none:Icons.notifications_active),
          title:Text(_label(row['new_status'])),
          subtitle:Text('طلب ${row['order_id']}\n${row['changed_at']}'),
          trailing:row['is_read']==true?const Icon(Icons.done):TextButton(
            onPressed:_busy?null:()=>_read(row['event_id'] as String),child:const Text('قراءة'))),
      ]);
    }),
  );
}

class AlAniTrackingPage extends StatefulWidget {
  const AlAniTrackingPage({super.key,required this.orderId});
  final String orderId;
  @override
  State<AlAniTrackingPage> createState()=>_AlAniTrackingPageState();
}
class _AlAniTrackingPageState extends State<AlAniTrackingPage> with WidgetsBindingObserver {
  Timer? _timer;
  StreamSubscription<dynamic>? _trackingAuth;
  late final String? _trackingActor;
  bool get _trackingSameActor=>_trackingActor!=null&&_trackingActor==AlAniCustomerExtras.db.auth.currentUser?.id;
  Map<String,dynamic>? _location;
  bool _loading=false;
  bool _failed=false;
  bool _active=true;
  int _generation=0;
  bool _showMap=false;
  static const _trackingTileUrl=String.fromEnvironment('ALANI_TRACKING_TEST_TILE_URL');
  bool get _tilesConfigured => _trackingTileUrl.startsWith('https://') && _trackingTileUrl.contains('{z}') && _trackingTileUrl.contains('{x}') && _trackingTileUrl.contains('{y}');
  @override
  void initState(){
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _trackingActor=AlAniCustomerExtras.db.auth.currentUser?.id;
    _trackingAuth=AlAniCustomerExtras.db.auth.onAuthStateChange.listen((_){
      if(mounted&&!_trackingSameActor){_active=false;_generation++;_timer?.cancel();setState((){_location=null;_showMap=false;_loading=false;});}
    });
    _start();
  }
  void _start(){
    if(!_trackingSameActor)return;
    _active=true;
    _poll();
    _timer?.cancel();
    _timer=Timer.periodic(const Duration(seconds:15),(_)=>_poll());
  }
  Future<void> _poll() async {
    if (!_active || _loading || !mounted || !_trackingSameActor) return;
    final generation=_generation;
    final actor=AlAniCustomerExtras.db.auth.currentUser?.id;
    setState(()=>_loading=true);
    try {
      final result=await AlAniCustomerExtras.call('alani_read_location_test',{'p_order_id':widget.orderId}).timeout(const Duration(seconds:10));
      if (!mounted || !_active || generation!=_generation || actor!=AlAniCustomerExtras.db.auth.currentUser?.id) return;
      setState((){_location=result==null?null:Map<String,dynamic>.from(result as Map);_failed=false;});
    } catch (_) {
      if(mounted && generation==_generation) setState((){_location=null;_failed=true;});
    } finally {
      if(mounted && generation==_generation) setState(()=>_loading=false);
    }
  }
  @override
  void didChangeAppLifecycleState(AppLifecycleState state){
    if(state==AppLifecycleState.resumed) {_start();return;}
    _active=false;_generation++;_timer?.cancel();
    if(mounted) setState((){_location=null;_loading=false;});
  }
  @override
  void dispose(){_trackingAuth?.cancel();_active=false;_generation++;_timer?.cancel();WidgetsBinding.instance.removeObserver(this);super.dispose();}
  @override
  Widget build(BuildContext context){
    final loc=_trackingSameActor?_location:null;
    final updated=DateTime.tryParse(loc?['updated_at']?.toString()??'');
    final fresh=updated!=null && DateTime.now().difference(updated).inSeconds<90;
    return Scaffold(appBar:AppBar(title:const Text('موقع المندوب — TEST')),
      body:ListView(padding:const EdgeInsets.all(16),children:[
        const Text('الموقع متاح لصاحب الطلب أثناء التوصيل فقط، عند موافقة المندوب. تحديث كل 15 ثانية.'),
        if(_loading) const LinearProgressIndicator(),
        if(_failed) const Text('تعذر تحديث الموقع. لا يوجد موقع معروض.'),
        if(!_failed && (!fresh || loc==null)) const Text('لا توجد مشاركة موقع حديثة.'),
        if(!_failed && fresh && loc!=null) ...[
          ListTile(leading:const Icon(Icons.location_on),title:const Text('آخر إحداثيات مستلمة'),
            subtitle:Text('${loc['latitude']}, ${loc['longitude']}')),
          Text('الدقة التقريبية: ${loc['accuracy_m']} متر'),
          Text('وقت التحديث: ${updated.toLocal()}'),
          if (_tilesConfigured) ...[
            SwitchListTile(title:const Text('عرض الموقع على الخريطة'),
              subtitle:const Text('مزود الخرائط الخارجي يستقبل طلبات صور المنطقة المعروضة.'),
              value:_showMap,onChanged:(value)=>setState(()=>_showMap=value)),
            if (_showMap)
              SizedBox(height:280,child:FlutterMap(
                key:ValueKey(loc['updated_at']),
                options:MapOptions(
                  initialCenter:ll.LatLng((loc['latitude'] as num).toDouble(),(loc['longitude'] as num).toDouble()),
                  initialZoom:14,minZoom:8,maxZoom:18),
                children:[
                  TileLayer(urlTemplate:_trackingTileUrl,userAgentPackageName:'com.shitreed.shitreed_customer'),
                  MarkerLayer(markers:[Marker(
                    point:ll.LatLng((loc['latitude'] as num).toDouble(),(loc['longitude'] as num).toDouble()),
                    width:44,height:44,child:const Icon(Icons.location_on,color:Colors.green,size:40))]),
                  RichAttributionWidget(attributions:[TextSourceAttribution('© OpenStreetMap contributors')]),
                ],
              )),
          ] else const Text('الخريطة تحتاج مزود صور خرائط معتمداً في TEST.'),
          const Text('وقت الوصول غير متاح دون خدمة مسارات معتمدة.'),

        ],
        TextButton(onPressed:_loading?null:_poll,child:const Text('تحديث الآن')),
      ]));
  }
}
