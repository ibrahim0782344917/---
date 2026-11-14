import 'package:flutter_test/flutter_test.dart';
import 'package:shitreed_merchant/admin/store_reviews_page.dart';

void main() {
  test('merchant approvals require a meaningful review reason', () {
    expect(validReviewReason(''), isFalse);
    expect(validReviewReason('موافق'), isFalse);
    expect(validReviewReason('   تأكدت من المحل   '), isFalse);
    expect(validReviewReason(
      'تحققت من صاحب المتجر والعنوان وصحة بيانات الاتصال'),
      isTrue);
    expect(validReviewReason('أ' * 1001), isFalse);
  });
}
