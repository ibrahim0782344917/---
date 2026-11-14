/// The buyer and merchant must use separate accounts for real orders.
/// A store owner buying from their own store must not be counted as a sale.
class MerchantOrderRules {
  const MerchantOrderRules._();

  static bool isSelfPurchase({String? buyerId, String? merchantUserId}) =>
      buyerId != null && merchantUserId != null && buyerId == merchantUserId;

  /// Error messages for merchant-safe presentation: never show raw SQL details,
  /// buyer private data or database internals inside a SnackBar.
  static String friendlyStatusError(Object error) {
    final description = error.toString();
    if (description.contains('INVALID_BUYER_TRANSITION')) {
      return 'الطلب صادر من حسابك نفسه كزبون. لا يمكنك قبوله كتاجر؛ استخدم حساب زبون منفصل للاختبار.';
    }
    if (description.contains('INVALID_MERCHANT_TRANSITION')) {
      return 'حالة الطلب تغيرت أو العملية غير متاحة حالياً. حدّث الطلبات.';
    }
    if (description.contains('PERMISSION_DENIED')) {
      return 'ما عندك صلاحية تعديل هذا الطلب.';
    }
    if (description.contains('ORDER_NOT_FOUND')) {
      return 'الطلب غير موجود أو لم يعد متاحاً.';
    }
    if (description.contains('LOGIN_REQUIRED')) {
      return 'انتهت جلسة الدخول. سجّل الدخول مجدداً.';
    }
    return 'تعذر تعديل حالة الطلب. تحقق من الإنترنت أو تواصل مع الدعم.';
  }
}
