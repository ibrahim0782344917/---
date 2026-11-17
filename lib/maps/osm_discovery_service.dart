// ignore_for_file: curly_braces_in_flow_control_structures
import 'dart:convert';

import 'package:shitreed_customer/backend/marketplace_backend.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// An OpenStreetMap discovery result is NEVER a Shitreed merchant account.
/// Products/checkout are only available for approved Shitreed store records.
class OsmPlace {
  const OsmPlace({
    required this.id,
    required this.name,
    required this.category,
    required this.address,
    required this.latitude,
    required this.longitude,
  });
  final String id;
  final String name;
  final String category;
  final String address;
  final double latitude;
  final double longitude;

  static OsmPlace? fromJson(Object? object) {
    if (object is! Map) return null;
    final data = Map<String, dynamic>.from(object);
    final id = data['id'], name = data['name'];
    final latitude = data['latitude'], longitude = data['longitude'];
    if (id is! String || id.isEmpty || name is! String || name.isEmpty ||
        latitude is! num || longitude is! num ||
        !latitude.toDouble().isFinite || !longitude.toDouble().isFinite ||
        latitude < 29 || latitude > 37.7 ||
        longitude < 38.5 || longitude > 48.9) return null;
    return OsmPlace(
      id: id,
      name: name,
      category: data['category'] is String ? data['category'] as String : 'محل أو خدمة',
      address: data['address'] is String ? data['address'] as String : 'العراق',
      latitude: latitude.toDouble(), longitude: longitude.toDouble(),
    );
  }
}

class OsmDiscoveryService {
  /// All queries are explicitly user-triggered; never on every map pan.
  static Future<List<OsmPlace>> nearby({
    required double latitude, required double longitude,
  }) async {
    if (!MarketplaceBackend.configured) {
      throw StateError('يلزم ربط Supabase بشتريد');
    }
    final response = await Supabase.instance.client.functions.invoke(
      'nearby-osm',
      body: {'latitude': latitude, 'longitude': longitude},
    );
    if (response.status != 200) {
      throw StateError('خدمة المحلات غير متاحة حالياً');
    }
    final dynamic payload = response.data is String
        ? jsonDecode(response.data as String) : response.data;
    if (payload is! Map || payload['places'] is! List ||
        payload['source'] != 'OpenStreetMap') {
      throw const FormatException('Invalid OSM discovery payload');
    }
    return (payload['places'] as List)
        .map(OsmPlace.fromJson)
        .whereType<OsmPlace>()
        .toList(growable: false);
  }

  static String friendlyError(Object error) {
    if (error is FunctionException) {
      if (error.status == 429) {
        return 'وصلنا حدّ البحث التجريبي عن المحلات. جرّب لاحقاً.';
      }
      if (error.status == 404) {
        return 'خدمة اكتشاف المحلات تحتاج تحديثاً من إدارة شتريد.';
      }
      if (error.status == 400) {
        return 'ابحث داخل حدود العراق فقط.';
      }
      return 'خدمة OpenStreetMap مشغولة حالياً. جرّب مرة ثانية لاحقاً.';
    }
    if (error is FunctionsFetchException || error is FunctionsRelayException) {
      return 'تعذّر الاتصال بالخادم. تحقق من الإنترنت.';
    }
    return 'تعذر تحميل المحلات حالياً. متاجر شتريد المعتمدة تظهر بشكل مستقل.';
  }
}
