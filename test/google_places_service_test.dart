import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shitreed_customer/maps/google_places_service.dart';

void main() {
  test('converts Google place fields safely', () {
    final store = GooglePlaceStore.fromJson({
      'id': 'ChIJ-example',
      'name': 'محل في بغداد',
      'address': 'الكرادة، بغداد',
      'category': 'سوبرماركت',
      'latitude': 33.3,
      'longitude': 44.4,
    });
    expect(store, isNotNull);
    expect(store!.name, 'محل في بغداد');
    expect(store.latitude, 33.3);
    expect(store.category, 'سوبرماركت');
  });

  test('shows an actionable message when Places is not enabled', () {
    final message = GooglePlacesService.errorMessage(
      FunctionsHttpException(
        status: 503,
        details: {'code': 'PLACES_NOT_ENABLED'},
      ),
    );
    expect(message, contains('مو مفعّل'));
    expect(message, contains('المعتمدة'));
  });

  test('tells a missing Edge Function apart from a throttled call', () {
    expect(
      GooglePlacesService.errorMessage(
        FunctionsHttpException(status: 404)),
      contains('مو منشورة'),
    );
    expect(
      GooglePlacesService.errorMessage(
        FunctionsHttpException(status: 429)),
      contains('الحد المسموح'),
    );
  });

  test('rejects incomplete Google place results', () {
    expect(GooglePlaceStore.fromJson({'id': '1', 'name': 'محل'}), isNull);
    expect(GooglePlaceStore.fromJson({'latitude': 1, 'longitude': 2}), isNull);
    expect(GooglePlaceStore.fromJson(null), isNull);
  });
}
