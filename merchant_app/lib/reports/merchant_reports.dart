import 'package:flutter/material.dart';
import 'package:shitreed_merchant/commerce/commerce_service.dart';
import 'package:shitreed_merchant/shared/merchant_widgets.dart';

class MerchantReport {
  final int stores;
  final int pendingApprovalStores;
  final int placedOrders;
  final int acceptedOrders;
  final int preparingOrders;
  final int readyOrders;
  final int cancelledOrRejected;
  final int totalOrderValueIqd;

  const MerchantReport({
    required this.stores,
    required this.pendingApprovalStores,
    required this.placedOrders,
    required this.acceptedOrders,
    required this.preparingOrders,
    required this.readyOrders,
    required this.cancelledOrRejected,
    required this.totalOrderValueIqd,
  });
}

Future<MerchantReport> loadMerchantReport() async {
  final stores = await CommerceService.myStores();
  var placed = 0;
  var accepted = 0;
  var preparing = 0;
  var ready = 0;
  var cancelled = 0;
  var grossOrderValue = 0;
  for (final store in stores) {
    final orders = await CommerceService.merchantOrders(store['id'] as String);
    for (final order in orders) {
      final status = order['status'] as String? ?? '';
      switch (status) {
        case 'placed':
          placed++;
        case 'accepted':
          accepted++;
        case 'preparing':
          preparing++;
        case 'ready':
          ready++;
        case 'rejected':
        case 'cancelled':
          cancelled++;
      }
      if (status != 'cancelled' && status != 'rejected') {
        grossOrderValue += (order['total_iqd'] as num).toInt();
      }
    }
  }
  return MerchantReport(
    stores: stores.length,
    pendingApprovalStores: stores.where((s) =>
      s['status'] == 'pending').length,
    placedOrders: placed,
    acceptedOrders: accepted,
    preparingOrders: preparing,
    readyOrders: ready,
    cancelledOrRejected: cancelled,
    totalOrderValueIqd: grossOrderValue,
  );
}

class MerchantReportsPage extends StatefulWidget {
  const MerchantReportsPage({super.key});

  @override
  State<MerchantReportsPage> createState() => _MerchantReportsPageState();
}

class _MerchantReportsPageState extends State<MerchantReportsPage> {
  late Future<MerchantReport> _report;
  @override
  void initState() {
    super.initState();
    _refresh();
  }

  void _refresh() {
    setState(() {
      _report = loadMerchantReport();
    });
  }

  Widget _stat(String label, String value, IconData icon) => Expanded(
    child: Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(17),
        color: Colors.white,
        border: Border.all(color: const Color(0xFFF0E6FA)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 24, color: merchantPurple),
        const SizedBox(height: 12),
        Text(value, style: const TextStyle(
          fontSize: 22, fontWeight: FontWeight.w900, color: merchantDark)),
        const SizedBox(height: 5),
        Text(label, style: const TextStyle(
          color: Colors.black54, fontSize: 12)),
      ]),
    ),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('إحصائيات متاجري')),
    body: RefreshIndicator(
      onRefresh: () async {
        _refresh();
        await _report;
      },
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('ملخص الطلبات', style: TextStyle(
            fontSize: 25, color: merchantDark, fontWeight: FontWeight.w900)),
          const SizedBox(height: 7),
          const Text(
            'هذه أرقام الطلبات المسجلة، وليست تقرير إيرادات محصلة.',
            style: TextStyle(color: Colors.black54)),
          const SizedBox(height: 18),
          FutureBuilder<MerchantReport>(
            future: _report,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return const Text(
                  'تعذر تحميل الإحصائيات. اسحب الشاشة للتحديث.');
              }
              final report = snapshot.data!;
              return Column(children: [
                Row(children: [
                  _stat('متاجري', report.stores.toString(),
                    Icons.storefront_outlined),
                  const SizedBox(width: 12),
                  _stat('قيد الموافقة', report.pendingApprovalStores.toString(),
                    Icons.pending_actions),
                ]),
                const SizedBox(height: 12),
                Row(children: [
                  _stat('طلبات جديدة', report.placedOrders.toString(),
                    Icons.new_releases_outlined),
                  const SizedBox(width: 12),
                  _stat('طلبات مقبولة', report.acceptedOrders.toString(),
                    Icons.check_circle_outline),
                ]),
                const SizedBox(height: 12),
                Row(children: [
                  _stat('قيد التحضير', report.preparingOrders.toString(),
                    Icons.timer_outlined),
                  const SizedBox(width: 12),
                  _stat('جاهزة للتسليم', report.readyOrders.toString(),
                    Icons.local_shipping_outlined),
                ]),
                const SizedBox(height: 12),
                Row(children: [
                  _stat('ملغية / مرفوضة',
                    report.cancelledOrRejected.toString(),
                    Icons.cancel_outlined),
                  const SizedBox(width: 12),
                  _stat('قيمة الطلبات النشطة',
                    priceText(report.totalOrderValueIqd),
                    Icons.receipt_long),
                ]),
                const SizedBox(height: 25),
                const Text(
                  'مهم: لا تُعتبر قيمة الطلبات مبيعات مدفوعة. '
                  'الدفع عند الاستلام ولا يوجد تسجيل للتحصيل أو رسوم '
                  'التوصيل بعد. آخر 60 طلباً لكل متجر فقط تدخل بالحساب.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.black54, fontSize: 12),
                ),
              ]);
            },
          ),
        ],
      ),
    ),
  );
}
