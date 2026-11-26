import 'package:flutter/material.dart';
import 'alani_support_chat.dart';

/// Searchable store FAQ, not a generative AI service. No network query or medical advice.
class AlAniHelpCenterPage extends StatefulWidget {
  const AlAniHelpCenterPage({super.key});
  @override
  State<AlAniHelpCenterPage> createState()=>_AlAniHelpCenterPageState();
}
class _AlAniHelpCenterPageState extends State<AlAniHelpCenterPage>{
  String query='';
  static const entries=<(String,String)>[
    ('كيف أدفع قيمة الطلب؟','الدفع الحالي نقداً عند الاستلام. شحن المحفظة الإلكترونية غير متاح حالياً.'),
    ('كم أجور التوصيل؟','أجور الطلب العادي 5,000 دينار عراقي. راجع المجموع الظاهر قبل التأكيد.'),
    ('كيف أتابع طلبي؟','افتح سجل طلباتك لمراجعة الحالة الحالية. لا يعرض هذا الإصدار موقع المندوب المباشر.'),
    ('كيف ألغي طلبي؟','افتح تفاصيل الطلب. الإلغاء متاح قبل قبول المتجر عندما يظهر خيار الإلغاء. إذا لم يظهر، تواصل مع المتجر.'),
    ('ماذا أفعل إذا وصل منتج مكسور أو غير مطابق؟','احتفظ برقم الطلب ووصف المشكلة وصور الضرر إن أمكن، وتواصل مع المتجر لمراجعتها. لا ترسل معلومات مالية أو صحية حساسة في الرسائل.'),
    ('كيف أتواصل مع فريق الدعم؟','استخدم الدردشة الخاصة بالمتجر عندما تكون متاحة في إصدارك.'),
    ('هل أستطيع شحن المحفظة أو إرسال حوالة؟','الشحن والرصيد المالي غير مفعّلين حالياً. لا تحول أموالاً بناءً على هذه الصفحة.'),
    ('هل المفضلة ترسل إشعارات عند انخفاض الأسعار؟','تُراجع مؤشرات السعر والمخزون عند فتح المفضلة وتحديثها. إرسال الإشعارات الخارجية غير مفعّل حالياً.'),
    ('هل وصفات الأعشاب تعالج الأمراض؟','المحتوى للتثقيف وليس تشخيصاً أو وصفة علاجية. استشر مختصاً صحياً.'),
  ];
  static String normalized(String s)=>s.toLowerCase().replaceAll(RegExp(r'[\u064B-\u065F\u0670\u0640]'),'').replaceAll(RegExp('[أإآ]'),'ا').replaceAll('ى','ي').trim();
  @override
  Widget build(BuildContext context){
    final words=normalized(query).split(RegExp(r'\s+')).where((s)=>s.isNotEmpty).toList();
    final matches=entries.where((entry)=>words.every((w)=>normalized(entry.$1+' '+entry.$2).contains(w))).toList();
    return Scaffold(appBar:AppBar(title:const Text('مركز المساعدة')),
      body:ListView(padding:const EdgeInsets.all(16),children:[
        const Card(child:ListTile(leading:Icon(Icons.help_outline),title:Text('الأسئلة الشائعة'),
          subtitle:Text('ابحث عن إجابات المتجر. هذا بحث في معلومات ثابتة وليس مساعد ذكاء اصطناعي.'))),
        const SizedBox(height:12),
        TextField(maxLength:120,onChanged:(v)=>setState(()=>query=v),
          decoration:const InputDecoration(prefixIcon:Icon(Icons.search),labelText:'ابحث عن الدفع أو التوصيل أو الطلب')),
        if(matches.isEmpty)const ListTile(title:Text('لا توجد إجابة مطابقة. جرّب كلمة أخرى أو تواصل مع الدعم.')),
        for(final entry in matches)Card(child:ExpansionTile(title:Text(entry.$1),
          children:[Padding(padding:const EdgeInsets.all(16),child:Text(entry.$2))])),
        const SizedBox(height:16),
        if(AlAniSupportFeature.enabled)FilledButton.icon(
          onPressed:()=>Navigator.of(context).push<void>(MaterialPageRoute(builder:(_)=>const AlAniCustomerSupportPage())),
          icon:const Icon(Icons.chat_bubble_outline),label:const Text('تواصل مع فريق الدعم')),
      ]));
  }
}
