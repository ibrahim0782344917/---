import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shitreed_merchant/shared/merchant_widgets.dart';

/// Saves multi-product campaigns atomically; checkout validates discounts server-side.
class MerchantCampaignsPage extends StatefulWidget {
  final String storeId,storeName;
  const MerchantCampaignsPage({super.key,required this.storeId,required this.storeName});
  @override State<MerchantCampaignsPage> createState()=>_MerchantCampaignsPageState();
}
class _MerchantCampaignsPageState extends State<MerchantCampaignsPage> {
  static const enabled =
      bool.fromEnvironment('SHITREED_CAMPAIGNS_ENABLED', defaultValue:false) &&
      (String.fromEnvironment('SUPABASE_URL') ==
        'https://tgvdwotbrnhcoykuxdpr.supabase.co' ||
       bool.fromEnvironment('ALANI_CAMPAIGNS_PRODUCTION_APPROVED',
         defaultValue:false));
  late Future<List<Map<String,dynamic>>> _campaigns;
  @override void initState(){super.initState();_setFuture();}
  void _setFuture() {
    _campaigns=enabled ? _load() : Future.value(<Map<String,dynamic>>[]);
  }
  Future<List<Map<String,dynamic>>> _load() async {
    return await Supabase.instance.client.from('shitreed_store_campaigns')
      .select('id,title,description,starts_at,ends_at,is_published,'
        'product_id,image_url')
      .eq('store_id',widget.storeId).order('starts_at',ascending:false);
  }
  Future<void> _refresh() async {
    setState(_setFuture);
    try{await _campaigns;}catch(_){/* FutureBuilder displays errors */ }
  }
  void _notice(String s){
    if(mounted){
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(s)));
    }
  }
  Future<void> _create([Map<String,dynamic>? existing]) async {
    final db = Supabase.instance.client;
    final title = TextEditingController(text: existing?['title']?.toString() ?? '');
    final details = TextEditingController(text: existing?['description']?.toString() ?? '');
    final image = TextEditingController(text: existing?['image_url']?.toString() ?? '');
    DateTime start = DateTime.tryParse(existing?['starts_at']?.toString() ?? '')
      ?.toLocal() ?? DateTime.now().add(const Duration(hours: 1));
    DateTime end = DateTime.tryParse(existing?['ends_at']?.toString() ?? '')
      ?.toLocal() ?? start.add(const Duration(days: 3));
    bool publish = existing?['is_published'] == true;
    bool saving = false;
    List<Map<String,dynamic>> products = [];
    final selected = <String>{};
    final prices = <String,TextEditingController>{};
    try {
      final rows = await db.from('products').select('id,name,price_iqd')
        .eq('store_id',widget.storeId).eq('is_active',true).limit(100);
      products=rows.map((x)=>Map<String,dynamic>.from(x)).toList();
      for(final p in products){
        prices[p['id'].toString()]=TextEditingController();
      }
      if(existing!=null){
        final prior=await db.from('shitreed_campaign_items')
          .select('product_id,sale_price_iqd')
          .eq('campaign_id',existing['id']);
        for(final row in prior){
          final id=row['product_id'].toString();
          if(prices.containsKey(id)){
            selected.add(id);
            prices[id]!.text=row['sale_price_iqd'].toString();
          }
        }
      }
    }catch(_){
      _notice('تعذّر تحميل المنتجات وأسعار العرض. تحقق من الصلاحيات.');
      title.dispose();details.dispose();image.dispose();
      for(final p in prices.values){p.dispose();}
      return;
    }
    if(!mounted){
      title.dispose();details.dispose();image.dispose();
      for(final p in prices.values){p.dispose();}
      return;
    }
    final result=await showDialog<bool>(
      context:context,
      builder:(ctx)=>StatefulBuilder(
        builder:(dialogContext,update)=>AlertDialog(
          title:Text(existing==null?'عرض جديد مع خصومات':'تعديل عرض المنتجات'),
          content:SizedBox(width:480,child:SingleChildScrollView(
            child:Column(mainAxisSize:MainAxisSize.min,children:[
              const Text('اختَر أكثر من منتج وحدد سعر العرض لكل واحد. '
                'السعر الأصلي يبقى محفوظاً، وتُحسب الخصومات على الخادم '
                'فقط أثناء وقت العرض.',style:TextStyle(fontSize:12,height:1.6)),
              const SizedBox(height:12),
              TextField(controller:title,maxLength:100,
                decoration:const InputDecoration(labelText:'عنوان العرض',
                  border:OutlineInputBorder())),
              TextField(controller:details,maxLength:600,maxLines:3,
                decoration:const InputDecoration(labelText:'وصف العرض',
                  border:OutlineInputBorder())),
              TextField(controller:image,maxLength:1024,
                decoration:const InputDecoration(
                  labelText:'رابط صورة HTTPS (اختياري)',
                  border:OutlineInputBorder())),
              const Divider(height:28),
              Text('منتجات العرض (${selected.length} مختارة)',
                style:const TextStyle(fontWeight:FontWeight.w900)),
              for(final p in products) ...[
                CheckboxListTile(
                  contentPadding:EdgeInsets.zero,
                  value:selected.contains(p['id'].toString()),
                  title:Text(p['name'].toString()),
                  subtitle:Text('السعر الأصلي: ${p['price_iqd']} د.ع'),
                  onChanged:saving?null:(v)=>update(() {
                    if(v==true){selected.add(p['id'].toString());}
                    else{selected.remove(p['id'].toString());}
                  }),
                ),
                if(selected.contains(p['id'].toString()))
                  Padding(padding:const EdgeInsets.only(bottom:14),
                    child:TextField(
                      controller:prices[p['id'].toString()],
                      keyboardType:TextInputType.number,
                      onChanged:(_)=>update((){}),
                      decoration:InputDecoration(
                        labelText:'السعر الجديد لـ ${p['name']} بالدينار',
                        helperText:(){
                          final amount=int.tryParse(prices[p['id'].toString()]?.text ?? '');
                          final regular=(p['price_iqd'] as num).toInt();
                          if(amount==null || amount<=0 || amount>=regular){
                            return 'الخصم يجب أن يكون أقل من $regular د.ع';
                          }
                          final pct=((regular-amount)*100/regular).round();
                          return 'السعر القديم $regular ← الجديد $amount (خصم $pct%)';
                        }(),
                        border:const OutlineInputBorder(),
                      ),
                    ),
                  ),
              ],
              const SizedBox(height:8),
              ListTile(
                title:const Text('بداية العرض'),
                subtitle:Text(start.toString().substring(0,16)),
                trailing:const Icon(Icons.schedule),
                onTap:saving?null:() async{
                  final day=await showDatePicker(context:dialogContext,
                    initialDate:start,
                    firstDate:DateTime.now().subtract(const Duration(days:365)),
                    lastDate:DateTime.now().add(const Duration(days:365)));
                  if(day==null||!dialogContext.mounted)return;
                  final time=await showTimePicker(context:dialogContext,
                    initialTime:TimeOfDay.fromDateTime(start));
                  if(time!=null){
                    update(()=>start=DateTime(day.year,day.month,day.day,
                      time.hour,time.minute));
                  }
                },
              ),
              ListTile(
                title:const Text('نهاية العرض'),
                subtitle:Text(end.toString().substring(0,16)),
                trailing:const Icon(Icons.event_busy_outlined),
                onTap:saving?null:() async{
                  final day=await showDatePicker(context:dialogContext,
                    initialDate:end,
                    firstDate:DateTime.now().subtract(const Duration(days:365)),
                    lastDate:DateTime.now().add(const Duration(days:365)));
                  if(day==null||!dialogContext.mounted)return;
                  final time=await showTimePicker(context:dialogContext,
                    initialTime:TimeOfDay.fromDateTime(end));
                  if(time!=null){
                    update(()=>end=DateTime(day.year,day.month,day.day,
                      time.hour,time.minute));
                  }
                },
              ),
              SwitchListTile(
                title:const Text('نشر العرض في موعده'),
                value:publish,
                onChanged:saving?null:(v)=>update(()=>publish=v)),
            ]),
          )),
          actions:[
            TextButton(onPressed:saving?null:()=>Navigator.pop(dialogContext,false),
              child:const Text('إلغاء')),
            FilledButton(
              onPressed:saving?null:() async{
                final url=image.text.trim();
                final rows=<Map<String,dynamic>>[];
                for(final p in products){
                  final id=p['id'].toString();
                  if(!selected.contains(id))continue;
                  final amount=int.tryParse(prices[id]?.text.trim()??'');
                  final regular=(p['price_iqd'] as num).toInt();
                  if(amount==null || amount<=0 || amount>=regular){
                    _notice('أدخل سعراً مخفضاً صحيحاً لكل منتج محدد.');
                    return;
                  }
                  rows.add({'product_id':id,'sale_price_iqd':amount});
                }
                if(rows.isEmpty || title.text.trim().length<3 ||
                  !end.isAfter(start) ||
                  end.difference(start)>const Duration(days:90) ||
                  (url.isNotEmpty && (!url.startsWith('https://') ||
                    (Uri.tryParse(url)?.host.isEmpty??true)))){
                  _notice('اختر المنتجات وحدد الأسعار وعنوان العرض ومدته.');
                  return;
                }
                update(()=>saving=true);
                try{
                  final id=await db.rpc('alani_save_campaign',params:{
                    'p_id':existing?['id'],
                    'p_store_id':widget.storeId,
                    'p_title':title.text.trim(),
                    'p_description':details.text.trim(),
                    'p_image_url':url.isEmpty?null:url,
                    'p_starts_at':start.toUtc().toIso8601String(),
                    'p_ends_at':end.toUtc().toIso8601String(),
                    'p_published':publish,
                    'p_items':rows,
                  });
                  if(id==null)throw StateError('NOT_SAVED');
                  if(dialogContext.mounted)Navigator.pop(dialogContext,true);
                }catch(_){
                  _notice('تعذّر حفظ العرض. تأكد من الأسعار والصلاحيات.');
                  if(dialogContext.mounted)update(()=>saving=false);
                }
              },
              child:const Text('حفظ العرض والخصومات')),
          ],
        ),
      ),
    );
    title.dispose();details.dispose();image.dispose();
    for(final p in prices.values){p.dispose();}
    if(result==true){await _refresh();_notice('تم حفظ المنتجات والخصومات.');}
  }
  String _state(Map<String,dynamic> row) {
    if (row['is_published'] != true) return 'مسودة';
    final start = DateTime.tryParse(row['starts_at']?.toString() ?? '');
    final end = DateTime.tryParse(row['ends_at']?.toString() ?? '');
    final now = DateTime.now().toUtc();
    if (start == null || end == null) return 'وقت غير صحيح';
    if (now.isBefore(start)) return 'مجدول للنشر';
    if (!now.isBefore(end)) return 'منتهي';
    return 'نشط حالياً';
  }
  Future<void> _toggle(Map<String,dynamic> row) async {
    try{
      final result=await Supabase.instance.client
        .from('shitreed_store_campaigns')
        .update({'is_published':row['is_published']!=true})
        .eq('id',row['id']).eq('store_id',widget.storeId).select('id');
      if(result.isEmpty)throw StateError('PERMISSION_DENIED');
      await _refresh();_notice('تم تحديث نشر العرض.');
    }catch(_){_notice('تعذر تعديل العرض؛ تحقق من صلاحية المتجر.');}
  }
  @override Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:Text('عروض ${widget.storeName}')),
    floatingActionButton:enabled?FloatingActionButton.extended(
      onPressed:_create,icon:const Icon(Icons.add),label:const Text('عرض مؤقت')):null,
    body:ListView(padding:const EdgeInsets.all(16),children:[
      const Text('شريط العروض المؤقتة',style:TextStyle(
        color:merchantDark,fontSize:23,fontWeight:FontWeight.w900)),
      const SizedBox(height:8),
      const Text('تحدد موعد البداية والنهاية والنشر. '
        'سعر الخصم لكل منتج يُحسب عند الطلب من الخادم.',
        style:TextStyle(height:1.6)),
      if(!enabled)const Card(child:Padding(padding:EdgeInsets.all(18),
        child:Text('نظام العروض قيد التجهيز. '
          'لن يُفعّل نشر العروض قبل عزل قاعدة الاختبار وفحص الصلاحيات.'))),
      if(enabled)FutureBuilder<List<Map<String,dynamic>>>(
        future:_campaigns,builder:(context,snapshot){
          if(snapshot.connectionState!=ConnectionState.done){
            return const Center(child:CircularProgressIndicator());
          }
          if(snapshot.hasError){
            return const Card(
              child:Padding(padding:EdgeInsets.all(17),
                child:Text('تعذر تحميل العروض. تأكد من تفعيل قاعدة البيانات.')));
          }
          final list=snapshot.data??[];
          if(list.isEmpty){
            return const ListTile(title:Text('لا توجد عروض مسجلة بعد.'));
          }
          return Column(children:[
            for(final row in list)Card(child:ListTile(
              title:Text(row['title']?.toString()??''),
              subtitle:Text("${_state(row)} • ${row['description'] ?? ''}\n${row['starts_at'] ?? ''} — ${row['ends_at'] ?? ''}"),
              isThreeLine:true,
              trailing:Switch(value:row['is_published']==true,
                onChanged:(_)=>_toggle(row)),
              onTap:()=>_create(row),
            )),
          ]);
        },
      ),
    ]),
  );
}