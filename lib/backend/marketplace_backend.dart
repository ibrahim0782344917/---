import 'package:supabase_flutter/supabase_flutter.dart';

/// App-visible connection values. NEVER use a service_role / secret key in mobile code.
class MarketplaceBackend {
  static const url = String.fromEnvironment('SUPABASE_URL');
  static const publishableKey =
      String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');

  static bool get configured =>
      url.startsWith('https://') && publishableKey.isNotEmpty;

  static Future<void> initialize() async {
    if (!configured) return;
    await Supabase.initialize(url: url, publishableKey: publishableKey);
  }

  static Future<List<MarketplaceStore>> approvedStores() async {
    if (!configured) return const [];
    final rows = await Supabase.instance.client
        .from('stores')
        .select('id,name,area,category,latitude,longitude')
        .eq('status', 'approved')
        .order('name');

    return rows.map((row) => MarketplaceStore(
          id: row['id'] as String,
          name: row['name'] as String,
          area: row['area'] as String,
          category: row['category'] as String,
          latitude: (row['latitude'] as num?)?.toDouble(),
          longitude: (row['longitude'] as num?)?.toDouble(),
        )).toList(growable: false);
  }

  /// Public marketplace listings must include approved stores only.
  ///
  /// Merchants are allowed by RLS to read their own pending products for
  /// management, so RLS alone cannot filter the customer-facing catalog.
  static Future<List<MarketplaceProduct>> publishedProducts() async {
    if (!configured) return const [];
    final approved = await approvedStores();
    if (approved.isEmpty) return const [];
    final approvedIds = approved.map((store) => store.id).toList();
    final rows = await Supabase.instance.client
        .from('products')
        .select('id,name,description,price_iqd,store_id,stock_quantity,image_url')
        .inFilter('store_id', approvedIds)
        .eq('is_active', true)
        .order('name')
        .limit(60);

    return rows.map((row) => MarketplaceProduct(
      id: row['id'] as String,
      name: row['name'] as String,
      priceIqd: (row['price_iqd'] as num).toInt(),
      storeId: row['store_id'] as String,
      description: row['description'] as String? ?? '',
      stockQuantity: (row['stock_quantity'] as num).toInt(),
      imageUrl: row['image_url'] as String?,
    )).toList(growable: false);
  }

  static User? get currentUser => configured
      ? Supabase.instance.client.auth.currentUser
      : null;

  static Future<void> signOut() async {
    if (configured) await Supabase.instance.client.auth.signOut();
  }
}

class MarketplaceStore {
  final String id;
  final String name;
  final String area;
  final String category;
  final double? latitude;
  final double? longitude;

  const MarketplaceStore({
    required this.id,
    required this.name,
    required this.area,
    required this.category,
    this.latitude,
    this.longitude,
  });
}

class MarketplaceProduct {
  final String id;
  final String name;
  final int priceIqd;
  final String storeId;
  final String description;
  final int stockQuantity;
  final String? imageUrl;

  const MarketplaceProduct({
    required this.id,
    required this.name,
    required this.priceIqd,
    required this.storeId,
    this.description = '',
    this.stockQuantity = 0,
    this.imageUrl,
  });
}
