// ignore_for_file: prefer_interpolation_to_compose_strings
import 'package:flutter/material.dart';
import 'package:shitreed_merchant/commerce/commerce_service.dart';

const _purple = Color(0xFF51159B);
const _dark = Color(0xFF280B53);

String _statusLabel(String status) {
  switch (status) {
    case 'placed':
      return 'بانتظار قبول المتجر';
    case 'accepted':
      return 'قبله المتجر';
    case 'preparing':
      return 'قيد التجهيز';
    case 'ready':
      return 'جاهز للتسليم';
    case 'cancelled':
      return 'ملغي';
    case 'rejected':
      return 'مرفوض من المتجر';
    default:
      return 'قيد المعالجة';
  }
}

String _iqd(Object? amount) {
  final raw = (amount is num ? amount.toInt() : 0).toString();
  return raw.replaceAllMapped(
      RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
      (m) => m[1]! + ',') + ' د.ع';
}

/// Displays server-snapshotted line items, not mutable product catalog data.
class OrderTimelinePage extends StatefulWidget {
  const OrderTimelinePage({
    super.key,
    required this.orderId,
    required this.totalIqd,
    required this.status,
  });

  final String orderId;
  final int totalIqd;
  final String status;

  @override
  State<OrderTimelinePage> createState() => _OrderTimelinePageState();
}

class _OrderTimelinePageState extends State<OrderTimelinePage> {
  late Future<List<Map<String, dynamic>>> _items;
  late Future<List<Map<String, dynamic>>> _events;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _items = CommerceService.orderItems(widget.orderId);
    _events = CommerceService.orderStatusEvents(widget.orderId);
  }

  Future<void> _refresh() async {
    setState(() {
      _load();
    });
    await Future.wait<dynamic>([_items, _events]);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('تفاصيل الطلب')),
    body: RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'طلب رقم ' + widget.orderId.substring(0, 8),
            style: const TextStyle(
              color: _dark, fontWeight: FontWeight.w900, fontSize: 22)),
          const SizedBox(height: 7),
          Text('الحالة: ' + _statusLabel(widget.status),
            style: const TextStyle(
              color: _purple, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text('المجموع: ' + _iqd(widget.totalIqd),
            style: const TextStyle(
              color: _dark, fontSize: 18, fontWeight: FontWeight.w900)),
          const Text(
            'طريقة الدفع: عند الاستلام. هذا ليس إثبات دفع.',
            style: TextStyle(color: Colors.black54, fontSize: 12)),
          const SizedBox(height: 22),
          const Text('المنتجات والكميات', style: TextStyle(
            fontSize: 18, fontWeight: FontWeight.w900, color: _dark)),
          const SizedBox(height: 8),
          FutureBuilder<List<Map<String, dynamic>>>(
            future: _items,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snap.hasError) {
                return const Text(
                    'تعذّر تحميل تفاصيل الطلب. اسحب الشاشة للتحديث.');
              }
              final lines = snap.data ?? [];
              if (lines.isEmpty) {
                return const Text('لا تتوفر تفاصيل المنتجات لهذا الطلب.');
              }
              return Column(
                children: [
                  for (final line in lines)
                    Card(
                      color: Colors.white,
                      child: ListTile(
                        title: Text(line['product_name'] as String? ?? ''),
                        subtitle: Text(
                          'الكمية: ' + line['quantity'].toString() +
                          ' • سعر الواحدة: ' + _iqd(line['unit_price_iqd']),
                        ),
                        trailing: Text(
                          _iqd(line['line_total_iqd']),
                          style: const TextStyle(
                            fontWeight: FontWeight.bold, color: _purple),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: 19),
          const Text('مراحل الطلب', style: TextStyle(
            fontSize: 18, fontWeight: FontWeight.w900, color: _dark)),
          const SizedBox(height: 7),
          FutureBuilder<List<Map<String, dynamic>>>(
            future: _events,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snap.hasError) {
                return const Text('تعذّر تحميل سجل حالة الطلب.');
              }
              final events = snap.data ?? [];
              if (events.isEmpty) {
                return const Text(
                  'لا توجد حركة سابقة مسجّلة لهذا الطلب.',
                );
              }
              return Column(children: [
                for (final event in events)
                  ListTile(
                    leading: const Icon(Icons.check_circle_outline,
                      color: _purple),
                    title: Text(_statusLabel(
                      event['new_status'] as String? ?? '')),
                    subtitle: Text(
                      event['changed_at']?.toString() ?? '',
                      style: const TextStyle(fontSize: 11),
                    ),
                  ),
              ]);
            },
          ),
          const SizedBox(height: 16),
          const Text(
            'استلام الطلب وتحصيل المبلغ لم يرتبطا بعد بنظام '
            'تتبع مندوب أو إثبات تحصيل. هذه الحالة تبيّن '
            'ما سجّله المتجر حتى الآن فقط.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.black54, fontSize: 12)),
        ],
      ),
    ),
  );
}
