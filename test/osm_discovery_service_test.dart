import 'package:flutter_test/flutter_test.dart';
import 'package:shitreed_customer/maps/osm_discovery_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test('OSM place decoding uses real geographic coordinates', () {
    final p = OsmPlace.fromJson({
      'id': 'node/120', 'name': 'مكتبة بغداد',
      'category': 'قرطاسية', 'address': 'بغداد - العراق',
      'latitude': 33.312, 'longitude': 44.365,
    });
    expect(p, isNotNull);
    expect(p!.name, 'مكتبة بغداد');
    expect(p.latitude, 33.312);
  });

  test('invalid or out-of-area objects cannot become visible shops', () {
    expect(OsmPlace.fromJson(null), isNull);
    expect(OsmPlace.fromJson({'id':'node/1','name':'محل'}), isNull);
    expect(OsmPlace.fromJson({
      'id':'node/1','name':'محل','latitude': 10,'longitude': 44,
    }), isNull);
    expect(OsmPlace.fromJson({
      'id':'node/1','name':'محل','latitude': 33.2,'longitude': 999,
    }), isNull);
  });

  test('user sees clear message when public OSM rate limit is hit', () {
    expect(
      OsmDiscoveryService.friendlyError(
        const FunctionsHttpException(status: 429)),
      contains('حدّ البحث'),
    );
    expect(
      OsmDiscoveryService.friendlyError(
        const FunctionsHttpException(status: 404)),
      contains('تحديث'),
    );
  });
}
