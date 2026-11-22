import 'dart:math';
import 'package:file_picker/file_picker.dart';
import 'admin_api.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AlAniAdminUploadedVideo {
  final String path;
  final String url;
  const AlAniAdminUploadedVideo(this.path, this.url);
}

/// Admin uses its authenticated Supabase session. Storage RLS enforces ownership.
class AlAniAdminGallery {
  static const storeId = '25091ca2-c0da-416c-b634-81b188ee66be';
  static const bucket = 'alani-reels';
  static const maxBytes = 40 * 1024 * 1024;

  static String? validate(String name, int length) {
    if (!name.toLowerCase().endsWith('.mp4')) {
      return 'الاستوديو: مطلوب فيديو MP4 فقط.';
    }
    if (length <= 0 || length > maxBytes) {
      return 'الحد الأقصى للفيديو ٤٠ ميغابايت.';
    }
    return null;
  }

  static Future<AlAniAdminUploadedVideo> upload(PlatformFile file) async {
    final client = AdminApi.client;
    final user = client.auth.currentUser;
    if (user == null) throw StateError('سجل الدخول بحساب المالك أولاً.');
    final validation = validate(file.name, file.size);
    if (validation != null) throw FormatException(validation);
    final store = await client.from('stores')
      .select('owner_id,status').eq('id', storeId).maybeSingle();
    if (store == null || store['owner_id'] != user.id ||
        store['status'] != 'approved') {
      throw StateError('فقط حساب مالك المتجر المعتمد يرفع الفيديو.');
    }
    final bytes = file.bytes;
    if (bytes == null || validate(file.name, bytes.length) != null) {
      throw StateError('تعذر قراءة ملف الفيديو من الاستوديو.');
    }
    final random = Random.secure();
    final nonce = List.generate(4, (_) =>
      random.nextInt(0x100000000).toRadixString(16).padLeft(8, '0')).join();
    final path = '$storeId/${user.id}/$nonce.mp4';
    final storage = client.storage.from(bucket);
    await storage.uploadBinary(path, bytes,
      fileOptions: const FileOptions(contentType:'video/mp4', upsert:false));
    return AlAniAdminUploadedVideo(path,storage.getPublicUrl(path));
  }

  static Future<void> remove(String path) async {
    await AdminApi.client.storage.from(bucket).remove([path]);
  }
