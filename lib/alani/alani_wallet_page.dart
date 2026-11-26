import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Production funding proof submission, never a payment or balance operation.
/// The server must independently enable intake and an approved provider.
class AlAniWalletPage extends StatefulWidget {
  const AlAniWalletPage({super.key});
  @override
  State<AlAniWalletPage> createState()=>_AlAniWalletPageState();
}
class _AlAniWalletPageState extends State<AlAniWalletPage> {
  final db=Supabase.instance.client;
  final amount=TextEditingController(), reference=TextEditingController();
  late final String? actor;
  Map<String,dynamic>? status;
  List<Map<String,dynamic>> requests=[];
  String? provider,notice,attemptKey,extension;
  XFile? proof;
  bool busy=false,loading=true,sessionChanged=false;
  StreamSubscription<AuthState>? _auth;
  bool get sameActor=>!sessionChanged&&actor!=null&&actor==db.auth.currentUser?.id;
  bool get intake=>status?['intake_enabled']==true&&sameActor;
  @override
  void initState(){
    super.initState();
    actor=db.auth.currentUser?.id;
    _auth=db.auth.onAuthStateChange.listen((_){
      if(mounted&&db.auth.currentUser?.id!=actor){
        amount.clear();reference.clear();
        setState((){
          sessionChanged=true;status=null;requests=[];proof=null;extension=null;
          provider=null;attemptKey=null;notice=null;loading=false;
        });
      }
    });
    unawaited(load());
  }
  @override
  void dispose(){_auth?.cancel();amount.dispose();reference.dispose();super.dispose();}
  Future<void> load()async{
    if(!mounted)return;
    if(!sameActor){setState((){status=null;requests=[];loading=false;notice='سجّل الدخول بحسابك لعرض طلبات الشحن.';});return;}
    setState(()=>loading=true);
    try{
      final a=await db.rpc('alani_wallet_status');
      if(!mounted||!sameActor)return;
      final b=await db.rpc('alani_wallet_my_requests');
      if(!mounted||!sameActor)return;
      setState((){
        status=Map<String,dynamic>.from(a as Map);
        requests=(b as List).map((x)=>Map<String,dynamic>.from(x as Map)).toList();
        notice=null;
      });
    }catch(_){if(mounted)setState((){status=null;requests=[];notice='تعذر التحقق من حالة المحفظة.';});}
    finally{if(mounted)setState(()=>loading=false);}
  }
  String newKey(){
    final random=Random.secure();
    final b=List<int>.generate(16,(_)=>random.nextInt(256));
    b[6]=(b[6]&15)|64;b[8]=(b[8]&63)|128;
    final h=b.map((x)=>x.toRadixString(16).padLeft(2,'0')).join();
    return '${h.substring(0,8)}-${h.substring(8,12)}-${h.substring(12,16)}-${h.substring(16,20)}-${h.substring(20)}';
  }
  Future<void> choose()async{
    if(!intake||busy||attemptKey!=null)return;
    try{
      final selected=await ImagePicker().pickImage(source:ImageSource.gallery);
      if(!mounted||selected==null||!sameActor)return;
      final name=selected.name.toLowerCase();
      final ext=name.endsWith('.png')?'png':name.endsWith('.jpg')||name.endsWith('.jpeg')?'jpg':null;
      if(ext==null||await selected.length()>5242880){
        if(mounted)setState(()=>notice='اختر صورة JPG أو PNG لا تتجاوز 5 ميغابايت.');return;
      }
      if(mounted&&sameActor)setState((){proof=selected;extension=ext;notice=null;});
    }catch(_){if(mounted)setState(()=>notice='تعذر اختيار الصورة.');}
  }
  Future<void> submit()async{
    if(!intake||busy||proof==null||provider==null||extension==null)return;
    final value=int.tryParse(amount.text.trim()),ref=reference.text.trim();
    final selectedProof=proof,selectedExtension=extension,selectedProvider=provider;
    if(value==null||value<1||value>1000000000||ref.length<4||ref.length>120){
      setState(()=>notice='راجع المبلغ والمرجع قبل الإرسال.');return;
    }
    if(attemptKey==null){
      final ok=await showDialog<bool>(context:context,builder:(context)=>AlertDialog(
        title:const Text('إرسال إثبات تحويل سابق'),
        content:const Text('لا ترسل أموالاً بسبب هذه الصفحة. الإيصال للمراجعة فقط ولا يضيف رصيداً تلقائياً.'),
        actions:[TextButton(onPressed:()=>Navigator.pop(context,false),child:const Text('إلغاء')),
          FilledButton(onPressed:()=>Navigator.pop(context,true),child:const Text('تأكيد الإرسال'))]));
      if(ok!=true||!mounted||!intake||busy)return;
      // Do not submit if another confirmation or account change altered the form.
      if(int.tryParse(amount.text.trim())!=value||reference.text.trim()!=ref||proof!=selectedProof||extension!=selectedExtension||provider!=selectedProvider)return;
      attemptKey=newKey();
    }
    if(!mounted||!sameActor||busy)return;
    setState(()=>busy=true);
    try{
      final bytes=await selectedProof!.readAsBytes();
      final png=bytes.length>=8&&bytes[0]==137&&bytes[1]==80&&bytes[2]==78&&bytes[3]==71&&bytes[4]==13&&bytes[5]==10&&bytes[6]==26&&bytes[7]==10;
      final jpg=bytes.length>=3&&bytes[0]==255&&bytes[1]==216&&bytes[2]==255;
      if(bytes.isEmpty||bytes.length>5242880||(selectedExtension=='png'?!png:!jpg))throw StateError('INVALID_IMAGE');
      if(!sameActor||!mounted)return;
      final raw=await db.rpc('alani_wallet_reserve_proof',params:{
        'p_key':attemptKey,'p_amount_iqd':value,'p_provider':selectedProvider,
        'p_reference':ref,'p_extension':selectedExtension});
      final reserved=Map<String,dynamic>.from(raw as Map);
      if(!sameActor||!mounted)return;
      final path=reserved['path'] as String,id=reserved['id'] as String;
      if(!path.startsWith('$actor/$id/'))throw StateError('INVALID_PATH');
      if(reserved['submitted']!=true){
        try{
          await db.storage.from('alani-wallet-proof-private').uploadBinary(path,bytes,
            fileOptions:FileOptions(contentType:selectedExtension=='png'?'image/png':'image/jpeg',upsert:false));
        }on StorageException catch(e){
          // A repeated attempt may encounter an existing immutable file.
          if(e.statusCode!='409'&&e.statusCode!='Duplicate')rethrow;
        }
        if(!sameActor||!mounted)return;
        await db.rpc('alani_wallet_submit_proof',params:{'p_id':id});
      }
      if(!mounted||!sameActor)return;
      setState((){attemptKey=null;proof=null;extension=null;amount.clear();reference.clear();notice='تم إرسال الإثبات للمراجعة، ولم تتم إضافة رصيد.';});
      await load();
    }catch(_){
      if(mounted&&sameActor)setState(()=>notice='لم نتأكد من اكتمال الإرسال. أعد المحاولة بنفس البيانات؛ لا تحول مبلغاً جديداً.');
    }finally{if(mounted)setState(()=>busy=false);}
  }
  String label(dynamic x)=>switch(x){
    'draft'=>'لم يكتمل الإرسال','submitted'=>'بانتظار المراجعة','under_review'=>'قيد المراجعة',
    'needs_information'=>'تحتاج معلومات','rejected'=>'مرفوض','externally_verified'=>'تم التحقق من التحويل (ليس رصيداً)',_=>'غير معروف'};
  @override
  Widget build(BuildContext context){
    final colors=Theme.of(context).colorScheme;
    final options=((status?['providers'] as List?)??[]).map((x)=>Map<String,dynamic>.from(x as Map)).toList();
    final selected=options.any((x)=>x['code']==provider)?provider:null;
    return Scaffold(appBar:AppBar(title:const Text('محفظتي وإثباتات التحويل'),
      actions:[IconButton(onPressed:busy?null:load,tooltip:'تحديث',icon:const Icon(Icons.refresh))]),
      body:!sameActor?const Center(child:Text('سجّل الدخول ثم أعد فتح المحفظة.')):ListView(padding:const EdgeInsets.all(16),children:[
        Card(color:colors.primaryContainer,child:Padding(padding:const EdgeInsets.all(20),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          Icon(Icons.account_balance_wallet_outlined,color:colors.onPrimaryContainer,size:32),
          const SizedBox(height:12),
          Text('الرصيد المالي',style:TextStyle(color:colors.onPrimaryContainer,fontWeight:FontWeight.w700)),
          Text('غير متاح حالياً',style:TextStyle(color:colors.onPrimaryContainer,fontSize:25,fontWeight:FontWeight.w800)),
          Text('لا يُضاف رصيد من صورة إيصال أو مبلغ معلن.',style:TextStyle(color:colors.onPrimaryContainer)),
        ]))),
        if(loading)const LinearProgressIndicator(),
        if(notice!=null)ListTile(leading:const Icon(Icons.info_outline),title:Text(notice!)),
        if(!intake)const Card(child:ListTile(leading:Icon(Icons.lock_outline),title:Text('استقبال إثباتات التحويل مغلق حالياً'),subtitle:Text('لا تحول أي مبلغ للشحن حتى إعلان طريقة دفع معتمدة.'))),
        if(intake)...[
          const ListTile(title:Text('إثبات تحويل تم سابقاً'),subtitle:Text('إرسال الإثبات لا يؤكد وصول الأموال.')),
          TextField(controller:amount,enabled:!busy&&attemptKey==null,keyboardType:TextInputType.number,decoration:const InputDecoration(labelText:'المبلغ بالدينار العراقي')),
          const SizedBox(height:12),
          DropdownButtonFormField<String>(initialValue:selected,decoration:const InputDecoration(labelText:'جهة التحويل المعتمدة'),
            items:options.map((x)=>DropdownMenuItem(value:x['code'] as String,child:Text(x['label'].toString()))).toList(),
            onChanged:busy||attemptKey!=null?null:(v)=>setState(()=>provider=v)),
          const SizedBox(height:12),
          TextField(controller:reference,enabled:!busy&&attemptKey==null,maxLength:120,decoration:const InputDecoration(labelText:'مرجع الحوالة')),
          OutlinedButton.icon(onPressed:busy||attemptKey!=null?null:choose,icon:const Icon(Icons.upload_file),label:Text(proof==null?'اختيار صورة الإثبات': 'تم اختيار صورة')),
          FilledButton(onPressed:busy?null:submit,child:Text(busy?'جارٍ الإرسال…':attemptKey==null?'إرسال للمراجعة':'إعادة المحاولة بنفس البيانات')),
        ],
        const SizedBox(height:16),
        Text('آخر طلبات الشحن',style:Theme.of(context).textTheme.titleLarge),
        if(!loading&&requests.isEmpty)const ListTile(title:Text('لا توجد طلبات شحن مسجلة.')),
        for(final r in requests)Card(child:ListTile(leading:const Icon(Icons.receipt_long_outlined),title:Text('${r['amount_iqd']} د.ع'),subtitle:Text(label(r['status'])))),
      ]));
  }
}
