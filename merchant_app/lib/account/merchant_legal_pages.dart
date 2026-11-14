import 'package:flutter/material.dart';
import 'package:shitreed_merchant/shared/merchant_widgets.dart';

class LegalSection {
  final String title, body;
  const LegalSection(this.title,this.body);
}

const merchantPrivacySections = <LegalSection>[
  LegalSection('عن تطبيق شتريد تاجر',
    'هذه سياسة خصوصية تطبيق شتريد تاجر لإدارة المتاجر والمنتجات '
    'وطلبات الزبائن في العراق. يلزم تأكيد اسم الناشر القانوني '
    'وبريد الدعم قبل النشر على Google Play.'),
  LegalSection('بيانات الحساب والمتاجر',
    'تُعالج هوية المستخدم والبريد الإلكتروني عبر Supabase Auth. '
    'ويمكن للتاجر إدخال اسم المتجر والعنوان والمنطقة والهاتف والشعار '
    'والوصف وأوقات الدوام وإحداثيات موقع المحل.'),
  LegalSection('المنتجات والطلبات',
    'نستخدم أسماء المنتجات والصور والأسعار والمخزون، '
    'وعنوان الزبون ورقم هاتفه وملاحظات التوصيل وتفاصيل طلبه '
    'والمراحل اللازمة لتجهيز الطلب. بيانات الطلب لا تُعرض '
    'إلا للأطراف المخوّلة وفق صلاحيات قاعدة البيانات.'),
  LegalSection('المشاركة والمزوّدون',
    'يستخدم التطبيق Supabase للحسابات والتخزين والبيانات، '
    'وتظهر للزبائن بيانات المتاجر المعتمدة والمنتجات المنشورة. '
    'صور المنتجات عامة حسب إعدادات التخزين. '
    'لا توجد بوابة دفع إلكتروني مفعّلة حالياً.'),
  LegalSection('حماية البيانات',
    'نستخدم اتصالات HTTPS وصلاحيات Row Level Security. '
    'لا تُحفظ كلمات المرور بنص ظاهر داخل جداول المتاجر، '
    'ولا تُضمّن مفاتيح إدارة Supabase في تطبيق Android.'),
  LegalSection('الاحتفاظ والحذف',
    'يمكنك تقديم طلب حذف حساب من الإعدادات. الطلب يُسجَّل '
    'للمراجعة ولا يحذف الحساب تلقائياً. قد تستلزم الطلبات '
    'والمعاملات الاحتفاظ ببعض السجلات لالتزامات قانونية. '
    'يجب تحديد مدد الاحتفاظ رسمياً قبل الإطلاق.'),
  LegalSection('الدعم والتواصل',
    'يمكن إرسال طلب دعم من داخل التطبيق بعد تسجيل الدخول. '
    'يلزم نشر بريد دعم رسمي وصفحة سياسة خصوصية عامة متاحة '
    'من دون تسجيل دخول قبل تقديم التطبيق إلى Google Play.'),
];

const merchantTermsSections = <LegalSection>[
  LegalSection('فتح حساب تاجر',
    'يُسجل التاجر بريداً صحيحاً، ويقدّم بيانات متجره '
    'ويؤكد ملكيته. تسجيل الحساب لا يساوي اعتماد المتجر.'),
  LegalSection('المنتجات والمخزون',
    'التاجر مسؤول عن دقة الأوصاف والصور والأسعار والكميات، '
    'واحترام حقوق الصور والملكية الفكرية وقوانين البيع.'),
  LegalSection('المبيعات',
    'الطلبات الحالية بالدفع عند الاستلام فقط. '
    'قبول الطلب وتحضيره لا يثبت تحصيل المبلغ أو تسليمه.'),
  LegalSection('السلع المحظورة',
    'يُمنع نشر مواد غير قانونية أو مقلدة أو مضللة أو انتحال '
    'ملكية المحلات أو إساءة استخدام بيانات الزبائن.'),
  LegalSection('الدعم والنزاعات',
    'يمكن تقديم شكاوى عبر مركز الدعم. سياسة الاسترجاع '
    'والتوصيل والتحصيل المالي ما زالت تحتاج اعتماداً تشغيلياً.'),
  LegalSection('الخدمات المستقبلية',
    'الإعلانات المدفوعة، بوابة الدفع الإلكتروني، '
    'وتتبع المندوب والإيرادات المصرفية ليست مفعلة في '
    'الإصدار التجريبي الحالي.'),
];

class MerchantLegalPage extends StatelessWidget {
  const MerchantLegalPage({super.key,required this.title,
    required this.sections});
  final String title;
  final List<LegalSection> sections;
  @override
  Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:Text(title)),
    body:SafeArea(child:ListView(padding:const EdgeInsets.all(16),
      children:[
        const Icon(Icons.verified_user_outlined,
          size:56,color:merchantPurple),
        const SizedBox(height:10),
        Text(title,textAlign:TextAlign.center,
          style:const TextStyle(fontSize:24,color:merchantDark,
            fontWeight:FontWeight.w900)),
        const Text('مسودة قبل النشر التجاري',
          textAlign:TextAlign.center,
          style:TextStyle(color:Colors.deepOrange)),
        const SizedBox(height:18),
        for(final section in sections)Card(
          color:Colors.white,margin:const EdgeInsets.only(bottom:10),
          child:Padding(padding:const EdgeInsets.all(15),
            child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,
              children:[
                Text(section.title,style:const TextStyle(
                  fontWeight:FontWeight.w900,color:merchantDark,
                  fontSize:17)),
                const SizedBox(height:8),
                Text(section.body,
                  style:const TextStyle(height:1.6)),
              ]))),
      ]))),
  );
}

class MerchantAboutPage extends StatelessWidget {
  const MerchantAboutPage({super.key});
  @override
  Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:const Text('معلومات المطوّر والتطبيق')),
    body:SafeArea(child:ListView(padding:const EdgeInsets.all(16),
      children:[
        Container(
          padding:const EdgeInsets.all(25),
          decoration:BoxDecoration(
            borderRadius:BorderRadius.circular(22),
            gradient:const LinearGradient(
              colors:[merchantDark,merchantPurple])),
          child:const Column(children:[
            Icon(Icons.storefront_rounded,
              color:merchantOrange,size:75),
            SizedBox(height:8),
            Text('شتريد تاجر',style:TextStyle(
              fontSize:28,fontWeight:FontWeight.w900,
              color:Colors.white)),
            Text('كل متجرك بين إيديك',
              style:TextStyle(color:Colors.white70)),
          ]),
        ),
        const SizedBox(height:20),
        const _Info('اسم التطبيق','شتريد تاجر'),
        const _Info('معرّف Android',
          'com.shitreed.shitreed_merchant'),
        const _Info('جهة التطوير',
          'مشروع شتريد — يحتاج تأكيد الاسم القانوني'),
        const _Info('الموقع','بغداد، العراق'),
        const _Info('التواصل','مركز المساعدة داخل التطبيق'),
        const _Info('بريد المطوّر العام',
          'لم يُحدَّد — مطلوب قبل النشر'),
        const _Info('رابط السياسة الخارجي',
          'بانتظار استضافة صفحة عامة بدون تسجيل'),
        const SizedBox(height:18),
        const Text('الإصدار الحالي اختبار تجريبي، '
          'وليس إعلان جاهزية الدفع الإلكتروني أو خدمات التوصيل.',
          textAlign:TextAlign.center,
          style:TextStyle(color:Colors.black54)),
      ]))),
  );
}

class _Info extends StatelessWidget {
  const _Info(this.label,this.value);
  final String label,value;
  @override
  Widget build(BuildContext context)=>Card(
    color:Colors.white,child:Padding(
      padding:const EdgeInsets.all(15),
      child:Column(crossAxisAlignment:CrossAxisAlignment.start,
        children:[
          Text(label,style:const TextStyle(
            color:Colors.black54,fontSize:12)),
          const SizedBox(height:4),
          SelectableText(value,style:const TextStyle(
            color:merchantDark,fontWeight:FontWeight.w800)),
        ])));
}

class MerchantFaqPage extends StatelessWidget {
  const MerchantFaqPage({super.key});
  @override
  Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:const Text('الأسئلة الشائعة')),
    body:SafeArea(child:ListView(
      padding:const EdgeInsets.all(15),children:const[
        _Faq('شلون أفتح حساب تاجر؟',
          'من شاشة الدخول اختر إنشاء حساب، أكد بريدك '
          'ثم قدم طلب تسجيل متجر وتحقق من ملكيته.'),
        _Faq('ليش متجري ما يظهر؟',
          'لا يظهر المتجر في تطبيق الزبائن '
          'إلا بعد موافقة الإدارة على ملكيته.'),
        _Faq('شلون أضيف منتج؟',
          'من قسم المنتجات اختر محلك، ثم أضف الاسم '
          'والسعر والكمية والصورة واحفظه.'),
        _Faq('أكدر أعدل أو أخفي منتج؟',
          'إي، من خيارات المنتج عدّل البيانات أو '
          'اخفِ المنتج وأعد نشره بدون حذف تاريخ الطلبات.'),
        _Faq('الدفع الإلكتروني موجود؟',
          'حالياً فقط تسجيل طلبات الدفع عند الاستلام.'),
        _Faq('شلون أطلب حذف الحساب؟',
          'من الحساب والإعدادات اختر طلب حذف الحساب، '
          'واكمل التأكيد ليُسجل طلب مراجعة حقيقي.'),
      ]))),
  );
}

class _Faq extends StatelessWidget {
  const _Faq(this.question,this.answer);
  final String question,answer;
  @override
  Widget build(BuildContext context)=>Card(
    color:Colors.white,child:ExpansionTile(
      title:Text(question,style:const TextStyle(
        fontWeight:FontWeight.w800)),
      children:[Padding(
        padding:const EdgeInsets.fromLTRB(16,0,16,16),
        child:Text(answer,style:const TextStyle(height:1.6)),
      )],
    ));
}
