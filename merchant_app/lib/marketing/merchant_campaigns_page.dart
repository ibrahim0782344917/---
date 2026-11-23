import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shitreed_merchant/shared/merchant_widgets.dart';

/// Uses store-owner RLS. Does not change checkout prices.
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
    final details = TextEditingController(
      text: existing?['description']?.toString() ?? '');
    final image = TextEditingController(
      text: existing?['image_url']?.toString() ?? '');
    DateTime start = DateTime.tryParse(
      existing?['starts_at']?.toString() ?? '')?.toLocal() ??
      DateTime.now().add(const Duration(hours: 1));
    DateTime end = DateTime.tryParse(
      existing?['ends_at']?.toString() ?? '')?.toLocal() ??
      start.add(const Duration(days: 3));
    String productId = existing?['product_id']?.toString() ?? '';
    bool publish = existing?['is_published'] == true;
    bool saving = false;
    List<Map<String,dynamic>> products = [];
    try {
      final rows = await db.from('products').select('id,name')
        .eq('store_id', widget.storeId).eq('is_active', true).limit(100);
      products = rows.map((e) => Map<String,dynamic>.from(e)).toList();
    } catch (_) {
      _notice('تعذّر تحميل المنتجات. يمكنك إنشاء عرض عام.');
    }
    if (!mounted) return;
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: Text(existing == null ? 'إنشاء عرض لفترة محدودة' : 'تعديل العرض'),
          content: SizedBox(width: 440, child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Text('العرض يظهر فقط خلال موعده. '
                'لا تُطبّق تخفيضات الأسعار تلقائياً على الفاتورة.',
                style: TextStyle(fontSize: 12)),
              const SizedBox(height: 12),
              TextField(controller: title, maxLength: 100,
                decoration: const InputDecoration(labelText: 'عنوان العرض',
                  border: OutlineInputBorder())),
              TextField(controller: details, maxLength: 600, maxLines: 3,
                decoration: const InputDecoration(labelText: 'وصف العرض',
                  border: OutlineInputBorder())),
              TextField(controller: image, maxLength: 1024,
                decoration: const InputDecoration(
                  labelText: 'رابط صورة العرض HTTPS (اختياري)',
                  border: OutlineInputBorder())),
              DropdownButtonFormField<String>(
                initialValue: products.any((p) => p['id'] == productId)
                  ? productId : '',
                decoration: const InputDecoration(
                  labelText: 'منتج مرتبط (اختياري)',
                  border: OutlineInputBorder()),
                items: [
                  const DropdownMenuItem<String>(value: '',
                    child: Text('عرض عام — بدون منتج')),
                  for (final p in products)
                    DropdownMenuItem<String>(
                      value: p['id'].toString(),
                      child: Text(p['name']?.toString() ?? 'منتج',
                        overflow: TextOverflow.ellipsis)),
                ],
                onChanged: (v) => update(() => productId = v ?? ''),
              ),
              ListTile(
                title: const Text('بداية العرض'),
                subtitle: Text(start.toString().substring(0,16)),
                trailing: const Icon(Icons.schedule),
                onTap: () async {
                  final day = await showDatePicker(
                    context: context,
                    initialDate: start,
                    firstDate: DateTime.now().subtract(const Duration(days: 365)),
                    lastDate: DateTime.now().add(const Duration(days: 365)));
                  if (day == null || !context.mounted) return;
                  final time = await showTimePicker(
                    context: context, initialTime: TimeOfDay.fromDateTime(start));
                  if (time != null) update(() => start = DateTime(
                    day.year,day.month,day.day,time.hour,time.minute));
                },
              ),
              ListTile(
                title: const Text('نهاية العرض'),
                subtitle: Text(end.toString().substring(0,16)),
                trailing: const Icon(Icons.event_busy_outlined),
                onTap: () async {
                  final day = await showDatePicker(
                    context: context,
                    initialDate: end,
                    firstDate: DateTime.now().subtract(const Duration(days:365)),
                    lastDate: DateTime.now().add(const Duration(days:365)));
                  if (day == null || !context.mounted) return;
                  final time = await showTimePicker(
                    context: context, initialTime: TimeOfDay.fromDateTime(end));
                  if (time != null) update(() => end = DateTime(
                    day.year,day.month,day.day,time.hour,time.minute));
                },
              ),
              SwitchListTile(
                title: const Text('نشر العرض في موعده'),
                value: publish,
                onChanged: (v) => update(() => publish = v)),
            ]),
          )),
          actions: [
            TextButton(onPressed: saving ? null :
              () => Navigator.pop(context,false),
              child: const Text('إلغاء')),
            FilledButton(onPressed: saving ? null : () async {
              final url = image.text.trim();
              if (title.text.trim().length < 3 ||
                  !end.isAfter(start) ||
                  end.difference(start) > const Duration(days: 90) ||
                  (url.isNotEmpty && (!url.startsWith('https://') ||
                    (Uri.tryParse(url)?.host.isEmpty ?? true)))) {
                _notice('تحقق من عنوان العرض والتوقيت والرابط. '
                  'المدة لا تتجاوز 90 يوماً.');
                return;
              }
              update(() => saving = true);
              try {
                final uid = db.auth.currentUser?.id;
                if (uid == null) throw StateError('LOGIN_REQUIRED');
                final data = <String,dynamic>{
                  'title': title.text.trim(),
                  'description': details.text.trim(),
                  'image_url': url.isEmpty ? null : url,
                  'product_id': productId.isEmpty ? null : productId,
                  'starts_at': start.toUtc().toIso8601String(),
                  'ends_at': end.toUtc().toIso8601String(),
                  'is_published': publish,
                };
                final records = existing == null
                  ? await db.from('shitreed_store_campaigns')
                      .insert({...data,
                        'store_id': widget.storeId, 'created_by': uid})
                      .select('id')
                  : await db.from('shitreed_store_campaigns')
                      .update(data)
                      .eq('id', existing['id'])
                      .eq('store_id',widget.storeId).select('id');
                if (records.isEmpty) throw StateError('PERMISSION_DENIED');
                if (context.mounted) Navigator.pop(context,true);
              } catch (_) {
                _notice('ما تم حفظ العرض. افحص الصلاحيات والتواريخ.');
                if (context.mounted) update(() => saving = false);
              }
            }, child: const Text('حفظ العرض')),
          ],
        ),
      ),
    );
    title.dispose();
    details.dispose();
    image.dispose();
    if (result == true) { await _refresh(); _notice('تم حفظ العرض بنجاح.'); }
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
        'التخفيض السعري يحتاج نظام حساب خادمي مستقلاً.',
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