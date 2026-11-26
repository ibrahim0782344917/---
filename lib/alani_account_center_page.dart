import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AlAniAccountCenterPage extends StatefulWidget {
  const AlAniAccountCenterPage({super.key, required this.scope});
  final String scope;
  static const enabled = String.fromEnvironment('SUPABASE_URL') ==
      'https://tgvdwotbrnhcoykuxdpr.supabase.co';

  @override
  State<AlAniAccountCenterPage> createState() => _AlAniAccountCenterPageState();
}

class _AlAniAccountCenterPageState extends State<AlAniAccountCenterPage> {
  late Future<Map<String, dynamic>> _data;
  StreamSubscription<AuthState>? _auth;
  SupabaseClient get _client => Supabase.instance.client;

  Future<Map<String, dynamic>> _load() async {
    if (!AlAniAccountCenterPage.enabled || _client.auth.currentUser == null) {
      throw StateError('Unavailable');
    }
    final user = _client.auth.currentUser!.id;
    final result = await _client.rpc('alani_center_read_test',
        params: {'p_scope': widget.scope});
    if (_client.auth.currentUser?.id != user) {
      throw StateError('Session changed');
    }
    return Map<String, dynamic>.from(result as Map);
  }

  void _refresh() {
    if (mounted) setState(() => _data = _load());
  }

  @override
  void initState() {
    super.initState();
    _data = _load();
    if (AlAniAccountCenterPage.enabled) {
      _auth = _client.auth.onAuthStateChange.listen((_) => _refresh());
    }
  }

  @override
  void dispose() {
    _auth?.cancel();
    super.dispose();
  }

  Widget _metric(String label, Object? value, IconData icon) => Card(
    child: ListTile(
      leading: Icon(icon),
      title: Text(label),
      trailing: Text(value?.toString() ?? '—',
        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final customer = widget.scope == 'customer';
    final admin = widget.scope == 'admin';
    return Scaffold(
      appBar: AppBar(title: Text(customer ? 'محفظتي' :
        admin ? 'إدارة الزبائن والمحفظة' : 'زبائن المتجر والمحفظة'),
        actions: [IconButton(onPressed: _refresh,
          tooltip: 'تحديث', icon: const Icon(Icons.refresh))]),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _data,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError || !snapshot.hasData) {
            return Center(child: Padding(padding: const EdgeInsets.all(24),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.lock_outline, size: 44),
                const SizedBox(height: 12),
                const Text('تعذر الوصول. تحقق من اتصالك وصلاحية حسابك.'),
                TextButton(onPressed: _refresh, child: const Text('إعادة المحاولة')),
              ])));
          }
          final d = snapshot.data!;
          final transactions = d['transactions'] as List? ?? const [];
          return RefreshIndicator(
            onRefresh: () async {
              _refresh();
              try { await _data; } catch (_) { /* UI shows generic error. */ }
            },
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16), children: [
                Card(child: ListTile(
                  leading: const Icon(Icons.shield_outlined),
                  title: const Text('بيئة الاختبار — لا أموال حقيقية'),
                  subtitle: Text(customer ?
                    'الرصيد والحركات تجريبية. الشحن والدفع والسحب مغلقة.' :
                    'عرض إحصائيات مصرح بها فقط. لا أرقام هواتف أو عناوين.' ),
                )),
                if (customer) ...[
                  _metric('الرصيد التجريبي (د.ع)', d['balance_iqd'],
                    Icons.account_balance_wallet_outlined),
                  const Padding(padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text('آخر الحركات', style: TextStyle(fontWeight: FontWeight.bold))),
                  if (transactions.isEmpty) const ListTile(title: Text('لا توجد حركات')),
                  for (final raw in transactions)
                    if (raw is Map) _metric(
                      'حركة تجريبية — الرصيد بعدها: ${raw['balance_after_iqd']} د.ع',
                      raw['delta_iqd'], Icons.receipt_long_outlined),
                ] else if (admin) ...[
                  _metric('الزبائن القدامى المحفوظون', d['legacy_contacts'], Icons.people_outline),
                  _metric('سجلات قائمة المراجعة', d['review_queue'], Icons.fact_check_outlined),
                  _metric('الاستيراد الاصطناعي المحفوظ', d['synthetic_contacts'], Icons.file_upload_outlined),
                  _metric('المحافظ التجريبية', d['wallet_accounts'], Icons.account_balance_wallet_outlined),
                  _metric('حركات المحفظة التجريبية', d['wallet_movements'], Icons.receipt_long_outlined),
                  const ListTile(leading: Icon(Icons.lock_outline),
                    title: Text('الاستيراد الحقيقي والشحن مغلقان'),
                    subtitle: Text('استخدم صفحة استيراد الزبائن لمراجعة CSV محلياً.')),
                ] else ...[
                  _metric('زبائن طلبوا من المتجر', d['customers'], Icons.people_outline),
                  _metric('طلبات المتجر', d['orders'], Icons.receipt_long_outlined),
                  const ListTile(leading: Icon(Icons.lock_outline),
                    title: Text('الاستيراد والشحن المالي من صلاحيات الإدارة بعد الاعتماد'),
                    subtitle: Text('لا يحق للتاجر الوصول إلى رصيد الزبون أو جهات اتصاله.')),
                ],
              ]),
          );
        }),
    );
  }
}
