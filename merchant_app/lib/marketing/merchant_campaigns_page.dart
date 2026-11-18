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
  static const enabled=bool.fromEnvironment('SHITREED_CAMPAIGNS_ENABLED',
    defaultValue:false);
  late Future<List<Map<String,dynamic>>> _campaigns;
  @override void initState(){super.initState();_setFuture();}
  void _setFuture() {
    _campaigns=enabled ? _load() : Future.value(<Map<String,dynamic>>[]);
  }
  Future<List<Map<String,dynamic>>> _load() async {
    return await Supabase.instance.client.from('shitreed_store_campaigns')
      .select('id,title,description,starts_at,ends_at,is_published')
      .eq('store_id',widget.storeId).order('starts_at',ascending:false);
  }
  Future<void> _refresh() async {
    setState(_setFuture);
    try{await _campaigns;}catch(_){/* FutureBuilder displays errors */ }
  }
  void _notice(String s){
    if(mounted)ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content:Text(s)));
  }
  Future<void> _create() async {
    final title=TextEditingController(),details=TextEditingController();
    DateTime start=DateTime.now().add(const Duration(days:1));
    DateTime end=start.add(const Duration(days:7));
    bool publish=false, saving=false;
    final result=await showDialog<bool>(context:context,
      builder:(ctx)=>StatefulBuilder(builder:(context,update)=>AlertDialog(
        title:const Text('جدولة بانر عرض'),
        content:SizedBox(width:440,child:SingleChildScrollView(
          child:Column(mainAxisSize:MainAxisSize.min,children:[
            const Text('هذا بانر إعلامي؛ لا يغيّر سعر الشراء تلقائياً.',
              style:TextStyle(fontSize:12)),
            const SizedBox(height:9),
            TextField(controller:title,maxLength:100,
              decoration:const InputDecoration(labelText:'عنوان العرض',
                border:OutlineInputBorder())),
            TextField(controller:details,maxLines:3,maxLength:600,
              decoration:const InputDecoration(labelText:'تفاصيل العرض',
                border:OutlineInputBorder())),
            ListTile(
              title:const Text('بداية العرض'),
              subtitle:Text(start.toLocal().toString().substring(0,10)),
              trailing:const Icon(Icons.date_range),
              onTap:()async {
                final picked=await showDatePicker(context:context,
                  firstDate:DateTime.now(),
                  lastDate:DateTime.now().add(const Duration(days:365)),
                  initialDate:start);
                if(picked!=null)update(()=>start=picked);
              }),
            ListTile(
              title:const Text('نهاية العرض'),
              subtitle:Text(end.toLocal().toString().substring(0,10)),
              trailing:const Icon(Icons.event),
              onTap:()async {
                final picked=await showDatePicker(context:context,
                  firstDate:DateTime.now(),
                  lastDate:DateTime.now().add(const Duration(days:365)),
                  initialDate:end);
                if(picked!=null)update(()=>end=picked);
              }),
            SwitchListTile(
              title:const Text('نشر العرض عند بدء مدته'),
              value:publish,onChanged:(v)=>update(()=>publish=v)),
          ]))),
        actions:[
          TextButton(onPressed:saving?null:()=>Navigator.pop(context,false),
            child:const Text('إلغاء')),
          FilledButton(onPressed:saving?null:()async {
            final begins=DateTime(start.year,start.month,start.day);
            final ends=DateTime(end.year,end.month,end.day,23,59,59);
            if(title.text.trim().length<3 || !ends.isAfter(begins) ||
              ends.difference(begins).inDays>90){
              _notice('العنوان مطلوب والمدة لا تتجاوز 90 يوماً.');return;
            }
            update(()=>saving=true);
            try{
              final uid=Supabase.instance.client.auth.currentUser?.id;
              if(uid==null)throw StateError('LOGIN_REQUIRED');
              await Supabase.instance.client.from('shitreed_store_campaigns')
                .insert({
                  'store_id':widget.storeId,
                  'created_by':uid,
                  'title':title.text.trim(),
                  'description':details.text.trim(),
                  'starts_at':begins.toUtc().toIso8601String(),
                  'ends_at':ends.toUtc().toIso8601String(),
                  'is_published':publish,
                });
              if(context.mounted)Navigator.pop(context,true);
            }catch(_){
              _notice('تعذر الحفظ؛ تحقق من اعتماد المتجر والصلاحيات.');
              if(context.mounted)update(()=>saving=false);
            }
          },child:const Text('حفظ')),
        ],
      )));
    title.dispose();details.dispose();
    if(result==true){await _refresh();_notice('تم حفظ العرض.');}
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
    appBar:AppBar(title:Text('عروض '+widget.storeName)),
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
          if(snapshot.hasError)return const Card(
            child:Padding(padding:EdgeInsets.all(17),
              child:Text('تعذر تحميل العروض. تأكد من تفعيل قاعدة البيانات.')));
          final list=snapshot.data??[];
          if(list.isEmpty)return const ListTile(
            title:Text('لا توجد عروض مسجلة بعد.'));
          return Column(children:[
            for(final row in list)Card(child:ListTile(
              title:Text(row['title']?.toString()??''),
              subtitle:Text((row['description']?.toString()??'')+'\n'+
                (row['starts_at']?.toString()??'')+' — '+
                (row['ends_at']?.toString()??'')),
              isThreeLine:true,
              trailing:Switch(value:row['is_published']==true,
                onChanged:(_)=>_toggle(row)),
            )),
          ]);
        },
      ),
    ]),
  );
}