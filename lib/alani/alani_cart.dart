import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shitreed_customer/commerce/commerce_service.dart';
import 'package:shitreed_customer/commerce/customer_commerce_pages.dart';
import 'package:shitreed_customer/auth/customer_auth_page.dart';
import 'package:shitreed_customer/backend/marketplace_backend.dart';
import 'package:shitreed_customer/alani/alani_content.dart';
import 'package:shitreed_customer/alani/alani_checkout_readiness.dart';
import 'package:shitreed_customer/alani/alani_offers_page.dart';
import 'alani_pages.dart';

const _green = Color(0xFF01BE5F);
const _ink = Color(0xFF173E2A);

/// This app never accepts COD orders until BOTH the client feature flags and
/// the verified server-side fee migration are approved. Release AAB defaults
/// both to false. Existing general Shitreed checkout is not modified.
class AlAniCartPage extends StatefulWidget {
  const AlAniCartPage({super.key});
  @override
  State<AlAniCartPage> createState() => _AlAniCartPageState();
}

class _AlAniCartPageState extends State<AlAniCartPage> {
  static const deliveryFee = 5000;
  bool _serverReady = false;
  bool _checking = false;

  final address = TextEditingController();
  final phone = TextEditingController();
  final notes = TextEditingController();
  List<Map<String,dynamic>> savedAddresses = [];
  bool submitting = false;
  String? requestKey, lastPayload;
  Map<String,dynamic>? _quote;
  bool _quoteLoading=false;
  int _quoteSequence=0;
  Timer? _quoteTimer;

  bool get canSubmit => AlAniCheckoutReadiness.clientApproved &&
      _serverReady && !_checking &&
      (!AlAniOffersGate.enabled || (_quote!=null && !_quoteLoading));

  Future<void> _refreshReadiness() async {
    if (!mounted) return;
    setState(() { _checking = true; _serverReady = false; });
    final ready = await AlAniCheckoutReadiness.checkServer();
    if (mounted) setState(() { _serverReady = ready; _checking = false; });
  }

  @override
  void initState(){
    super.initState();
    _loadAddresses();
    _refreshReadiness();
    CommerceCart.instance.addListener(_onCartChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if(mounted)_refreshQuote();
    });
    _quoteTimer=Timer.periodic(const Duration(seconds:30),(_){
      if(mounted && CommerceCart.instance.items.isNotEmpty)_refreshQuote();
    });
  }

  Future<void> _loadAddresses() async {
    if(MarketplaceBackend.currentUser==null)return;
    try {
      final rows=await CommerceService.mySavedAddresses();
      if(mounted)setState(()=>savedAddresses=rows);
    }catch(_){/* Manual address entry remains available. */}
  }

  @override
  void _onCartChanged(){
    if(mounted)_refreshQuote();
  }

  List<Map<String,dynamic>> _requestItems() => CommerceCart.instance.items
    .map((line)=><String,dynamic>{
      'product_id':line.product.id,'quantity':line.quantity,
    }).toList();

  Future<Map<String,dynamic>> _priceFromServer(
      List<Map<String,dynamic>> items) async {
    final value=await Supabase.instance.client.rpc('alani_discount_quote',
      params:{'p_items':items});
    return Map<String,dynamic>.from(value as Map);
  }

  Future<void> _refreshQuote() async {
    final seq=++_quoteSequence;
    if(!AlAniOffersGate.enabled || !MarketplaceBackend.configured ||
       CommerceCart.instance.items.isEmpty){
      if(mounted)setState((){_quote=null;_quoteLoading=false;});
      return;
    }
    setState((){_quote=null;_quoteLoading=true;});
    try{
      final quote=await _priceFromServer(_requestItems());
      if(!mounted || seq!=_quoteSequence)return;
      setState((){_quote=quote;_quoteLoading=false;});
    }catch(_){
      if(mounted && seq==_quoteSequence){
        setState((){_quote=null;_quoteLoading=false;});
      }
    }
  }

  void dispose(){
    _quoteSequence++;
    _quoteTimer?.cancel();
    CommerceCart.instance.removeListener(_onCartChanged);
    address.dispose();phone.dispose();notes.dispose();
    super.dispose();
  }

  static String uuid4() {
    final secure=Random.secure();
    final bytes=List<int>.generate(16,(_)=>secure.nextInt(256));
    bytes[6]=(bytes[6]&0x0f)|0x40;
    bytes[8]=(bytes[8]&0x3f)|0x80;
    final hex=bytes.map((value)=>value.toRadixString(16).padLeft(2,'0')).join();
    return '${hex.substring(0,8)}-${hex.substring(8,12)}-${hex.substring(12,16)}-${hex.substring(16,20)}-${hex.substring(20)}';
  }

  void notice(String message){
    if(!mounted)return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content:Text(message),
        duration:const Duration(seconds:6)));
  }

  Future<void> submit() async {
    if(!canSubmit || submitting)return;
    await _refreshReadiness();
    if(!mounted || !canSubmit)return;
    final cart=CommerceCart.instance;
    if(cart.items.isEmpty || cart.storeId!=AlAniSettings.storeId)return;
    if(MarketplaceBackend.currentUser==null){
      final signedIn=await Navigator.push<bool>(context,
        MaterialPageRoute(builder:(_)=>const CustomerAuthPage()));
      if(!mounted||signedIn!=true)return;
      await _loadAddresses();
    }
    if(!mounted)return;
    if(address.text.trim().length<8 || phone.text.trim().length<8){
      notice('اكتب عنوان توصيل مفصلاً ورقم هاتف صحيحاً.');
      return;
    }
    final approved=await CommerceService.isStoreApproved(AlAniSettings.storeId);
    if(!mounted)return;
    if(!approved){
      notice('المتجر لا يستقبل طلبات حالياً.');return;
    }
    final currentItems=_requestItems();
    // When promotional pricing is active, only the server quote authorizes
    // the total shown for confirmation. Its atomic checkout RPC independently
    // recalculates the discount, stock and delivery fee.
    Map<String,dynamic>? quote;
    if(AlAniOffersGate.enabled){
      try{
        quote=await _priceFromServer(currentItems);
      }catch(_){
        notice('تعذّر التأكد من سعر العرض. حدّث السلة قبل الطلب.');
        await _refreshQuote();
        return;
      }
    }
    if(!mounted)return;
    final subtotal=(quote?['subtotal_iqd'] as num?)?.toInt()??cart.totalIqd;
    final expectedTotal=(quote?['total_iqd'] as num?)?.toInt()??
      cart.totalIqd+deliveryFee;
    if(expectedTotal!=subtotal+deliveryFee){
      notice('الإجمالي لا يطابق رسوم التوصيل. حدّث السلة.');
      return;
    }
    final body=<String,dynamic>{
      'p_items':currentItems,
      'p_delivery_address':address.text.trim(),
      'p_phone':phone.text.trim(),
      'p_notes':notes.text.trim(),
      'p_expected_total_iqd':expectedTotal,
    };
    final fingerprint=jsonEncode(body);
    if(requestKey==null||lastPayload!=fingerprint){
      requestKey=uuid4();
      lastPayload=fingerprint;
    }

    final confirmed=await showDialog<bool>(
      context:context,builder:(ctx)=>AlertDialog(
        title:const Text('تأكيد الطلب — الدفع عند الاستلام'),
        content:Text('المنتجات بعد الخصم: ${priceText(subtotal)}\nالتوصيل: ٥٬٠٠٠ د.ع\nالإجمالي: ${priceText(expectedTotal)}\nسيعيد الخادم التحقق من الأسعار والخصومات عند تأكيد الطلب.'),
        actions:[
          TextButton(onPressed:()=>Navigator.pop(ctx,false),
            child:const Text('إلغاء')),
          FilledButton(onPressed:()=>Navigator.pop(ctx,true),
            child:const Text('أوافق على تأكيد الطلب')),
        ],
      ),
    );
    if(confirmed!=true||!mounted)return;
    setState(()=>submitting=true);
    try {
      // The idempotency key stays unchanged across network retries of
      // identical cart, address, phone and notes.
      final id=(await Supabase.instance.client.rpc('place_alani_cash_order',
        params:{...body,'p_request_key':requestKey})).toString();
      if(id.length<8)throw const FormatException('INVALID_ORDER_ID');
      final result=await Supabase.instance.client.from('orders')
        .select('total_iqd,delivery_fee_iqd')
        .eq('id',id).eq('store_id',AlAniSettings.storeId).single();
      final lines=await CommerceService.orderItems(id);
      final subtotal=lines.fold<int>(0,(sum,line)=>
        sum+((line['line_total_iqd'] as num?)?.toInt()??0));
      final serverFee=(result['delivery_fee_iqd'] as num?)?.toInt();
      final serverTotal=(result['total_iqd'] as num?)?.toInt();
      if(serverFee!=deliveryFee||serverTotal!=subtotal+deliveryFee){
        throw StateError('ORDER_TOTAL_NOT_VERIFIED');
      }
      if(!mounted)return;
      cart.clear();
      address.clear();phone.clear();notes.clear();
      requestKey=null;lastPayload=null;
      notice('تم تسجيل الطلب بنجاح. رقمه: ${id.substring(0,8)}. الدفع عند الاستلام.');
    } catch(error) {
      if(!mounted)return;
      if(error is StateError&&error.message=='ORDER_TOTAL_NOT_VERIFIED'){
        notice('سُجل رد من الخادم لكن إجمالي التوصيل غير مؤكد. '
          'راجع الطلبات قبل المحاولة مرة ثانية.');
      }else{
        notice(CommerceService.checkoutErrorMessage(error));
      }
    } finally{
      if(mounted)setState(()=>submitting=false);
    }
  }

  @override
  Widget build(BuildContext context)=>AnimatedBuilder(
    animation:CommerceCart.instance,
    builder:(context,_){
      final cart=CommerceCart.instance;
      final items=cart.items;
      final quotedLines=<String,_StringKeyQuote>{};
      for(final row in (_quote?['lines'] as List<dynamic>? ?? [])){
        final values=Map<String,dynamic>.from(row as Map);
        quotedLines[values['product_id'].toString()]=_StringKeyQuote(
          (values['unit_price_iqd'] as num).toInt(),
          (values['regular_price_iqd'] as num).toInt(),
        );
      }
      final offerSubtotal=(_quote?['subtotal_iqd'] as num?)?.toInt();
      final offerTotal=(_quote?['total_iqd'] as num?)?.toInt();
      return ListView(padding:const EdgeInsets.all(17),children:[
        const Text('سلة السيد إبراهيم العاني',
          style:TextStyle(fontSize:23,fontWeight:FontWeight.w900,color:_ink)),
        const SizedBox(height:7),
        const Text('الدفع نقداً عند الاستلام. '
          'التوصيل ٥٬٠٠٠ دينار عراقي.',
          style:TextStyle(fontSize:13)),
        const SizedBox(height:15),
        if (AlAniCheckoutReadiness.testMode) const Card(
          color: Color(0xFFFFF3D6),
          child: Padding(
            padding: EdgeInsets.all(14),
            child: Text(
              'وضع اختبار فقط: الطلبات تُسجل على قاعدة shitreed-test '
              'ولا تُرسل للتاجر أو للمندوب. لا توجد عملية دفع حقيقية.',
              style: TextStyle(fontWeight: FontWeight.w700, height: 1.6),
            ),
          ),
        ),
        if(items.isEmpty)const Padding(
          padding:EdgeInsets.all(33),
          child:Center(child:Text('السلة فارغة. اختر من منتجات متجرنا.'))),
        for(final item in items)Card(color:Colors.white,child:ListTile(
          title:Text(item.product.name),
          subtitle:quotedLines[item.product.id] == null
            ? Text(priceText(item.product.priceIqd))
            : Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
                if(quotedLines[item.product.id]!.discounted)
                  Text(priceText(item.product.priceIqd),
                    style:const TextStyle(
                      decoration:TextDecoration.lineThrough,
                      color:Colors.grey)),
                Text(priceText(quotedLines[item.product.id]!.unitPrice),
                  style:TextStyle(fontWeight:FontWeight.w700,
                    color:quotedLines[item.product.id]!.discounted
                      ?const Color(0xFF0E8246):_ink)),
              ]),
          trailing:Wrap(crossAxisAlignment:WrapCrossAlignment.center,children:[
            IconButton(tooltip:'تقليل الكمية',
              onPressed:submitting?null:()=>cart.subtract(item.product),
              icon:const Icon(Icons.remove_circle_outline)),
            Text(item.quantity.toString()),
            IconButton(tooltip:'زيادة الكمية',
              onPressed:submitting?null:()=>cart.add(item.product),
              icon:const Icon(Icons.add_circle_outline)),
          ]),
        )),
        if(items.isNotEmpty)...[
          OutlinedButton.icon(onPressed:submitting?null:cart.clear,
            icon:const Icon(Icons.remove_shopping_cart_outlined),
            label:const Text('إفراغ السلة')),
          const SizedBox(height:15),
          ListTile(title:const Text('مجموع المنتجات'),
            trailing:Text(priceText(offerSubtotal??cart.totalIqd))),
          const ListTile(title:Text('أجور التوصيل'),
            trailing:Text('٥٬٠٠٠ د.ع')),
          ListTile(
            title:const Text('الإجمالي المتوقع مع التوصيل',
              style:TextStyle(fontWeight:FontWeight.bold)),
            trailing:Text(priceText(offerTotal??cart.totalIqd+deliveryFee),
              style:const TextStyle(fontWeight:FontWeight.w900,color:_green)),
          ),
          if(AlAniOffersGate.enabled && _quoteLoading)
            const LinearProgressIndicator(),
          if(AlAniOffersGate.enabled && _quote==null && !_quoteLoading)
            TextButton.icon(onPressed:_refreshQuote,
              icon:const Icon(Icons.refresh),
              label:const Text('تحديث أسعار العروض')),
          if(offerSubtotal!=null && offerSubtotal<cart.totalIqd)
            ListTile(title:const Text('وفرت بالعروض الحالية'),
              trailing:Text(priceText(cart.totalIqd-offerSubtotal),
                style:const TextStyle(color:Color(0xFF07814E),
                  fontWeight:FontWeight.bold))),
          if(!canSubmit)Card(
            color:const Color(0xFFFFF0D9),
            child:Padding(padding:const EdgeInsets.all(16),
              child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
                Text(_checking
                  ? 'جارٍ التحقق من جاهزية الخادم ورسوم التوصيل…'
                  : 'الشراء الحقيقي مقفل إلى أن يؤكد الخادم احتساب ٥٬٠٠٠ دينار للتوصيل. لن نسجل طلباً ناقص الرسوم.',
                  style:const TextStyle(height:1.7)),
                TextButton.icon(
                  onPressed:_checking?null:_refreshReadiness,
                  icon:const Icon(Icons.refresh),
                  label:const Text('إعادة فحص جاهزية الشراء'),
                ),
              ]))),
          if(canSubmit)...[
            if(savedAddresses.isNotEmpty)DropdownButtonFormField<String>(
              decoration:const InputDecoration(
                labelText:'عناويني المحفوظة',border:OutlineInputBorder()),
              items:savedAddresses.map((row)=>DropdownMenuItem<String>(
                value:row['id'].toString(),
                child:Text(row['label']?.toString()??'عنوان',
                  overflow:TextOverflow.ellipsis),
              )).toList(),
              onChanged:(selected){
                if(selected==null)return;
                final row=savedAddresses.firstWhere((v)=>v['id']==selected);
                address.text=row['address_text']?.toString()??'';
                final savedPhone=row['contact_phone']?.toString()??'';
                if(savedPhone.isNotEmpty)phone.text=savedPhone;
              },
            ),
            const SizedBox(height:10),
            TextField(controller:address,maxLength:300,
              decoration:const InputDecoration(
                labelText:'عنوان التوصيل',border:OutlineInputBorder())),
            const SizedBox(height:9),
            TextField(controller:phone,maxLength:25,
              keyboardType:TextInputType.phone,
              decoration:const InputDecoration(
                labelText:'رقم هاتف الاستلام',border:OutlineInputBorder())),
            const SizedBox(height:9),
            TextField(controller:notes,maxLength:400,maxLines:2,
              decoration:const InputDecoration(
                labelText:'ملاحظات (اختياري)',border:OutlineInputBorder())),
          ],
          const SizedBox(height:8),
          FilledButton.icon(
            onPressed:canSubmit&&!submitting?submit:null,
            icon:Icon(canSubmit?Icons.local_shipping_outlined:Icons.lock_outline),
            label:Text(submitting?'جارٍ تأكيد الطلب…':
              canSubmit?'تأكيد الطلب والدفع عند الاستلام':
                'الطلب عند الاستلام قيد التجهيز'),
          ),
          TextButton(
            onPressed:()=>Navigator.push(context,MaterialPageRoute<void>(
              builder:(_)=>const AlAniInfoPage(type:'payments'))),
            child:const Text('اقرأ سياسة الدفع والتوصيل'),
          ),
        ],
      ]);
    },
  );
}

class _StringKeyQuote {
  const _StringKeyQuote(this.unitPrice,this.oldPrice);
  final int unitPrice;
  final int oldPrice;
  bool get discounted => unitPrice<oldPrice;
}
