import 'package:flutter/material.dart';
import 'package:alani_admin_app/api.dart';

void main() => runApp(const AlAniAdminApp());
const _pine=Color(0xFF1C503B);
const _cream=Color(0xFFF7F4EA);

class AlAniAdminApp extends StatefulWidget {
  const AlAniAdminApp({super.key});
  @override
  State<AlAniAdminApp> createState()=>_AlAniAdminAppState();
}

class _AlAniAdminAppState extends State<AlAniAdminApp> {
  final api=AlAniAdminApi();
  final email=TextEditingController(),password=TextEditingController();
  Map<String,dynamic> data={};
  String? error;
  bool busy=false,signedIn=false;
  int tab=0;

  @override
  void dispose(){email.dispose();password.dispose();api.dispose();super.dispose();}

  List<Map<String,dynamic>> rows(String key) =>
    ((data[key] as List<dynamic>?)??const [])
      .map((x)=>Map<String,dynamic>.from(x as Map)).toList();
  List<Map<String,dynamic>> get posts =>
    (((data['posts'] as Map?)?['items'] as List<dynamic>?)??const [])
      .map((x)=>Map<String,dynamic>.from(x as Map)).toList();
  bool get contentEnabled => (data['posts'] as Map?)?['available']==true;

  String money(dynamic value){
    final s=((value as num?)?.toInt()??0).toString();
    return s.replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
      (m)=>m[1]!+',')+' د.ع';
  }

  void notify(String message){
    if(!mounted)return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(message)));
  }

  Future<void> logIn()async{
    if(busy)return;
    if(!email.text.contains('@')||password.text.length<8){
      setState(()=>error='تحقق من البريد الإلكتروني وكلمة المرور.');
      return;
    }
    setState((){busy=true;error=null;});
    try{
      await api.login(email.text,password.text);
      final result=await api.overview();
      if(mounted)setState((){signedIn=true;data=result;tab=0;});
      password.clear();
    }catch(_){
      if(mounted)setState(()=>error='تعذر الدخول؛ استخدم حساب مالك المتجر.');
    }finally{if(mounted)setState(()=>busy=false);}
  }

  Future<void> reload()async{
    try{
      final result=await api.overview();
      if(mounted)setState(()=>data=result);
    }catch(_){notify('تعذر تحديث البيانات؛ راجع اتصال الإنترنت والجلسة.');}
  }

  void logOut(){
    api.logOut();
    if(mounted)setState((){signedIn=false;data={};tab=0;error=null;});
  }

  Widget field(TextEditingController c,String title,{int lines=1,bool number=false}) =>
    Padding(padding:const EdgeInsets.only(bottom:10),child:TextField(
      controller:c,maxLines:lines,
      keyboardType:number?TextInputType.number:TextInputType.text,
      decoration:InputDecoration(labelText:title,border:const OutlineInputBorder()),
    ));

  Future<void> editProduct([Map<String,dynamic>? p])async{
    final name=TextEditingController(text:p?['name'] as String???'');
    final description=TextEditingController(text:p?['description'] as String???'');
    final price=TextEditingController(text:p?['price_iqd']?.toString()??'');
    final stock=TextEditingController(text:p?['stock_quantity']?.toString()??'');
    final image=TextEditingController(text:p?['image_url'] as String???'');
    bool active=p?['is_active']!=false;
    final changed=await showDialog<bool>(context:context,builder:(dialogContext)=>
      StatefulBuilder(builder:(ctx,setDialog)=>AlertDialog(
        title:Text(p==null?'إضافة منتج':'تعديل منتج'),
        content:SizedBox(width:400,child:SingleChildScrollView(child:Column(
          mainAxisSize:MainAxisSize.min,
          children:[
            field(name,'اسم المنتج'),field(price,'السعر بالدينار',number:true),
            field(stock,'المخزون',number:true),
            field(description,'وصف المنتج',lines:3),
            field(image,'رابط الصورة HTTPS'),
            SwitchListTile(title:const Text('المنتج منشور'),
              value:active,onChanged:(v)=>setDialog(()=>active=v)),
          ],
        ))),
        actions:[
          TextButton(onPressed:()=>Navigator.pop(ctx,false),
            child:const Text('إلغاء')),
          FilledButton(onPressed:()async{
            final amount=int.tryParse(price.text),quantity=int.tryParse(stock.text);
            if(name.text.trim().length<2||amount==null||amount<0||
               quantity==null||quantity<0){
              notify('تحقق من اسم المنتج والسعر والمخزون.');return;
            }
            try{
              await api.saveProduct({
                if(p!=null) 'id':p['id'],
                'name':name.text.trim(),'description':description.text.trim(),
                'price_iqd':amount,'stock_quantity':quantity,
                'image_url':image.text.trim(),'is_active':active,
              });
              if(ctx.mounted)Navigator.pop(ctx,true);
            }catch(_){notify('تعذر حفظ المنتج؛ تحقق من البيانات والصلاحيات.');}
          },child:const Text('حفظ')),
        ],
      )));
    name.dispose();description.dispose();price.dispose();stock.dispose();image.dispose();
    if(changed==true){await reload();notify('تم حفظ المنتج.');}
  }

  Future<void> editPost([Map<String,dynamic>? p])async{
    final title=TextEditingController(text:p?['title'] as String???'');
    final body=TextEditingController(text:p?['body'] as String???'');
    final ingredients=TextEditingController(text:p?['ingredients'] as String???'');
    final safety=TextEditingController(text:p?['safety_note'] as String???'');
    final photo=TextEditingController(text:p?['image_url'] as String???'');
    final video=TextEditingController(text:p?['video_url'] as String? ?? '');
    String kind=p?['kind'] as String? ?? 'post';
    String status=p?['status'] as String? ?? 'draft';
    final changed=await showDialog<bool>(context:context,builder:(dialogContext)=>
      StatefulBuilder(builder:(ctx,setDialog)=>AlertDialog(
        title:const Text('إدارة الفيديوهات والوصفات'),
        content:SizedBox(width:410,child:SingleChildScrollView(
          child:Column(mainAxisSize:MainAxisSize.min,children:[
            DropdownButtonFormField<String>(
              initialValue:kind,
              items:const [
                DropdownMenuItem(value:'video',child:Text('فيديو')),
                DropdownMenuItem(value:'recipe',child:Text('وصفة')),
                DropdownMenuItem(value:'article',child:Text('مقال')),
                DropdownMenuItem(value:'post',child:Text('منشور نصي')),
              ],
              onChanged:(value)=>setDialog(()=>kind=value??kind),
              decoration:const InputDecoration(labelText:'نوع المحتوى'),
            ),
            const SizedBox(height:12),
            field(title,'عنوان المحتوى'),field(body,'النص/الشرح',lines:4),
            if(kind=='recipe')...[
              field(ingredients,'المكونات',lines:3),
              field(safety,'التحذيرات',lines:3),
            ],
            field(photo,'رابط الصورة HTTPS'),
            if(kind=='video')field(video,'رابط الفيديو HTTPS'),
            DropdownButtonFormField<String>(
              initialValue:status,
              items:const [
                DropdownMenuItem(value:'draft',child:Text('مسودة')),
                DropdownMenuItem(value:'published',child:Text('منشور')),
              ],
              onChanged:(v)=>setDialog(()=>status=v??status),
              decoration:const InputDecoration(labelText:'حالة النشر'),
            ),
          ]),
        )),
        actions:[
          TextButton(onPressed:()=>Navigator.pop(ctx,false),
            child:const Text('إلغاء')),
          FilledButton(onPressed:()async{
            if(title.text.trim().length<3 ||
               (kind=='video'&&!video.text.trim().startsWith('https://'))){
              notify('أدخل عنواناً صالحاً ورابط فيديو HTTPS.');return;
            }
            try{
              await api.savePost({
                if(p!=null)'id':p['id'],
                'kind':kind,'status':status,
                'title':title.text.trim(),'body':body.text.trim(),
                'ingredients':ingredients.text.trim(),
                'safety_note':safety.text.trim(),
                'image_url':photo.text.trim(),
                'video_url':video.text.trim(),
              });
              if(ctx.mounted)Navigator.pop(ctx,true);
            }catch(_){notify('تعذّر حفظ المحتوى؛ تأكد من تفعيل قاعدة المحتوى.');}
          },child:const Text('حفظ')),
        ],
      )));
    for(final c in [title,body,ingredients,safety,photo,video]){c.dispose();}
    if(changed==true){await reload();notify('تم حفظ المنشور.');}
  }

  Future<void> changeOrder(String id,String status)async{
    try{
      await api.changeOrder(id,status);
      await reload();notify('تم تحديث الطلب.');
    }catch(_){notify('حالة الطلب غير مسموح بها أو حدث خطأ اتصال.');}
  }

  Widget loginView()=>Scaffold(
    backgroundColor:_cream,
    body:SafeArea(child:Center(child:SingleChildScrollView(
      padding:const EdgeInsets.all(24),
      child:ConstrainedBox(constraints:const BoxConstraints(maxWidth:440),
        child:Column(mainAxisSize:MainAxisSize.min,children:[
          const Icon(Icons.eco,size:70,color:_pine),
          const SizedBox(height:17),
          const Text('السيد إبراهيم العاني',
            style:TextStyle(fontSize:27,fontWeight:FontWeight.w900,color:_pine)),
          const Text('تطبيق الإدارة الخاص بالمتجر'),
          const SizedBox(height:26),
          field(email,'البريد الإلكتروني'),
          TextField(controller:password,obscureText:true,
            decoration:const InputDecoration(labelText:'كلمة المرور',
              border:OutlineInputBorder())),
          if(error!=null)Padding(
            padding:const EdgeInsets.all(12),
            child:Text(error!,style:const TextStyle(color:Colors.red))),
          const SizedBox(height:14),
          SizedBox(width:double.infinity,child:FilledButton.icon(
            onPressed:busy?null:logIn,
            icon:const Icon(Icons.lock_open),
            label:Text(busy?'جارٍ التحقق…':'دخول مالك المتجر'),
          )),
          const SizedBox(height:14),
          const Text('المدير هو مالك المتجر المسجل في Supabase فقط.',
            textAlign:TextAlign.center,style:TextStyle(color:Colors.black54)),
        ]),
      ),
    ))),
  );

  Widget productsView(){
    final all=rows('products');
    return ListView(padding:const EdgeInsets.all(13),children:[
      Row(children:[
        const Expanded(child:Text('المنتجات والمخزون',
          style:TextStyle(fontSize:21,fontWeight:FontWeight.w900,color:_pine))),
        FilledButton.icon(onPressed:()=>editProduct(),
          icon:const Icon(Icons.add),label:const Text('إضافة')),
      ]),
      if(all.isEmpty)const ListTile(title:Text('لا توجد منتجات مسجلة')),
      for(final p in all)Card(color:Colors.white,child:ListTile(
        title:Text(p['name'] as String? ?? ''),
        subtitle:Text(money(p['price_iqd'])+' • المخزون: '+
          (p['stock_quantity']??0).toString()+
          (p['is_active']==true?' • منشور':' • مخفي')),
        trailing:const Icon(Icons.edit_outlined),
        onTap:()=>editProduct(p),
      )),
    ]);
  }

  Widget ordersView(){
    final all=rows('orders');
    return ListView(padding:const EdgeInsets.all(13),children:[
      const Text('طلبات الزبائن',style:TextStyle(
        fontSize:22,fontWeight:FontWeight.w900,color:_pine)),
      if(all.isEmpty)const ListTile(title:Text('لا توجد طلبات حتى الآن')),
      for(final o in all) Card(color:Colors.white,child:Padding(
        padding:const EdgeInsets.all(12),child:Column(
          crossAxisAlignment:CrossAxisAlignment.stretch,children:[
            Text('طلب رقم '+(o['id'] as String).substring(0,8),
              style:const TextStyle(fontWeight:FontWeight.w800)),
            Text(money(o['total_iqd'])+' • '+
              AlAniAdminApi.statusLabel(o['status'] as String)),
            Text(o['delivery_address'] as String? ?? '',
              style:const TextStyle(color:Colors.black54)),
            Wrap(spacing:8,children:[
              for(final next in AlAniAdminApi.nextStatuses(o['status'] as String))
                OutlinedButton(onPressed:()=>changeOrder(o['id'] as String,next),
                  child:Text(AlAniAdminApi.statusLabel(next))),
            ]),
          ],
        ),
      )),
    ]);
  }

  Widget postsView()=>ListView(padding:const EdgeInsets.all(13),children:[
    Row(children:[
      const Expanded(child:Text('الفيديوهات والوصفات والمدونة',
        style:TextStyle(fontSize:20,fontWeight:FontWeight.w900,color:_pine))),
      FilledButton.icon(onPressed:contentEnabled?()=>editPost():null,
        icon:const Icon(Icons.add),label:const Text('إضافة')),
    ]),
    if(!contentEnabled)const Card(child:Padding(
      padding:EdgeInsets.all(20),child:Text(
        'جدول نشر المحتوى لم يُفعّل بعد. '
        'لن تتاح الكتابة قبل اكتمال اختبارات الصلاحيات.'))),
    for(final p in posts)Card(color:Colors.white,child:ListTile(
      title:Text(p['title'] as String? ?? ''),
      subtitle:Text(AlAniAdminApi.kindLabel(p['kind'] as String? ?? '')+
        ' • '+(p['status']=='published'?'منشور':'مسودة')),
      trailing:const Icon(Icons.edit_outlined),
      onTap:()=>editPost(p),
    )),
  ]);

  Widget reportsView(){
    final products=rows('products'),orders=rows('orders');
    final total=orders.fold<int>(0,(sum,o)=>
      sum+((o['total_iqd'] as num?)?.toInt()??0));
    return ListView(padding:const EdgeInsets.all(13),children:[
      const Text('ملخص الإدارة',style:TextStyle(
        fontSize:22,fontWeight:FontWeight.w900,color:_pine)),
      Card(child:ListTile(title:const Text('المنتجات'),
        trailing:Text(products.length.toString()))),
      Card(child:ListTile(title:const Text('الطلبات'),
        trailing:Text(orders.length.toString()))),
      Card(child:ListTile(title:const Text('الطلبات الجديدة'),
        trailing:Text(orders.where((o)=>o['status']=='placed').length.toString()))),
      Card(child:ListTile(title:const Text('قيمة الطلبات المسجلة'),
        trailing:Text(money(total)))),
      const Text('قيمة الطلبات ليست إيراداً تم تحصيله فعلياً.',
        style:TextStyle(color:Colors.black54)),
    ]);
  }

  @override
  Widget build(BuildContext context)=>MaterialApp(
    title:'إدارة السيد إبراهيم العاني',
    debugShowCheckedModeBanner:false,
    locale:const Locale('ar'),
    builder:(ctx,child)=>Directionality(
      textDirection:TextDirection.rtl,child:child??const SizedBox.shrink()),
    theme:ThemeData(useMaterial3:true,
      colorScheme:ColorScheme.fromSeed(seedColor:_pine),
      scaffoldBackgroundColor:_cream,
      appBarTheme:const AppBarTheme(backgroundColor:_pine,
        foregroundColor:Colors.white)),
    home:!signedIn?loginView():Scaffold(
      appBar:AppBar(title:const Text('إدارة السيد إبراهيم العاني'),actions:[
        IconButton(onPressed:reload,tooltip:'تحديث',
          icon:const Icon(Icons.refresh)),
        IconButton(onPressed:logOut,tooltip:'خروج',
          icon:const Icon(Icons.logout)),
      ]),
      body:IndexedStack(index:tab,children:[
        productsView(),ordersView(),postsView(),reportsView()
      ]),
      bottomNavigationBar:NavigationBar(
        selectedIndex:tab,onDestinationSelected:(v)=>setState(()=>tab=v),
        destinations:const [
          NavigationDestination(icon:Icon(Icons.inventory_2_outlined),
            label:'المنتجات'),
          NavigationDestination(icon:Icon(Icons.receipt_long_outlined),
            label:'الطلبات'),
          NavigationDestination(icon:Icon(Icons.menu_book_outlined),
            label:'المحتوى'),
          NavigationDestination(icon:Icon(Icons.assessment_outlined),
            label:'التقارير'),
        ],
      ),
    ),
  );
}
