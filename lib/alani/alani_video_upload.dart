import 'dart:math';

import 'package:image_picker/image_picker.dart';
import 'package:shitreed_customer/alani/alani_content.dart';
import 'package:shitreed_customer/alani/alani_editor.dart';
import 'package:shitreed_customer/backend/marketplace_backend.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Owner-only video uploads. The storage.objects RLS policy is the real guard.
class AlAniUploadedVideo {
  final String path;
  final String url;
  const AlAniUploadedVideo({required this.path, required this.url});
}

class AlAniGalleryVideos {
  static const bucket = 'alani-reels';
  static const maxBytes = 40 * 1024 * 1024;

  static String? validationError(String filename, int bytes) {
    if (!filename.toLowerCase().endsWith('.mp4')) {
      return 'اختَر فيديو بصيغة MP4 من الاستوديو.';
    }
    if (bytes == 0 || bytes > maxBytes) {
      return 'حجم الفيديو يجب أن يكون بين 1 بايت و40 ميغابايت.';
    }
    return null;
  }

  static Future<XFile?> pick() async =>
      ImagePicker().pickVideo(source: ImageSource.gallery);

  static Future<AlAniUploadedVideo> upload(XFile video) async {
    if (!MarketplaceBackend.configured ||
        !await AlAniEditorService.isOwner()) {
      throw StateError('فقط مالك المتجر يملك صلاحية رفع الفيديو.');
    }
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) throw StateError('يرجى تسجيل دخول مالك المتجر.');
    final size = await video.length();
    final error = validationError(video.name, size);
    if (error != null) throw FormatException(error);
    // Keep the object name unpredictable so unlisted draft assets cannot be
    // trivially guessed, although the bucket itself serves public media.
    final random = Random.secure();
    final nonce = List.generate(4, (_) =>
        random.nextInt(0x100000000).toRadixString(16).padLeft(8, '0')).join();
    final path = AlAniSettings.storeId + '/' + user.id + '/' + nonce + '.mp4';
    final storage = Supabase.instance.client.storage.from(bucket);
    // Validate size before loading the bytes into mobile memory.
    final bytes = await video.readAsBytes();
    if (validationError(video.name, bytes.length) != null) {
      throw StateError('تغير حجم الفيديو بعد اختياره، أعد المحاولة.');
    }
    await storage.uploadBinary(
      path,
      bytes,
      fileOptions: const FileOptions(contentType: 'video/mp4', upsert: false),
    );
    return AlAniUploadedVideo(path: path, url: storage.getPublicUrl(path));
  }

  static Future<void> remove(String path) async {
    if (!await AlAniEditorService.isOwner()) return;
    await Supabase.instance.client.storage.from(bucket).remove([path]);
  }
}
