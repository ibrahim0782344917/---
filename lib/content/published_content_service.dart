import 'package:supabase_flutter/supabase_flutter.dart';

/// Metadata-only access to reviewed, published articles, recipes and videos.
/// Media must be uploaded by an authorized owner/editor in the Admin workflow.
class PublicContent {
  final String id;
  final String storeId;
  final String kind;
  final String title;
  final String body;
  final String ingredients;
  final String safetyNote;
  final String? imageUrl;
  final String? videoUrl;

  const PublicContent({
    required this.id,
    required this.storeId,
    required this.kind,
    required this.title,
    required this.body,
    required this.ingredients,
    required this.safetyNote,
    this.imageUrl,
    this.videoUrl,
  });

  factory PublicContent.fromRow(Map<String, dynamic> row) => PublicContent(
        id: row['id'] as String,
        storeId: row['store_id'] as String,
        kind: row['kind'] as String,
        title: row['title'] as String,
        body: row['body'] as String? ?? '',
        ingredients: row['ingredients'] as String? ?? '',
        safetyNote: row['safety_note'] as String? ?? '',
        imageUrl: row['image_url'] as String?,
        videoUrl: row['video_url'] as String?,
      );
}

class PublishedContentService {
  PublishedContentService._();

  /// Client-side published filter is mandatory: owners may read drafts via RLS,
  /// and customer-facing listings must never accidentally display them.
  static Future<List<PublicContent>> published({String? storeId}) async {
    var query = Supabase.instance.client
        .from('alani_publications')
        .select('id,store_id,kind,title,body,ingredients,safety_note,image_url,video_url')
        .eq('status', 'published');
    if (storeId != null) query = query.eq('store_id', storeId);
    final rows = await query.order('published_at', ascending: false).limit(60);
    return rows.map((row) => PublicContent.fromRow(row)).toList(growable: false);
  }
}
