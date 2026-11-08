import 'package:flutter_test/flutter_test.dart';
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

  test('rejects incomplete Google place results', () {
    expect(GooglePlaceStore.fromJson({'id': '1', 'name': 'محل'}), isNull);
    expect(GooglePlaceStore.fromJson({'latitude': 1, 'longitude': 2}), isNull);
    expect(GooglePlaceStore.fromJson(null), isNull);
  });
}
