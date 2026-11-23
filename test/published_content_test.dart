import 'package:flutter_test/flutter_test.dart';
import 'package:shitreed_customer/content/published_content_service.dart';

void main() {
  test('published content parses optional media and recipe fields', () {
    final item = PublicContent.fromRow({
      'id': 'abc', 'store_id': 'store1', 'kind': 'recipe',
      'title': 'Test recipe', 'body': 'Instructions',
      'ingredients': 'Ingredients', 'safety_note': 'Not medical advice',
      'image_url': null, 'video_url': null,
    });
    expect(item.kind, 'recipe');
    expect(item.safetyNote, 'Not medical advice');
    expect(item.imageUrl, isNull);
  });
}
