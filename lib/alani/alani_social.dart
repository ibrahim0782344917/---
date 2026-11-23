import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

/// Uses the reviewed, RLS-aware social RPCs. This is enabled for the isolated
/// test project only; production needs its own explicit approval.
class AlAniSocialActions extends StatefulWidget {
  const AlAniSocialActions({
    super.key, required this.publicationId, this.dark = false,
    this.vertical = false,
  });

  final String publicationId;
  final bool dark;
  final bool vertical;

  @override
  State<AlAniSocialActions> createState() => _AlAniSocialActionsState();
}

class _AlAniSocialActionsState extends State<AlAniSocialActions> {
  static const _testUrl = 'https://tgvdwotbrnhcoykuxdpr.supabase.co';
  static const enabled =
      bool.fromEnvironment('ALANI_SOCIAL_ENABLED', defaultValue: false) &&
      (String.fromEnvironment('SUPABASE_URL') == _testUrl ||
       bool.fromEnvironment('ALANI_SOCIAL_PRODUCTION_APPROVED',
         defaultValue: false));

  SupabaseClient get db => Supabase.instance.client;
  int likes = 0;
  int comments = 0;
  bool liked = false;
  bool saved = false;
  bool busy = false;
  bool loaded = false;

  @override
  void initState() {
    super.initState();
    if (enabled) _refresh();
  }

  @override
  void didUpdateWidget(covariant AlAniSocialActions oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.publicationId != widget.publicationId && enabled) {
      setState(() {
        likes = 0; comments = 0; liked = false; saved = false; loaded = false;
      });
      _refresh();
    }
  }

  void notice(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)));
  }

  Future<void> _refresh() async {
    if (!enabled || db.auth.currentUser == null) return;
    try {
      final response = await db.rpc('alani_social_summary',
        params: {'p_id': widget.publicationId});
      final stats = Map<String, dynamic>.from(response as Map);
      if (mounted) setState(() {
        likes = (stats['likes'] as num?)?.toInt() ?? 0;
        comments = (stats['comments'] as num?)?.toInt() ?? 0;
        liked = stats['liked'] == true;
        saved = stats['saved'] == true;
        loaded = true;
      });
    } catch (_) {
      notice('تعذّر تحميل التفاعلات. جرّب تحديث الصفحة.');
    }
  }

  bool requireLogin() {
    if (db.auth.currentUser != null) return true;
    notice('سجّل دخولك أولاً للإعجاب أو الحفظ أو التعليق.');
    return false;
  }

  Future<void> toggle(String kind) async {
    if (!enabled || busy || !requireLogin()) return;
    setState(() => busy = true);
    try {
      // Database RPC verifies published content, current user and unique likes.
      await db.rpc('alani_toggle_reaction',
        params: {'p_id': widget.publicationId, 'p_kind': kind});
      await _refresh();
    } catch (_) {
      notice('تعذّر حفظ التفاعل، حاول مرة ثانية.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  static const _publicUrl = String.fromEnvironment('ALANI_PUBLIC_URL',
    defaultValue: 'https://alani-site-admin-staging.up.railway.app');

  String get shareUrl =>
      '$_publicUrl/?post=${Uri.encodeComponent(widget.publicationId)}';

  Future<void> _shareWith(String kind) async {
    final url = switch (kind) {
      'whatsapp' => Uri.https('wa.me', '/', {'text': shareUrl}),
      'telegram' => Uri.https('t.me', '/share/url', {
          'url': shareUrl,
          'text': 'منشور من السيد إبراهيم العاني',
        }),
      _ => null,
    };
    if (url == null) return;
    try {
      if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
        notice('تعذّر فتح تطبيق المشاركة.');
      }
    } catch (_) {
      notice('تعذّر فتح تطبيق المشاركة.');
    }
  }

  Future<void> share() async {
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('مشاركة المنشور', style: TextStyle(
            fontWeight: FontWeight.w800, fontSize: 19)),
          const SizedBox(height: 14),
          Wrap(spacing: 16, alignment: WrapAlignment.center, children: [
            ActionChip(
              avatar: const Icon(Icons.copy_outlined),
              label: const Text('نسخ الرابط'),
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: shareUrl));
                if (sheetContext.mounted) Navigator.pop(sheetContext);
                notice('تم نسخ رابط المنشور.');
              },
            ),
            ActionChip(
              avatar: const Icon(Icons.chat_outlined),
              label: const Text('واتساب'),
              onPressed: () {
                Navigator.pop(sheetContext);
                _shareWith('whatsapp');
              },
            ),
            ActionChip(
              avatar: const Icon(Icons.send_outlined),
              label: const Text('تلغرام'),
              onPressed: () {
                Navigator.pop(sheetContext);
                _shareWith('telegram');
              },
            ),
          ]),
          const SizedBox(height: 12),
          const Text('تُفتح التطبيقات الخارجية فقط بعد اختيارك لها.',
            style: TextStyle(fontSize: 12)),
        ]),
      )),
    );
  }

  Future<void> _comment() async {
    if (!enabled || !requireLogin()) return;
    final controller = TextEditingController();
    try {
      final submitted = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('إضافة تعليق'),
          content: TextField(
            controller: controller, minLines: 2, maxLines: 5,
            maxLength: 500,
            decoration: const InputDecoration(
              labelText: 'التعليق يظهر بعد موافقة المشرف',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('إلغاء')),
            FilledButton(onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('إرسال')),
          ],
        ),
      );
      if (submitted != true) return;
      final body = controller.text.trim();
      if (body.length < 3 || body.length > 500) {
        notice('التعليق لازم يكون بين 3 و500 حرف.');
        return;
      }
      await db.rpc('alani_submit_comment',
        params: {'p_id': widget.publicationId, 'p_body': body});
      notice('انرسل تعليقك للمراجعة، ما راح يظهر إلا بعد الموافقة.');
      await _refresh();
    } catch (_) {
      notice('ما تم إرسال التعليق. حاول مرة ثانية.');
    } finally {
      controller.dispose();
    }
  }

  Future<void> _viewComments() async {
    if (!enabled) return;
    try {
      final rows = await db.from('alani_post_comments')
        .select('id,body,created_at')
        .eq('publication_id', widget.publicationId)
        .eq('status', 'approved')
        .order('created_at', ascending: false).limit(50);
      if (!mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (sheetContext) => SafeArea(child: SizedBox(
          height: MediaQuery.sizeOf(sheetContext).height * .64,
          child: Column(children: [
            Padding(padding: const EdgeInsets.all(12),
              child: Row(children: [
                const Expanded(child: Text('التعليقات المعتمدة',
                  style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700))),
                IconButton(
                  tooltip: 'إضافة تعليق',
                  onPressed: () {
                    Navigator.pop(sheetContext);
                    _comment();
                  },
                  icon: const Icon(Icons.add_comment_outlined),
                ),
              ])),
            Expanded(child: rows.isEmpty
              ? const Center(child: Text('لا توجد تعليقات معتمدة بعد.'))
              : ListView.builder(
                  itemCount: rows.length,
                  itemBuilder: (_, index) {
                    final body = rows[index]['body']?.toString() ?? '';
                    return ListTile(
                      leading: const CircleAvatar(child: Icon(Icons.person)),
                      title: Text(body),
                      subtitle: const Text('تعليق معتمد'),
                    );
                  })),
          ]),
        )),
      );
    } catch (_) {
      notice('تعذّر عرض التعليقات حالياً.');
    }
  }

  Future<void> report() async {
    if (!enabled || !requireLogin()) return;
    final kind = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const ListTile(title: Text('سبب الإبلاغ'),
            subtitle: Text('يُراجع من فريق الإشراف')),
          for (final reason in const [
            ('spam', 'محتوى مزعج'),
            ('abuse', 'إساءة'),
            ('misleading', 'معلومات مضللة'),
            ('unsafe', 'محتوى غير آمن'),
            ('other', 'سبب آخر'),
          ])
            ListTile(title: Text(reason.$2),
              onTap: () => Navigator.pop(sheetContext, reason.$1)),
        ],
      )),
    );
    if (kind == null) return;
    try {
      await db.rpc('alani_report_content', params: {
        'p_id': widget.publicationId,
        'p_comment_id': null,
        'p_reason': kind,
      });
      notice('تم تسجيل البلاغ لدى الإشراف.');
    } catch (_) {
      notice('تعذّر تسجيل البلاغ أو يوجد بلاغ سابق.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.dark ? Colors.white : const Color(0xFF08714A);
    final icons = <Widget>[
      IconButton(tooltip: 'إعجاب',
        onPressed: enabled && !busy ? () => toggle('like') : null,
        icon: Icon(liked ? Icons.favorite : Icons.favorite_border,
          color: liked ? Colors.redAccent : color)),
      Text(loaded ? '$likes' : '—', style: TextStyle(color: color)),
      IconButton(tooltip: 'حفظ المنشور',
        onPressed: enabled && !busy ? () => toggle('save') : null,
        icon: Icon(saved ? Icons.bookmark : Icons.bookmark_outline,
          color: color)),
      IconButton(tooltip: 'التعليقات',
        onPressed: enabled ? _viewComments : null,
        icon: Icon(Icons.mode_comment_outlined, color: color)),
      Text(loaded ? '$comments' : '—', style: TextStyle(color: color)),
      IconButton(tooltip: 'مشاركة المنشور',
        onPressed: share,
        icon: Icon(Icons.share_outlined, color: color)),
      IconButton(tooltip: 'إبلاغ عن المحتوى',
        onPressed: enabled ? report : null,
        icon: Icon(Icons.flag_outlined, color: color)),
    ];
    return Column(mainAxisSize: MainAxisSize.min, children: [
      if (widget.vertical)
        Column(mainAxisSize: MainAxisSize.min, children: icons)
      else
        Wrap(alignment: WrapAlignment.start,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 2, children: icons),
      if (!enabled)
        const Text('التفاعلات قيد التفعيل',
          style: TextStyle(color: Colors.grey, fontSize: 11)),
      if (enabled && db.auth.currentUser == null)
        const Text('سجّل دخولك للتفاعل',
          style: TextStyle(color: Colors.grey, fontSize: 11)),
    ]);
  }
}
