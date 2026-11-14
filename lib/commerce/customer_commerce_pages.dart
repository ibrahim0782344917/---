// ignore_for_file: prefer_interpolation_to_compose_strings, curly_braces_in_flow_control_structures
import 'package:flutter/material.dart';
import 'package:shitreed_customer/auth/customer_auth_page.dart';
import 'package:shitreed_customer/backend/marketplace_backend.dart';
import 'package:shitreed_customer/commerce/commerce_service.dart';
import 'package:shitreed_customer/commerce/order_timeline_page.dart';

const _purple = Color(0xFF51159B);
const _dark = Color(0xFF280B53);

String priceText(int price) {
  final s = price.toString().replaceAllMapped(
    RegExp(r'(\d)(?=(\d{3})+(?!\d))'), (m) => m[1]! + ',',
  );
  return s + ' د.ع';
}

Widget productPhoto(String? url, {double height = 115}) {
  if (url == null || !url.startsWith('https://')) {
    return SizedBox(height: height,
      child: const Center(child: Icon(
        Icons.inventory_2_outlined, color: _purple, size: 50)));
  }
  return Image.network(url, height: height, fit: BoxFit.cover,
    errorBuilder: (context, error, stackTrace) => SizedBox(height: height,
      child: const Icon(Icons.broken_image_outlined, color: Colors.grey)));
}

class LiveStorePage extends StatefulWidget {
  final String storeId;
  final String name;
  final String area;
  const LiveStorePage({
    super.key, required this.storeId, required this.name, required this.area,
  });
  @override
  State<LiveStorePage> createState() => _LiveStorePageState();
}

class _LiveStorePageState extends State<LiveStorePage> {
  late Future<List<MarketplaceProduct>> _catalog;
  @override
  void initState() {
    super.initState();
    _catalog = CommerceService.storeProducts(widget.storeId);
  }

  void _refresh() => setState(() {
    _catalog = CommerceService.storeProducts(widget.storeId);
  });

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.name)),
    body: RefreshIndicator(onRefresh: () async {
      _refresh();
      await _catalog;
    }, child: ListView(padding: const EdgeInsets.all(16), children: [
      Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          gradient: const LinearGradient(colors: [_dark, _purple])),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Icon(Icons.storefront_outlined, size: 52, color: Colors.white),
          const SizedBox(height: 10),
          Text(widget.name, style: const TextStyle(
            fontSize: 25, color: Colors.white, fontWeight: FontWeight.w900)),
          Text('بغداد • ' + widget.area,
            style: const TextStyle(color: Colors.white70)),
          const SizedBox(height: 12),
          const Text('متجر معتمد • الأسعار يقدمها صاحب المحل',
            style: TextStyle(color: Colors.white)),
        ]),
      ),
      const SizedBox(height: 20),
      const Text('المنتجات المتاحة', style: TextStyle(
        fontSize: 21, fontWeight: FontWeight.w900)),
      const SizedBox(height: 9),
      FutureBuilder<List<MarketplaceProduct>>(
        future: _catalog,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Column(children: [
              const Text('ما گدرنا نحمّل المنتجات.'),
              OutlinedButton(onPressed: _refresh,
                child: const Text('حاول مرة ثانية')),
            ]);
          }
          final items = snap.data ?? [];
          if (items.isEmpty) {
            return const Padding(padding: EdgeInsets.all(24),
              child: Text('هذا المتجر ما نشر منتجات لحد الآن.',
                textAlign: TextAlign.center));
          }
          return Column(children: [
            for (final product in items) Card(
              color: Colors.white,
              margin: const EdgeInsets.only(bottom: 10),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(children: [
                  SizedBox(width: 95, child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: productPhoto(product.imageUrl, height: 98))),
                  const SizedBox(width: 12),
                  Expanded(child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(product.name, maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w800)),
                      if (product.description.isNotEmpty)
                        Text(product.description, maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12)),
                      const SizedBox(height: 7),
                      Text(priceText(product.priceIqd),
                        style: const TextStyle(
                          color: _purple, fontWeight: FontWeight.w800)),
                      Text(product.stockQuantity == 0
                          ? 'غير متوفر' : 'المتوفر: ' +
                            product.stockQuantity.toString(),
                        style: const TextStyle(fontSize: 11)),
                      const SizedBox(height: 6),
                      FilledButton.tonalIcon(
                        onPressed: product.stockQuantity == 0 ? null : () {
                          final okay = CommerceCart.instance.add(product);
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            content: Text(okay ? 'انضاف للسلة الحقيقية' :
                                'السلة لمتجر واحد فقط أو الكمية خلصت.'),
                          ));
                        },
                        icon: const Icon(Icons.add_shopping_cart, size: 17),
                        label: const Text('أضف للسلة'),
                      ),
                    ])),
                ]),
              )),
          ]);
        },
      ),
    ])),
  );
}

class LiveCartPage extends StatefulWidget {
  const LiveCartPage({super.key});
  @override
  State<LiveCartPage> createState() => _LiveCartPageState();
}

class _LiveCartPageState extends State<LiveCartPage> {
  final _address = TextEditingController();
  final _phone = TextEditingController();
  final _notes = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _address.dispose();
    _phone.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final cart = CommerceCart.instance;
    if (_submitting || cart.items.isEmpty || cart.storeId == null) return;
    if (MarketplaceBackend.currentUser == null) {
      final ok = await Navigator.of(context).push<bool>(
        MaterialPageRoute(builder: (_) => const CustomerAuthPage()));
      if (!mounted || ok != true) return;
    }
    if (_address.text.trim().length < 8 ||
        _phone.text.trim().length < 8) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('اكتب عنوان توصيل واضح ورقم هاتف صحيح.')));
      return;
    }
    setState(() => _submitting = true);
    try {
      // A merchant can see their own pending products through RLS, but
      // customer checkout must never accept orders for unapproved stores.
      if (!await CommerceService.isStoreApproved(cart.storeId!)) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          duration: Duration(seconds: 6),
          content: Text('المتجر بعده بانتظار موافقة الإدارة. '
              'الشراء يتفعل بعد اعتماد المتجر.'),
        ));
        return;
      }
      final requestId = cart.requestIdFor(
        deliveryAddress: _address.text,
        phone: _phone.text,
        notes: _notes.text,
      );
      final orderId = await CommerceService.placeCashOrder(
        storeId: cart.storeId!,
        requestId: requestId,
        items: cart.items,
        deliveryAddress: _address.text,
        phone: _phone.text,
        notes: _notes.text,
      );
      if (!mounted) return;
      cart.clear();
      _address.clear();
      _phone.clear();
      _notes.clear();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('تم إرسال الطلب بنجاح. رقمه: ' + orderId.substring(0, 8)),
      ));
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          duration: const Duration(seconds: 6),
          content: Text(CommerceService.checkoutErrorMessage(error)),
        ));
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: CommerceCart.instance,
    builder: (context, _) {
      final cart = CommerceCart.instance;
      return ListView(padding: const EdgeInsets.all(16), children: [
        const Text('سلتي الحقيقية', style: TextStyle(
          fontSize: 23, fontWeight: FontWeight.w900, color: _dark)),
        const SizedBox(height: 7),
        const Text('طلب واحد من متجر واحد • الدفع عند الاستلام',
          style: TextStyle(color: Colors.black54)),
        const SizedBox(height: 16),
        if (cart.items.isEmpty) const Padding(
          padding: EdgeInsets.all(36),
          child: Center(child: Text('السلة فارغة. اختار منتجات من متجر معتمد.'))),
        for (final line in cart.items) Card(
          color: Colors.white,
          child: ListTile(
            title: Text(line.product.name),
            subtitle: Text(priceText(line.product.priceIqd)),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              IconButton(
                onPressed: _submitting ? null : () => cart.subtract(line.product),
                icon: const Icon(Icons.remove_circle_outline)),
              Text(line.quantity.toString()),
              IconButton(
                onPressed: _submitting ? null : () {
                  if (!cart.add(line.product)) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text('الكمية المطلوبة أكبر من المخزون.')));
                  }
                },
                icon: const Icon(Icons.add_circle_outline)),
            ]),
          )),
        if (cart.items.isNotEmpty) ...[
          OutlinedButton.icon(
            onPressed: _submitting ? null : cart.clear,
            icon: const Icon(Icons.remove_shopping_cart_outlined),
            label: const Text('إفراغ السلة'),
          ),
          const SizedBox(height: 14),
          Text('المجموع: ' + priceText(cart.totalIqd),
            style: const TextStyle(
              fontSize: 20, fontWeight: FontWeight.w900, color: _purple)),
          const SizedBox(height: 6),
          const Text('المجموع يُعاد حسابه من قاعدة البيانات وقت الطلب.',
            style: TextStyle(color: Colors.black54, fontSize: 12)),
          const SizedBox(height: 16),
          TextField(
            controller: _address, maxLength: 300,
            decoration: const InputDecoration(
              labelText: 'عنوان التوصيل بالتفصيل',
              border: OutlineInputBorder())),
          const SizedBox(height: 9),
          TextField(
            controller: _phone, keyboardType: TextInputType.phone,
            maxLength: 25,
            decoration: const InputDecoration(
              labelText: 'رقم الهاتف للتوصيل', border: OutlineInputBorder())),
          const SizedBox(height: 9),
          TextField(
            controller: _notes, maxLength: 400, maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'ملاحظات (اختياري)', border: OutlineInputBorder())),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: _submitting ? null : _submit,
            style: FilledButton.styleFrom(backgroundColor: _purple,
              padding: const EdgeInsets.symmetric(vertical: 14)),
            icon: const Icon(Icons.local_shipping_outlined),
            label: Text(_submitting
              ? 'جاري تسجيل الطلب...' : 'تأكيد الطلب والدفع عند الاستلام'),
          ),
        ],
      ]);
    },
  );
}

class OrderHistoryPage extends StatefulWidget {
  const OrderHistoryPage({super.key});
  @override
  State<OrderHistoryPage> createState() => _OrderHistoryPageState();
}

class _OrderHistoryPageState extends State<OrderHistoryPage> {
  Future<List<Map<String, dynamic>>>? _orders;

  @override
  void initState() {
    super.initState();
    if (MarketplaceBackend.currentUser != null) {
      _orders = CommerceService.myOrders();
    }
  }

  void _refresh() => setState(() {
    _orders = CommerceService.myOrders();
  });

  Future<void> _cancel(String id) async {
    try {
      await CommerceService.changeOrderStatus(id, 'cancelled');
      if (!mounted) return;
      _refresh();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('تم إلغاء الطلب وإرجاع المنتجات للمخزون.')));
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ما يمكن إلغاء هذا الطلب في حالته الحالية.')));
    }
  }

  String _status(String value) {
    switch (value) {
      case 'placed': return 'بانتظار موافقة المتجر';
      case 'accepted': return 'قبله المتجر';
      case 'preparing': return 'جاري التحضير';
      case 'ready': return 'جاهز للتسليم';
      case 'rejected': return 'رفضه المتجر';
      case 'cancelled': return 'ملغي';
      default: return value;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (MarketplaceBackend.currentUser == null) {
      return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Text('سجّل دخول حتى تشوف طلباتك'),
        const SizedBox(height: 10),
        FilledButton(
          onPressed: () async {
            await Navigator.of(context).push<bool>(
              MaterialPageRoute(builder: (_) => const CustomerAuthPage()));
            if (mounted) _refresh();
          },
          child: const Text('تسجيل الدخول'),
        ),
      ]));
    }
    return RefreshIndicator(
      onRefresh: () async {
        _refresh();
        await _orders;
      },
      child: ListView(padding: const EdgeInsets.all(16), children: [
        const Text('طلباتي', style: TextStyle(
          fontSize: 23, color: _dark, fontWeight: FontWeight.w900)),
        const SizedBox(height: 10),
        FutureBuilder<List<Map<String, dynamic>>>(
          future: _orders,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return const Text('تعذّر جلب الطلبات. اسحب للأسفل لتحديث القائمة.');
            }
            final orders = snapshot.data ?? [];
            if (orders.isEmpty) {
              return const Padding(padding: EdgeInsets.all(30),
                child: Text('ما عندك طلبات حقيقية حالياً.',
                  textAlign: TextAlign.center));
            }
            return Column(children: [
              for (final order in orders) Card(
                color: Colors.white,
                child: ListTile(
                  onTap: () async {
                    await Navigator.of(context).push<void>(
                      MaterialPageRoute(builder: (_) => OrderTimelinePage(
                        orderId: order['id'] as String,
                        totalIqd: (order['total_iqd'] as num).toInt(),
                        status: order['status'] as String,
                      )),
                    );
                    if (mounted) _refresh();
                  },
                  title: Text('طلب رقم ' +
                    (order['id'] as String).substring(0, 8)),
                  subtitle: Text(
                    _status(order['status'] as String) + '\n' +
                    priceText((order['total_iqd'] as num).toInt()) +
                    ' • الدفع عند الاستلام'),
                  isThreeLine: true,
                  trailing: order['status'] == 'placed'
                      ? TextButton(
                          onPressed: () => _cancel(order['id'] as String),
                          child: const Text('إلغاء'))
                      : const Icon(Icons.receipt_long_outlined),
                ),
              ),
            ]);
          },
        ),
      ]),
    );
  }
}
