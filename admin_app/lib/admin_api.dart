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
