import 'package:supabase_flutter/supabase_flutter.dart';

/// Social actions are enforced again by SQL RPCs and RLS, not by the widget.
class AlAniSocialApi {
  const AlAniSocialApi._();
  static SupabaseClient get client => Supabase.instance.client;

  static String get userId => client.auth.currentUser?.id ?? '';

  static Future<Map<String, dynamic>> summary(String postId) async {
    final value = await client.rpc('alani_social_summary',
        params: {'p_id': postId});
    return Map<String, dynamic>.from(value as Map);
  }

  static Future<bool> reaction(String postId, String kind) async {
    final value = await client.rpc('alani_toggle_reaction',
        params: {'p_id': postId, 'p_kind': kind});
    return value == true;
  }

  static Future<void> rating(String postId, int stars) async {
    await client.rpc('alani_rate_publication',
        params: {'p_id': postId, 'p_stars': stars});
  }

  static Future<List<Map<String, dynamic>>> comments(String postId) async {
    final rows = await client.from('alani_post_comments')
        .select('id,user_id,body,status,created_at')
        .eq('publication_id', postId)
        .order('created_at', ascending: false).limit(70);
    return rows.map((row) => Map<String, dynamic>.from(row))
        .toList(growable: false);
  }

  static Future<void> comment(String postId, String body) async {
    await client.rpc('alani_submit_comment',
        params: {'p_id': postId, 'p_body': body});
  }

  static Future<void> editComment(
      String commentId, String body, {bool delete = false}) async {
    await client.rpc('alani_edit_own_comment',
        params: {'p_id': commentId, 'p_body': body, 'p_delete': delete});
  }

  static Future<void> report(String postId, String? commentId,
      String reason) async {
    await client.rpc('alani_report_content', params: {
      'p_id': postId, 'p_comment_id': commentId, 'p_reason': reason,
    });
  }

  static String shareLink(String postId) =>
      'https://alani-site-admin-staging.up.railway.app/#post=$postId';
}
