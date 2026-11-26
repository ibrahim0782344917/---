import 'package:flutter/material.dart';
import '../alani_fcm_pilot.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'alani_content.dart';
import 'alani_offers_page.dart';
import 'alani_support_chat.dart';
import 'alani_wallet_page.dart';
import 'alani_help_center_page.dart';
import 'alani_notification_preferences_page.dart';
import 'alani_order_updates.dart';
import 'alani_production_favorites_page.dart';
import 'alani_shop.dart';
import 'package:shitreed_customer/backend/marketplace_backend.dart';
import 'package:shitreed_customer/auth/customer_auth_page.dart';

const _green = Color(0xFF01BE5F);
const _ink = Color(0xFF173E2A);
const _cream = Color(0xFFF5FCF7);

/// UI-only preferences, scoped to the running application. No hidden changes
/// to profiles, orders or Supabase.
class AlAniUiSettings {
  static final darkMode = ValueNotifier<bool>(false);
  static final largeText = ValueNotifier<bool>(false);
}

class AlAniWelcomePage extends StatelessWidget {
  const AlAniWelcomePage({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: _cream,
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 27),
        children: [
          const SizedBox(height: 20),
          const Center(child: CircleAvatar(
            radius: 63,
            backgroundColor: Color(0xFFD6F7E2),
            child: Icon(Icons.spa_outlined,color:_green,size:77),
          )),
          const SizedBox(height: 25),
          const Text('أهلاً وسهلاً بكم',
            textAlign:TextAlign.center,
            style:TextStyle(color:_green,fontSize:18,fontWeight:FontWeight.w800)),
          const SizedBox(height:10),
          const Text(AlAniSettings.title,
            textAlign:TextAlign.center,
            style:TextStyle(color:_ink,fontSize:29,fontWeight:FontWeight.w900)),
          const SizedBox(height:8),
          const Text('للزيوت الطبيعية والأعشاب والعسل',
            textAlign:TextAlign.center,
            style:TextStyle(color:_ink,fontSize:16,fontWeight:FontWeight.w600)),
          const SizedBox(height:17),
          const Text('من الطبيعة إلى بيتك. اكتشف منتجاتنا المتوفرة '
            'وأسعارها، وشاهد الفيديوهات والوصفات والمقالات.',
            textAlign:TextAlign.center,
            style:TextStyle(fontSize:15,height:1.7)),
          const SizedBox(height:25),
          Card(color:Colors.white,child:Padding(
            padding:const EdgeInsets.all(14),
            child:Column(children:[
              const Text('الدفع نقداً عند الاستلام',
                style:TextStyle(color:_ink,fontWeight:FontWeight.bold)),
              const SizedBox(height:5),
              const Text('التوصيل ٥٬٠٠٠ د.ع — الرجوع الاختياري ٥٬٠٠٠ د.ع',
                textAlign:TextAlign.center,
                style:TextStyle(fontSize:12)),
              TextButton(
                onPressed:()=>Navigator.push(context,MaterialPageRoute<void>(
                  builder:(_)=>const AlAniInfoPage(type:'returns'))),
                child:const Text('اطلع على سياسة الاسترجاع والتعويض'),
              ),
            ]),
          )),
          const SizedBox(height:14),
          FilledButton.icon(
            style:FilledButton.styleFrom(
              backgroundColor:_green, foregroundColor:_ink,
              padding:const EdgeInsets.symmetric(vertical:15)),
            onPressed:()=>Navigator.of(context).pushReplacement<void,void>(
              MaterialPageRoute(builder:(_)=>const AlAniShopHome())),
            icon:const Icon(Icons.shopping_bag_outlined),
            label:const Text('الدخول إلى المتجر',
              style:TextStyle(fontWeight:FontWeight.w800)),
          ),
          const SizedBox(height:22),
        ],
      ),
    ),
  );
}

/// Content is authored by the store and reviewed against Iraqi consumer law.
class AlAniInfoPage extends StatelessWidget {
  final String type;
  const AlAniInfoPage({super.key, required this.type});

  static const types = {
    'about':'من نحن',
    'payments':'الدفع والتوصيل',
    'returns':'الاسترجاع والاستبدال',
    'damaged':'تعويض المنتج المكسور',
    'help':'الأسئلة الشائعة',
    'privacy':'سياسة الخصوصية',
    'terms':'الشروط والأحكام',
  };

  @override
  Widget build(BuildContext context) {
    final sections = switch(type) {
      'payments' => const [
        ('الدفع', 'نعتمد الدفع نقداً عند الاستلام فقط. لا تطلب هذه النسخة '
          'بيانات البطاقات أو الدفع الإلكتروني مقدماً.'),
        ('رسوم التوصيل', '٥٬٠٠٠ دينار عراقي للطلب. يظهر المبلغ بوضوح '
          'قبل تأكيد الطلب، وأي اختلاف يحتاج موافقة الزبون.'),
        ('الطلب التجاري', 'تقديم الطلبات من الموقع التجريبي غير مفعل '
          'حتى اكتمال الاختبارات وحماية البيانات.'),
      ],
      'returns' => const [
        ('الاسترجاع بعد الاستلام', 'نقبل تقديم طلب الاسترجاع بعد الاستلام '
          'ومراجعته بحسب سبب الطلب وحالة المنتج والحقوق القانونية.'),
        ('إرجاع اختياري لمنتج سليم', 'أجور التوصيل الأولى ٥٬٠٠٠ د.ع، '
          'وأجور نقل الإرجاع ٥٬٠٠٠ د.ع عندما تُنفذ الخدمتان فعلياً. '
          'يتم تحديد التسوية وفق تفاصيل الطلب والقانون.'),
        ('منتج مكسور أو غير مطابق', 'نعالج الضرر الذي يثبت أنه بسبب '
          'المتجر أو التوصيل، عبر التعويض أو الاستبدال أو رد المبلغ '
          'وفق الحالة. لا تُخصم أجور إرجاع اختيارية في هذه الحالة.'),
        ('كيفية الطلب', 'احتفظ برقم الطلب وجهّز وصف الحالة وصور الضرر '
          'إن توفرت، ثم تواصل مع المتجر إذا كانت صفحة الاسترجاع غير مفعّلة.'),
        ('حقوقك محفوظة', 'الشروط لا تنتقص من الحقوق الإلزامية '
          'للمستهلك بموجب القانون العراقي.'),
      ],
      'damaged' => const [
        ('نضمن معالجة الكسر', 'إذا استلمت زيتاً أو عسلاً أو منتجاً '
          'مكسوراً أو متسرباً بسبب التغليف أو النقل، نراجع الحالة '
          'ونقدّم المعالجة المناسبة بعد التحقق.'),
        ('طريقة التعويض', 'عند ثبوت الضرر الذي لا يرجع إلى سوء '
          'استخدام الزبون، يكون التعويض أو الاستبدال أو رد القيمة '
          'وفق الحالة وحقوقه القانونية.'),
        ('رسوم النقل', 'لا يتحمل الزبون أجور النقل الإضافية '
          'الناشئة عن خطأ ثابت من المتجر أو التوصيل.'),
        ('كيفية الإبلاغ', 'احتفظ بالعلبة وصوّر الضرر إن أمكن، '
          'ثم أرسل رقم الطلب ووصف المشكلة من صفحة طلب الاسترجاع.'),
      ],
      'privacy' => const [
        ('البيانات التي تستخدمها الخدمة', 'لدى تشغيل الطلبات، تتعامل '
          'الخدمة مع البريد الإلكتروني والعنوان ورقم الهاتف والطلبات '
          'لتنفيذ الخدمة، مع حساب Supabase Auth.'),
        ('معلومات الاسترجاع', 'عند تفعيل الخدمة، يعالج المتجر رقم الطلب '
          'وسبب الاسترجاع وتفاصيله ورابط صورة اختياري. '
          'لا تشارك هوية أو بيانات بطاقة مصرفية.'),
        ('الحماية والحقوق', 'تخضع بيانات الطلبات لصلاحيات حساب المشتري '
          'ومالك المتجر. يُستكمل اعتماد سياسة الحذف والاحتفاظ '
          'ووسيلة الاتصال القانونية قبل الإطلاق التجاري.'),
      ],
      'terms' => const [
        ('المتجر والدفع', 'متجر السيد إبراهيم العاني في بغداد — الغزالية. '
          'الدفع نقداً عند الاستلام. التوصيل ٥٬٠٠٠ دينار عراقي.'),
        ('إرجاع منتج سليم', 'تُراجع طلبات الاسترجاع بعد الاستلام. '
          'تُحسب أجور التوصيل الأول ٥٬٠٠٠ دينار وأجور الرجوع ٥٬٠٠٠ دينار '
          'إذا نُفذت الخدمتان لطلب إرجاع اختياري.'),
        ('منتج مكسور أو معيب', 'يعالج المتجر الضرر المثبت من جهته '
          'بالتعويض أو الاستبدال أو رد القيمة بحسب الحالة دون '
          'تحميل الزبون أجور خطأ المتجر.'),
        ('حقوق الزبون', 'لا تلغي الشروط الحقوق الإلزامية في القانون العراقي. '
          'الشراء من تطبيق الزبون متاح في الإصدار الإنتاجي المعتمد؛ '
          'تحقق من المجموع قبل تأكيد الطلب.'),
      ],
      'help' => const [
        ('كيف أدفع؟', 'نقداً عند الاستلام فقط.'),
        ('كم التوصيل؟', '٥٬٠٠٠ دينار عراقي للطلب.'),
        ('هل يمكن الإرجاع بعد الاستلام؟', 'نعم، عبر طلب مراجعة. '
          'إرجاع المنتج السليم اختيارياً يترتب عليه ٥٬٠٠٠ د.ع '
          'للتوصيل الأول و٥٬٠٠٠ د.ع لنقل الإرجاع عند تنفيذهما.'),
        ('ماذا لو المنتج مكسور؟', 'نعالج الضرر المثبت بالتعويض '
          'أو الاستبدال أو رد المبلغ بحسب الحالة، بدون رسوم خطأ المتجر.'),
        ('هل وصفات الأعشاب تعالج الأمراض؟', 'لا، المحتوى تثقيفي '
          'ولا يُغني عن استشارة مختص صحي.'),
      ],
      _ => const [
        ('متجر السيد إبراهيم العاني', 'متجر عراقي متخصص '
          'بالزيوت والأعشاب والعسل والمنتجات الطبيعية في بغداد — الغزالية.'),
        ('ما الذي نقدمه؟', 'منتجات المحل الفعلية مع أسعار بالدينار العراقي، '
          'وفيديوهات ومقالات ووصفات معلوماتية.'),
        ('رسالتنا', 'معلومات واضحة للمنتجات، مع سياسة دفع واسترجاع '
          'وتعويض معلنة للزبون.'),
        ('معلومة صحية', 'معلومات الأعشاب والوصفات للتثقيف '
          'ولا تمثل تشخيصاً أو علاجاً طبياً.'),
      ]
    };
    return Scaffold(
      appBar: AppBar(title: Text(types[type] ?? types['about']!)),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFFE4F8EA),
              borderRadius: BorderRadius.circular(20)),
            child: Column(children: [
              const Icon(Icons.eco_outlined,color:_green,size:48),
              const SizedBox(height:8),
              Text(types[type] ?? types['about']!,
                textAlign:TextAlign.center,style:const TextStyle(
                  fontSize:24,color:_ink,fontWeight:FontWeight.w900)),
            ]),
          ),
          const SizedBox(height:20),
          for(final section in sections) Card(
            color: Theme.of(context).cardColor,
            child: Padding(
              padding: const EdgeInsets.all(17),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(section.$1,style:const TextStyle(
                    fontSize:17,fontWeight:FontWeight.w900,color:_ink)),
                  const SizedBox(height:9),
                  Text(section.$2,style:const TextStyle(fontSize:14,height:1.7)),
                ],
              ),
            ),
          ),
          if(type=='returns'||type=='damaged') Padding(
            padding:const EdgeInsets.only(top:18),
            child:FilledButton.icon(
              onPressed:()=>Navigator.push(context,MaterialPageRoute<void>(
                builder:(_)=>const AlAniReturnPage())),
              icon:const Icon(Icons.assignment_return_outlined),
              label:const Text('تقديم طلب استرجاع أو تعويض'),
            ),
          ),
        ],
      ),
    );
  }
}

class AlAniReturnPage extends StatefulWidget {
  const AlAniReturnPage({super.key});
  @override
  State<AlAniReturnPage> createState()=>_AlAniReturnPageState();
}

class _AlAniReturnPageState extends State<AlAniReturnPage> {
  static const enabled = bool.fromEnvironment('ALANI_RETURNS_ENABLED',
    defaultValue:false);
  final _order = TextEditingController();
  final _details = TextEditingController();
  final _photo = TextEditingController();
  String _reason='change_mind';
  bool _sending=false;
  String? _error;

  @override
  void dispose() {
    _order.dispose();_details.dispose();_photo.dispose();super.dispose();
  }

  Future<void> _send() async {
    if(!enabled || _sending) return;
    final user = MarketplaceBackend.currentUser;
    if(user==null) {
      final result=await Navigator.of(context).push<bool>(
        MaterialPageRoute(builder:(_)=>const CustomerAuthPage()));
      if(result!=true || !mounted) return;
    }
    final id=RegExp(r'^[a-fA-F0-9]{8}-[a-fA-F0-9]{4}-'
      r'[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{12}$');
    if(!id.hasMatch(_order.text.trim()) ||
       _details.text.trim().length<15 ||
       (_photo.text.trim().isNotEmpty &&
        !Uri.tryParse(_photo.text.trim()).toString().startsWith('https://'))) {
      setState(()=>_error='تأكد من رقم الطلب والتفاصيل (١٥ حرفاً على الأقل) ورابط الصورة.');
      return;
    }
    setState((){_sending=true;_error=null;});
    try {
      final client=Supabase.instance.client;
      final user=client.auth.currentUser;
      if(user==null)throw StateError('يرجى تسجيل الدخول.');
      final matches=await client.from('orders').select('id,buyer_id,store_id')
        .eq('id',_order.text.trim())
        .eq('store_id',AlAniSettings.storeId).limit(1);
      if(matches.length!=1 || matches[0]['buyer_id']!=user.id) {
        throw StateError('هذا الطلب غير مرتبط بحسابك أو المتجر.');
      }
      await client.from('alani_return_requests').insert({
        'order_id':_order.text.trim(),
        'store_id':AlAniSettings.storeId,
        'customer_id':user.id,
        'reason':_reason,
        'details':_details.text.trim(),
        'photo_url':_photo.text.trim().isEmpty?null:_photo.text.trim(),
      });
      if(mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content:Text('تم إرسال طلب المراجعة بنجاح.')));
        Navigator.pop(context);
      }
    } catch(_) {
      if (mounted) {
        setState(() => _error='تعذر تسجيل الطلب الآن. '
          'تحقق من الحساب أو تفعيل نظام الاسترجاع.');
      }
    } finally {
      if (mounted) {
        setState(() => _sending=false);
      }
    }
  }

  @override
  Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:const Text('طلب استرجاع أو تعويض')),
    body:ListView(padding:const EdgeInsets.all(18),children:[
      const Card(child:Padding(padding:EdgeInsets.all(17),
        child:Text('الدفع عند الاستلام. أجور التوصيل ٥٬٠٠٠ د.ع '
          'وأجور الإرجاع الاختياري لمنتج سليم ٥٬٠٠٠ د.ع. '
          'يُعالج الكسر المثبت دون تحميل الزبون رسوم خطأ المتجر.',
          style:TextStyle(height:1.7)))),
      if(!enabled)const Card(color:Color(0xFFFFF1DA),
        child:Padding(padding:EdgeInsets.all(15),
          child:Text('استقبال طلبات الاسترجاع إلكترونياً لم يُفعّل بعد. '
          'هذه واجهة جاهزة للاختبار، ولن تدّعي إرسال طلب قبل تشغيل الخدمة.'))),
      const SizedBox(height:12),
      TextField(controller:_order,
        decoration:const InputDecoration(
          labelText:'رقم الطلب (UUID)',border:OutlineInputBorder())),
      const SizedBox(height:12),
      DropdownButtonFormField<String>(
        initialValue:_reason,
        items:const [
          DropdownMenuItem(value:'change_mind',child:Text('إرجاع منتج سليم')),
          DropdownMenuItem(value:'damaged',child:Text('مكسور أو متضرر')),
          DropdownMenuItem(value:'defective',child:Text('منتج معيب')),
          DropdownMenuItem(value:'wrong_item',child:Text('منتج مختلف')),
        ],
        onChanged:(v)=>setState(()=>_reason=v??_reason),
        decoration:const InputDecoration(labelText:'سبب الاسترجاع'),
      ),
      const SizedBox(height:12),
      TextField(controller:_details,minLines:4,maxLines:7,
        maxLength:2000,
        decoration:const InputDecoration(labelText:'شرح الحالة',
          border:OutlineInputBorder())),
      const SizedBox(height:12),
      TextField(controller:_photo,
        decoration:const InputDecoration(labelText:'رابط الصورة (اختياري)',
          border:OutlineInputBorder())),
      const SizedBox(height:8),
      const Text('لا تشارك هوية أو بيانات مصرفية. '
        'إرفاق الملفات مباشرة غير مفعّل في هذه النسخة.',
        style:TextStyle(fontSize:12,color:Colors.black54)),
      if(_error!=null)Padding(padding:const EdgeInsets.all(10),
        child:Text(_error!,style:const TextStyle(color:Colors.red))),
      const SizedBox(height:15),
      FilledButton.icon(
        onPressed:enabled&&!_sending?_send:null,
        icon:const Icon(Icons.send_outlined),
        label:Text(_sending?'جارٍ الإرسال…':
          enabled?'إرسال طلب المراجعة':'خدمة الاسترجاع قيد التجهيز'),
      ),
    ]),
  );
}

class AlAniSettingsPage extends StatelessWidget {
  const AlAniSettingsPage({super.key});
  @override
  Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:const Text('الإعدادات')),
    body:ListView(padding:const EdgeInsets.all(14),children:[
      const ListTile(
        leading:Icon(Icons.language),
        title:Text('لغة التطبيق'),
        subtitle:Text('العربية — عرض من اليمين إلى اليسار'),
      ),
      ValueListenableBuilder<bool>(
        valueListenable:AlAniUiSettings.darkMode,
        builder:(context,value,_)=>SwitchListTile(
          secondary:const Icon(Icons.dark_mode_outlined),
          title:const Text('الوضع الليلي'),
          subtitle:const Text('يتغير العرض أثناء تشغيل التطبيق'),
          value:value,
          onChanged:(v)=>AlAniUiSettings.darkMode.value=v,
        ),
      ),
      ValueListenableBuilder<bool>(
        valueListenable:AlAniUiSettings.largeText,
        builder:(context,value,_)=>SwitchListTile(
          secondary:const Icon(Icons.format_size),
          title:const Text('خط أكبر'),
          value:value,
          onChanged:(v)=>AlAniUiSettings.largeText.value=v,
        ),
      ),
      const Divider(),
      for (final record in const [
        ('payments','الدفع والتوصيل'),
        ('returns','سياسة الاسترجاع'),
        ('damaged','تعويض المنتج المكسور'),
        ('help','الأسئلة الشائعة'),
      ]) ListTile(
        title:Text(record.$2),trailing:const Icon(Icons.chevron_left),
        onTap:()=>Navigator.push(context,MaterialPageRoute<void>(
          builder:(_)=>AlAniInfoPage(type:record.$1))),
      ),
      const ListTile(
        title:Text('حول التطبيق'),
        subtitle:Text('السيد إبراهيم العاني — متجر الزيوت والأعشاب\n'
          'بغداد، الغزالية، العراق.'),
      ),
    ]),
  );
}

class AlAniStoreDrawer extends StatelessWidget {
  const AlAniStoreDrawer({super.key});
  void _go(BuildContext context,Widget page) {
    final navigator=Navigator.of(context);
    navigator.pop();
    navigator.push<void>(MaterialPageRoute(builder:(_)=>page));
  }
  @override
  Widget build(BuildContext context)=>Drawer(
    child:SafeArea(child:ListView(children:[
      const DrawerHeader(
        decoration:BoxDecoration(color:Color(0xFFE5F9EB)),
        child:Row(children:[
          Icon(Icons.eco,color:_green,size:38),
          SizedBox(width:12),
          Expanded(child:Column(
            mainAxisAlignment:MainAxisAlignment.center,
            crossAxisAlignment:CrossAxisAlignment.start,
            children:[
              Text('السيد إبراهيم العاني',maxLines:2,
                style:TextStyle(fontWeight:FontWeight.w900,
                  fontSize:17,color:_ink)),
              SizedBox(height:5),
              Text('الزيوت والأعشاب الطبيعية — بغداد',
                maxLines:2,overflow:TextOverflow.ellipsis,
                style:TextStyle(color:_ink,fontSize:11)),
            ],
          )),
        ]),
      ),
      ListTile(leading:const Icon(Icons.home_outlined),
        title:const Text('صفحة الترحيب'),
        onTap:()=>_go(context,const AlAniWelcomePage())),
      ListTile(leading:const Icon(Icons.local_offer_outlined),
        title:const Text('عروض لفترة محدودة'),
        onTap:()=>_go(context,const AlAniOffersPage())),
      ListTile(leading:const Icon(Icons.info_outline),
        title:const Text('من نحن'),
        onTap:()=>_go(context,const AlAniInfoPage(type:'about'))),
      ListTile(leading:const Icon(Icons.payments_outlined),
        title:const Text('الدفع عند الاستلام والتوصيل'),
        onTap:()=>_go(context,const AlAniInfoPage(type:'payments'))),
      ListTile(leading:const Icon(Icons.assignment_return_outlined),
        title:const Text('سياسة الاسترجاع'),
        onTap:()=>_go(context,const AlAniInfoPage(type:'returns'))),
      ListTile(leading:const Icon(Icons.add_box_outlined),
        title:const Text('التعويض عن الكسر'),
        onTap:()=>_go(context,const AlAniInfoPage(type:'damaged'))),
      ListTile(leading:const Icon(Icons.receipt_long_outlined),
        title:const Text('طلب استرجاع'),
        onTap:()=>_go(context,const AlAniReturnPage())),
      ListTile(leading:const Icon(Icons.account_balance_wallet_outlined),
        title:const Text('محفظتي وإثباتات التحويل'),
        onTap:()=>_go(context,const AlAniWalletPage())),
      if (const String.fromEnvironment('SUPABASE_URL')=='https://ltwncrewggdrjevakwpb.supabase.co')
        ListTile(leading:const Icon(Icons.favorite_border),
          title:const Text('مفضلتي وتنبيهات المنتجات'),
          onTap:()=>_go(context,const AlAniProductionFavoritesPage())),
      if (const String.fromEnvironment('SUPABASE_URL')=='https://ltwncrewggdrjevakwpb.supabase.co')
        ListTile(leading:const Icon(Icons.notifications_active_outlined),
          title:const Text('مركز الإشعارات'),
          onTap:()=>_go(context,const AlAniOrderNotificationsPage())),
      if (const String.fromEnvironment('SUPABASE_URL')=='https://ltwncrewggdrjevakwpb.supabase.co')
        ListTile(leading:const Icon(Icons.notifications_outlined),
          title:const Text('تفضيلات الإشعارات'),
          onTap:()=>_go(context,const AlAniNotificationPreferencesPage())),
      if (AlAniFcmPilot.configured)
        ListTile(leading:const Icon(Icons.notifications_outlined),
          title:const Text('إشعارات Firebase'),
          onTap:()=>_go(context,const AlAniFcmSettingsPage())),
      if (AlAniSupportFeature.enabled)
        ListTile(leading:const Icon(Icons.chat_bubble_outline),
          title:const Text('دردشة خاصة مع المتجر'),
          onTap:()=>_go(context,const AlAniCustomerSupportPage())),
      ListTile(leading:const Icon(Icons.help_outline),
        title:const Text('الأسئلة الشائعة'),
        onTap:()=>_go(context,const AlAniHelpCenterPage())),
      ListTile(leading:const Icon(Icons.settings_outlined),
        title:const Text('الإعدادات'),
        onTap:()=>_go(context,const AlAniSettingsPage())),
      ListTile(leading:const Icon(Icons.privacy_tip_outlined),
        title:const Text('سياسة الخصوصية'),
        onTap:()=>_go(context,const AlAniInfoPage(type:'privacy'))),
      ListTile(leading:const Icon(Icons.gavel_outlined),
        title:const Text('الشروط والأحكام'),
        onTap:()=>_go(context,const AlAniInfoPage(type:'terms'))),
      const Divider(),
      const Padding(padding:EdgeInsets.all(14),
        child:Text('حقوق المستهلك في العراق محفوظة. '
          'لا يعتبر المحتوى العشبي نصيحة طبية.',
          textAlign:TextAlign.center,
          style:TextStyle(color:Colors.black54,fontSize:11))),
    ])),
  );
}