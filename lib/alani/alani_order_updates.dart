import 'dart:async';
import 'package:flutter/material.dart';
import 'alani_customer_extras.dart';

class AlAniOrderNotificationsPage extends StatefulWidget {
  const AlAniOrderNotificationsPage({super.key});
  @override
  State<AlAniOrderNotificationsPage> createState() => _AlAniOrderNotificationsPageState();
}

class _AlAniOrderNotificationsPageState extends State<AlAniOrderNotificationsPage> {
  late Future<List<dynamic>> _items;
  bool _busy = false;
  @override
  void initState() { super.initState(); _items = _load(); }
  Future<List<dynamic>> _load() async =>
      (await AlAniCustomerExtras.call('alani_order_notifications_test')) as List;
  void _refresh() => setState(() => _items = _load());
  Future<void> _read(String id) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await AlAniCustomerExtras.call('alani_read_notification_test', {'p_event_id':id});
      if (mounted) _refresh();
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
    appBar:AppBar(title:const Text('إشعارات الطلبات — TEST'),
      actions:[IconButton(onPressed:_busy?null:_refresh,icon:const Icon(Icons.refresh))]),
    body:FutureBuilder<List<dynamic>>(future:_items,builder:(context,snapshot) {
      if (snapshot.connectionState!=ConnectionState.done) return const Center(child:CircularProgressIndicator());
      if (snapshot.hasError) return Center(child:TextButton(onPressed:_refresh,child:const Text('تعذر التحميل، أعد المحاولة')));
      final rows=snapshot.data ?? [];
      if(rows.isEmpty) return const Center(child:Text('لا توجد إشعارات طلبات.'));
      return ListView.builder(itemCount:rows.length,itemBuilder:(context,i) {
        final row=Map<String,dynamic>.from(rows[i] as Map);
        final read=row['is_read']==true;
        return ListTile(
          leading:Icon(read?Icons.notifications_none:Icons.notifications_active),
          title:Text(_label(row['new_status'])),
          subtitle:Text('طلب ${row['order_id']}\n${row['changed_at']}'),
          trailing:read?const Icon(Icons.done):TextButton(
            onPressed:_busy?null:()=>_read(row['event_id'] as String),child:const Text('قراءة')),
        );
      });
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
  Map<String,dynamic>? _location;
  bool _loading=false;
  bool _failed=false;
  bool _active=true;
  int _generation=0;
  @override
  void initState(){
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _start();
  }
  void _start(){
    _active=true;
    _poll();
    _timer?.cancel();
    _timer=Timer.periodic(const Duration(seconds:15),(_)=>_poll());
  }
  Future<void> _poll() async {
    if (!_active || _loading || !mounted) return;
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
  void dispose(){_active=false;_generation++;_timer?.cancel();WidgetsBinding.instance.removeObserver(this);super.dispose();}
  @override
  Widget build(BuildContext context){
    final loc=_location;
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
          Text('وقت التحديث: ${updated?.toLocal()}'),
        ],
        TextButton(onPressed:_loading?null:_poll,child:const Text('تحديث الآن')),
      ]));
  }
}
