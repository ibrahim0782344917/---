import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Private saved products and on-demand price/restock indicators.
/// No order placement, wallet or notification push operations.
class AlAniProductionFavoritesPage extends StatefulWidget {
  const AlAniProductionFavoritesPage({super.key});
  @override
  State<AlAniProductionFavoritesPage> createState()=>_AlAniProductionFavoritesPageState();
}
class _AlAniProductionFavoritesPageState extends State<AlAniProductionFavoritesPage> {
  final db=Supabase.instance.client;
  static const storeId='25091ca2-c0da-416c-b634-81b188ee66be';
  late final String? _actor;
  StreamSubscription<AuthState>? _auth;
  bool _changed=false,_loading=true,_busy=false;
  String? _error;
  List<Map<String,dynamic>> _saved=[],_catalog=[];
  bool get _sameActor=>!_changed&&_actor!=null&&db.auth.currentUser?.id==_actor;
  @override
  void initState(){
    super.initState();
    _actor=db.auth.currentUser?.id;
    _auth=db.auth.onAuthStateChange.listen((_){
      if(mounted&&db.auth.currentUser?.id!=_actor)setState((){
        _changed=true;_saved=[];_catalog=[];_loading=false;_error=null;
      });
    });
    unawaited(_load());
  }
  @override
  void dispose(){_auth?.cancel();super.dispose();}
  Future<void> _load()async{
    if(!mounted||!_sameActor)return;
    setState((){_loading=true;_error=null;});
    try{
      final raw=await db.rpc('alani_my_favorites');
      if(!mounted||!_sameActor)return;
      final products=await db.from('products').select('id,name,price_iqd,stock_quantity')
        .eq('store_id',storeId).eq('is_active',true).order('name').limit(100);
      if(!mounted||!_sameActor)return;
      setState((){
        _saved=(raw as List).map((x)=>Map<String,dynamic>.from(x as Map)).toList();
        _catalog=products.map((x)=>Map<String,dynamic>.from(x)).toList();
      });
    }catch(_){
      if(mounted&&_sameActor)setState((){_saved=[];_catalog=[];_error='تعذر تحميل المفضلة. تحقق من الاتصال.';});
    }finally{if(mounted)setState(()=>_loading=false);}
  }
  Future<void> _set(String id,bool save)async{
    if(!_sameActor||_busy||_loading)return;
    setState(()=>_busy=true);
    try{
      final result=await db.rpc('alani_set_favorite',params:{'p_product_id':id,'p_saved':save});
      if(!mounted||!_sameActor)return;
      if(result!=save)throw StateError('UNEXPECTED_RESULT');
      await _load();
    }catch(_){
      if(mounted&&_sameActor)ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content:Text('تعذر تأكيد العملية. حدّث القائمة للتحقق.')));
    }finally{if(mounted)setState(()=>_busy=false);}
  }
  @override
  Widget build(BuildContext context){
    final savedIds=_saved.map((x)=>x['id']).toSet();
    final alerts=_saved.where((x)=>x['price_dropped']==true||x['restocked']==true).length;
    return Scaffold(appBar:AppBar(title:const Text('مفضلتي وتنبيهات المنتجات'),actions:[
      IconButton(tooltip:'تحديث',onPressed:_loading||_busy?null:_load,icon:const Icon(Icons.refresh)),
    ]),body:!_sameActor?const Center(child:Text('سجّل الدخول ثم أعد فتح المفضلة.')):
      _loading?const Center(child:CircularProgressIndicator()):
      _error!=null?Center(child:TextButton(onPressed:_load,child:Text(_error!))):
      ListView(padding:const EdgeInsets.all(16),children:[
        Card(child:ListTile(leading:const Icon(Icons.notifications_none),
          title:Text('تنبيهات المنتجات: $alerts'),
          subtitle:const Text('تُحدّث عند فتح الصفحة أو تحديثها، وليست إشعارات خلفية.'))),
        Text('المنتجات المحفوظة',style:Theme.of(context).textTheme.titleLarge),
        if(_saved.isEmpty)const ListTile(title:Text('لم تحفظ منتجات بعد.')),
        for(final item in _saved)Card(child:ListTile(
          title:Text(item['name'].toString()),
          subtitle:Text('${item['price_iqd']} د.ع • المخزون: ${item['stock_quantity']}'
            '${item['price_dropped']==true?'\nانخفض السعر منذ الحفظ':''}'
            '${item['restocked']==true?'\nعاد المنتج للمخزون':''}'),
          trailing:IconButton(tooltip:'إزالة من المفضلة',onPressed:_busy?null:()=>_set(item['id'] as String,false),icon:const Icon(Icons.favorite)),
        )),
        const SizedBox(height:16),
        Text('أضف من منتجات المتجر',style:Theme.of(context).textTheme.titleLarge),
        if(_catalog.length>=100)const Text('تُعرض أول 100 نتيجة فقط.'),
        for(final item in _catalog.where((x)=>!savedIds.contains(x['id'])))Card(child:ListTile(
          title:Text(item['name'].toString()),subtitle:Text('${item['price_iqd']} د.ع'),
          trailing:IconButton(tooltip:'إضافة إلى المفضلة',onPressed:_busy?null:()=>_set(item['id'] as String,true),icon:const Icon(Icons.favorite_border)),
        )),
      ]));
  }
}
