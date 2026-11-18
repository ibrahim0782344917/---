import 'package:flutter/material.dart';
import 'alani_store_api.dart';
import 'alani_dashboard_filters.dart';
import 'alani_campaign_admin_page.dart';

const _pine=Color(0xFF01BE5F);

class AlAniStoreAdminPage extends StatefulWidget {
  final int initialTab;
  const AlAniStoreAdminPage({super.key,this.initialTab=0});
  @override
  State<AlAniStoreAdminPage> createState()=>_AlAniStoreAdminPageState();
}

class _AlAniStoreAdminPageState extends State<AlAniStoreAdminPage> {
  final api=AlAniAdminApi();
  Map<String,dynamic> data={};
  String? error;
  bool loading=true;
  late int tab;
  String productSearch='', stockFilter='all', orderSearch='', orderFilter='all', contentFilter='all';

  @override
  void dispose(){api.dispose();super.dispose();}

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

  @override
  void initState(){
    super.initState();
    tab=widget.initialTab.clamp(0,4);
    reload();
  }

  Future<void> reload()async{
    if(!mounted)return;
    setState((){loading=true;error=null;});
    try{
      final result=await api.overview();
      if(mounted)setState(()=>data=result);
    }catch(e){
      if(mounted)setState(()=>error=e.toString().replaceFirst('Bad state: ',''));
    }finally{
      if(mounted)setState(()=>loading=false);
    }
  }

  Widget field(TextEditingController c,String title,{int lines=1,bool number=false}) =>
    Padding(padding:const EdgeInsets.only(bottom:10),child:TextField(
      controller:c,maxLines:lines,
      keyboardType:number?TextInputType.number:TextInputType.text,
      decoration:InputDecoration(labelText:title,border:const OutlineInputBorder()),
    ));

  Future<void> editProduct([Map<String,dynamic>? p])async{
    final name=TextEditingController(text:p?['name'] as String? ?? '');
    final description=TextEditingController(text:p?['description'] as String? ?? '');
    final price=TextEditingController(text:p?['price_iqd']?.toString()??'');
    final stock=TextEditingController(text:p?['stock_quantity']?.toString()??'');
    final image=TextEditingController(text:p?['image_url'] as String? ?? '');
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
    final title=TextEditingController(text:p?['title'] as String? ?? '');
    final body=TextEditingController(text:p?['body'] as String? ?? '');
    final ingredients=TextEditingController(text:p?['ingredients'] as String? ?? '');
    final safety=TextEditingController(text:p?['safety_note'] as String? ?? '');
    final photo=TextEditingController(text:p?['image_url'] as String? ?? '');
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

  Widget productsView(){
    final all=AlAniAdminFilters.products(
      rows('products'),search:productSearch,inventory:stockFilter);
    final lowCount=rows('products').where(AlAniAdminFilters.lowStock).length;
    return ListView(padding:const EdgeInsets.all(13),children:[
      Card(color:const Color(0xFFE7F8EE),child:ListTile(
        leading:const Icon(Icons.campaign_outlined,color:_pine),
        title:const Text('إدارة شريط العروض المؤقتة',
          style:TextStyle(fontWeight:FontWeight.w800)),
        subtitle:const Text('جدولة إعلان يظهر للزبائن في فترة محددة '
          'بعد تفعيل قاعدة العروض'),
        trailing:const Icon(Icons.chevron_left),
        onTap:()=>Navigator.of(context).push(MaterialPageRoute<void>(
          builder:(_)=>const AlAniCampaignAdminPage())),
      )),
      Row(children:[
        const Expanded(child:Text('المنتجات والمخزون',
          style:TextStyle(fontSize:21,fontWeight:FontWeight.w900,color:_pine))),
        FilledButton.icon(onPressed:()=>editProduct(),
          icon:const Icon(Icons.add),label:const Text('إضافة')),
      ]),
      Card(color:const Color(0xFFEDF9F1),child:ListTile(
        leading:const Icon(Icons.inventory_2_outlined,color:_pine),
        title:const Text('تنبيه المخزون'),
        subtitle:Text('منتجات بكمية 5 أو أقل: $lowCount'),
        onTap:()=>setState(()=>stockFilter='low'),
      )),
      const SizedBox(height:10),
      TextField(
        decoration:const InputDecoration(
          labelText:'ابحث عن اسم المنتج أو الوصف',
          prefixIcon:Icon(Icons.search),
          border:OutlineInputBorder(),
        ),
        onChanged:(value)=>setState(()=>productSearch=value),
      ),
      const SizedBox(height:10),
      Wrap(spacing:7,children:[
        for(final filter in const {
          'all':'الكل','low':'مخزون قليل',
          'out':'نفد المخزون','hidden':'مخفي',
        }.entries)
          ChoiceChip(
            label:Text(filter.value),
            selected:stockFilter==filter.key,
            onSelected:(_)=>setState(()=>stockFilter=filter.key),
          ),
      ]),
      if(all.isEmpty)const ListTile(title:Text('لا توجد منتجات مطابقة للبحث')),
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
    final all=AlAniAdminFilters.orders(
      rows('orders'),search:orderSearch,status:orderFilter);
    return ListView(padding:const EdgeInsets.all(13),children:[
      const Text('طلبات الزبائن',style:TextStyle(
        fontSize:22,fontWeight:FontWeight.w900,color:_pine)),
      const SizedBox(height:10),
      TextField(
        decoration:const InputDecoration(
          labelText:'بحث برقم الطلب أو عنوان التوصيل',
          prefixIcon:Icon(Icons.search),
          border:OutlineInputBorder(),
        ),
        onChanged:(v)=>setState(()=>orderSearch=v),
      ),
      const SizedBox(height:10),
      Wrap(spacing:7,children:[
        for(final filter in const {
          'all':'الكل','placed':'جديد','accepted':'مقبول',
          'preparing':'التجهيز','ready':'جاهز',
          'rejected':'مرفوض',
        }.entries)
          ChoiceChip(
            label:Text(filter.value),
            selected:orderFilter==filter.key,
            onSelected:(_)=>setState(()=>orderFilter=filter.key),
          ),
      ]),
      if(all.isEmpty)const ListTile(title:Text('لا توجد طلبات مطابقة')),
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
    Wrap(spacing:7,children:[
      for(final filter in const {
        'all':'كل المحتوى','video':'فيديوهات',
        'recipe':'وصفات','article':'مقالات','post':'منشورات',
      }.entries)
        ChoiceChip(label:Text(filter.value),
          selected:contentFilter==filter.key,
          onSelected:(_)=>setState(()=>contentFilter=filter.key)),
    ]),
    if(!contentEnabled)const Card(child:Padding(
      padding:EdgeInsets.all(20),child:Text(
        'جدول نشر المحتوى لم يُفعّل بعد. '
        'لن تتاح الكتابة قبل اكتمال اختبارات الصلاحيات.'))),
    for(final p in AlAniAdminFilters.posts(posts,kind:contentFilter))
      Card(color:Colors.white,child:ListTile(
      title:Text(p['title'] as String? ?? ''),
      subtitle:Text(AlAniAdminApi.kindLabel(p['kind'] as String? ?? '')+
        ' • '+(p['status']=='published'?'منشور':'مسودة')),
      trailing:const Icon(Icons.edit_outlined),
      onTap:()=>editPost(p),
    )),
  ]);


  Future<void> reviewReturn(Map<String,dynamic> request,String status) async {
    final note=TextEditingController();
    final confirmed=await showDialog<bool>(
      context:context,builder:(ctx)=>AlertDialog(
        title:Text('مراجعة الاسترجاع: '+status),
        content:TextField(
          controller:note,maxLines:3,maxLength:1000,
          decoration:const InputDecoration(
            labelText:'ملاحظة المراجعة (10 أحرف على الأقل)',
            border:OutlineInputBorder()),
        ),
        actions:[
          TextButton(onPressed:()=>Navigator.pop(ctx,false),
            child:const Text('إلغاء')),
          FilledButton(onPressed:()=>Navigator.pop(ctx,true),
            child:const Text('تأكيد تغيير الحالة')),
        ],
      ),
    );
    final text=note.text.trim();
    note.dispose();
    if(confirmed!=true||text.length<10) {
      if(confirmed==true)notify('اكتب ملاحظة واضحة قبل المراجعة.');
      return;
    }
    try{
      await api.reviewReturn(id:request['id'] as String,status:status,note:text);
      await reload();
      notify('تم تسجيل قرار المراجعة. لم يُنفذ استرداد مالي تلقائي.');
    }catch(_){
      notify('تعذرت مراجعة الطلب؛ نظام الاسترجاع قد يكون غير مفعل.');
    }
  }

  Widget returnsView(){
    final dataReturns=data['returns'] as Map?;
    final enabled=dataReturns?['available']==true;
    final requests=((dataReturns?['items'] as List<dynamic>?)??const [])
      .map((e)=>Map<String,dynamic>.from(e as Map)).toList();
    String reason(String value)=>switch(value){
      'change_mind'=>'إرجاع منتج سليم',
      'damaged'=>'منتج مكسور/تالف',
      'wrong_item'=>'منتج مختلف',
      'defective'=>'منتج معيب',
      _=>value
    };
    String status(String value)=>switch(value){
      'submitted'=>'قُدّم','reviewing'=>'قيد المراجعة',
      'approved'=>'مقبول','declined'=>'مرفوض','resolved'=>'تمت المعالجة',
      _=>value
    };
    List<String> next(String current)=>switch(current){
      'submitted'=>const ['reviewing'],
      'reviewing'=>const ['approved','declined'],
      'approved'=>const ['resolved'],
      _=>const []
    };
    return ListView(padding:const EdgeInsets.all(13),children:[
      const Text('الاسترجاع والتعويض',style:TextStyle(
        fontSize:22,fontWeight:FontWeight.w900,color:_pine)),
      const SizedBox(height:10),
      const Text('لا تُطبق أجور الرجوع الاختياري عند ثبوت تلف '
        'يرجع إلى المتجر أو شركة التوصيل. '
        'قرارات المراجعة هنا لا تنفذ استرداد مبالغ تلقائياً.',
        style:TextStyle(fontSize:13,height:1.6)),
      if(!enabled)const Card(child:Padding(
        padding:EdgeInsets.all(18),
        child:Text('قاعدة طلبات الاسترجاع لم تُفعّل بعد. '
          'لا يمكن استقبال أو معالجة الطلبات من التطبيق حالياً.'))),
      if(enabled&&requests.isEmpty)const ListTile(
        title:Text('لا توجد طلبات استرجاع حتى الآن.')),
      for(final item in requests)
        Card(color:Colors.white,child:Padding(
          padding:const EdgeInsets.all(14),
          child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
            Text('طلب: '+(item['order_id']??'').toString().substring(0,8),
              style:const TextStyle(fontWeight:FontWeight.w900)),
            const SizedBox(height:5),
            Text(reason(item['reason'] as String? ?? '')),
            Text('الحالة: '+status(item['status'] as String? ?? '')),
            const SizedBox(height:5),
            Text(item['details'] as String? ?? '',
              style:const TextStyle(fontSize:13)),
            Wrap(spacing:8,children:[
              for(final value in next(item['status'] as String? ?? ''))
                OutlinedButton(
                  onPressed:()=>reviewReturn(item,value),
                  child:Text(status(value)),
                ),
            ]),
          ]),
        )),
    ]);
  }

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
      Card(child:ListTile(title:const Text('منتجات بمخزون قليل أو منتهٍ'),
        trailing:Text(products.where(AlAniAdminFilters.lowStock).length.toString()))),
      Card(child:ListTile(title:const Text('قيمة الطلبات المسجلة'),
        trailing:Text(money(total)))),
      const Text('قيمة الطلبات ليست إيراداً تم تحصيله فعلياً.',
        style:TextStyle(color:Colors.black54)),
    ]);
  }

  @override
  Widget build(BuildContext context) => loading
    ? const Scaffold(body:Center(child:CircularProgressIndicator()))
    : error!=null
      ? Scaffold(appBar:AppBar(title:const Text('صلاحيات متجر السيد إبراهيم العاني')),
          body:Center(child:Padding(padding:const EdgeInsets.all(22),
            child:Column(mainAxisSize:MainAxisSize.min,children:[
              Text(error!,textAlign:TextAlign.center),
              const SizedBox(height:12),
              OutlinedButton(onPressed:reload,child:const Text('إعادة التحقق')),
            ]))))
      : Scaffold(
      appBar:AppBar(title:const Text('إدارة السيد إبراهيم العاني'),actions:[
        IconButton(onPressed:reload,tooltip:'تحديث',
          icon:const Icon(Icons.refresh)),
      ]),
      body:IndexedStack(index:tab,children:[
        productsView(),ordersView(),returnsView(),postsView(),reportsView()
      ]),
      bottomNavigationBar:NavigationBar(
        selectedIndex:tab,onDestinationSelected:(v)=>setState(()=>tab=v),
        destinations:const [
          NavigationDestination(icon:Icon(Icons.inventory_2_outlined),
            label:'المنتجات'),
          NavigationDestination(icon:Icon(Icons.receipt_long_outlined),
            label:'الطلبات'),
          NavigationDestination(icon:Icon(Icons.assignment_return_outlined),
            label:'الاسترجاع'),
          NavigationDestination(icon:Icon(Icons.menu_book_outlined),
            label:'المحتوى'),
          NavigationDestination(icon:Icon(Icons.assessment_outlined),
            label:'التقارير'),
        ],
      ),
    );
}
