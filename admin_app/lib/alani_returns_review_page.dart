import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// The server validates the signed-in actor, store ownership and status.
class AlAniReturnsReviewPage extends StatefulWidget {
  const AlAniReturnsReviewPage({super.key});
  @override
  State<AlAniReturnsReviewPage> createState() => _AlAniReturnsReviewPageState();
}
class _AlAniReturnsReviewPageState extends State<AlAniReturnsReviewPage> {
  SupabaseClient get db => Supabase.instance.client;
  late Future<List<Map<String,dynamic>>> rows;
  bool busy=false;
  static const labels={'submitted':'جديد','reviewing':'قيد المراجعة','approved':'مقبول','declined':'مرفوض','resolved':'مغلق'};
  static const kinds={'refund':'رد مبلغ','replacement':'استبدال','compensation':'تعويض','no_payment':'دون دفع'};
  @override
  void initState(){super.initState(); rows=load();}
  Future<List<Map<String,dynamic>>> load() async => await db.from('alani_return_requests')
    .select('id,order_id,status,reason,details,resolution_note,resolution_kind,planned_amount_iqd,planned_outbound_fee_iqd,planned_return_fee_iqd')
    .eq('store_id','25091ca2-c0da-416c-b634-81b188ee66be')
    .order('created_at',ascending:false).limit(50);
  Future<void> reload() async {
    final next=load(); setState(()=>rows=next);
    try {await next;} catch (_) {}
  }
  void notice(String message){if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(message)));}
  Future<void> execute(Future<void> Function() action) async {
    if(busy)return;
    setState(()=>busy=true);
    try {await action(); if(mounted){await reload();notice('تم حفظ القرار في الخادم. لا يوجد دفع تلقائي.');}}
    catch(_){notice('تعذر حفظ القرار. تحقق من الصلاحية والحالة والاتصال.');}
    finally {if(mounted)setState(()=>busy=false);}
  }
  Future<void> review(Map<String,dynamic> row,String status) async {
    final controller=TextEditingController();
    final note=await showDialog<String>(context:context,builder:(ctx)=>AlertDialog(
      title:Text(labels[status]??status),
      content:Column(mainAxisSize:MainAxisSize.min,children:[
        if(status=='resolved') const Text('أغلق الطلب فقط بعد تنفيذ المعالجة المتفق عليها خارج التطبيق. الإغلاق لا ينفذ دفعاً.'),
        TextField(controller:controller,maxLines:3,maxLength:1000,decoration:const InputDecoration(labelText:'ملاحظة (10 أحرف على الأقل)')),
      ]),
      actions:[TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('رجوع')),
        FilledButton(onPressed:()=>Navigator.pop(ctx,controller.text.trim()),child:const Text('تأكيد'))],
    ));
    controller.dispose();
    if(!mounted||note==null)return;
    if(note.length<10){notice('أدخل ملاحظة لا تقل عن 10 أحرف.');return;}
    await execute(() async {final result=await db.rpc('alani_review_return',params:{'p_request_id':row['id'],'p_new_status':status,'p_note':note});if(result!=status)throw StateError('NOT_CONFIRMED');});
  }
  Future<void> plan(Map<String,dynamic> row) async {
    var kind='replacement';var outbound=false;var inbound=false;
    final amount=TextEditingController(text:'0');
    final optionalFees=row['reason']=='change_mind';
    final ok=await showDialog<bool>(context:context,builder:(ctx)=>StatefulBuilder(builder:(ctx,update)=>AlertDialog(
      title:const Text('خطة معالجة الاسترجاع'),
      content:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[
        DropdownButtonFormField<String>(initialValue:kind,items:kinds.entries.map((e)=>DropdownMenuItem(value:e.key,child:Text(e.value))).toList(),onChanged:(v)=>update(()=>kind=v??kind)),
        if(kind=='refund'||kind=='compensation') TextField(controller:amount,keyboardType:TextInputType.number,decoration:const InputDecoration(labelText:'المبلغ بالدينار')),
        if(optionalFees) ...[
          CheckboxListTile(value:outbound,onChanged:(v)=>update(()=>outbound=v??false),title:const Text('رسوم الذهاب 5000')),
          CheckboxListTile(value:inbound,onChanged:(v)=>update(()=>inbound=v??false),title:const Text('رسوم الرجوع 5000')),
        ],
        const Text('هذه خطة فقط ولا تُحوّل أموالاً. رسوم التلف أو الخطأ صفر.'),
      ])),
      actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('رجوع')),FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('حفظ الخطة'))],
    )));
    final value=(kind=='refund'||kind=='compensation')?int.tryParse(amount.text.trim()):0;
    amount.dispose();
    if(!mounted||ok!=true)return;
    if(value==null||value<0||((kind=='refund'||kind=='compensation')&&value==0)){notice('أدخل مبلغاً صحيحاً.');return;}
    await execute(() async {
      final result=await db.rpc('alani_plan_return_resolution',params:{'p_request_id':row['id'],'p_kind':kind,'p_amount_iqd':value,'p_outbound_fee_iqd':optionalFees&&outbound?5000:0,'p_return_fee_iqd':optionalFees&&inbound?5000:0});
      if(result is! Map||result['payment_executed']!=false)throw StateError('INVALID_RESPONSE');
    });
  }
  @override
  Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:const Text('الاسترجاع والتعويض'),actions:[IconButton(onPressed:busy?null:reload,icon:const Icon(Icons.refresh))]),
    body:FutureBuilder<List<Map<String,dynamic>>>(future:rows,builder:(context,snapshot){
      if(snapshot.hasError)return const Center(child:Text('تعذر تحميل الطلبات. تحقق من الصلاحيات والاتصال.'));
      if(!snapshot.hasData)return const Center(child:CircularProgressIndicator());
      return RefreshIndicator(onRefresh:reload,child:ListView(physics:const AlwaysScrollableScrollPhysics(),padding:const EdgeInsets.all(16),children:[
        const Text('مراجعة ومعالجة طلبات الزبائن؛ لا يتم الدفع تلقائياً.'),
        if(snapshot.data!.isEmpty)const ListTile(title:Text('لا توجد طلبات استرجاع حالياً.')),
        for(final row in snapshot.data!)Card(child:Padding(padding:const EdgeInsets.all(12),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          Text('طلب: ${row['order_id']}',style:const TextStyle(fontWeight:FontWeight.bold)),
          Text(labels[row['status']]??'غير معروف'),
          Text(row['details']?.toString()??''),
          if(row['resolution_kind']!=null)Text('الخطة: ${kinds[row['resolution_kind']]??''} • ${row['planned_amount_iqd']} د.ع'),
          Wrap(spacing:8,children:[
            if(row['status']=='submitted')OutlinedButton(onPressed:busy?null:()=>review(row,'reviewing'),child:const Text('بدء المراجعة')),
            if(row['status']=='reviewing')FilledButton(onPressed:busy?null:()=>review(row,'approved'),child:const Text('قبول')),
            if(row['status']=='submitted'||row['status']=='reviewing')OutlinedButton(onPressed:busy?null:()=>review(row,'declined'),child:const Text('رفض')),
            if(row['status']=='approved')FilledButton(onPressed:busy?null:()=>plan(row),child:const Text('خطة التعويض')),
            if(row['status']=='approved'&&row['resolution_kind']!=null)OutlinedButton(onPressed:busy?null:()=>review(row,'resolved'),child:const Text('إغلاق بعد المعالجة')),
          ]),
        ]))),
      ]));
    }),
  );
}
