import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shitreed_merchant/backend/marketplace_backend.dart';
import 'package:shitreed_merchant/commerce/commerce_service.dart';
import 'package:shitreed_merchant/shared/merchant_widgets.dart';
import 'package:shitreed_merchant/merchant/shop_location.dart';

class MerchantStoreSettingsPage extends StatefulWidget {
  final Map<String, dynamic> store;
  const MerchantStoreSettingsPage({super.key, required this.store});

  @override
  State<MerchantStoreSettingsPage> createState() =>
      _MerchantStoreSettingsPageState();
}

class _MerchantStoreSettingsPageState
    extends State<MerchantStoreSettingsPage> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _area;
  late final TextEditingController _category;
  late final TextEditingController _address;
  late final TextEditingController _phone;
  late final TextEditingController _description;
  late final TextEditingController _openingHours;
  XFile? _logo;
  late final TextEditingController _latitude;
  late final TextEditingController _longitude;
  bool _busy = false;
  bool _locating = false;

  @override
  void initState() {
    super.initState();
    final store = widget.store;
    _name = TextEditingController(text: store['name'] as String? ?? '');
    _area = TextEditingController(text: store['area'] as String? ?? '');
    _category = TextEditingController(
      text: store['category'] as String? ?? '');
    _address = TextEditingController(
      text: store['address'] as String? ?? '');
    _phone = TextEditingController(text: store['phone'] as String? ?? '');
    _description = TextEditingController(text: store['description'] as String? ?? '');
    _openingHours = TextEditingController(text: store['opening_hours'] as String? ?? '');
    _latitude = TextEditingController(
      text: store['latitude']?.toString() ?? '');
    _longitude = TextEditingController(
      text: store['longitude']?.toString() ?? '');
  }

  @override
  void dispose() {
    for (final controller in [
      _name, _area, _category, _address, _phone, _description,
      _openingHours, _latitude, _longitude
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Widget _field(TextEditingController controller, String label,
      {int minLength = 2, bool optional = false,
       TextInputType? keyboard}) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextFormField(
      controller: controller, keyboardType: keyboard,
      decoration: InputDecoration(labelText: label),
      validator: (value) => optional ||
          (value ?? '').trim().length >= minLength
          ? null : 'يرجى إدخال بيانات صحيحة',
    ),
  );

  Future<void> _chooseLogo() async {
    try {
      final chosen = await ImagePicker().pickImage(
        source: ImageSource.gallery, maxWidth: 900, imageQuality: 85);
      if (chosen != null && mounted) {
        setState(() => _logo = chosen);
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تعذر اختيار صورة شعار المتجر.')),
        );
      }
    }
  }

  Future<void> _captureLocation() async {
    if (_busy || _locating) return;
    setState(() => _locating = true);
    try {
      final pos = await captureShopLocation();
      if (!mounted) return;
      _latitude.text = pos.latitude.toStringAsFixed(6);
      _longitude.text = pos.longitude.toStringAsFixed(6);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('تم تحديد موقع المحل. راجع الموقع قبل الحفظ.')));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e is StateError ? e.message.toString()
              : 'تعذر تحديد الموقع. أدخل الإحداثيات يدوياً.')));
      }
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  Future<void> _save() async {
    if (_busy || _locating || !_form.currentState!.validate()) return;
    final latString = _latitude.text.trim();
    final lngString = _longitude.text.trim();
    final lat = latString.isEmpty ? null : double.tryParse(latString);
    final lng = lngString.isEmpty ? null : double.tryParse(lngString);
    if ((latString.isNotEmpty || lngString.isNotEmpty) &&
        !isBaghdadShopLocation(lat, lng)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('إحداثيات المتجر غير صحيحة.')));
      return;
    }
    if (_phone.text.trim().isNotEmpty &&
        !validShopPhone(_phone.text)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('رقم الهاتف غير صالح.')));
      return;
    }
    setState(() => _busy = true);
    try {
      String? newLogo;
      if (_logo != null) {
        newLogo = await CommerceService.uploadProductImage(
          widget.store['id'] as String, _logo!);
      }
      await CommerceService.updateStore(
        storeId: widget.store['id'] as String,
        name: _name.text,
        area: _area.text,
        category: _category.text,
        address: _address.text,
        phone: _phone.text.trim().isEmpty ? null : _phone.text,
        description: _description.text,
        openingHours: _openingHours.text,
        logoUrl: newLogo,
        latitude: lat,
        longitude: lng,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('تعذر حفظ البيانات. تحقق من حساب المتجر.')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('إعدادات المتجر')),
    body: SafeArea(child: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(widget.store['name'] as String? ?? '',
          style: const TextStyle(fontSize: 24,
            fontWeight: FontWeight.w900, color: merchantDark)),
        const SizedBox(height: 5),
        const Text(
          'تقدر تغير بيانات متجرك، لكن الموافقة أو الإيقاف '
          'من صلاحيات الإدارة فقط.',
          style: TextStyle(color: Colors.black54),
        ),
        const SizedBox(height: 16),
        ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: productPhoto(widget.store['logo_url'] as String?,
            height: 115)),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _chooseLogo,
          icon: const Icon(Icons.add_photo_alternate),
          label: Text(_logo == null
              ? 'اختيار شعار المتجر'
              : 'الشعار المختار: ${_logo!.name}'),
        ),
        const SizedBox(height: 20),
        Form(key: _form, child: Column(children: [
          _field(_name, 'اسم المحل'),
          _field(_area, 'المنطقة'),
          _field(_category, 'التصنيف'),
          _field(_address, 'العنوان', minLength: 8),
          _field(_phone, 'هاتف المحل (مطلوب للاعتماد)',
            optional: true, keyboard: TextInputType.phone),
          _field(_description, 'وصف المحل (اختياري)', optional: true),
          _field(_openingHours, 'أوقات الدوام (مثلاً 9 ص - 10 م)',
            optional: true),
          OutlinedButton.icon(
            onPressed: (_busy || _locating) ? null : _captureLocation,
            icon: const Icon(Icons.my_location_outlined),
            label: Text(_locating ? 'جاري تحديد الموقع...' :
              'أنا داخل المحل: تحديد الموقع تلقائياً'),
          ),
          const Text('الموقع لا يُطلب تلقائياً، ولا تحفظ إحداثيات بيتك.',
            style: TextStyle(fontSize: 12, color: Colors.black54)),
          const SizedBox(height: 12),
          _field(_latitude, 'خط العرض (مطلوب للاعتماد)',
            optional: true, keyboard: TextInputType.number),
          _field(_longitude, 'خط الطول (مطلوب للاعتماد)',
            optional: true, keyboard: TextInputType.number),
        ])),
        FilledButton.icon(
          onPressed: (_busy || _locating) ? null : _save,
          style: FilledButton.styleFrom(
            backgroundColor: merchantPurple,
            padding: const EdgeInsets.symmetric(vertical: 14)),
          icon: const Icon(Icons.save_outlined),
          label: Text(_busy ? 'جاري الحفظ...' : 'حفظ بيانات المتجر'),
        ),
      ],
    )),
  );
}

class MerchantEditProductPage extends StatefulWidget {
  final MarketplaceProduct product;
  const MerchantEditProductPage({super.key, required this.product});

  @override
  State<MerchantEditProductPage> createState() =>
      _MerchantEditProductPageState();
}

class _MerchantEditProductPageState
    extends State<MerchantEditProductPage> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _description;
  late final TextEditingController _price;
  late final TextEditingController _stock;
  XFile? _selectedImage;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final product = widget.product;
    _name = TextEditingController(text: product.name);
    _description = TextEditingController(text: product.description);
    _price = TextEditingController(text: product.priceIqd.toString());
    _stock = TextEditingController(
      text: product.stockQuantity.toString());
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _price.dispose();
    _stock.dispose();
    super.dispose();
  }

  Future<void> _chooseImage() async {
    try {
      final selection = await ImagePicker().pickImage(
        source: ImageSource.gallery, maxWidth: 1400, imageQuality: 82);
      if (mounted && selection != null) {
        setState(() => _selectedImage = selection);
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('تعذر فتح معرض الصور.')));
      }
    }
  }

  Future<void> _save() async {
    if (_busy || !_form.currentState!.validate()) return;
    final price = int.tryParse(_price.text.trim());
    final stock = int.tryParse(_stock.text.trim());
    if (price == null || price < 0 || stock == null || stock < 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('السعر والمخزون لازم يكونان أرقاماً صحيحة.')));
      return;
    }
    setState(() => _busy = true);
    try {
      String? newImageUrl;
      if (_selectedImage != null) {
        newImageUrl = await CommerceService.uploadProductImage(
          widget.product.storeId, _selectedImage!);
      }
      await CommerceService.updateProduct(
        original: widget.product,
        name: _name.text,
        description: _description.text,
        priceIqd: price,
        stockQuantity: stock,
        imageUrl: newImageUrl,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('فشل تحديث المنتج أو رفع صورته.')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('تعديل المنتج')),
    body: SafeArea(child: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('عدّل تفاصيل منتجك',
          style: TextStyle(fontSize: 23, fontWeight: FontWeight.w900,
            color: merchantDark)),
        const SizedBox(height: 14),
        ClipRRect(
          borderRadius: BorderRadius.circular(17),
          child: productPhoto(widget.product.imageUrl, height: 132)),
        const SizedBox(height: 12),
        Form(key: _form, child: Column(children: [
          TextFormField(
            controller: _name, maxLength: 160,
            decoration: const InputDecoration(labelText: 'اسم المنتج'),
            validator: (value) => (value ?? '').trim().length >= 2
                ? null : 'اسم المنتج قصير جداً',
          ),
          TextFormField(
            controller: _description, maxLength: 3000,
            maxLines: 3, decoration: const InputDecoration(
              labelText: 'الوصف'),
          ),
          TextFormField(
            controller: _price,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'السعر بالدينار العراقي'),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _stock,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'المخزون'),
          ),
        ])),
        const SizedBox(height: 14),
        OutlinedButton.icon(
          onPressed: _chooseImage,
          icon: const Icon(Icons.add_photo_alternate_outlined),
          label: Text(_selectedImage == null
              ? 'تغيير صورة المنتج'
              : 'الصورة المختارة: ${_selectedImage!.name}'),
        ),
        const SizedBox(height: 17),
        FilledButton.icon(
          onPressed: _busy ? null : _save,
          style: FilledButton.styleFrom(backgroundColor: merchantPurple),
          icon: const Icon(Icons.save_outlined),
          label: Text(_busy ? 'جاري التعديل...' : 'حفظ التعديلات'),
        ),
      ],
    )),
  );
}
