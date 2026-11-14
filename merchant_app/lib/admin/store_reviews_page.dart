import 'package:flutter/material.dart';
import 'package:shitreed_merchant/shared/merchant_widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// The server checks admin membership against auth.users.raw_app_meta_data.
/// Neither UI visibility nor a client-supplied role grants approval rights.
class StoreReviewService {
  StoreReviewService._();

  static SupabaseClient get _db => Supabase.instance.client;

  static Future<bool> isAdmin() async {
    final result = await _db.rpc('shitreed_is_admin');
    return result == true;
  }

  static Future<List<Map<String, dynamic>>> pendingStores() async {
    final rows = await _db.rpc('shitreed_pending_store_reviews');
    return (rows as List).map((row) =>
        Map<String, dynamic>.from(row as Map)).toList(growable: false);
  }

  static Future<String> decide({
    required String storeId,
    required String decision,
    required String reason,
  }) async {
    if (!validReviewReason(reason) ||
        (decision != 'approve' && decision != 'reject')) {
      throw StateError('INVALID_REVIEW_DETAILS');
    }
    final result = await _db.rpc('shitreed_review_store', params: {
      'p_store_id': storeId,
      'p_decision': decision,
      'p_reason': reason.trim(),
    });
    return result.toString();
  }
}

/// Checks only the UX. Database validates authorization and details again.
bool validReviewReason(String reason) =>
    reason.trim().length >= 20 && reason.trim().length <= 1000;

class StoreReviewsPage extends StatefulWidget {
  const StoreReviewsPage({super.key});

  @override
  State<StoreReviewsPage> createState() => _StoreReviewsPageState();
}

class _StoreReviewsPageState extends State<StoreReviewsPage> {
  late Future<List<Map<String, dynamic>>> _queue;
  bool _reviewing = false;

  @override
  void initState() {
    super.initState();
    _queue = StoreReviewService.pendingStores();
  }

  Future<void> _refresh() async {
    final next = StoreReviewService.pendingStores();
    setState(() {
      _queue = next;
    });
    await next;
  }

  Future<void> _review(Map<String, dynamic> store, String decision) async {
    if (_reviewing) return;
    final controller = TextEditingController();
    var verified = false;
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: Text(decision == 'approve'
              ? 'اعتماد محل بعد التحقق'
              : 'رفض طلب تسجيل المحل'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(store['store_name'] as String? ?? ''),
                const SizedBox(height: 10),
                const Text(
                  'راجع إثبات ملكية المحل وبيانات الاتصال والعنوان '
                  'قبل الموافقة. الموافقة تسمح بعرض المنتجات '
                  'واستقبال طلبات الدفع عند الاستلام.',
                  style: TextStyle(fontSize: 12),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: controller,
                  maxLength: 1000,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'سبب القرار وتفاصيل التحقق (20 حرفاً على الأقل)',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (_) => setDialogState(() {}),
                ),
                if (decision == 'approve')
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: verified,
                    onChanged: (v) => setDialogState(() {
                      verified = v ?? false;
                    }),
                    title: const Text(
                      'تحققت من ملكية المحل وبياناته فعلياً',
                      style: TextStyle(fontSize: 13),
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: validReviewReason(controller.text) &&
                      (decision != 'approve' || verified)
                  ? () => Navigator.pop(dialogContext, controller.text.trim())
                  : null,
              child: Text(decision == 'approve' ? 'اعتماد المحل' : 'رفض الطلب'),
            ),
          ],
        ),
      ),
    );
    // The dialog owns the input; no text is sent to the database unless the
    // authenticated administrator confirmed the review.
    controller.dispose();
    if (result == null || !mounted) return;
    setState(() => _reviewing = true);
    try {
      await StoreReviewService.decide(
        storeId: store['store_id'] as String,
        decision: decision,
        reason: result,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(decision == 'approve'
            ? 'تم اعتماد المحل وتسجيل قرار المراجعة.'
            : 'تم رفض الطلب وتسجيل سبب القرار.'),
      ));
      await _refresh();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
            'تعذر حفظ القرار. تأكد من صلاحية المدير '
            'وأن المتجر ما زال بانتظار المراجعة.'),
        ));
      }
    } finally {
      if (mounted) setState(() => _reviewing = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('مراجعة المحلات')),
    body: RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('طلبات اعتماد المتاجر',
              style: TextStyle(
                fontSize: 22,
                color: merchantDark,
                fontWeight: FontWeight.w900,
              )),
          const SizedBox(height: 8),
          const Text(
            'هذه الصفحة للمشرف المفوّض فقط. '
            'اعتماد المتجر يتطلب التحقق من ملكيته '
            'والالتزام بشروط المنصة؛ لا تعتمد طلبات مجهولة.',
            style: TextStyle(color: Colors.black54),
          ),
          const SizedBox(height: 14),
          FutureBuilder<List<Map<String, dynamic>>>(
            future: _queue,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return const Text(
                  'لا يمكن عرض طلبات المراجعة. '
                  'قد تكون صلاحيات الإدارة غير مفعّلة لهذا الحساب.',
                );
              }
              final rows = snapshot.data ?? [];
              if (rows.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 32),
                  child: Text('ماكو طلبات جديدة للمراجعة.',
                      textAlign: TextAlign.center),
                );
              }
              return Column(
                children: [
                  for (final store in rows)
                    Card(
                      color: Colors.white,
                      margin: const EdgeInsets.only(bottom: 12),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(store['store_name'] as String? ?? '',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 18,
                                )),
                            const SizedBox(height: 6),
                            Text('${store['area']} • ${store['category']}'),
                            const SizedBox(height: 6),
                            Text('العنوان: ${store['store_address']}'),
                            if ((store['store_phone'] as String?)?.isNotEmpty ??
                                false)
                              Text('الهاتف: ${store['store_phone']}'),
                            const SizedBox(height: 12),
                            Wrap(
                              spacing: 8,
                              children: [
                                OutlinedButton(
                                  onPressed: _reviewing
                                      ? null
                                      : () => _review(store, 'reject'),
                                  child: const Text('رفض'),
                                ),
                                FilledButton.icon(
                                  onPressed: _reviewing
                                      ? null
                                      : () => _review(store, 'approve'),
                                  icon: const Icon(Icons.verified_user_outlined),
                                  label: const Text('تحقق واعتمد'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    ),
  );
}
