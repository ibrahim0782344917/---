import 'package:shitreed_customer/backend/marketplace_backend.dart';

/// Presentation-only filters. Prices, stock and checkout are server-authoritative.
class AlAniCatalogFilters {
  const AlAniCatalogFilters._();

  static List<MarketplaceProduct> apply(
    List<MarketplaceProduct> products, {
    String sort = 'default',
    bool inStockOnly = false,
  }) {
    final result = products.where((p) =>
        !inStockOnly || p.stockQuantity > 0).toList(growable: true);
    if (sort == 'price_asc') {
      result.sort((a,b) => a.priceIqd.compareTo(b.priceIqd));
    } else if (sort == 'price_desc') {
      result.sort((a,b) => b.priceIqd.compareTo(a.priceIqd));
    } else if (sort == 'name') {
      result.sort((a,b) => a.name.compareTo(b.name));
    }
    return result;
  }
}
