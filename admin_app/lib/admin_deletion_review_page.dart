import 'package:flutter/material.dart';
import 'admin_api.dart';

abstract final class AdminDeletionPolicy {
  static bool canFinalize(Map<String,dynamic> data) =>
    data['status']=='processing' && data['account_exists']==true &&
    data['protected_account']==false &&
    data['eligible_for_clean_account_deletion']==true &&
    data['execution_enabled']==true;
}
class AdminDeletionReviewPage extends StatefulWidget {
  const AdminDeletionReviewPage({super.key});
  @override
  State<AdminDeletionReviewPage> createState()=>_AdminDeletionReviewPageState();
}
class _AdminDeletionReviewPageState extends State<AdminDeletionReviewPage> {
  late Future<List<Map<String,dynamic>>> rows;
  bool busy=false;
  @override
  void initState(){super.initState();rows=load();}
  Future<List<Map<String,dynamic>>> load() async {
    final r=await AdminApi.client.rpc('alani_deletion_review_queue',params:{'p_limit':50});
    return (r as List).map((x)=>Map<String,dynamic>.from(x as Map)).toList();
  }
  Future<void> refresh() async {
    if(!mounted)return;
    final next=load();setState(()=>rows=next);
    try{await next;}catch(_){}
  }
  void message(String text){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(text)));}
  Future<Map<String,dynamic>> preview(String id) async =>
    Map<String,dynamic>.from(await AdminApi.client.rpc('alani_deletion_review_preview',params:{'p_request_id':id}) as Map);
  Future<void> inspect(Map<String,dynamic> row) async {
    if(busy)return;
    final id=row['id'].toString();
    setState(()=>busy=true);
    try {
      final data=await preview(id);
      if(!mounted)return;
      final action=await showDialog<String>(context:context,builder:(ctx)=>AlertDialog(
        title:const Text('فحص طلب الحذف'),
        content:SingleChildScrollView(child:Column(crossAxisAlignment:CrossAxisAlignment.start,mainAxisSize:MainAxisSize.min,children:[
          Text('رقم الطلب: $id',textDirection:TextDirection.ltr),
          Text('الطلبات المفتوحة: ${data['open_orders']}'),
          Text('الارتباطات المانعة: ${data['blocking_relationships']}'),
          Text('ارتباطات تحتاج مراجعة: ${data['additional_review_blockers']}'),
          Text('الملفات المرتبطة: ${data['owned_storage_objects']}'),
          Text(data['protected_account']==true?'حساب محمي من الحذف.':data['eligible_for_clean_account_deletion']==true?'مؤهل للحذف بعد المراجعة.':'تجب معالجة الارتباطات والبيانات قبل الحذف.'),
          const SizedBox(height:8),
          const Text('حذف الحساب نهائي ولا يمكن التراجع عنه من التطبيق. لا تحذف سجلات الطلبات أو المحاسبة لتجاوز الفحص.'),
        ])),
        actions:[
          TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('إغلاق')),
          if(data['status']=='pending') FilledButton(onPressed:()=>Navigator.pop(ctx,'review'),child:const Text('بدء المراجعة')),
          if(AdminDeletionPolicy.canFinalize(data)) FilledButton(onPressed:()=>Navigator.pop(ctx,'finalize'),child:const Text('متابعة الحذف')),
        ],
      ));
      if(!mounted)return;
      if(action=='review'){
        final r=await AdminApi.client.rpc('alani_deletion_begin_review',params:{'p_request_id':id});
        if(r!='processing')throw StateError('REVIEW_NOT_CONFIRMED');
        message('تم بدء المراجعة. افحص الطلب مرة أخرى قبل الحذف.');
      }
      if(action=='finalize'){
        final controller=TextEditingController();
        final confirmed=await showDialog<bool>(context:context,builder:(ctx)=>StatefulBuilder(builder:(ctx,update)=>AlertDialog(
          title:const Text('تأكيد نهائي غير قابل للتراجع'),
          content:Column(mainAxisSize:MainAxisSize.min,children:[
            const Text('سيُحذف حساب الزبون المؤهل وجلساته وبياناته الشخصية. اكتب كلمة حذف لتأكيد القرار.'),
            TextField(controller:controller,onChanged:(_)=>update((){}),decoration:const InputDecoration(labelText:'اكتب حذف')),
          ]),
          actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('رجوع')),
            FilledButton(onPressed:controller.text.trim()=='حذف'?()=>Navigator.pop(ctx,true):null,child:const Text('تنفيذ الحذف النهائي'))],
        )));
        controller.dispose();
        if(confirmed!=true||!mounted)return;
        final result=await AdminApi.client.rpc('alani_deletion_finalize',params:{'p_request_id':id,'p_confirmation':'DELETE $id'});
        if(result!='completed')throw StateError('DELETE_NOT_CONFIRMED');
        message('تم تأكيد حذف الحساب من الخادم.');
      }
      if(mounted)await refresh();
    }catch(_){message('تعذر تنفيذ العملية. تحقق من التحقق بخطوتين وصلاحياتك وارتباطات الحساب.');}
    finally{if(mounted)setState(()=>busy=false);}
  }
  @override
  Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:const Text('طلبات حذف الحساب'),actions:[IconButton(onPressed:busy?null:refresh,icon:const Icon(Icons.refresh))]),
    body:FutureBuilder<List<Map<String,dynamic>>>(future:rows,builder:(context,snapshot){
      if(snapshot.hasError)return const Center(child:Text('تعذر فتح طلبات الحذف. يلزم المدير العام وجلسة تحقق بخطوتين.'));
      if(!snapshot.hasData)return const Center(child:CircularProgressIndicator());
      return RefreshIndicator(onRefresh:refresh,child:ListView(physics:const AlwaysScrollableScrollPhysics(),padding:const EdgeInsets.all(16),children:[
        const Text('حذف الحسابات المؤهلة فقط بعد طلب الزبون ومراجعة الإدارة. الحسابات ذات الارتباطات التجارية تحتاج معالجة مستقلة.'),
        if(snapshot.data!.isEmpty)const ListTile(title:Text('لا توجد طلبات حذف حالياً.')),
        for(final row in snapshot.data!)Card(child:ListTile(
          title:Text('طلب: ${row['id']}'),
          subtitle:Text(row['status']=='pending'?'بانتظار المراجعة':'قيد المراجعة'),
          onTap:busy?null:()=>inspect(row),trailing:const Icon(Icons.chevron_left),
        )),
      ]));
    }),
  );
}
