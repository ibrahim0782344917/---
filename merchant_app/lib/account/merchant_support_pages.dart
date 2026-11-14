// ignore_for_file: prefer_interpolation_to_compose_strings
import 'package:flutter/material.dart';
import 'package:shitreed_merchant/account/merchant_account_service.dart';
import 'package:shitreed_merchant/shared/merchant_widgets.dart';

class MerchantSupportPage extends StatefulWidget {
  const MerchantSupportPage({super.key});
  @override
  State<MerchantSupportPage> createState()=>_MerchantSupportPageState();
}

class _MerchantSupportPageState extends State<MerchantSupportPage> {
  final _subject=TextEditingController();
  final _message=TextEditingController();
  late Future<List<Map<String,dynamic>>> _tickets;
  bool _sending=false;
  @override
  void initState(){super.initState();_tickets=MerchantAccountService.myTickets();}
  @override
  void dispose(){_subject.dispose();_message.dispose();super.dispose();}

  Future<void> _refresh() async {
    final result=MerchantAccountService.myTickets();
    setState((){_tickets=result;});
    await result;
  }

  Future<void> _send() async {
    if(_sending)return;
    if(_subject.text.trim().length<5||_message.text.trim().length<15){
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content:Text('اكتب عنواناً وتفاصيل واضحة لا تقل عن 15 حرفاً.')));
      return;
    }
    setState((){_sending=true;});
    try {
      final id=await MerchantAccountService.openSupportTicket(
        subject:_subject.text,message:_message.text);
      if(!mounted)return;
      _subject.clear();
      _message.clear();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content:Text('انرسل طلب الدعم. رقمه: '+id.substring(0,8))));
      await _refresh();
    }catch(_){
      if(mounted)ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content:Text('تعذر إرسال طلب الدعم. '
          'تحقق من الاتصال أو جرّب بعدين، الحد اليومي 5 طلبات.')));
    }finally{
      if(mounted)setState((){_sending=false;});
    }
  }
  @override
  Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:const Text('الدعم والمساعدة')),
    body:SafeArea(child:RefreshIndicator(
      onRefresh:_refresh,
      child:ListView(padding:const EdgeInsets.all(16),
        children:[
          const Text('تواصل مع شتريد',style:TextStyle(
            fontSize:23,fontWeight:FontWeight.w900,
            color:merchantDark)),
          const SizedBox(height:6),
          const Text('الطلبات تُسجل فعلياً في Supabase. '
            'تحتاج ردود الدعم إلى فريق تشغيل معتمد.',
            style:TextStyle(color:Colors.black54)),
          const SizedBox(height:18),
          TextField(controller:_subject,maxLength:120,
            decoration:const InputDecoration(
              labelText:'عنوان المشكلة',border:OutlineInputBorder())),
          const SizedBox(height:10),
          TextField(controller:_message,minLines:4,maxLines:7,maxLength:2000,
            decoration:const InputDecoration(
              labelText:'تفاصيل المشكلة أو رقم الطلب',
              border:OutlineInputBorder())),
          FilledButton.icon(
            onPressed:_sending?null:_send,
            style:FilledButton.styleFrom(
              backgroundColor:merchantPurple),
            icon:const Icon(Icons.send_outlined),
            label:Text(_sending?'جاري الإرسال...':'إرسال طلب للدعم')),
          const SizedBox(height:24),
          const Text('طلباتي السابقة',style:TextStyle(
            color:merchantDark,fontSize:19,fontWeight:FontWeight.w900)),
          const SizedBox(height:12),
          FutureBuilder<List<Map<String,dynamic>>>(
            future:_tickets,
            builder:(context,snapshot){
              if(snapshot.connectionState!=ConnectionState.done){
                return const Center(child:CircularProgressIndicator());
              }
              if(snapshot.hasError){
                return const Text('تعذر جلب طلبات الدعم.');
              }
              final rows=snapshot.data??[];
              if(rows.isEmpty)return const Padding(
                padding:EdgeInsets.all(18),
                child:Text('ماكو طلبات دعم سابقة.',
                  textAlign:TextAlign.center));
              return Column(children:[
                for(final row in rows)Card(
                  color:Colors.white,
                  child:ListTile(
                    leading:const Icon(Icons.support_agent,
                      color:merchantPurple),
                    title:Text(row['subject'] as String? ?? ''),
                    subtitle:Text('الحالة: '+(row['status']?.toString()??'')),
                    trailing:Text(
                      (row['id'] as String).substring(0,8),
                      style:const TextStyle(fontSize:11)),
                  )),
              ]);
            }),
        ]))),
  );
}

class MerchantDeleteAccountPage extends StatefulWidget {
  const MerchantDeleteAccountPage({super.key});
  @override
  State<MerchantDeleteAccountPage> createState()=>
      _MerchantDeleteAccountPageState();
}
class _MerchantDeleteAccountPageState
    extends State<MerchantDeleteAccountPage> {
  final _note=TextEditingController();
  late Future<List<Map<String,dynamic>>> _requests;
  bool _understood=false,_sending=false;
  @override
  void initState(){super.initState();_requests=MerchantAccountService.myDeletionRequests();}
  @override
  void dispose(){_note.dispose();super.dispose();}
  Future<void> _refresh() async {
    final next=MerchantAccountService.myDeletionRequests();
    setState((){_requests=next;});
    await next;
  }
  Future<void> _submit() async {
    if(_sending||!_understood)return;
    setState((){_sending=true;});
    try{
      final id=await MerchantAccountService.requestAccountDeletion(
        _note.text.trim());
      if(!mounted)return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        duration:const Duration(seconds:6),
        content:Text('تم تسجيل طلب حذف الحساب '+id.substring(0,8)+
          '. الحساب ما انحذف بعد.')));
      await _refresh();
    }catch(_){
      if(mounted)ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content:Text('تعذر إرسال طلب حذف الحساب.')));
    }finally{
      if(mounted)setState((){_sending=false;});
    }
  }
  @override
  Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:const Text('حذف حساب التاجر')),
    body:SafeArea(child:RefreshIndicator(
      onRefresh:_refresh,
      child:ListView(padding:const EdgeInsets.all(16),
        children:[
          const Icon(Icons.person_remove_outlined,
            size:58,color:Colors.deepOrange),
          const SizedBox(height:12),
          const Text('طلب حذف حساب شتريد تاجر',
            textAlign:TextAlign.center,style:TextStyle(
              fontSize:23,fontWeight:FontWeight.w900,
              color:merchantDark)),
          const SizedBox(height:16),
          const Text('يُسجَّل طلبك في النظام للمراجعة '
            'والتحقق من ملكية الحساب والطلبات المرتبطة بمتاجرك. '
            'هذا ليس حذفاً فورياً. ينبغي على فريق المنصة '
            'إكمال معالجة الحذف وإبلاغك بأي بيانات يلزم '
            'الاحتفاظ بها قانونياً.',
            style:TextStyle(height:1.6)),
          const SizedBox(height:16),
          TextField(controller:_note,maxLength:1000,
            minLines:3,maxLines:6,
            decoration:const InputDecoration(
              labelText:'سبب الطلب أو ملاحظات (اختياري)',
              border:OutlineInputBorder())),
          CheckboxListTile(
            value:_understood,
            onChanged:(checked)=>setState((){
              _understood=checked??false;
            }),
            title:const Text('أؤكد طلب حذف حسابي '
              'وأفهم أن المعالجة ليست فورية.'),
            controlAffinity:ListTileControlAffinity.leading,
          ),
          FilledButton.icon(
            onPressed:_understood&&!_sending?_submit:null,
            style:FilledButton.styleFrom(
              backgroundColor:Colors.deepOrange),
            icon:const Icon(Icons.delete_outline),
            label:Text(_sending?'جاري تسجيل الطلب...':
              'إرسال طلب حذف الحساب')),
          const SizedBox(height:24),
          const Text('حالة طلباتي',style:TextStyle(
            color:merchantDark,fontSize:19,fontWeight:FontWeight.w900)),
          FutureBuilder<List<Map<String,dynamic>>>(
            future:_requests,builder:(context,snapshot){
              if(snapshot.connectionState!=ConnectionState.done){
                return const Center(child:CircularProgressIndicator());
              }
              if(snapshot.hasError){
                return const Text('تعذر تحميل حالة الطلبات.');
              }
              final rows=snapshot.data??[];
              if(rows.isEmpty)return const Text('لا توجد طلبات سابقة.');
              return Column(children:[
                for(final row in rows)Card(color:Colors.white,
                  child:ListTile(
                    leading:const Icon(Icons.description_outlined,
                      color:merchantPurple),
                    title:Text('الحالة: '+row['status'].toString()),
                    subtitle:Text('التاريخ: '+row['created_at'].toString()),
                  )),
              ]);
            }),
          const SizedBox(height:16),
          const Text('للنشر على Google Play يلزم '
            'توفير رابط عام لحذف الحساب خارج التطبيق أيضاً.',
            style:TextStyle(color:Colors.deepOrange,fontSize:12)),
        ]))),
  );
}
