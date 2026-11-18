import 'package:shitreed_customer/backend/marketplace_backend.dart';
import 'package:shitreed_customer/commerce/commerce_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Independent storefront flavor. This ID is public, not an API credential.
/// It points to the already-approved Al-Ani store in Shitreed.
class AlAniSettings {
  static const storeId = String.fromEnvironment(
    'ALANI_STORE_ID',
    defaultValue: '25091ca2-c0da-416c-b634-81b188ee66be',
  );
  static const title = 'السيد إبراهيم العاني';
  static const subtitle = 'الزيوت الطبيعية • الأعشاب • المنتجات الطبيعية';
  static const area = 'بغداد - الغزالية';
}

class AlAniPublication {
  final String id;
  final String kind;
  final String title;
  final String body;
  final String? imageUrl;
  final String? videoUrl;
  final String ingredients;
  final String safetyNote;
  final DateTime? publishedAt;

  const AlAniPublication({
    required this.id,
    required this.kind,
    required this.title,
    required this.body,
    required this.ingredients,
    required this.safetyNote,
    this.imageUrl,
    this.videoUrl,
    this.publishedAt,
  });

  factory AlAniPublication.fromJson(Map<String, dynamic> data) {
    return AlAniPublication(
      id: data['id'] as String,
      kind: data['kind'] as String,
      title: data['title'] as String,
      body: (data['body'] as String?) ?? '',
      ingredients: (data['ingredients'] as String?) ?? '',
      safetyNote: (data['safety_note'] as String?) ?? '',
      imageUrl: data['image_url'] as String?,
      videoUrl: data['video_url'] as String?,
      publishedAt: DateTime.tryParse(
        (data['published_at'] as String?) ?? '',
      ),
    );
  }
}

/// Reads only the single approved shop. Never creates fictional products or
/// checks out against another merchant's account.
class AlAniStoreData {
  const AlAniStoreData._();

  static Future<List<MarketplaceProduct>> products() async {
    if (!MarketplaceBackend.configured || AlAniSettings.storeId.isEmpty) {
      return const [];
    }
    if (!await CommerceService.isStoreApproved(AlAniSettings.storeId)) {
      return const [];
    }
    return CommerceService.storeProducts(AlAniSettings.storeId);
  }

  /// Content is optional until docs/ALANI_CONTENT_SCHEMA_REVIEW.sql has been
  /// reviewed and deployed to a separate test database. Failure is surfaced
  /// in the UI, not disguised as empty published content.
  static Future<List<AlAniPublication>> publications() async {
    if (!MarketplaceBackend.configured || AlAniSettings.storeId.isEmpty) {
      return const [];
    }
    final rows = await Supabase.instance.client
        .from('alani_publications')
        .select(
          'id,kind,title,body,ingredients,safety_note,image_url,'
          'video_url,published_at',
        )
        .eq('store_id', AlAniSettings.storeId)
        .eq('status', 'published')
        .order('published_at', ascending: false)
        .limit(100);
    return rows.map((row) => AlAniPublication.fromJson(row)).toList();
  }
}
