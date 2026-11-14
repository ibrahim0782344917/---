import 'dart:convert';
import 'dart:math';

/// One idempotency key for each unchanged checkout payload.
///
/// If the network fails after the server creates an order, retrying with this
/// token returns the original order instead of charging/reserving stock twice.
/// The key changes whenever store, cart, delivery details, or notes change.
class CheckoutRequestToken {
  CheckoutRequestToken({String Function()? idGenerator})
      : _idGenerator = idGenerator ?? _uuidV4;

  final String Function() _idGenerator;
  String? _payload;
  String? _requestId;

  String forOrder({
    required String storeId,
    required Iterable<({String productId, int quantity})> items,
    required String deliveryAddress,
    required String phone,
    required String notes,
  }) {
    final sorted = items.toList()
      ..sort((a, b) => a.productId.compareTo(b.productId));
    final payload = jsonEncode({
      'store_id': storeId,
      'items': [
        for (final line in sorted)
          {'product_id': line.productId, 'quantity': line.quantity},
      ],
      'delivery_address': deliveryAddress.trim(),
      'phone': phone.trim(),
      'notes': notes.trim(),
    });
    if (_payload != payload || _requestId == null) {
      _payload = payload;
      _requestId = _idGenerator();
    }
    return _requestId!;
  }

  void reset() {
    _payload = null;
    _requestId = null;
  }

  static String _uuidV4() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-'
        '${hex.substring(20)}';
  }
}
