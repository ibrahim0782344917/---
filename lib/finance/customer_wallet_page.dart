// ignore_for_file: prefer_interpolation_to_compose_strings
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Read-only balances calculated by the private double-entry ledger.
/// No client operation can top up, withdraw, credit, or edit money.
class CustomerWalletPage extends StatefulWidget {
  const CustomerWalletPage({super.key});
  @override
  State<CustomerWalletPage> createState() => _CustomerWalletPageState();
}

class _CustomerWalletPageState extends State<CustomerWalletPage> {
  late Future<_WalletSnapshot> _data;

  @override
  void initState() {
    super.initState();
    _data = _fetch();
  }

  Future<_WalletSnapshot> _fetch() async {
    final db = Supabase.instance.client;
    if (db.auth.currentUser == null) throw StateError('LOGIN_REQUIRED');
    final results = await Future.wait<dynamic>([
      db.rpc('shitreed_wallet_overview'),
      db.rpc('shitreed_wallet_activity', params: {'p_limit': 30}),
    ]);
    final summaryRows = results[0] as List;
    if (summaryRows.isEmpty) throw StateError('NO_WALLET_SUMMARY');
    final summary = Map<String, dynamic>.from(summaryRows.first as Map);
    final activity = (results[1] as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList(growable: false);
    return _WalletSnapshot(summary, activity);
  }

  Future<void> _refresh() async {
    final next = _fetch();
    setState(() => _data = next);
    await next;
  }

  String _iqd(dynamic n) =>
      (n is num ? n.toInt() : int.tryParse('$n') ?? 0).toString() + ' د.ع';

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('محفظتي ونقاطي')),
        body: FutureBuilder<_WalletSnapshot>(
          future: _data,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.shield_outlined, size: 52),
                      const SizedBox(height: 12),
                      const Text(
                        'الرصيد غير متاح حالياً. لم يتم تفعيل الخدمات المالية بعد.',
                        textAlign: TextAlign.center,
                      ),
                      TextButton(onPressed: _refresh, child: const Text('إعادة المحاولة')),
                    ],
                  ),
                ),
              );
            }
            final data = snapshot.data!;
            return RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(padding: const EdgeInsets.all(16), children: [
                Card(
                  color: const Color(0xFFEAE0FA),
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('الرصيد المالي المسجّل'),
                        const SizedBox(height: 8),
                        Text(_iqd(data.summary['cash_balance_iqd']),
                            style: const TextStyle(fontSize: 29, fontWeight: FontWeight.w900)),
                        const SizedBox(height: 8),
                        const Text('لا يمكن الشحن أو السحب حالياً حتى اعتماد بوابة الدفع.',
                            style: TextStyle(fontSize: 12)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.stars_outlined),
                    title: const Text('نقاط المكافآت'),
                    subtitle: const Text('ليست أموالاً ولا قابلة للسحب النقدي'),
                    trailing: Text((data.summary['reward_points'] ?? 0).toString()),
                  ),
                ),
                const SizedBox(height: 16),
                const Text('حركة الرصيد', style: TextStyle(
                  fontSize: 19, fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                if (data.activity.isEmpty)
                  const ListTile(title: Text('لا توجد معاملات مالية مسجّلة'))
                else
                  for (final entry in data.activity)
                    ListTile(
                      leading: Icon(entry['currency'] == 'POINT'
                          ? Icons.stars_outlined : Icons.receipt_long),
                      title: Text((entry['description'] ?? 'حركة رصيد').toString()),
                      subtitle: Text((entry['occurred_at'] ?? '').toString()),
                      trailing: Text(entry['currency'] == 'POINT'
                          ? (entry['amount'] ?? 0).toString() + ' نقطة'
                          : _iqd(entry['amount'])),
                    ),
                const SizedBox(height: 18),
                const Text('جميع المعاملات تُحتسب على الخادم. '
                    'لا تخزن المحفظة أرصدة قابلة للتعديل من الهاتف.',
                    style: TextStyle(fontSize: 12, color: Colors.black54)),
              ]),
            );
          },
        ),
      );
}

class _WalletSnapshot {
  final Map<String, dynamic> summary;
  final List<Map<String, dynamic>> activity;
  const _WalletSnapshot(this.summary, this.activity);
}
