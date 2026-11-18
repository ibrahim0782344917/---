import 'package:flutter/material.dart';
import 'package:shitreed_customer/alani/alani_content.dart';
import 'package:shitreed_customer/backend/marketplace_backend.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _green = Color(0xFF1C503B);

/// The server RLS policies are the authorization boundary.
/// A client-side owner check is only a convenience for the admin UI.
class AlAniEditorService {
  const AlAniEditorService._();

  static Future<bool> isOwner() async {
    final user = MarketplaceBackend.currentUser;
    if (!MarketplaceBackend.configured || user == null) return false;
    final row = await Supabase.instance.client.from('stores')
        .select('owner_id')
        .eq('id', AlAniSettings.storeId)
        .maybeSingle();
    return row != null && row['owner_id'] == user.id;
  }

  static Future<List<Map<String, dynamic>>> entries() async {
    final rows = await Supabase.instance.client
        .from('alani_publications')
        .select('id,kind,title,body,status,ingredients,safety_note,'
          'image_url,video_url,created_at')
        .eq('store_id', AlAniSettings.storeId)
        .order('created_at', ascending: false);
    return rows;
  }
}

class AlAniEditorPage extends StatefulWidget {
  const AlAniEditorPage({super.key});
  @override
  State<AlAniEditorPage> createState() => _AlAniEditorPageState();
}

class _AlAniEditorPageState extends State<AlAniEditorPage> {
  late Future<bool> _owner;
  late Future<List<Map<String, dynamic>>> _entries;

  @override
  void initState() {
    super.initState();
    _owner = AlAniEditorService.isOwner();
    _entries = AlAniEditorService.entries();
  }

  Future<void> _reload() async {
    setState(() => _entries = AlAniEditorService.entries());
    try { await _entries; } catch (_) { /* Error shown below. */ }
  }

  Future<void> _edit([Map<String, dynamic>? initial]) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => AlAniEditPublicationPage(initial: initial)),
    );
    if (changed == true) await _reload();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('إدارة فيديوهات ومقالات المتجر')),
    floatingActionButton: FutureBuilder<bool>(
      future: _owner,
      builder: (context, snapshot) => snapshot.data == true
        ? FloatingActionButton.extended(
            onPressed: () => _edit(),
            icon: const Icon(Icons.add),
            label: const Text('منشور جديد'),
          )
        : const SizedBox.shrink(),
    ),
    body: FutureBuilder<bool>(
      future: _owner,
      builder: (context, auth) {
        if (auth.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (auth.data != true) {
          return const Center(child: Padding(
            padding: EdgeInsets.all(20),
            child: Text(
              'هذه الإدارة مخصصة لصاحب المتجر فقط. '
              'سجّل دخولاً بالحساب المالك للمتجر.',
              textAlign: TextAlign.center,
            ),
          ));
        }
        return RefreshIndicator(
          onRefresh: _reload,
          child: FutureBuilder<List<Map<String, dynamic>>>(
            future: _entries,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return ListView(children: const [
                  Padding(padding: EdgeInsets.all(20),
                    child: Text('جدول المقالات والفيديوهات لم يُفعّل بعد. '
                      'راجع ملف ALANI_CONTENT_SCHEMA_REVIEW.sql '
                      'على بيئة الاختبار أولاً.')),
                ]);
              }
              final rows = snapshot.data ?? [];
              if (rows.isEmpty) {
                return ListView(children: const [
                  Padding(padding: EdgeInsets.all(28),
                    child: Text('لا توجد منشورات. أنشئ أول مقال أو فيديو.',
                      textAlign: TextAlign.center)),
                ]);
              }
              return ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: rows.length,
                itemBuilder: (context, index) {
                  final row = rows[index];
                  return Card(child: ListTile(
                    title: Text(row['title'] as String? ?? ''),
                    subtitle: Text((row['kind'] as String? ?? '') + ' • ' +
                      (row['status'] == 'published' ? 'منشور' : 'مسودة')),
                    trailing: const Icon(Icons.edit_outlined),
                    onTap: () => _edit(row),
                  ));
                },
              );
            },
          ),
        );
      },
    ),
  );
}

class AlAniEditPublicationPage extends StatefulWidget {
  final Map<String, dynamic>? initial;
  const AlAniEditPublicationPage({super.key, this.initial});

  @override
  State<AlAniEditPublicationPage> createState() =>
      _AlAniEditPublicationPageState();
}

class _AlAniEditPublicationPageState
    extends State<AlAniEditPublicationPage> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _title;
  late final TextEditingController _body;
  late final TextEditingController _ingredients;
  late final TextEditingController _warning;
  late final TextEditingController _image;
  late final TextEditingController _video;
  late String _kind;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial ?? {};
    _title = TextEditingController(text: initial['title'] as String? ?? '');
    _body = TextEditingController(text: initial['body'] as String? ?? '');
    _ingredients = TextEditingController(
      text: initial['ingredients'] as String? ?? '');
    _warning = TextEditingController(
      text: initial['safety_note'] as String? ?? '');
    _image = TextEditingController(
      text: initial['image_url'] as String? ?? '');
    _video = TextEditingController(
      text: initial['video_url'] as String? ?? '');
    _kind = initial['kind'] as String? ?? 'post';
  }

  @override
  void dispose() {
    for (final controller in [
      _title, _body, _ingredients, _warning, _image, _video,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  String? _httpsOrEmpty(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final uri = Uri.tryParse(value.trim());
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
      return 'استخدم رابط HTTPS صالحاً.';
    }
    return null;
  }

  Future<void> _save(String status) async {
    if (_busy || !_form.currentState!.validate()) return;
    if (_kind == 'video' && _video.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('أدخل رابط الفيديو قبل حفظه.'),
      ));
      return;
    }
    setState(() => _busy = true);
    try {
      final owner = await AlAniEditorService.isOwner();
      if (!owner) throw StateError('المالك غير مخوّل');
      final payload = <String, dynamic>{
        'store_id': AlAniSettings.storeId,
        'kind': _kind,
        'title': _title.text.trim(),
        'body': _body.text.trim(),
        'ingredients': _ingredients.text.trim(),
        'safety_note': _warning.text.trim(),
        'image_url': _image.text.trim().isEmpty ? null : _image.text.trim(),
        'video_url': _video.text.trim().isEmpty ? null : _video.text.trim(),
        'status': status,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
        if (status == 'published')
          'published_at': DateTime.now().toUtc().toIso8601String(),
      };
      final table = Supabase.instance.client.from('alani_publications');
      if (widget.initial == null) {
        await table.insert(payload);
      } else {
        await table.update(payload)
            .eq('id', widget.initial!['id'] as String)
            .eq('store_id', AlAniSettings.storeId);
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('تعذر الحفظ؛ تحقق من الصلاحيات وجدول المحتوى.'),
      ));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _field(
    String label, TextEditingController controller, {
    int maxLines = 1, int maxLength = 1000,
    String? Function(String?)? validator,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextFormField(
      controller: controller,
      minLines: maxLines == 1 ? 1 : 2,
      maxLines: maxLines,
      maxLength: maxLength,
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        alignLabelWithHint: maxLines > 1,
        border: const OutlineInputBorder(),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(
      widget.initial == null ? 'إنشاء محتوى جديد' : 'تعديل المنشور',
    )),
    body: Form(
      key: _form,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          DropdownButtonFormField<String>(
            initialValue: _kind,
            decoration: const InputDecoration(
              labelText: 'نوع المحتوى', border: OutlineInputBorder()),
            items: const [
              DropdownMenuItem(value: 'video', child: Text('فيديو')),
              DropdownMenuItem(value: 'recipe', child: Text('وصفة')),
              DropdownMenuItem(value: 'article', child: Text('مدونة / مقال')),
              DropdownMenuItem(value: 'post', child: Text('منشور نصي')),
            ],
            onChanged: (value) => setState(() => _kind = value ?? 'post'),
          ),
          const SizedBox(height: 12),
          _field('العنوان', _title, maxLength: 180,
            validator: (value) => (value ?? '').trim().length < 3
              ? 'العنوان يجب أن يحتوي على 3 أحرف على الأقل' : null),
          _field('النص / الشرح', _body, maxLines: 8, maxLength: 30000),
          if (_kind == 'recipe') ...[
            _field('المكونات', _ingredients,
              maxLines: 4, maxLength: 8000),
            _field('التحذيرات والاستعمال الآمن', _warning,
              maxLines: 4, maxLength: 4000),
          ],
          _field('رابط صورة HTTPS (اختياري)', _image,
            maxLength: 1000, validator: _httpsOrEmpty),
          if (_kind == 'video') _field('رابط الفيديو HTTPS', _video,
            maxLength: 1000, validator: _httpsOrEmpty),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: _busy ? null : () => _save('draft'),
            style: FilledButton.styleFrom(backgroundColor: _green),
            icon: const Icon(Icons.save_outlined),
            label: const Text('حفظ مسودة'),
          ),
          const SizedBox(height: 9),
          OutlinedButton.icon(
            onPressed: _busy ? null : () => _save('published'),
            icon: const Icon(Icons.publish_outlined),
            label: const Text('نشر المحتوى'),
          ),
          const SizedBox(height: 12),
          const Text('نشر الوصفات والادعاءات الصحية مسؤولية صاحب المتجر. '
            'يُمنع تقديم وعد علاجي مضلل. '
            'الفيديو يُشغّل عبر الرابط الخارجي في هذه النسخة.',
            style: TextStyle(fontSize: 12, color: Colors.black54)),
        ],
      ),
    ),
  );
}
