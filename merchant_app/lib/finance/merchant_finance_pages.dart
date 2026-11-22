// ignore_for_file: prefer_interpolation_to_compose_strings
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Merchant wallet information: viewing only, no user initiated balance edits.
class MerchantWalletPage extends StatefulWidget {
  const MerchantWalletPage({super.key});
  @override
  State<MerchantWalletPage> createState() => _MerchantWalletPageState();
}

class _MerchantWalletPageState extends State<MerchantWalletPage> {
  late Future<Map<String, dynamic>> _report;
  @override
  void initState() {
    super.initState();
    _report = _load();
  }

  Future<Map<String, dynamic>> _load() async {
    final result = await Supabase.instance.client.rpc('shitreed_wallet_overview');
    final rows = result as List;
    if (rows.isEmpty) throw StateError('NO_FINANCIAL_REPORT');
    return Map<String, dynamic>.from(rows.first as Map);
  }

  Future<void> _refresh() async {
    final next = _load();
    setState(() => _report = next);
    await next;
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('رصيد التاجر')),
    body: FutureBuilder<Map<String, dynamic>>(
      future: _report,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: TextButton(
            onPressed: _refresh,
            child: const Text('الرصيد غير متاح. اضغط لإعادة المحاولة'),
          ));
        }
        return RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(padding: const EdgeInsets.all(18), children: [
            Card(child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('الرصيد المسجّل بالتسوية'),
                  const SizedBox(height: 12),
                  Text((snapshot.data!['merchant_balance_iqd'] ?? 0).toString() + ' د.ع',
                    style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 12),
                  const Text('هذه القيمة ليست إثباتاً لاستلام أموال فعلية. '
                      'التحويل والسحب غير مفعلين حتى اعتماد بوابة دفع.',
                      style: TextStyle(fontSize: 12)),
                ],
              ),
            )),
          ]),
        );
      },
    ),
  );
}

/// Aggregate finance & chat metrics only. Server requires trusted admin
/// app_metadata and returns no customer phone, private chat text or secrets.
class ShitreedAdminOversightPage extends StatefulWidget {
  const ShitreedAdminOversightPage({super.key});
  @override
  State<ShitreedAdminOversightPage> createState() => _ShitreedAdminOversightPageState();
}

class _ShitreedAdminOversightPageState extends State<ShitreedAdminOversightPage> {
  late Future<Map<String, dynamic>> _stats;
  @override
  void initState() {
    super.initState();
    _stats = _load();
  }

  Future<Map<String, dynamic>> _load() async {
    final result = await Supabase.instance.client.rpc(
      'shitreed_admin_finance_chat_summary',
    );
    return Map<String, dynamic>.from(result as Map);
  }

  Future<void> _refresh() async {
    final next = _load();
    setState(() => _stats = next);
    await next;
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('الإدارة • الأموال والدردشة')),
    body: FutureBuilder<Map<String, dynamic>>(
      future: _stats,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: TextButton(
            onPressed: _refresh,
            child: const Text('لا توجد صلاحية أو الخدمة غير مفعّلة — إعادة المحاولة'),
          ));
        }
        final values = snapshot.data!;
        final rows = <(String, String)>[
          ('قيود دفتر المحفظة', 'ledger_journals'),
          ('رصيد محافظ الزبائن', 'cash_customer_iqd'),
          ('رصيد التجار', 'cash_merchants_iqd'),
          ('نقاط المكافآت', 'reward_points'),
          ('المحادثات', 'chat_threads'),
          ('الرسائل', 'chat_messages'),
        ];
        return RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(padding: const EdgeInsets.all(16), children: [
            const Text('مؤشرات إدارية مجمّعة فقط',
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 19)),
            const SizedBox(height: 12),
            for (final row in rows)
              Card(child: ListTile(
                title: Text(row.$1),
                trailing: Text((values[row.$2] ?? 0).toString(),
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              )),
            const SizedBox(height: 12),
            const Text('لا يمكن تعديل الأرصدة من هذه الشاشة. '
              'الإيداع والاسترداد والتسوية تحتاج مراجعة مالية '
              'وأذونات خدمة خلفية مستقلة.',
              style: TextStyle(fontSize: 12, color: Colors.black54)),
          ]),
        );
      },
    ),
  );
}
