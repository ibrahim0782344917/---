import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

abstract final class AlAniCustomerExtras {
  static const enabled =
      bool.fromEnvironment('ALANI_CUSTOMER_EXTRAS_ENABLED', defaultValue: false) &&
      String.fromEnvironment('SUPABASE_URL') ==
          'https://tgvdwotbrnhcoykuxdpr.supabase.co';
  static const storeId = '25091ca2-c0da-416c-b634-81b188ee66be';
  static SupabaseClient get db => Supabase.instance.client;
  static Future<dynamic> call(String name, [Map<String,dynamic>? params]) async {
    if (!enabled || db.auth.currentUser == null) throw StateError('TEST_LOGIN_REQUIRED');
    return db.rpc(name, params: params);
  }
}

class AlAniCustomerExtrasPage extends StatefulWidget {
  const AlAniCustomerExtrasPage({super.key});
  @override
  State<AlAniCustomerExtrasPage> createState() => _AlAniCustomerExtrasPageState();
}

class _AlAniCustomerExtrasPageState extends State<AlAniCustomerExtrasPage> {
  late Future<List<dynamic>> _data;
  final _code = TextEditingController();
  bool _busy = false;
  @override
  void initState() { super.initState(); _data = _load(); }
  @override
  void dispose() { _code.dispose(); super.dispose(); }
  Future<List<dynamic>> _load() => Future.wait([
    AlAniCustomerExtras.call('alani_my_points_test'),
    AlAniCustomerExtras.call('alani_my_favorites_test'),
    AlAniCustomerExtras.call('alani_my_invite_test'),
    AlAniCustomerExtras.call('alani_my_subscriptions_test'),
    AlAniCustomerExtras.call('alani_list_bundles_test'),
  ]);
  void _refresh() => setState(() => _data = _load());
  Future<void> _run(Future<dynamic> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      if (mounted) {
        _refresh();
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم حفظ العملية.')));
      }
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تعذرت العملية. تحقق من الحساب والبيانات.')));
    } finally { if (mounted) setState(() => _busy = false); }
  }
  Future<void> _previewBundle(String id)async{
    if(_busy)return;
    setState(()=>_busy=true);
    try{
      final quote=Map<String,dynamic>.from(await AlAniCustomerExtras.call('alani_bundle_quote_test',{'p_bundle_id':id}) as Map);
      if(!mounted)return;
      final lines=(quote['items'] as List).map((e)=>Map<String,dynamic>.from(e as Map)).toList();
      await showDialog<void>(context:context,builder:(ctx)=>AlertDialog(
        title:Text(quote['title'].toString()),
        content:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.start,children:[
          for(final line in lines) Text(line['product_name'].toString()+' × '+line['quantity'].toString()),
          Text('سعر الباقة: '+quote['bundle_subtotal_iqd'].toString()+' د.ع'),
          Text('التوصيل: '+quote['delivery_fee_iqd'].toString()+' د.ع'),
          Text('المجموع: '+quote['total_iqd'].toString()+' د.ع'),
          const Text('عرض سعر فقط؛ لم يُنشأ طلب.'),
        ])),
        actions:[TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('إغلاق'))],
      ));
    }catch(_){if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('الباقة غير متاحة بالسعر أو المخزون الحالي.')));}
    finally{if(mounted)setState(()=>_busy=false);}
  }
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('المفضلة والمكافآت — TEST'),
      actions: [IconButton(onPressed: _busy ? null : _refresh, icon: const Icon(Icons.refresh))]),
    body: FutureBuilder<List<dynamic>>(future: _data, builder: (context, snap) {
      if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
      if (snap.hasError || !snap.hasData) return Center(child: TextButton(onPressed: _refresh, child: const Text('تعذر التحميل. إعادة المحاولة')));
      final points = Map<String,dynamic>.from(snap.data![0] as Map);
      final favorites = (snap.data![1] as List).map((e) => Map<String,dynamic>.from(e as Map)).toList();
      final invite = Map<String,dynamic>.from(snap.data![2] as Map);
      final subscriptions = (snap.data![3] as List).map((e) => Map<String,dynamic>.from(e as Map)).toList();
      final bundles = (snap.data![4] as List).map((e) => Map<String,dynamic>.from(e as Map)).toList();
      return ListView(padding: const EdgeInsets.all(16), children: [
        Card(child: ListTile(leading: const Icon(Icons.stars_outlined), title: Text('نقاط الشراء: ${points['points']}'), subtitle: const Text('ليست أموالاً ولا XP. الاستبدال والسحب غير متاحين.'))),
        const SizedBox(height: 12),
        const Text('دعوة الأصدقاء', style: TextStyle(fontSize: 18,fontWeight: FontWeight.bold)),
        SelectableText(invite['code'].toString()),
        TextButton.icon(onPressed: () async {
          await Clipboard.setData(ClipboardData(text: invite['code'].toString()));
        }, icon: const Icon(Icons.copy), label: const Text('نسخ رمز الدعوة')),
        Text('عدد الإحالات المسجلة: ${invite['invite_count']}'),
        const Text('صرف مكافآت الإحالات غير مفعّل.'),
        if (invite['already_referred'] != true) ...[
          TextField(controller: _code, decoration: const InputDecoration(labelText: 'رمز دعوة صديق')),
          FilledButton(onPressed: _busy ? null : () => _run(() => AlAniCustomerExtras.call('alani_claim_invite_test', {'p_code': _code.text.trim()})), child: const Text('تسجيل الدعوة')),
        ],
        const SizedBox(height: 16),
        const Text('الباقات والعروض',style:TextStyle(fontSize:18,fontWeight:FontWeight.bold)),
        const Text('معاينة عروض TEST فقط، لا تتوفر عملية شراء الباقة حالياً.'),
        if(bundles.isEmpty) const Text('لا توجد باقات نشطة.'),
        for(final bundle in bundles)
          ListTile(title:Text(bundle['title'].toString()),
            subtitle:Text(bundle['price_iqd'].toString()+' د.ع'+(bundle['free_delivery']==true?' • توصيل مجاني':' • توصيل 5,000 د.ع')),
            trailing:TextButton(onPressed:_busy?null:()=>_previewBundle(bundle['id'] as String),child:const Text('معاينة'))),
        const SizedBox(height:16),
        const Text('اشتراكاتي الشهرية', style: TextStyle(fontSize: 18,fontWeight: FontWeight.bold)),
        const Text('تفضيل شراء شهري فقط، دون إنشاء طلب أو خصم تلقائي.'),
        if (subscriptions.isEmpty) const Text('لا توجد اشتراكات مسجلة.'),
        for (final sub in subscriptions)
          ListTile(title: Text(sub['name'].toString()),
            subtitle: Text('الكمية: '+sub['quantity'].toString()+' • '+(sub['active']==true?'نشط':'متوقف')),
            trailing: sub['active']==true?TextButton(onPressed:_busy?null:()=>_run(()=>AlAniCustomerExtras.call('alani_set_subscription_test',{'p_product_id':sub['product_id'],'p_quantity':sub['quantity'],'p_active':false})),child:const Text('إيقاف')):null),
        const SizedBox(height:16),
        const Text('مفضلتي', style: TextStyle(fontSize: 18,fontWeight: FontWeight.bold)),
        if (favorites.isEmpty) const Text('لا توجد منتجات محفوظة.'),
        for (final item in favorites)
          Card(child: ListTile(
            title: Text(item['name'].toString()),
            subtitle: Text('${item['price_iqd']} د.ع • المخزون: ${item['stock_quantity']}'
              '${item['price_dropped'] == true ? '\nانخفض السعر منذ الحفظ' : ''}'
              '${item['restocked'] == true ? '\nعاد المنتج للمخزون' : ''}'),
            trailing: IconButton(tooltip: 'إزالة من المفضلة', icon: const Icon(Icons.favorite), onPressed: _busy ? null : () => _run(() => AlAniCustomerExtras.call('alani_set_favorite_test', {'p_product_id':item['id'],'p_saved':false}))),
          )),
      ]);
    }),
  );
}
