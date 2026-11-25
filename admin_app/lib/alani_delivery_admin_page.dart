import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Admin oversight is read-only; dispatch still requires a merchant/admin
/// approval flow. This UI never displays buyer phones, addresses or PIN codes.
abstract final class AlAniAdminDeliveryGate {
  static const enabled =
      (bool.fromEnvironment('ALANI_TEST_DELIVERY_ENABLED',
            defaultValue: false) &&
          String.fromEnvironment('SUPABASE_URL') ==
              'https://tgvdwotbrnhcoykuxdpr.supabase.co') ||
      (bool.fromEnvironment('ALANI_DELIVERY_PRODUCTION_APPROVED',
            defaultValue: false) &&
          String.fromEnvironment('SUPABASE_URL') ==
              'https://ltwncrewggdrjevakwpb.supabase.co');
}

class AlAniAdminDeliveryPage extends StatefulWidget {
  const AlAniAdminDeliveryPage({super.key});
  @override
  State<AlAniAdminDeliveryPage> createState() =>
      _AlAniAdminDeliveryPageState();
}

class _AlAniAdminDeliveryPageState extends State<AlAniAdminDeliveryPage> {
  late Future<List<Map<String, dynamic>>> _deliveries;

  @override
  void initState() {
    super.initState();
    _deliveries = _load();
  }

  Future<List<Map<String, dynamic>>> _load() async {
    final data = await Supabase.instance.client.rpc('alani_owner_delivery_jobs');
    return (data as List<dynamic>).map(
      (x) => Map<String, dynamic>.from(x as Map),
    ).toList();
  }

  Future<void> _refresh() async {
    final next = _load();
    setState(() => _deliveries = next);
    await next;
  }

  @override
  Widget build(BuildContext context) {
    if (!AlAniAdminDeliveryGate.enabled) {
      return Scaffold(
        appBar: AppBar(title: const Text('مراقبة التوصيل')),
        body: const Center(child: Text(
          'لوحة مراقبة المندوبين متاحة في قاعدة TEST فقط.')),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('متابعة مندوبي التوصيل'),
        actions: [
          IconButton(onPressed: _refresh,tooltip: 'تحديث',
            icon: const Icon(Icons.refresh)),
        ]),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text('مراقبة الطلبات التي خرجت للتوصيل '
              'وإثبات التسليم دون كشف رموز الاستلام أو أرقام الهواتف.',
              style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 14),
            FutureBuilder<List<Map<String, dynamic>>>(
              future: _deliveries,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return const Text('تعذّر عرض عمليات التوصيل. '
                    'تحقق من صلاحية الإدارة.');
                }
                final rows = snapshot.data ?? [];
                if (rows.isEmpty) {
                  return const Text('ماكو تكليفات توصيل بعد.');
                }
                return Column(children: [
                  for (final row in rows)
                    Card(
                      child: ListTile(
                        leading: Icon(row['delivered_at'] != null
                          ? Icons.verified_outlined
                          : Icons.local_shipping_outlined),
                        title: Text(
                          'طلب #${row['order_id'].toString().substring(0,8)}'),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('المندوب: #${row['courier_id'].toString().substring(0,8)}'),
                            Text('الحالة: ${row['status'] == 'delivered'
                              ? 'تم التسليم' : 'قيد التوصيل'}'),
                            if (row['picked_up_at'] != null)
                              const Text('المندوب استلم المنتجات'),
                            if (row['delivered_at'] != null)
                              const Text('إثبات التسليم مسجل على الخادم'),
                          ],
                        ),
                      ),
                    ),
                ]);
              },
            ),
          ],
        ),
      ),
    );
  }
}
