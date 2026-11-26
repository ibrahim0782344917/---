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
  final int openGoodsIqd;
  final int openDeliveryIqd;
  final int openOrderTotalIqd;
  final int deliveredOrderTotalIqd;
  final int deliveredOrders;
  final int outForDeliveryOrders;
  final bool limitedSample;

  const MerchantReport({
    required this.stores,
    required this.pendingApprovalStores,
    required this.placedOrders,
    required this.acceptedOrders,
    required this.preparingOrders,
    required this.readyOrders,
    required this.cancelledOrRejected,
    required this.totalOrderValueIqd,
    this.openGoodsIqd = 0,
    this.openDeliveryIqd = 0,
    this.openOrderTotalIqd = 0,
    this.deliveredOrderTotalIqd = 0,
    this.deliveredOrders = 0,
    this.outForDeliveryOrders = 0,
    this.limitedSample = false,
  });
}

Future<MerchantReport> loadMerchantReport() async {
  final stores = await CommerceService.myStores();
  final orders = <Map<String, dynamic>>[];
  var limited = false;
  for (final store in stores) {
    final rows = await CommerceService.merchantOrders(store['id'] as String);
    limited = limited || rows.length >= 60;
    orders.addAll(rows);
  }
  return summarizeMerchantOrders(stores, orders, limitedSample: limited);
}

/// Order commitments only. Neither delivered status nor a COD order proves
/// cash collection. Unknown or inconsistent financial amounts fail closed.
MerchantReport summarizeMerchantOrders(
    List<Map<String, dynamic>> stores, List<Map<String, dynamic>> orders,
    {bool limitedSample = false}) {
  var placed = 0, accepted = 0, preparing = 0, ready = 0;
  var cancelled = 0, delivered = 0, inTransit = 0;
  var openGoods = 0, openDelivery = 0, openTotal = 0, deliveredTotal = 0;
  const open = {'placed','accepted','preparing','ready','out_for_delivery'};
  final seen = <String>{};
  for (final order in orders) {
    final id = order['id'];
    if (id is! String || id.isEmpty || !seen.add(id)) {
      throw StateError('INVALID_OR_DUPLICATE_ORDER');
    }
    final status = order['status'];
    switch (status) {
      case 'placed': placed++;
      case 'accepted': accepted++;
      case 'preparing': preparing++;
      case 'ready': ready++;
      case 'out_for_delivery': inTransit++;
      case 'delivered': delivered++;
      case 'rejected':
      case 'cancelled': cancelled++;
      default: throw StateError('UNKNOWN_ORDER_STATUS');
    }
    if (open.contains(status) || status == 'delivered') {
      final total = order['total_iqd'];
      final fee = order['delivery_fee_iqd'];
      if (total is! num || fee is! num || !total.isFinite || !fee.isFinite ||
          total != total.toInt() || fee != fee.toInt() ||
          fee < 0 || total < fee) {
        throw StateError('INVALID_ORDER_AMOUNTS');
      }
      if (open.contains(status)) {
        openTotal += total.toInt();
        openDelivery += fee.toInt();
        openGoods += total.toInt() - fee.toInt();
      } else {
        deliveredTotal += total.toInt();
      }
    }
  }
  return MerchantReport(
    stores: stores.length,
    pendingApprovalStores: stores.where((s) => s['status'] == 'pending').length,
    placedOrders: placed, acceptedOrders: accepted, preparingOrders: preparing,
    readyOrders: ready, cancelledOrRejected: cancelled,
    totalOrderValueIqd: openTotal + deliveredTotal,
    openGoodsIqd: openGoods, openDeliveryIqd: openDelivery,
    openOrderTotalIqd: openTotal, deliveredOrderTotalIqd: deliveredTotal,
    deliveredOrders: delivered, outForDeliveryOrders: inTransit,
    limitedSample: limitedSample,
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
                  _stat('إجمالي الطلبات المفتوحة',
                    priceText(report.openOrderTotalIqd),
                    Icons.receipt_long),
                ]),
                const SizedBox(height: 12),
                Card(child: Column(children: [
                  ListTile(title: const Text('قيمة بضائع الطلبات المفتوحة'),
                    trailing: Text(priceText(report.openGoodsIqd))),
                  ListTile(title: const Text('رسوم توصيل الطلبات المفتوحة'),
                    trailing: Text(priceText(report.openDeliveryIqd))),
                  ListTile(title: const Text('خرج للتوصيل'),
                    trailing: Text(report.outForDeliveryOrders.toString())),
                  ListTile(title: const Text('طلبات مسلّمة (لا تثبت التحصيل)'),
                    trailing: Text(report.deliveredOrders.toString())),
                  ListTile(title: const Text('إجمالي الطلبات المسلّمة'),
                    trailing: Text(priceText(report.deliveredOrderTotalIqd))),
                  const ListTile(title: Text('النقد المحصّل وصافي الربح'),
                    subtitle: Text('غير متاح حتى تفعيل تسوية التحصيل والتكاليف')),
                ])),
                if (report.limitedSample)
                  const Text('تنبيه: وصل التقرير إلى حد 60 طلباً لكل متجر؛ الأرقام جزئية.'),
                const SizedBox(height: 25),
                const Text(
                  'آخر 60 طلباً لكل متجر فقط. الملغاة والمرفوضة لا تدخل في الإجمالي. '
                  'قيمة الطلبات ليست مبيعات مدفوعة، ولا تمثل الربح الصافي.',
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
