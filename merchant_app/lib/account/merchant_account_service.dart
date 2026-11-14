import 'package:supabase_flutter/supabase_flutter.dart';

/// Merchant account operations always use the signed-in Supabase session.
/// Never embed a service_role key or writable admin credentials in Android.
class MerchantAccountService {
  MerchantAccountService._();

  static SupabaseClient get _db => Supabase.instance.client;

  static String get _userId {
    final id = _db.auth.currentUser?.id;
    if (id == null) throw StateError('LOGIN_REQUIRED');
    return id;
  }

  static String? get accountEmail => _db.auth.currentUser?.email;

  static Future<String> openSupportTicket({
    required String subject,
    required String message,
  }) async {
    _userId;
    final id = await _db.rpc('shitreed_merchant_open_ticket', params: {
      'p_subject': subject.trim(),
      'p_body': message.trim(),
    });
    return id.toString();
  }

  static Future<List<Map<String, dynamic>>> myTickets() async {
    final user = _userId;
    final rows = await _db.from('shitreed_merchant_support_tickets')
        .select('id,subject,status,created_at')
        .eq('user_id', user)
        .order('created_at', ascending: false)
        .limit(30);
    return rows;
  }

  /// Submits a request only. Account and business records are NOT deleted
  /// immediately; a controlled deletion/retention workflow must follow.
  static Future<String> requestAccountDeletion(String note) async {
    _userId;
    final id = await _db.rpc('shitreed_merchant_request_deletion',
      params: {'p_note': note.trim()});
    return id.toString();
  }

  static Future<List<Map<String, dynamic>>> myDeletionRequests() async {
    final user = _userId;
    final rows = await _db.from('shitreed_merchant_deletion_requests')
        .select('id,status,created_at,updated_at')
        .eq('user_id', user)
        .order('created_at', ascending: false)
        .limit(10);
    return rows;
  }
}
