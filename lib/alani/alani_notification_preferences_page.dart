import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'alani_customer_extras.dart';

class AlAniNotificationPreferencesPage extends StatefulWidget {
  const AlAniNotificationPreferencesPage({super.key});
  @override
  State<AlAniNotificationPreferencesPage> createState()=>_AlAniNotificationPreferencesPageState();
}
class _AlAniNotificationPreferencesPageState extends State<AlAniNotificationPreferencesPage>{
  late final String? _actor;
  StreamSubscription<AuthState>? _auth;
  bool _changed=false;
  static const _production=String.fromEnvironment('SUPABASE_URL')=='https://ltwncrewggdrjevakwpb.supabase.co';
  String get _table=>_production?'alani_notification_preferences':'alani_notification_preferences_test';
  final _prefs=<String,bool>{'order_updates':false,'favorite_updates':false,'monthly_reviews':false,if(_production)'support_updates':false};
  bool _loading=true,_busy=false,_failed=false;
  bool get _allowed=>!_changed&&(_production||AlAniCustomerExtras.enabled)&&_actor!=null&&_actor==AlAniCustomerExtras.db.auth.currentUser?.id;
  @override
  void initState(){
    super.initState();_actor=AlAniCustomerExtras.db.auth.currentUser?.id;
    _auth=AlAniCustomerExtras.db.auth.onAuthStateChange.listen((_){
      if(mounted&&AlAniCustomerExtras.db.auth.currentUser?.id!=_actor)setState((){
        _changed=true;_loading=false;_prefs.updateAll((key,value)=>false);
      });
    });
    unawaited(_load());
  }
  @override
  void dispose(){_auth?.cancel();super.dispose();}
  Future<void> _load()async{
    if(!_allowed){if(mounted)setState((){_loading=false;_failed=true;});return;}
    setState((){_loading=true;_failed=false;});
    try{
      final row=await AlAniCustomerExtras.db.from(_table)
          .select(_prefs.keys.join(',')).eq('user_id',_actor!).maybeSingle();
      if(mounted&&_allowed)setState((){
        for(final key in _prefs.keys){_prefs[key]=row?[key]==true;}
      });
    }catch(_){if(mounted)setState(()=>_failed=true);}
    finally{if(mounted)setState(()=>_loading=false);}
  }
  Future<void> _save()async{
    if(!_allowed||_busy||_loading||_failed)return;
    setState(()=>_busy=true);
    try{
      await AlAniCustomerExtras.db.from(_table).upsert({'user_id':_actor!,..._prefs});
      if(mounted&&_allowed)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('حُفظت تفضيلات الإشعارات.')));
    }catch(_){if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('تعذر تأكيد الحفظ. أعد المحاولة.')));}
    finally{if(mounted)setState(()=>_busy=false);}
  }
  @override
  Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:Text(_production?'تفضيلات الإشعارات':'تفضيلات الإشعارات — TEST')),body:
    !_allowed?const Center(child:Text('أعد فتح الصفحة بالحساب الحالي.')):
    _loading?const Center(child:CircularProgressIndicator()):
    _failed?Center(child:TextButton(onPressed:_load,child:const Text('إعادة التحميل'))):
    ListView(padding:const EdgeInsets.all(16),children:[
      const Text('تفضيلات اختيارية لإرسال الإشعارات الخارجية مستقبلاً. لا يجري إرسال Firebase حالياً، ولا تتغير تنبيهات التطبيق الداخلية.'),
      for(final e in const {'order_updates':'تحديثات الطلبات','favorite_updates':'انخفاض الأسعار وتوفر المفضلة','monthly_reviews':'مراجعة الاشتراكات الشهرية',if(_production)'support_updates':'رسائل فريق الدعم'}.entries)
        SwitchListTile(title:Text(e.value),value:_prefs[e.key]!,onChanged:_busy?null:(v)=>setState(()=>_prefs[e.key]=v)),
      FilledButton(onPressed:_busy?null:_save,child:const Text('حفظ التفضيلات')),
    ]));
}
