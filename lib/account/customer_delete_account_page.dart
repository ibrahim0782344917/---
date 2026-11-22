import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// The customer only requests account deletion. A trusted backend handles
/// actual identity verification, session revocation and legally required retention.
abstract class CustomerDeletionRepository {
  Future<String> requestDeletion(String reason);
  Future<List<Map<String, dynamic>>> myRequests();
}

class SupabaseCustomerDeletionRepository implements CustomerDeletionRepository {
  const SupabaseCustomerDeletionRepository();

  SupabaseClient get _db => Supabase.instance.client;

  @override
  Future<String> requestDeletion(String reason) async {
    if (_db.auth.currentUser == null) throw StateError('LOGIN_REQUIRED');
    final result = await _db.rpc('shitreed_customer_request_deletion',
        params: {'p_reason': reason.trim()});
    return result.toString();
  }

  @override
  Future<List<Map<String, dynamic>>> myRequests() async {
    if (_db.auth.currentUser == null) throw StateError('LOGIN_REQUIRED');
    final rows = await _db.from('customer_deletion_requests')
        .select('id,status,requested_at,processed_at')
        .order('requested_at', ascending: false)
        .limit(10);
    return (rows as List).map((row) =>
        Map<String, dynamic>.from(row as Map)).toList(growable: false);
  }
}

class CustomerDeleteAccountPage extends StatefulWidget {
  final CustomerDeletionRepository? repository;
  const CustomerDeleteAccountPage({super.key, this.repository});

  @override
  State<CustomerDeleteAccountPage> createState() =>
      _CustomerDeleteAccountPageState();
}

class _CustomerDeleteAccountPageState extends State<CustomerDeleteAccountPage> {
  final _reason = TextEditingController();
  late CustomerDeletionRepository _repository;
  late Future<List<Map<String, dynamic>>> _requests;
  bool _confirmed = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _repository = widget.repository ?? const SupabaseCustomerDeletionRepository();
    _requests = _repository.myRequests();
  }

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    final request = _repository.myRequests();
    setState(() => _requests = request);
    await request;
  }

  Future<void> _submit() async {
    if (_busy || !_confirmed || _reason.text.trim().length > 500) return;
    setState(() => _busy = true);
    try {
      final id = await _repository.requestDeletion(_reason.text);
      if (!mounted) return;
      _reason.clear();
      setState(() => _confirmed = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('تم تسجيل طلب حذف الحساب رقم ' +
            (id.length >= 8 ? id.substring(0, 8) : id) +
            '. الحساب لم يُحذف بعد.'),
      ));
      await _reload();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('تعذر تسجيل طلب حذف الحساب. تحقق من الاتصال أو راجع الدعم.'),
        ));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('حذف حساب شتريد')),
        body: SafeArea(
          child: RefreshIndicator(
            onRefresh: _reload,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              children: [
                const Icon(Icons.person_remove_outlined,
                    size: 58, color: Colors.deepOrange),
                const SizedBox(height: 12),
                const Text('طلب حذف حساب الزبون',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 21)),
                const SizedBox(height: 14),
                const Text(
                  'تقدر تطلب حذف حسابك وبياناتك المرتبطة به. '
                  'الطلب يُراجع للتحقق من الملكية ومعالجة الطلبات '
                  'والرصيد والنزاعات غير المنتهية. '
                  'هذا ليس حذفاً فورياً، وسنوضح ما يُحتفظ به '
                  'للالتزامات القانونية قبل إتمام العملية.',
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _reason,
                  maxLength: 500,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'سبب الطلب أو ملاحظات (اختياري)',
                    border: OutlineInputBorder(),
                  ),
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _confirmed,
                  title: const Text(
                    'أؤكد أنني أريد إرسال طلب حذف حسابي وبياناتي',
                  ),
                  onChanged: _busy ? null : (value) =>
                      setState(() => _confirmed = value ?? false),
                ),
                FilledButton.icon(
                  onPressed: _confirmed && !_busy ? _submit : null,
                  icon: const Icon(Icons.delete_outline),
                  label: Text(_busy ? 'يتم إرسال الطلب...' : 'إرسال طلب حذف حسابي'),
                ),
                const SizedBox(height: 24),
                const Text('متابعة الطلبات السابقة',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                const SizedBox(height: 8),
                FutureBuilder<List<Map<String, dynamic>>>(
                  future: _requests,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState != ConnectionState.done) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (snapshot.hasError) {
                      return const Text(
                        'تعذّر عرض طلبات الحذف. حاول إعادة تحميل الصفحة.');
                    }
                    final rows = snapshot.data ?? [];
                    if (rows.isEmpty) {
                      return const Text('لا توجد طلبات حذف سابقة.');
                    }
                    return Column(children: [
                      for (final request in rows)
                        ListTile(
                          leading: const Icon(Icons.history),
                          title: Text('الحالة: ' +
                              (request['status'] ?? 'pending').toString()),
                          subtitle: Text((request['requested_at'] ?? '').toString()),
                        ),
                    ]);
                  },
                ),
                const SizedBox(height: 18),
                const Text('لأمان بياناتك لا تضع كلمة المرور أو أرقام البطاقات '
                    'في ملاحظات الطلب.',
                    style: TextStyle(fontSize: 12, color: Colors.black54)),
              ],
            ),
          ),
        ),
      );
}
