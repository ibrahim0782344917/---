import 'package:flutter_test/flutter_test.dart';
import 'package:shitreed_admin/alani_gallery_upload.dart';

void main() {
  test('admin gallery accepts only MP4 videos within size bounds', () {
    expect(AlAniAdminGallery.validate('oil.mp4', 1024),isNull);
    expect(AlAniAdminGallery.validate('oil.MP4', 1024),isNull);
    expect(AlAniAdminGallery.validate('oil.mp4', 0),isNotNull);
    expect(AlAniAdminGallery.validate('oil.mov', 1024),isNotNull);
    expect(AlAniAdminGallery.validate('oil.mp4',
      AlAniAdminGallery.maxBytes+1),isNotNull);
  });
}
