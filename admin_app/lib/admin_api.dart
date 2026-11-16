import 'package:supabase_flutter/supabase_flutter.dart';

/// Only a public Supabase publishable key belongs in the client.
class AdminApi {
  static const url = String.fromEnvironment('SUPABASE_URL');
  static const publicKey =
      String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');

  static bool get configured =>
      url.startsWith('https://') && publicKey.isNotEmpty;

  static SupabaseClient get client => Supabase.instance.client;

  static Future<void> initialize() async {
    if (configured) {
      await Supabase.initialize(url: url, publishableKey: publicKey);
    }
  }

  static Future<String?> currentRole() async =>
      await client.rpc('shitreed_admin_role') as String?;

  static Future<Map<String, dynamic>> dashboard() async {
    final result = await client.rpc('shitreed_admin_dashboard');
    return Map<String, dynamic>.from(result as Map);
  }

  static Future<List<Map<String, dynamic>>> rows(
    String section, {
    int offset = 0,
    int limit = 30,
  }) async {
    final result = await client.rpc(
      'shitreed_admin_rows',
      params: {
        'p_section': section,
        'p_offset': offset,
        'p_limit': limit,
      },
    );
    final items = (result as Map)['items'] as List<dynamic>? ?? [];
    return items
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList(growable: false);
  }

  static Future<String> action(
    String section,
    String id,
    String action,
    String reason,
  ) async {
    final response = await client.rpc(
      'shitreed_admin_change',
      params: {
        'p_section': section,
        'p_id': id,
        'p_action': action,
        'p_reason': reason.trim(),
      },
    );
    return response.toString();
  }

  static Future<String> setStaff({
    required String userId,
    required String role,
    required bool enabled,
    required String reason,
  }) async {
    final response = await client.rpc(
      'shitreed_admin_set_staff',
      params: {
        'p_user_id': userId,
        'p_role': role,
        'p_enabled': enabled,
        'p_reason': reason.trim(),
      },
    );
    return response.toString();
  }
  static Future<AdminPage> searchPage(String section, {
    String query = '', String filter = '', int offset = 0, int limit = 25,
  }) async {
    final response = await client.rpc('shitreed_admin_search', params: {
      'p_section': section, 'p_search': query.trim(),
      'p_filter': filter, 'p_offset': offset, 'p_limit': limit,
    });
    final data = Map<String, dynamic>.from(response as Map);
    return AdminPage(
      items: (data['items'] as List<dynamic>? ?? const [])
          .map((x) => Map<String, dynamic>.from(x as Map)).toList(),
      total: (data['total'] as num?)?.toInt() ?? 0,
    );
  }

  static Future<List<Map<String, dynamic>>> insights() async {
    final result = await client.rpc('shitreed_admin_insights');
    final rows = (result as Map)['daily'] as List<dynamic>? ?? [];
    return rows.map((x) => Map<String, dynamic>.from(x as Map)).toList();
  }

  static Future<Map<String, dynamic>> orderDetail(String orderId) async {
    final response = await client.rpc('shitreed_admin_order_detail',
        params: {'p_order_id': orderId});
    return Map<String, dynamic>.from(response as Map);
  }

  static Future<int> adjustStock({
    required String productId, required int delta, required String reason,
  }) async {
    final result = await client.rpc('shitreed_admin_inventory_adjust',
        params: {
          'p_product_id': productId, 'p_delta': delta,
          'p_reason': reason.trim(),
        });
    return (result as num).toInt();
  }

  static Future<int> setPrice({
    required String productId, required int priceIqd, required String reason,
  }) async {
    final result = await client.rpc('shitreed_admin_price_update',
        params: {
          'p_product_id': productId, 'p_price_iqd': priceIqd,
          'p_reason': reason.trim(),
        });
    return (result as num).toInt();
  }

  static Future<Map<String, dynamic>?> findUser(String email) async {
    final response = await client.rpc('shitreed_admin_find_user',
        params: {'p_email': email.trim()});
    return response == null ? null : Map<String, dynamic>.from(response as Map);
  }

}

class AdminAccess {
  static const roleLabels = <String, String>{
    'super_admin': 'المدير العام',
    'operations': 'إدارة العمليات',
    'merchant_reviewer': 'مراجعة المتاجر',
    'catalog_manager': 'إدارة المنتجات',
    'support': 'دعم الزبائن',
    'viewer': 'مشاهدة فقط',
  };

  static const sectionLabels = <String, String>{
    'overview': 'الرئيسية',
    'stores': 'المتاجر',
    'products': 'المنتجات',
    'orders': 'الطلبات',
    'customers': 'الزبائن',
    'staff': 'الفريق',
    'audit': 'سجل الإدارة',
  };

  static List<String> sectionsFor(String? role) => switch (role) {
    'super_admin' => const [
        'overview', 'stores', 'products', 'orders',
        'customers', 'staff', 'audit',
      ],
    'operations' => const [
        'overview', 'stores', 'products', 'orders', 'customers', 'audit',
      ],
    'merchant_reviewer' => const ['overview', 'stores', 'products'],
    'catalog_manager' => const ['overview', 'stores', 'products'],
    'support' => const ['overview', 'stores', 'products', 'orders', 'customers'],
    'viewer' => const ['overview', 'stores', 'products'],
    _ => const [],
  };

  static bool canChange(String? role, String section) {
    if (role == 'super_admin' || role == 'operations') {
      return section == 'stores' ||
          section == 'products' ||
          section == 'orders';
    }
    return (role == 'merchant_reviewer' && section == 'stores') ||
        (role == 'catalog_manager' && section == 'products') ||
        (role == 'support' && section == 'orders');
  }

  static bool isUuid(String value) => RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  ).hasMatch(value);
}

class AdminPage {
  final List<Map<String, dynamic>> items;
  final int total;
  const AdminPage({required this.items, required this.total});
}
