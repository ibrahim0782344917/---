import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shitreed_customer/alani/alani_social_api.dart';
import 'package:shitreed_customer/auth/customer_auth_page.dart';
import 'package:shitreed_customer/backend/marketplace_backend.dart';

/// Likes, comments, saves, rating, reporting, sharing for every post type.
class AlAniSocialPanel extends StatefulWidget {
  final String publicationId;
  final bool compact;
  final bool dark;
  const AlAniSocialPanel({
    super.key, required this.publicationId,
    this.compact = false, this.dark = false,
  });

  @override
  State<AlAniSocialPanel> createState() => _AlAniSocialPanelState();
}

class _AlAniSocialPanelState extends State<AlAniSocialPanel> {
  late Future<Map<String, dynamic>> _stats;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _stats = AlAniSocialApi.summary(widget.publicationId);
  }

  @override
  void didUpdateWidget(covariant AlAniSocialPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.publicationId != widget.publicationId) _reload();
  }

  void _reload() => setState(() {
    _stats = AlAniSocialApi.summary(widget.publicationId);
  });

  void _notice(String msg) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg)));
  }

  Future<bool> _needsLogin() async {
    if (MarketplaceBackend.currentUser != null) return true;
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const CustomerAuthPage()));
    if (!mounted) return false;
    if (MarketplaceBackend.currentUser == null) {
      _notice('سجّل الدخول حتى تتفاعل مع المنشور.');
      return false;
    }
    return true;
  }

  Future<void> _act(Future<void> Function() command) async {
    if (_busy || !await _needsLogin()) return;
    if (!mounted) return;
    setState(() => _busy = true);
    try {
      await command();
      if (mounted) _reload();
    } catch (_) {
      _notice('تعذرت العملية. تحقق من الاتصال والصلاحيات أو حاول مرة ثانية.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _share() async {
    await Clipboard.setData(ClipboardData(
      text: AlAniSocialApi.shareLink(widget.publicationId)));
    _notice('تم نسخ رابط المنشور. يمكنك مشاركته مع الآخرين.');
  }

  Future<void> _rate() async {
    if (!await _needsLogin() || !mounted) return;
    final stars = await showDialog<int>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('قيّم هذا المحتوى'),
        children: [
          for (var score = 1; score <= 5; score++)
            SimpleDialogOption(
              onPressed: () => Navigator.of(ctx).pop(score),
              child: Row(children: [
                for (var j = 0; j < score; j++)
                  const Icon(Icons.star_rounded, color: Color(0xFFD49E39)),
                const SizedBox(width: 8),
                Text('$score / 5'),
              ]),
            ),
        ],
      ),
    );
    if (stars != null) {
      await _act(() => AlAniSocialApi.rating(widget.publicationId, stars));
    }
  }

  Future<void> _report([String? commentId]) async {
    if (!await _needsLogin() || !mounted) return;
    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('سبب التبليغ'),
        children: [
          for (final entry in const [
            ('spam','إعلانات مزعجة'),
            ('abuse','إساءة'),
            ('misleading','معلومات مضللة'),
            ('unsafe','محتوى خطير'),
            ('other','سبب آخر'),
          ]) SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, entry.$1),
            child: Text(entry.$2),
          ),
        ],
      ),
    );
    if (reason != null) {
      await _act(() => AlAniSocialApi.report(
        widget.publicationId, commentId, reason));
      _notice('تم تقديم البلاغ للمراجعة؛ لا تظهر بيانات حسابك للعامة.');
    }
  }

  Future<void> _editComment(Map<String, dynamic> entry) async {
    final c = TextEditingController(text: entry['body']?.toString() ?? '');
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تعديل التعليق'),
        content: TextField(
          controller: c,
          minLines: 2, maxLines: 4, maxLength: 500,
          decoration: const InputDecoration(labelText: 'التعليق'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, c.text.trim()),
            child: const Text('إرسال للمراجعة'),
          ),
        ],
      ),
    );
    c.dispose();
    if (result == null || result.length < 3) return;
    await _act(() => AlAniSocialApi.editComment(
      entry['id'] as String, result));
  }

  Future<void> _comments() async {
    final input = TextEditingController();
    Future<List<Map<String, dynamic>>> posts =
        AlAniSocialApi.comments(widget.publicationId);
    bool sending = false;
    await showModalBottomSheet<void>(
      context: context, isScrollControlled: true,
      showDragHandle: true,
      builder: (sheet) => StatefulBuilder(
        builder: (ctx, modalState) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(sheet).bottom),
          child: SizedBox(
            height: MediaQuery.sizeOf(sheet).height * 0.62,
            child: Column(children: [
              const Text('التعليقات', style: TextStyle(
                fontSize: 18, fontWeight: FontWeight.bold)),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                child: Text('التعليقات الجديدة تُراجع قبل ظهورها للجميع.',
                  textAlign: TextAlign.center),
              ),
              Expanded(child: FutureBuilder<List<Map<String, dynamic>>>(
                future: posts,
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    if (snapshot.hasError) {
                      return const Center(child: Text('تعذر تحميل التعليقات.'));
                    }
                    return const Center(child: CircularProgressIndicator());
                  }
                  final rows = snapshot.data!;
                  if (rows.isEmpty) {
                    return const Center(child: Text('ماكو تعليقات منشورة بعد.'));
                  }
                  return ListView.builder(
                    itemCount: rows.length,
                    itemBuilder: (context, i) {
                      final item = rows[i];
                      final mine = item['user_id'] == AlAniSocialApi.userId &&
                          AlAniSocialApi.userId.isNotEmpty;
                      final pending = item['status'] != 'approved';
                      return ListTile(
                        title: Text(item['body']?.toString() ?? ''),
                        subtitle: Text(pending ? 'بانتظار الإشراف' : 'تعليق منشور'),
                        trailing: PopupMenuButton<String>(
                          tooltip: 'خيارات التعليق',
                          onSelected: (action) async {
                            if (action == 'report') await _report(item['id'] as String);
                            if (action == 'edit') await _editComment(item);
                            if (action == 'delete') await _act(() =>
                                AlAniSocialApi.editComment(
                                  item['id'] as String, '', delete: true));
                            if (ctx.mounted) modalState(() =>
                                posts = AlAniSocialApi.comments(widget.publicationId));
                          },
                          itemBuilder: (_) => [
                            if (mine) const PopupMenuItem(
                                value: 'edit', child: Text('تعديل')),
                            if (mine) const PopupMenuItem(
                                value: 'delete', child: Text('حذف')),
                            const PopupMenuItem(
                                value: 'report', child: Text('تبليغ')),
                          ],
                        ),
                      );
                    },
                  );
                },
              )),
              SafeArea(top: false, child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                child: Row(children: [
                  Expanded(child: TextField(
                    controller: input, maxLength: 500, maxLines: 2,
                    decoration: const InputDecoration(
                      hintText: 'اكتب تعليقك باحترام', border: OutlineInputBorder(),
                      counterText: '',
                    ),
                  )),
                  const SizedBox(width: 6),
                  IconButton.filled(
                    tooltip: 'إرسال التعليق للمراجعة',
                    onPressed: sending ? null : () async {
                      final body = input.text.trim();
                      if (body.length < 3) {
                        _notice('التعليق لازم يكون ٣ أحرف على الأقل.');
                        return;
                      }
                      if (!await _needsLogin()) return;
                      modalState(() => sending = true);
                      try {
                        await AlAniSocialApi.comment(widget.publicationId, body);
                        input.clear();
                        _notice('تم إرسال التعليق، بانتظار موافقة المشرف.');
                        if (ctx.mounted) modalState(() =>
                          posts = AlAniSocialApi.comments(widget.publicationId));
                      } catch (_) {
                        _notice('تعذر إرسال التعليق. حاول مرة ثانية.');
                      } finally {
                        if (ctx.mounted) modalState(() => sending = false);
                      }
                    },
                    icon: const Icon(Icons.send_rounded),
                  ),
                ]),
              )),
            ]),
          ),
        ),
      ),
    );
    input.dispose();
    if (mounted) _reload();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: _stats,
      builder: (ctx, snap) {
        if (snap.hasError) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: TextButton.icon(
              onPressed: _reload,
              icon: const Icon(Icons.refresh),
              label: const Text('التفاعلات غير متاحة — إعادة محاولة'),
            ),
          );
        }
        if (!snap.hasData) {
          return const SizedBox(
            height: 44, child: Center(child: CircularProgressIndicator()));
        }
        final data = snap.data!;
        final likes = (data['likes'] as num?)?.toInt() ?? 0;
        final comments = (data['comments'] as num?)?.toInt() ?? 0;
        final liked = data['liked'] == true;
        final saved = data['saved'] == true;
        final avg = data['rating']?.toString() ?? '—';
        final color = widget.dark ? Colors.white : const Color(0xFF173E2A);
        if (widget.compact) {
          return Column(mainAxisSize: MainAxisSize.min, children: [
            IconButton(
              color: color,
              tooltip: 'إعجاب — $likes',
              onPressed: _busy ? null : () => _act(() async {
                await AlAniSocialApi.reaction(widget.publicationId, 'like');
              }),
              icon: Icon(liked ? Icons.favorite : Icons.favorite_border),
            ),
            Text('$likes', style: TextStyle(color: color)),
            IconButton(
              color: color,
              tooltip: 'تعليقات — $comments',
              onPressed: _comments,
              icon: const Icon(Icons.mode_comment_outlined),
            ),
            IconButton(
              color: color,
              tooltip: 'حفظ المنشور',
              onPressed: () => _act(() async {
                await AlAniSocialApi.reaction(widget.publicationId, 'save');
              }),
              icon: Icon(saved ? Icons.bookmark : Icons.bookmark_outline),
            ),
            IconButton(
              color: color, tooltip: 'مشاركة', onPressed: _share,
              icon: const Icon(Icons.share_outlined),
            ),
            IconButton(
              color: color, tooltip: 'تبليغ', onPressed: () => _report(),
              icon: const Icon(Icons.flag_outlined),
            ),
          ]);
        }
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Divider(),
          Wrap(spacing: 4, runSpacing: 2, children: [
            TextButton.icon(
              onPressed: _busy ? null : () => _act(() async {
                await AlAniSocialApi.reaction(widget.publicationId, 'like');
              }),
              icon: Icon(liked ? Icons.favorite : Icons.favorite_border),
              label: Text('إعجاب ($likes)'),
            ),
            TextButton.icon(
              onPressed: _comments,
              icon: const Icon(Icons.mode_comment_outlined),
              label: Text('تعليقات ($comments)'),
            ),
            TextButton.icon(
              onPressed: () => _act(() async {
                await AlAniSocialApi.reaction(widget.publicationId, 'save');
              }),
              icon: Icon(saved ? Icons.bookmark : Icons.bookmark_outline),
              label: Text(saved ? 'محفوظ' : 'حفظ'),
            ),
            TextButton.icon(
              onPressed: _share, icon: const Icon(Icons.share_outlined),
              label: const Text('مشاركة'),
            ),
            TextButton.icon(
              onPressed: _rate, icon: const Icon(Icons.star_outline),
              label: Text('تقييم ($avg / 5)'),
            ),
            IconButton(
              tooltip: 'تبليغ عن المحتوى',
              onPressed: () => _report(),
              icon: const Icon(Icons.flag_outlined),
            ),
          ]),
        ]);
      },
    );
  }
}
