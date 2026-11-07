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
    await Supabase.initialize(url: url, anonKey: publishableKey);
  }

  static Future<List<MarketplaceStore>> approvedStores() async {
    if (!configured) return const [];
    final rows = await Supabase.instance.client
        .from('stores')
        .select('id,name,area,category')
        .eq('status', 'approved')
        .order('name');

    return rows.map((row) => MarketplaceStore(
          id: row['id'] as String,
          name: row['name'] as String,
          area: row['area'] as String,
          category: row['category'] as String,
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

  const MarketplaceStore({
    required this.id,
    required this.name,
    required this.area,
    required this.category,
  });
}
