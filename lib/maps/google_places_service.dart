import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shitreed_customer/backend/marketplace_backend.dart';

/// Temporary Google Places data. Never persist these results as verified stores.
/// Product inventory and checkout remain exclusive to approved Supabase merchants.
class GooglePlaceStore {
  const GooglePlaceStore({
    required this.id,
    required this.name,
    required this.address,
    required this.category,
    required this.latitude,
    required this.longitude,
  });

  final String id;
  final String name;
  final String address;
  final String category;
  final double latitude;
  final double longitude;

  static GooglePlaceStore? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final data = Map<String, dynamic>.from(raw);
    final latitude = data['latitude'];
    final longitude = data['longitude'];
    final id = data['id'];
    final name = data['name'];
    if (latitude is! num || longitude is! num ||
        id is! String || id.isEmpty || name is! String || name.isEmpty) {
      return null;
    }
    return GooglePlaceStore(
      id: id,
      name: name,
      address: data['address'] is String ? data['address'] as String : '',
      category: data['category'] is String ? data['category'] as String : 'محل',
      latitude: latitude.toDouble(),
      longitude: longitude.toDouble(),
    );
  }
}

class GooglePlacesService {
  /// Calls the protected server-side Places proxy, never Google with an app key.
  /// Only the current results are kept in widget memory (not Supabase).
  static Future<List<GooglePlaceStore>> nearby({
    required double latitude,
    required double longitude,
  }) async {
    if (!MarketplaceBackend.configured) {
      throw StateError('يلزم اتصال قاعدة شتريد');
    }
    final response = await Supabase.instance.client.functions.invoke(
      'nearby-shops',
      body: {'latitude': latitude, 'longitude': longitude},
    );
    if (response.status != 200) {
      throw StateError('خدمة محلات Google غير متاحة حالياً');
    }
    final dynamic data =
        response.data is String ? jsonDecode(response.data as String) : response.data;
    if (data is! Map || data['places'] is! List) {
      throw const FormatException('Invalid Places response');
    }
    return (data['places'] as List)
        .map(GooglePlaceStore.fromJson)
        .whereType<GooglePlaceStore>()
        .toList(growable: false);
  }
}
