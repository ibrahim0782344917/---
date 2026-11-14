// ignore_for_file: prefer_interpolation_to_compose_strings, curly_braces_in_flow_control_structures
import 'package:flutter/foundation.dart';
import 'package:shitreed_customer/commerce/checkout_request_token.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shitreed_customer/backend/marketplace_backend.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class CommerceCartItem {
  final MarketplaceProduct product;
  int quantity;
  CommerceCartItem(this.product, this.quantity);
}

class CommerceCart extends ChangeNotifier {
  CommerceCart._();
  static final CommerceCart instance = CommerceCart._();
  final Map<String, CommerceCartItem> _items = {};
  final CheckoutRequestToken _checkoutToken = CheckoutRequestToken();

  List<CommerceCartItem> get items => _items.values.toList(growable: false);
  int get count => _items.values.fold(0, (v, line) => v + line.quantity);
  int get totalIqd => _items.values.fold(
      0, (v, line) => v + line.product.priceIqd * line.quantity);
  String? get storeId =>
      _items.isEmpty ? null : _items.values.first.product.storeId;

  /// Keep a retry ID until the customer actually changes the order.
  String requestIdFor({
    required String deliveryAddress,
    required String phone,
    String notes = '',
  }) {
    final id = storeId;
    if (id == null) throw StateError('EMPTY_CART');
    return _checkoutToken.forOrder(
      storeId: id,
      items: _items.values.map((line) => (
        productId: line.product.id, quantity: line.quantity,
      )),
      deliveryAddress: deliveryAddress,
      phone: phone,
      notes: notes,
    );
  }

  bool add(MarketplaceProduct product) {
    if (product.stockQuantity < 1 ||
        (_items.isNotEmpty && storeId != product.storeId)) return false;
    final previous = _items[product.id];
    if (previous != null && previous.quantity >= product.stockQuantity) {
      return false;
    }
    if (previous == null) {
      _items[product.id] = CommerceCartItem(product, 1);
    } else {
      previous.quantity++;
    }
    _checkoutToken.reset();
    notifyListeners();
    return true;
  }

  void subtract(MarketplaceProduct product) {
    final line = _items[product.id];
    if (line == null) return;
    if (line.quantity <= 1) {
      _items.remove(product.id);
    } else {
      line.quantity--;
    }
    _checkoutToken.reset();
    notifyListeners();
  }

  void clear() {
    _items.clear();
    _checkoutToken.reset();
    notifyListeners();
  }
}

class CommerceService {
  CommerceService._();
  static SupabaseClient get _db => Supabase.instance.client;

  static String get _myUserId {
    final user = MarketplaceBackend.currentUser;
    if (user == null) throw StateError('لازم تسجل دخول أولاً.');
    return user.id;
  }

  static MarketplaceProduct _product(Map<String, dynamic> row) =>
      MarketplaceProduct(
        id: row['id'] as String,
        storeId: row['store_id'] as String,
        name: row['name'] as String,
        priceIqd: (row['price_iqd'] as num).toInt(),
        stockQuantity: (row['stock_quantity'] as num).toInt(),
        description: row['description'] as String? ?? '',
        imageUrl: row['image_url'] as String?,
      );

  static Future<List<MarketplaceProduct>> storeProducts(String storeId) async {
    final rows = await _db.from('products')
        .select('id,store_id,name,price_iqd,stock_quantity,description,image_url')
        .eq('store_id', storeId)
        .eq('is_active', true).order('name');
    return rows.map(_product).toList(growable: false);
  }

  static Future<List<MarketplaceProduct>> merchantProducts(String storeId) async {
    if (_myUserId.isEmpty) throw StateError('LOGIN_REQUIRED');
    final rows = await _db.from('products')
        .select('id,store_id,name,price_iqd,stock_quantity,description,image_url')
        .eq('store_id', storeId).order('name');
    return rows.map(_product).toList(growable: false);
  }

  static Future<List<Map<String, dynamic>>> myStores() async {
    final userId = _myUserId;
    return _db.from('stores')
        .select('id,name,area,category,status,address,latitude,longitude')
        .eq('owner_id', userId).order('created_at', ascending: false);
  }

  static Future<String> registerStore({
    required String name,
    required String area,
    required String category,
    required String address,
    double? latitude,
    double? longitude,
  }) async {
    final userId = _myUserId;
    final row = await _db.from('stores').insert({
      'owner_id': userId,
      'name': name.trim(),
      'area': area.trim(),
      'category': category.trim(),
      'address': address.trim(),
      'latitude': latitude,
      'longitude': longitude,
    }).select('id').single();
    return row['id'] as String;
  }

  static Future<void> addProduct({
    required String storeId,
    required String name,
    required String description,
    required int priceIqd,
    required int stockQuantity,
    String? imageUrl,
  }) async {
    if (_myUserId.isEmpty) throw StateError('LOGIN_REQUIRED');
    await _db.from('products').insert({
      'store_id': storeId,
      'name': name.trim(),
      'description': description.trim(),
      'price_iqd': priceIqd,
      'stock_quantity': stockQuantity,
      'image_url': imageUrl,
      'is_active': true,
    });
  }

  static Future<void> updateProductStock({
    required String productId, required int stockQuantity,
  }) async {
    if (_myUserId.isEmpty) throw StateError('LOGIN_REQUIRED');
    await _db.from('products').update({
      'stock_quantity': stockQuantity,
    }).eq('id', productId);
  }

  /// Public product photos, upload restricted to store owner by Storage RLS.
  static Future<String> uploadProductImage(String storeId, XFile file) async {
    if (_myUserId.isEmpty) throw StateError('LOGIN_REQUIRED');
    final bytes = await file.readAsBytes();
    if (bytes.isEmpty || bytes.lengthInBytes > 5242880) {
      throw StateError('حجم الصورة لازم يكون أقل من 5 ميگابايت.');
    }
    final name = file.name.toLowerCase();
    final extension = name.endsWith('.png') ? 'png'
        : name.endsWith('.webp') ? 'webp' : 'jpg';
    final mime = extension == 'png' ? 'image/png'
        : extension == 'webp' ? 'image/webp' : 'image/jpeg';
    final path = storeId + '/' +
        DateTime.now().microsecondsSinceEpoch.toString() + '.' + extension;
    await _db.storage.from('store-images').uploadBinary(
      path, bytes, fileOptions: FileOptions(
        contentType: mime, upsert: false,
      ),
    );
    return _db.storage.from('store-images').getPublicUrl(path);
  }

  /// Do not allow checkout of pending/unverified stores from a stale cart.
  /// The database RPC still performs the authoritative approval check.
  static Future<bool> isStoreApproved(String storeId) async {
    final result = await _db.from('stores')
        .select('id')
        .eq('id', storeId)
        .eq('status', 'approved')
        .maybeSingle();
    return result != null;
  }

  /// User-facing messages for known, sanitized backend checkout errors.
  static String checkoutErrorMessage(Object error) {
    if (error is PostgrestException) {
      return checkoutFailureText(error.message);
    }
    return 'ما گدرنا نتصل بالخادم. تأكد من الإنترنت وحاول مرة ثانية.';
  }

  static Future<String> placeCashOrder({
    required String storeId,
    required List<CommerceCartItem> items,
    required String deliveryAddress,
    required String phone,
    required String requestId,
    String notes = '',
  }) async {
    if (_myUserId.isEmpty) throw StateError('LOGIN_REQUIRED');
    final value = await _db.rpc('place_cash_order', params: {
      'p_store_id': storeId,
      'p_items': items.map((line) => {
        'product_id': line.product.id,
        'quantity': line.quantity,
      }).toList(),
      'p_delivery_address': deliveryAddress.trim(),
      'p_phone': phone.trim(),
      'p_notes': notes.trim(),
      'p_request_id': requestId,
    });
    return value.toString();
  }

  static Future<List<Map<String, dynamic>>> myOrders() async {
    final uid = _myUserId;
    return _db.from('orders')
        .select('id,store_id,status,total_iqd,created_at,payment_method')
        .eq('buyer_id', uid).order('created_at', ascending: false).limit(60);
  }

  static Future<List<Map<String, dynamic>>> merchantOrders(
      String storeId) async {
    if (_myUserId.isEmpty) throw StateError('LOGIN_REQUIRED');
    return _db.from('orders')
        .select('id,store_id,status,total_iqd,created_at,delivery_address,phone,notes')
        .eq('store_id', storeId).order('created_at', ascending: false).limit(60);
  }

  static Future<String> changeOrderStatus(String id, String status) async {
    if (_myUserId.isEmpty) throw StateError('LOGIN_REQUIRED');
    final result = await _db.rpc('change_cash_order_status', params: {
      'p_order_id': id,
      'p_new_status': status,
    });
    return result.toString();
  }
}

/// Never display internal SQL exception details or personal information.
String checkoutFailureText(String serverMessage) {
  if (serverMessage.contains('IDEMPOTENCY_KEY_REUSED')) {
    return 'تغيّرت تفاصيل الطلب؛ حدّث السلة وجرّب من جديد.';
  }
  if (serverMessage.contains('STORE_NOT_AVAILABLE')) {
    return 'المتجر بعده بانتظار موافقة الإدارة، لذلك الطلبات مو مفعلة إله.';
  }
  if (serverMessage.contains('OUT_OF_STOCK')) {
    return 'الكمية المطلوبة نفدت. حدث المنتجات وعدّل السلة.';
  }
  if (serverMessage.contains('PRODUCT_UNAVAILABLE')) {
    return 'أحد المنتجات ما عاد متوفر. حدث السلة وحاول مرة ثانية.';
  }
  if (serverMessage.contains('LOGIN_REQUIRED')) {
    return 'لازم تسجّل دخولك حتى تكمل الطلب.';
  }
  if (serverMessage.contains('INVALID_DELIVERY_DETAILS')) {
    return 'تأكد من عنوان التوصيل ورقم الهاتف قبل الطلب.';
  }
  if (serverMessage.contains('INVALID_ITEMS') ||
      serverMessage.contains('INVALID_ITEM') ||
      serverMessage.contains('INVALID_OR_DUPLICATE_ITEM')) {
    return 'محتوى السلة يحتاج تحديث قبل إتمام الطلب.';
  }
  return 'تعذر إنشاء الطلب الآن. جرّب لاحقاً أو اتصل بالدعم.';
}
