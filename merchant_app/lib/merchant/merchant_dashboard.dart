// ignore_for_file: prefer_interpolation_to_compose_strings, curly_braces_in_flow_control_structures
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shitreed_merchant/backend/marketplace_backend.dart';
import 'package:shitreed_merchant/commerce/commerce_service.dart';
import 'package:shitreed_merchant/shared/merchant_widgets.dart';
import 'package:shitreed_merchant/reports/merchant_reports.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _purple = Color(0xFF51159B);
const _dark = Color(0xFF280B53);

class MerchantDashboardPage extends StatefulWidget {
  const MerchantDashboardPage({super.key});
  @override
  State<MerchantDashboardPage> createState() => _MerchantDashboardPageState();
}

class _MerchantDashboardPageState extends State<MerchantDashboardPage> {
  late Future<List<Map<String, dynamic>>> _stores;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  void _refresh() => setState(() => _stores = CommerceService.myStores());

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('شتريد تاجر'),
      actions: [
        IconButton(
          icon: const Icon(Icons.bar_chart_rounded),
          tooltip: 'الإحصائيات',
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) =>
              const MerchantReportsPage())),
        ),
        IconButton(
          icon: const Icon(Icons.logout),
          tooltip: 'تسجيل الخروج',
          onPressed: () async {
            final shouldLogout = await showDialog<bool>(
              context: context,
              builder: (dialogContext) => AlertDialog(
                title: const Text('تسجيل الخروج'),
                content: const Text('تريد تطلع من حساب التاجر؟'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(dialogContext).pop(false),
                    child: const Text('إلغاء'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.of(dialogContext).pop(true),
                    child: const Text('خروج'),
                  ),
                ],
              ),
            );
            if (shouldLogout == true && context.mounted) {
              await Supabase.instance.client.auth.signOut();
            }
          },
        ),
      ],
    ),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: () async {
        final added = await Navigator.of(context).push<bool>(
          MaterialPageRoute(builder: (_) => const MerchantRegistrationPage()));
        if (added == true) _refresh();
      },
      label: const Text('إضافة متجري'),
      icon: const Icon(Icons.add_business),
    ),
    body: RefreshIndicator(onRefresh: () async {
      _refresh();
      await _stores;
    }, child: ListView(padding: const EdgeInsets.all(16), children: [
      const Text('متاجري على شتريد', style: TextStyle(
        color: _dark, fontSize: 23, fontWeight: FontWeight.w900)),
      const SizedBox(height: 5),
      const Text('حتى يظهر متجرك للزبائن، يجب مراجعة الملكية واعتماده.',
        style: TextStyle(color: Colors.black54)),
      const SizedBox(height: 16),
      FutureBuilder<List<Map<String, dynamic>>>(
        future: _stores,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return const Text('تعذر تحميل المتاجر. اسحب للتحديث.');
          }
          final stores = snap.data ?? [];
          if (stores.isEmpty) {
            return const Padding(padding: EdgeInsets.all(25),
              child: Text('ما عندك متجر بعد. اضغط «إضافة متجري».',
                textAlign: TextAlign.center));
          }
          return Column(children: [
            for (final store in stores)
              Card(color: Colors.white,
                child: Padding(padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(store['name'] as String, style: const TextStyle(
                        fontWeight: FontWeight.w900, fontSize: 19)),
                      Text((store['area'] as String) + ' • ' +
                        (store['category'] as String)),
                      const SizedBox(height: 5),
                      Text(store['status'] == 'approved'
                          ? '✓ متجر معتمد'
                          : store['status'] == 'pending'
                            ? 'بانتظار التحقق من ملكية المتجر'
                            : 'الحساب موقوف من الإدارة',
                        style: TextStyle(
                          color: store['status'] == 'approved'
                              ? Colors.green : Colors.deepOrange)),
                      const SizedBox(height: 10),
                      Wrap(spacing: 8, runSpacing: 6, children: [
                        OutlinedButton.icon(
                          onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(builder: (_) =>
                              MerchantProductsPage(
                                storeId: store['id'] as String,
                                storeName: store['name'] as String))),
                          icon: const Icon(Icons.inventory_2_outlined),
                          label: const Text('المنتجات والمخزون'),
                        ),
                        OutlinedButton.icon(
                          onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(builder: (_) =>
                              MerchantOrdersPage(
                                storeId: store['id'] as String))),
                          icon: const Icon(Icons.receipt_long),
                          label: const Text('طلبات المتجر'),
                        ),
                      ]),
                    ],
                  ))),
          ]);
        },
      ),
      const SizedBox(height: 85),
    ])),
  );
}

class MerchantRegistrationPage extends StatefulWidget {
  const MerchantRegistrationPage({super.key});
  @override
  State<MerchantRegistrationPage> createState() => _MerchantRegistrationPageState();
}

class _MerchantRegistrationPageState extends State<MerchantRegistrationPage> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _area = TextEditingController();
  final _category = TextEditingController();
  final _address = TextEditingController();
  final _latitude = TextEditingController();
  final _longitude = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    for (final c in [_name,_area,_category,_address,_latitude,_longitude]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate() || _busy) return;
    final lat = _latitude.text.trim().isEmpty
      ? null : double.tryParse(_latitude.text.trim());
    final lng = _longitude.text.trim().isEmpty
      ? null : double.tryParse(_longitude.text.trim());
    if ((_latitude.text.trim().isNotEmpty &&
          (lat == null || lat < -90 || lat > 90)) ||
        (_longitude.text.trim().isNotEmpty &&
          (lng == null || lng < -180 || lng > 180))) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('إحداثيات الموقع غير صحيحة.')));
      return;
    }
    setState(() => _busy = true);
    try {
      await CommerceService.registerStore(
        name: _name.text, area: _area.text,
        category: _category.text, address: _address.text,
        latitude: lat, longitude: lng,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('فشل تسجيل المتجر. تأكد من البيانات والاتصال.')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _field(TextEditingController c, String label,
      {int minimum = 2, bool optional = false,
       TextInputType? keyboardType}) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextFormField(
      controller: c, keyboardType: keyboardType,
      decoration: InputDecoration(
        labelText: label, border: const OutlineInputBorder()),
      validator: (v) => optional || (v ?? '').trim().length >= minimum
          ? null : 'أدخل بيانات صحيحة',
    ),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('تسجيل متجر جديد')),
    body: ListView(padding: const EdgeInsets.all(16), children: [
      const Text('طلب إضافة متجر', style: TextStyle(
        color: _dark, fontWeight: FontWeight.w900, fontSize: 22)),
      const SizedBox(height: 7),
      const Text('المتجر يبدأ بحالة «بانتظار الموافقة». لا تنشر بيانات أو '
          'أسعاراً لا تملك حق نشرها.',
        style: TextStyle(color: Colors.black54)),
      const SizedBox(height: 18),
      Form(key: _form, child: Column(children: [
        _field(_name, 'اسم المتجر'),
        _field(_area, 'المنطقة (مثلاً المنصور)'),
        _field(_category, 'التصنيف (مثلاً موبايلات)'),
        _field(_address, 'العنوان بالتفصيل', minimum: 8),
        _field(_latitude, 'خط العرض من Google Maps (اختياري)',
          optional: true, keyboardType: TextInputType.number),
        _field(_longitude, 'خط الطول من Google Maps (اختياري)',
          optional: true, keyboardType: TextInputType.number),
      ])),
      FilledButton(
        onPressed: _busy ? null : _submit,
        style: FilledButton.styleFrom(backgroundColor: _purple),
        child: Text(_busy ? 'جاري الإرسال...' : 'إرسال طلب إضافة المتجر'),
      ),
      const SizedBox(height: 12),
      const Text('إضافة موقع دقيق اختيارية الآن. سيظهر دبوس المحل '
        'في خريطة شتريد بعد اعتماد المتجر.',
        textAlign: TextAlign.center,
        style: TextStyle(color: Colors.black54)),
    ]),
  );
}

class MerchantProductsPage extends StatefulWidget {
  final String storeId, storeName;
  const MerchantProductsPage({
    super.key, required this.storeId, required this.storeName,
  });
  @override
  State<MerchantProductsPage> createState() => _MerchantProductsPageState();
}

class _MerchantProductsPageState extends State<MerchantProductsPage> {
  late Future<List<MarketplaceProduct>> _products;
  @override
  void initState() {
    super.initState();
    _refresh();
  }
  void _refresh() => setState(() {
    _products = CommerceService.merchantProducts(widget.storeId);
  });

  Future<void> _updateStock(MarketplaceProduct item) async {
    final controller = TextEditingController(
      text: item.stockQuantity.toString());
    final next = await showDialog<int>(context: context, builder: (dialog) =>
      AlertDialog(
        title: Text('تعديل مخزون ' + item.name),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'الكمية الجديدة', border: OutlineInputBorder())),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialog),
            child: const Text('إلغاء')),
          FilledButton(
            onPressed: () => Navigator.pop(dialog,
              int.tryParse(controller.text.trim())),
            child: const Text('حفظ')),
        ],
      ));
    controller.dispose();
    if (next == null || next < 0) return;
    try {
      await CommerceService.updateProductStock(
        productId: item.id, stockQuantity: next);
      if (mounted) _refresh();
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر تعديل المخزون.')));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text('منتجات ' + widget.storeName)),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: () async {
        final added = await Navigator.of(context).push<bool>(
          MaterialPageRoute(builder: (_) =>
            MerchantNewProductPage(storeId: widget.storeId)));
        if (added == true) _refresh();
      },
      label: const Text('إضافة منتج'),
      icon: const Icon(Icons.add),
    ),
    body: RefreshIndicator(onRefresh: () async {
      _refresh();
      await _products;
    }, child: ListView(padding: const EdgeInsets.all(15), children: [
      const Text('المنتجات والمخزون', style: TextStyle(
        fontSize: 22, color: _dark, fontWeight: FontWeight.w900)),
      const SizedBox(height: 12),
      FutureBuilder<List<MarketplaceProduct>>(
        future: _products,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return const Text('تعذّر تحميل المنتجات. جرّب التحديث.');
          }
          final items = snap.data ?? [];
          if (items.isEmpty) return const Text(
            'ما ضفت منتجات بعد. اضغط «إضافة منتج».');
          return Column(children: [
            for (final p in items) Card(
              color: Colors.white,
              child: ListTile(
                leading: SizedBox(width: 65,
                  child: productPhoto(p.imageUrl, height: 65)),
                title: Text(p.name),
                subtitle: Text(priceText(p.priceIqd) +
                    ' • مخزون ' + p.stockQuantity.toString()),
                trailing: IconButton(
                  onPressed: () => _updateStock(p),
                  tooltip: 'تعديل المخزون',
                  icon: const Icon(Icons.edit_outlined, color: _purple)),
              ),
            ),
          ]);
        },
      ),
      const SizedBox(height: 90),
    ])),
  );
}

class MerchantNewProductPage extends StatefulWidget {
  final String storeId;
  const MerchantNewProductPage({super.key, required this.storeId});
  @override
  State<MerchantNewProductPage> createState() => _MerchantNewProductPageState();
}

class _MerchantNewProductPageState extends State<MerchantNewProductPage> {
  final _name = TextEditingController();
  final _description = TextEditingController();
  final _price = TextEditingController();
  final _stock = TextEditingController();
  XFile? _photo;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _price.dispose();
    _stock.dispose();
    super.dispose();
  }

  Future<void> _choosePhoto() async {
    try {
      final selected = await ImagePicker().pickImage(
        source: ImageSource.gallery, maxWidth: 1400, imageQuality: 82);
      if (mounted && selected != null) setState(() => _photo = selected);
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('ما گدرنا نفتح معرض الصور.')));
    }
  }

  Future<void> _save() async {
    if (_busy) return;
    final name = _name.text.trim();
    final price = int.tryParse(_price.text.trim());
    final stock = int.tryParse(_stock.text.trim());
    if (name.length < 2 || price == null || price < 0 ||
        stock == null || stock < 0 || _description.text.length > 3000) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('تحقق من الاسم والسعر بالدينار والمخزون.')));
      return;
    }
    setState(() => _busy = true);
    try {
      String? photoUrl;
      if (_photo != null) {
        photoUrl = await CommerceService.uploadProductImage(
          widget.storeId, _photo!);
      }
      await CommerceService.addProduct(
        storeId: widget.storeId, name: name,
        description: _description.text, priceIqd: price,
        stockQuantity: stock, imageUrl: photoUrl,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('فشل إضافة المنتج أو الصورة. تحقق من أذونات المتجر والحجم.')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('إضافة منتج حقيقي')),
    body: ListView(padding: const EdgeInsets.all(16), children: [
      const Text('منتج جديد', style: TextStyle(
        fontWeight: FontWeight.w900, fontSize: 22, color: _dark)),
      const SizedBox(height: 12),
      TextField(controller: _name, maxLength: 160,
        decoration: const InputDecoration(
          labelText: 'اسم المنتج', border: OutlineInputBorder())),
      TextField(controller: _description, maxLines: 3, maxLength: 3000,
        decoration: const InputDecoration(
          labelText: 'وصف المنتج ومواصفاته', border: OutlineInputBorder())),
      TextField(controller: _price, keyboardType: TextInputType.number,
        decoration: const InputDecoration(
          labelText: 'السعر بالدينار العراقي', border: OutlineInputBorder())),
      const SizedBox(height: 12),
      TextField(controller: _stock, keyboardType: TextInputType.number,
        decoration: const InputDecoration(
          labelText: 'الكمية المتوفرة', border: OutlineInputBorder())),
      const SizedBox(height: 12),
      OutlinedButton.icon(
        onPressed: _choosePhoto,
        icon: const Icon(Icons.add_photo_alternate_outlined),
        label: Text(_photo == null ? 'اختيار صورة من المعرض'
          : 'الصورة المختارة: ' + _photo!.name),
      ),
      const Text('صور JPEG أو PNG أو WebP • الحد الأقصى 5 MB.',
        style: TextStyle(fontSize: 12, color: Colors.black54)),
      const SizedBox(height: 20),
      FilledButton(
        onPressed: _busy ? null : _save,
        style: FilledButton.styleFrom(backgroundColor: _purple,
          padding: const EdgeInsets.all(14)),
        child: Text(_busy ? 'جاري الحفظ...' : 'حفظ المنتج'),
      ),
    ]),
  );
}

class MerchantOrdersPage extends StatefulWidget {
  final String storeId;
  const MerchantOrdersPage({super.key, required this.storeId});
  @override
  State<MerchantOrdersPage> createState() => _MerchantOrdersPageState();
}

class _MerchantOrdersPageState extends State<MerchantOrdersPage> {
  late Future<List<Map<String, dynamic>>> _orders;
  @override
  void initState() {
    super.initState();
    _refresh();
  }
  void _refresh() => setState(() {
    _orders = CommerceService.merchantOrders(widget.storeId);
  });

  Future<void> _change(String id, String status) async {
    try {
      await CommerceService.changeOrderStatus(id, status);
      if (mounted) _refresh();
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر تغيير حالة الطلب.')));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('طلبات المتجر')),
    body: RefreshIndicator(onRefresh: () async {
      _refresh();
      await _orders;
    }, child: ListView(padding: const EdgeInsets.all(14), children: [
      const Text('الطلبات الحقيقية', style: TextStyle(
        fontSize: 21, fontWeight: FontWeight.w900, color: _dark)),
      const SizedBox(height: 12),
      FutureBuilder<List<Map<String, dynamic>>>(
        future: _orders,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) return const Text('ما گدرنا نحمّل الطلبات.');
          final orders = snap.data ?? [];
          if (orders.isEmpty) return const Text('ماكو طلبات بعد.');
          return Column(children: [
            for (final o in orders) Card(color: Colors.white,
              child: Padding(padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('طلب ' + (o['id'] as String).substring(0, 8),
                      style: const TextStyle(fontWeight: FontWeight.w900)),
                    Text('الحالة: ' + (o['status'] as String)),
                    Text('المبلغ: ' + priceText(
                        (o['total_iqd'] as num).toInt())),
                    Text('الهاتف: ' + (o['phone'] as String)),
                    Text('العنوان: ' + (o['delivery_address'] as String)),
                    if ((o['notes'] as String).isNotEmpty)
                      Text('ملاحظة: ' + (o['notes'] as String)),
                    const SizedBox(height: 8),
                    if (o['status'] == 'placed') Row(children: [
                      OutlinedButton(
                        onPressed: () => _change(o['id'] as String, 'rejected'),
                        child: const Text('رفض')),
                      const SizedBox(width: 10),
                      FilledButton(
                        onPressed: () => _change(o['id'] as String, 'accepted'),
                        child: const Text('قبول الطلب')),
                    ]),
                    if (o['status'] == 'accepted') FilledButton.tonal(
                      onPressed: () => _change(o['id'] as String, 'preparing'),
                      child: const Text('بدء التحضير')),
                    if (o['status'] == 'preparing') FilledButton.tonal(
                      onPressed: () => _change(o['id'] as String, 'ready'),
                      child: const Text('جاهز للتسليم')),
                  ],
                ))),
          ]);
        },
      ),
    ])),
  );
}
