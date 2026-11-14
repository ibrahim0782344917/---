import 'package:flutter/material.dart';
import 'package:shitreed_merchant/account/merchant_account_service.dart';
import 'package:shitreed_merchant/account/merchant_legal_pages.dart';
import 'package:shitreed_merchant/account/merchant_support_pages.dart';
import 'package:shitreed_merchant/shared/merchant_widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class MerchantAccountPage extends StatelessWidget {
  const MerchantAccountPage({super.key});

  void _go(BuildContext context,Widget screen) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder:(_)=>screen));
  }

  @override
  Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:const Text('الحساب والإعدادات')),
    body:SafeArea(child:ListView(padding:const EdgeInsets.all(16),
      children:[
        Container(
          padding:const EdgeInsets.all(20),
          decoration:BoxDecoration(
            borderRadius:BorderRadius.circular(23),
            gradient:const LinearGradient(
              colors:[merchantDark,merchantPurple])),
          child:Column(
            crossAxisAlignment:CrossAxisAlignment.start,children:[
              const Icon(Icons.account_circle_outlined,
                size:47,color:Colors.white),
              const SizedBox(height:8),
              const Text('حساب التاجر',style:TextStyle(
                color:Colors.white,fontSize:25,
                fontWeight:FontWeight.w900)),
              const SizedBox(height:4),
              Text(MerchantAccountService.accountEmail??'',
                style:const TextStyle(color:Colors.white70)),
              const SizedBox(height:10),
              const Text('التحكم ببيانات حسابك وخصوصيته',
                style:TextStyle(color:Colors.white70)),
            ]),
        ),
        const SizedBox(height:22),
        const _Heading('المساعدة'),
        _SettingTile(Icons.support_agent_outlined,
          'مركز الدعم','افتح طلباً وتابعه',
          ()=>_go(context,const MerchantSupportPage())),
        _SettingTile(Icons.help_outline,'الأسئلة الشائعة',
          'إرشادات إدارة الحساب والمتجر',
          ()=>_go(context,const MerchantFaqPage())),
        const SizedBox(height:14),
        const _Heading('المعلومات والقوانين'),
        _SettingTile(Icons.privacy_tip_outlined,
          'سياسة الخصوصية','حماية البيانات واستخدامها',
          ()=>_go(context,const MerchantLegalPage(
            title:'سياسة الخصوصية',
            sections:merchantPrivacySections))),
        _SettingTile(Icons.gavel_outlined,
          'الشروط والأحكام','التزامات التجار وسياسة الطلبات',
          ()=>_go(context,const MerchantLegalPage(
            title:'الشروط والأحكام',sections:merchantTermsSections))),
        _SettingTile(Icons.info_outline,
          'معلومات المطوّر والتطبيق','التواصل والنسخة والهوية',
          ()=>_go(context,const MerchantAboutPage())),
        const SizedBox(height:14),
        const _Heading('أمان الحساب'),
        _SettingTile(Icons.person_remove_outlined,
          'طلب حذف الحساب','إرسال طلب رسمي ومتابعته',
          ()=>_go(context,const MerchantDeleteAccountPage())),
        const SizedBox(height:18),
        OutlinedButton.icon(
          onPressed:() async {
            final approved=await showDialog<bool>(
              context:context,builder:(dialog)=>AlertDialog(
                title:const Text('تسجيل الخروج'),
                content:const Text('تريد تطلع من حساب شتريد تاجر؟'),
                actions:[
                  TextButton(onPressed:()=>Navigator.pop(dialog,false),
                    child:const Text('إلغاء')),
                  FilledButton(onPressed:()=>Navigator.pop(dialog,true),
                    child:const Text('تسجيل الخروج')),
                ],
              ));
            if(approved==true){
              await Supabase.instance.client.auth.signOut();
            }
          },
          icon:const Icon(Icons.logout),
          label:const Text('تسجيل الخروج')),
        const SizedBox(height:13),
        const Text('شتريد تاجر • نسخة تجريبية',
          textAlign:TextAlign.center,
          style:TextStyle(color:Colors.black54,fontSize:12)),
      ]))),
  );
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);
  final String text;
  @override
  Widget build(BuildContext context)=>Padding(
    padding:const EdgeInsets.only(bottom:9),
    child:Text(text,style:const TextStyle(
      color:merchantDark,fontSize:18,fontWeight:FontWeight.w900)));
}

class _SettingTile extends StatelessWidget {
  const _SettingTile(this.icon,this.title,this.subtitle,this.onTap);
  final IconData icon;
  final String title,subtitle;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context)=>Card(
    color:Colors.white,margin:const EdgeInsets.only(bottom:8),
    child:ListTile(
      onTap:onTap,
      leading:CircleAvatar(
        backgroundColor:const Color(0xFFEFE1FA),
        child:Icon(icon,color:merchantPurple)),
      title:Text(title,
        style:const TextStyle(fontWeight:FontWeight.w800)),
      subtitle:Text(subtitle,
        style:const TextStyle(fontSize:12)),
      trailing:const Icon(Icons.chevron_left),
    ));
}
