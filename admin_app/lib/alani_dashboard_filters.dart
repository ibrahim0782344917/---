/// Pure display-only filtering: authorization remains on the server and RLS.
class AlAniAdminFilters {
  const AlAniAdminFilters._();

  static bool lowStock(Map<String, dynamic> product, {int threshold = 5}) {
    final quantity = (product['stock_quantity'] as num?)?.toInt() ?? 0;
    return quantity <= threshold;
  }

  static List<Map<String, dynamic>> products(
    List<Map<String, dynamic>> items, {
    String search = '',
    String inventory = 'all',
  }) {
    final q = search.trim().toLowerCase();
    return items.where((item) {
      final name = (item['name'] ?? '').toString().toLowerCase();
      final description = (item['description'] ?? '').toString().toLowerCase();
      if (q.isNotEmpty && !'$name $description'.contains(q)) return false;
      if (inventory == 'low' && !lowStock(item)) return false;
      if (inventory == 'out' &&
          ((item['stock_quantity'] as num?)?.toInt() ?? 0) != 0) {
        return false;
      }
      if (inventory == 'hidden' && item['is_active'] == true) return false;
      return true;
    }).toList(growable: false);
  }

  static List<Map<String, dynamic>> orders(
    List<Map<String, dynamic>> items, {
    String search = '',
    String status = 'all',
  }) {
    final q = search.trim().toLowerCase();
    return items.where((item) {
      if (status != 'all' && item['status'] != status) return false;
      if (q.isEmpty) return true;
      final id = (item['id'] ?? '').toString().toLowerCase();
      final address = (item['delivery_address'] ?? '').toString().toLowerCase();
      return id.contains(q) || address.contains(q);
    }).toList(growable: false);
  }

  static List<Map<String, dynamic>> posts(
    List<Map<String, dynamic>> items, {
    String kind = 'all',
  }) => items.where((item) =>
      kind == 'all' || item['kind'] == kind).toList(growable: false);
}
