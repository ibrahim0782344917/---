import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'admin_api.dart';

/// Moderation remains server-authorized by RLS/RPCs.
class AlAniSocialModerationPage extends StatefulWidget {
  const AlAniSocialModerationPage({super.key});
  @override
  State<AlAniSocialModerationPage> createState()=>_ModerationState();
}
class _ModerationState extends State<AlAniSocialModerationPage> {
  static const storeId='25091ca2-c0da-416c-b634-81b188ee66be';
  final userId=TextEditingController();
  String role='writer';
  bool busy=false;
  late Future<List<List<Map<String,dynamic>>>> query;

  SupabaseClient get db=>AdminApi.client;

  @override
  void initState(){super.initState();query=load();}
  Future<List<List<Map<String,dynamic>>>> load() async {
    final comments=await db.from('alani_post_comments')
      .select('id,publication_id,body,status,created_at')
      .inFilter('status',['pending','approved','hidden','rejected'])
      .order('created_at',ascending:false).limit(100);
    final reports=await db.from('alani_post_reports')
      .select('id,publication_id,reason,status,created_at')
      .eq('status','open').order('created_at',ascending:false).limit(100);
    final staff=await db.from('alani_content_staff')
      .select('user_id,role').eq('store_id',storeId);
    return [comments,reports,staff].map((r)=>r.map((e)=>
      Map<String,dynamic>.from(e)).toList()).toList();
  }
  Future<void> refresh() async {
    final next=load();
    if(mounted)setState(()=>query=next);
    try{await next;}catch(_){/* handled by FutureBuilder */}
  }
  void notice(String text){
    if(mounted)ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content:Text(text)));
  }
  Future<void> action(String rpc,Map<String,dynamic> params) async {
    if(busy)return;
    setState(()=>busy=true);
    try{
      await db.rpc(rpc,params:params);
      await refresh();
      notice('تم حفظ القرار في سجل الإشراف.');
    }catch(_){notice('تعذر الحفظ. تأكد من صلاحية الإدارة والاتصال.');}
    finally{if(mounted)setState(()=>busy=false);}
  }
  Widget comments(List<Map<String,dynamic>> rows)=>ListView(children:[
    const ListTile(title:Text('الإشراف على التعليقات'),
      subtitle:Text('التعليق الجديد مخفي لحين الموافقة.')),
    if(rows.isEmpty)const ListTile(title:Text('لا توجد تعليقات')),
    for(final c in rows)Card(child:ListTile(
      title:Text(c['body']?.toString()??''),
      subtitle:Text('الحالة: '+(c['status']??'').toString()),
      trailing:PopupMenuButton<String>(
        onSelected:(v)=>action('alani_moderate_comment',{
          'p_id':c['id'],'p_status':v}),
        itemBuilder:(_)=>const [
          PopupMenuItem(value:'approved',child:Text('موافقة')),
          PopupMenuItem(value:'hidden',child:Text('إخفاء')),
          PopupMenuItem(value:'rejected',child:Text('رفض')),
        ],
      ),
    )),
  ]);
  Widget reports(List<Map<String,dynamic>> rows)=>ListView(children:[
    const ListTile(title:Text('بلاغات منشورات المتجر'),
      subtitle:Text('تأكد من البلاغ قبل أخذ القرار.')),
    if(rows.isEmpty)const ListTile(title:Text('لا توجد بلاغات مفتوحة')),
    for(final c in rows)Card(child:ListTile(
      title:Text('سبب البلاغ: '+(c['reason']??'').toString()),
      subtitle:Text('المنشور: '+(c['publication_id']??'').toString()),
      trailing:PopupMenuButton<String>(
        onSelected:(v)=>action('alani_review_report',{
          'p_id':c['id'],'p_status':v}),
        itemBuilder:(_)=>const [
          PopupMenuItem(value:'reviewed',child:Text('تمت المراجعة')),
          PopupMenuItem(value:'dismissed',child:Text('رفض البلاغ')),
        ],
      ),
    )),
  ]);
  Widget staff(List<Map<String,dynamic>> rows)=>ListView(
    padding:const EdgeInsets.all(13),children:[
      const Text('الكاتب ينشئ مسودة، المحرر ينشر، والمشرف يراجع التعليقات والبلاغات.'),
      const SizedBox(height:10),
      TextField(controller:userId,decoration:const InputDecoration(
        labelText:'معرف المستخدم UUID',border:OutlineInputBorder())),
      DropdownButtonFormField<String>(
        initialValue:role,
        items:const [
          DropdownMenuItem(value:'writer',child:Text('كاتب')),
          DropdownMenuItem(value:'editor',child:Text('محرر')),
          DropdownMenuItem(value:'moderator',child:Text('مشرف')),
        ],
        onChanged:(v)=>setState(()=>role=v??role)),
      FilledButton.icon(
        onPressed:busy?null:(){
          if(!RegExp(r'^[0-9a-fA-F]{8}(?:-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$')
              .hasMatch(userId.text.trim())){notice('أدخل UUID صحيحاً.');return;}
          action('alani_set_content_staff',{
            'p_user_id':userId.text.trim(),'p_role':role,'p_enabled':true});
        },
        icon:const Icon(Icons.person_add),label:const Text('منح الدور')),
      const Divider(),
      for(final row in rows)ListTile(
        title:Text(row['user_id']?.toString()??''),
        subtitle:Text('الدور: '+(row['role']??'').toString()),
        trailing:IconButton(
          tooltip:'سحب الصلاحية',
          onPressed:busy?null:()=>action('alani_set_content_staff',{
            'p_user_id':row['user_id'],'p_role':row['role'],'p_enabled':false}),
          icon:const Icon(Icons.person_remove_outlined))),
    ],
  );
  @override
  void dispose(){userId.dispose();super.dispose();}
  @override
  Widget build(BuildContext context)=>DefaultTabController(
    length:3,child:Scaffold(
      appBar:AppBar(
        title:const Text('إشراف السيد إبراهيم العاني'),
        actions:[IconButton(onPressed:refresh,icon:const Icon(Icons.refresh))],
        bottom:const TabBar(tabs:[
          Tab(text:'التعليقات'),Tab(text:'البلاغات'),Tab(text:'الكتّاب')]),
      ),
      body:FutureBuilder<List<List<Map<String,dynamic>>>>(
        future:query,builder:(context,snap){
          if(snap.connectionState!=ConnectionState.done){
            return const Center(child:CircularProgressIndicator());
          }
          if(snap.hasError){
            return Center(child:TextButton(onPressed:refresh,
              child:const Text('الإشراف غير متاح — إعادة المحاولة')));
          }
          final x=snap.data!;
          return TabBarView(children:[
            comments(x[0]),reports(x[1]),staff(x[2])]);
        }),
    ),
  );
}
