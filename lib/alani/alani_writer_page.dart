import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shitreed_customer/alani/alani_content.dart';
import 'package:shitreed_customer/alani/alani_editor.dart';

/// Writers can create their own drafts only; editors publish via Admin.
class AlAniWriterPage extends StatefulWidget {
  const AlAniWriterPage({super.key});
  @override
  State<AlAniWriterPage> createState() => _AlAniWriterState();
}
class _AlAniWriterState extends State<AlAniWriterPage> {
  late Future<List<Map<String,dynamic>>> drafts;
  bool saving=false;
  SupabaseClient get db => Supabase.instance.client;
  @override
  void initState(){super.initState();drafts=_load();}
  static Future<bool> authorized() async {
    final db=Supabase.instance.client;
    final me=db.auth.currentUser;
    if(me==null)return false;
    if(await AlAniEditorService.isOwner())return true;
    try{
      final row=await db.from('alani_content_staff').select('role')
        .eq('store_id',AlAniSettings.storeId).eq('user_id',me.id)
        .maybeSingle();
      return row!=null &&
        ['writer','editor','moderator'].contains(row['role']) &&
        row['role']!='moderator';
    }catch(_){return false;}
  }
  Future<List<Map<String,dynamic>>> _load() async {
    if(db.auth.currentUser==null)return [];
    final rows=await db.from('alani_publications')
      .select('id,kind,title,body,status,created_at')
      .eq('store_id',AlAniSettings.storeId)
      .eq('created_by',db.auth.currentUser!.id)
      .eq('status','draft').order('created_at',ascending:false).limit(100);
    return rows.map((r)=>Map<String,dynamic>.from(r)).toList();
  }
  Future<void> refresh()async {
    final next=_load();
    if(mounted)setState(()=>drafts=next);
    try{await next;}catch(_){/* FutureBuilder displays error. */}
  }
  void inform(String message){
    if(mounted)ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content:Text(message)));
  }
  Future<void> edit([Map<String,dynamic>? original])async {
    final title=TextEditingController(text:original?['title']?.toString()??'');
    final body=TextEditingController(text:original?['body']?.toString()??'');
    String kind=original?['kind']?.toString()??'article';
    if(!['article','recipe','post'].contains(kind))kind='article';
    await showDialog<void>(
      context:context,
      builder:(dialog)=>StatefulBuilder(
        builder:(ctx,setDialog)=>AlertDialog(
          title:Text(original==null?'مسودة جديدة':'تعديل مسودتي'),
          content:SizedBox(width:440,child:SingleChildScrollView(
            child:Column(mainAxisSize:MainAxisSize.min,children:[
              DropdownButtonFormField<String>(
                initialValue:kind,
                items:const [
                  DropdownMenuItem(value:'article',child:Text('مقال')),
                  DropdownMenuItem(value:'recipe',child:Text('وصفة')),
                  DropdownMenuItem(value:'post',child:Text('منشور')),
                ],
                onChanged:saving?null:(value)=>setDialog(()=>kind=value??kind)),
              TextField(controller:title,maxLength:180,
                decoration:const InputDecoration(labelText:'العنوان')),
              TextField(controller:body,minLines:4,maxLines:9,maxLength:10000,
                decoration:const InputDecoration(labelText:'نص المسودة')),
              const Text('المسودة لا تظهر للزبائن حتى ينشرها المحرر أو المالك.'),
            ]),
          )),
          actions:[
            TextButton(onPressed:saving?null:()=>Navigator.pop(ctx),
              child:const Text('إلغاء')),
            FilledButton(
              onPressed:saving?null:()async{
                if(title.text.trim().length<3){
                  inform('عنوان المسودة يجب أن يحتوي ٣ أحرف على الأقل.');
                  return;
                }
                setDialog(()=>saving=true);
                try{
                  await db.rpc('alani_save_writer_draft',params:{
                    'p_id':original?['id'],
                    'p_kind':kind,
                    'p_title':title.text.trim(),
                    'p_body':body.text.trim(),
                  });
                  if(ctx.mounted)Navigator.pop(ctx);
                  await refresh();inform('انحفظت المسودة بنجاح.');
                }catch(_){inform('تعذر حفظ المسودة. تحقق من صلاحية الكاتب.');}
                finally{if(ctx.mounted)setDialog(()=>saving=false);}
              },
              child:const Text('حفظ مسودة')),
          ],
        ),
      ),
    );
    title.dispose();body.dispose();
  }
  @override
  Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:const Text('مسوداتي — السيد إبراهيم العاني'),
      actions:[IconButton(onPressed:refresh,
        tooltip:'تحديث',icon:const Icon(Icons.refresh))]),
    floatingActionButton:FloatingActionButton.extended(
      onPressed:()=>edit(),icon:const Icon(Icons.edit),
      label:const Text('كتابة مسودة')),
    body:FutureBuilder<List<Map<String,dynamic>>>(
      future:drafts,builder:(context,snap){
        if(snap.connectionState!=ConnectionState.done){
          return const Center(child:CircularProgressIndicator());
        }
        if(snap.hasError){
          return Center(child:TextButton(onPressed:refresh,
            child:const Text('تعذر عرض المسودات. إعادة المحاولة')));
        }
        final rows=snap.data!;
        if(rows.isEmpty)return const Center(child:Text(
          'ما عندك مسودات بعد. اضغط كتابة مسودة.'));
        return ListView.builder(
          padding:const EdgeInsets.all(13),itemCount:rows.length,
          itemBuilder:(context,i){
            final item=rows[i];
            return Card(child:ListTile(
              leading:const Icon(Icons.drafts_outlined),
              title:Text(item['title']?.toString()??''),
              subtitle:Text(item['body']?.toString()??'',
                maxLines:2,overflow:TextOverflow.ellipsis),
              trailing:const Icon(Icons.edit_outlined),
              onTap:()=>edit(item),
            ));
          },
        );
      },
    ),
  );
}
