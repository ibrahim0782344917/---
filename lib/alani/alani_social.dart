import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Moderated social engagement for published Al-Ani content.
/// Never pretends to save interactions when its database feature is disabled.
class AlAniSocialActions extends StatefulWidget {
  const AlAniSocialActions({super.key,required this.publicationId,this.dark=false});
  final String publicationId;
  final bool dark;
  @override
  State<AlAniSocialActions> createState()=>_AlAniSocialActionsState();
}

class _AlAniSocialActionsState extends State<AlAniSocialActions> {
  static const enabled=bool.fromEnvironment('ALANI_SOCIAL_ENABLED',
    defaultValue:false);
  SupabaseClient get db=>Supabase.instance.client;
  int likes=0,comments=0;
  bool liked=false,saved=false,busy=false;

  @override
  void initState(){super.initState();if(enabled)_refresh();}

  void notice(String message){
    if(mounted)ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content:Text(message)));
  }

  Future<void> _refresh()async {
    if(!enabled)return;
    try{
      final stats=Map<String,dynamic>.from(await db.rpc(
        'alani_social_stats',params:{'p_publication_id':widget.publicationId}) as Map);
      final uid=db.auth.currentUser?.id;
      final own=uid==null?<Map<String,dynamic>>[]:
        await db.from('alani_publication_reactions').select('action')
          .eq('publication_id',widget.publicationId).eq('user_id',uid);
      if(mounted)setState((){
        likes=(stats['likes'] as num?)?.toInt()??0;
        comments=(stats['comments'] as num?)?.toInt()??0;
        liked=own.any((v)=>v['action']=='like');
        saved=own.any((v)=>v['action']=='save');
      });
    }catch(_){notice('تعذر جلب التفاعلات.');}
  }

  Future<void> toggle(String action)async {
    if(!enabled||busy)return;
    final uid=db.auth.currentUser?.id;
    if(uid==null){notice('سجّل دخولك أولاً.');return;}
    setState(()=>busy=true);
    try{
      if(action=='like'?liked:saved){
        await db.from('alani_publication_reactions').delete()
          .eq('publication_id',widget.publicationId)
          .eq('user_id',uid).eq('action',action);
      }else{
        await db.from('alani_publication_reactions').insert({
          'publication_id':widget.publicationId,'action':action});
      }
      await _refresh();
    }catch(_){notice('تعذّر تسجيل التفاعل.');}
    finally{if(mounted)setState(()=>busy=false);}
  }

  Future<void> share()async {
    const base=String.fromEnvironment('ALANI_PUBLIC_URL',
      defaultValue:'https://alani-site-admin-staging.up.railway.app');
    await Clipboard.setData(ClipboardData(
      text:base+'/?post='+widget.publicationId));
    notice('تم نسخ رابط المنشور للمشاركة.');
  }

  Future<void> comment()async {
    if(!enabled)return;
    final uid=db.auth.currentUser?.id;
    if(uid==null){notice('سجّل دخولك أولاً للتعليق.');return;}
    final ctrl=TextEditingController();
    final accepted=await showDialog<bool>(context:context,builder:(ctx)=>
      AlertDialog(title:const Text('إضافة تعليق'),
        content:TextField(controller:ctrl,maxLength:1200,maxLines:4,
          decoration:const InputDecoration(
            labelText:'التعليق ينتظر مراجعة الإشراف')),
        actions:[
          TextButton(onPressed:()=>Navigator.pop(ctx,false),
            child:const Text('إلغاء')),
          FilledButton(onPressed:()=>Navigator.pop(ctx,true),
            child:const Text('إرسال'))
        ]));
    final body=ctrl.text.trim();
    ctrl.dispose();
    if(accepted!=true)return;
    if(body.length<2){notice('أدخل تعليقاً لا يقل عن حرفين.');return;}
    try{
      await db.from('alani_publication_comments').insert({
        'publication_id':widget.publicationId,'body':body});
      notice('تم إرسال التعليق للمراجعة.');await _refresh();
    }catch(_){notice('تعذّر إرسال التعليق.');}
  }

  Future<void> report()async {
    if(!enabled)return;
    if(db.auth.currentUser==null){notice('سجّل دخولك للإبلاغ.');return;}
    try{
      await db.from('alani_publication_reports').insert({
        'publication_id':widget.publicationId,'reason':'other',
        'details':'بلاغ من تطبيق الزبون يتطلب مراجعة المحتوى',
      });
      notice('تم تسجيل البلاغ لدى الإشراف.');
    }catch(_){notice('تعذّر إرسال البلاغ أو لديك بلاغ سابق.');}
  }

  @override
  Widget build(BuildContext context){
    final color=widget.dark?Colors.white:const Color(0xFF0D7850);
    return Wrap(crossAxisAlignment:WrapCrossAlignment.center,spacing:1,
      children:[
        IconButton(tooltip:'إعجاب',onPressed:enabled&&!busy?()=>toggle('like'):null,
          icon:Icon(liked?Icons.favorite:Icons.favorite_border,color:color)),
        Text('$likes',style:TextStyle(color:color)),
        IconButton(tooltip:'حفظ المنشور',onPressed:enabled&&!busy?()=>toggle('save'):null,
          icon:Icon(saved?Icons.bookmark:Icons.bookmark_border,color:color)),
        IconButton(tooltip:'تعليق',onPressed:enabled?comment:null,
          icon:Icon(Icons.comment_outlined,color:color)),
        IconButton(tooltip:'مشاركة الرابط',onPressed:share,
          icon:Icon(Icons.share_outlined,color:color)),
        IconButton(tooltip:'إبلاغ الإشراف',onPressed:enabled?report:null,
          icon:Icon(Icons.flag_outlined,color:color)),
        if(!enabled)const Text('التفاعلات قيد التفعيل',
          style:TextStyle(color:Colors.grey,fontSize:11)),
      ]);
  }
}
