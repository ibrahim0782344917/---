import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Test-only handoff UI. A production flag alone must never unlock checkout.
abstract final class AlAniDeliveryGate {
  static const storeId = '25091ca2-c0da-416c-b634-81b188ee66be';
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

abstract final class AlAniDeliveryStages {
  static String label(String status) => switch (status) {
        'placed' => 'بانتظار قبول المتجر',
        'accepted' => 'تم قبول الطلب',
        'preparing' => 'جارٍ تحضير المنتجات',
        'ready' => 'جاهز لتعيين المندوب',
        'out_for_delivery' => 'خرج للتوصيل',
        'delivered' => 'تم التسليم برمز الاستلام',
        'rejected' => 'رفض المتجر الطلب',
        'cancelled' => 'تم إلغاء الطلب',
        _ => 'جاري تحديث حالة الطلب',
      };
}

/// Buyer-only tracking: does not fetch a courier phone number or private
/// delivery credentials. The server verifies buyer identity and handoff state.
class AlAniCustomerDeliveryCard extends StatefulWidget {
  const AlAniCustomerDeliveryCard({super.key, required this.orderId});
  final String orderId;

  @override
  State<AlAniCustomerDeliveryCard> createState() =>
      _AlAniCustomerDeliveryCardState();
}

class _AlAniCustomerDeliveryCardState
    extends State<AlAniCustomerDeliveryCard> {
  late Future<Map<String, dynamic>> _delivery;
  bool _issuing = false;

  @override
  void initState() {
    super.initState();
    _delivery = _load();
  }

  Future<Map<String, dynamic>> _load() async {
    final response = await Supabase.instance.client.rpc(
      'alani_order_delivery_status',
      params: {'p_order_id': widget.orderId},
    );
    return Map<String, dynamic>.from(response as Map);
  }

  Future<void> _refresh() async {
    final next = _load();
    setState(() => _delivery = next);
    await next;
  }

  Future<void> _issuePin() async {
    if (_issuing) return;
    setState(() => _issuing = true);
    try {
      final response = await Supabase.instance.client.rpc(
        'alani_issue_delivery_pin',
        params: {'p_order_id': widget.orderId},
      );
      final result = Map<String, dynamic>.from(response as Map);
      final pin = result['code']?.toString() ?? '';
      if (!RegExp(r'^[0-9]{6}$').hasMatch(pin)) {
        throw const FormatException('Invalid delivery code');
      }
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: const Text('رمز استلام الطلب'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(pin, textDirection: TextDirection.ltr,
                style: const TextStyle(fontWeight: FontWeight.w900,
                  fontSize: 32, letterSpacing: 5)),
              const SizedBox(height: 12),
              const Text('الرمز صالح لمدة 15 دقيقة. لا تعطه للمندوب '
                'إلا بعد أن تستلم المنتجات وتتأكد من سلامتها. '
                'هذا الرمز ليس إثبات تحصيل المبلغ.'),
            ],
          ),
          actions: [
            FilledButton(onPressed: () => Navigator.pop(context),
              child: const Text('فهمت')),
          ],
        ),
      );
      if (mounted) await _refresh();
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(
          'تعذّر إصدار الرمز. تأكد من استلام المندوب للطلب '
          'أو انتظر دقيقة قبل طلب رمز جديد.')),
      );
    } finally {
      if (mounted) setState(() => _issuing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!AlAniDeliveryGate.enabled) {
      return const Card(child: Padding(
        padding: EdgeInsets.all(16),
        child: Text('تتبّع المندوب برمز الاستلام قيد الاختبار؛ '
          'لم يتم تفعيله لطلبات الإنتاج.'),
      ));
    }
    return Card(
      child: Padding(padding: const EdgeInsets.all(14), child:
        FutureBuilder<Map<String, dynamic>>(
          future: _delivery,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return OutlinedButton.icon(
                onPressed: _refresh, icon: const Icon(Icons.refresh),
                label: const Text('تعذّر جلب حالة المندوب؛ حاول مجدداً'),
              );
            }
            final data = snapshot.data!;
            final status = data['status']?.toString() ?? '';
            final dispatched = data['dispatched_at']?.toString();
            final picked = data['picked_up_at']?.toString();
            final delivered = data['delivered_at']?.toString();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(children: [
                  const Icon(Icons.local_shipping_outlined),
                  const SizedBox(width: 9),
                  const Expanded(child: Text('تتبّع التوصيل',
                    style: TextStyle(fontWeight: FontWeight.w900,
                      fontSize: 17))),
                  IconButton(onPressed: _refresh,
                    tooltip: 'تحديث التوصيل',
                    icon: const Icon(Icons.refresh)),
                ]),
                Text(AlAniDeliveryStages.label(status)),
                if (dispatched != null)
                  const ListTile(
                    leading: Icon(Icons.assignment_turned_in_outlined),
                    title: Text('تم تعيين المندوب')),
                if (picked != null)
                  const ListTile(
                    leading: Icon(Icons.inventory_2_outlined),
                    title: Text('استلم المندوب المنتجات من المتجر')),
                if (delivered != null)
                  const ListTile(
                    leading: Icon(Icons.verified_outlined),
                    title: Text('تم التسليم بإثبات رمز الزبون')),
                if (status == 'out_for_delivery' && picked != null) ...[
                  const SizedBox(height: 10),
                  FilledButton.icon(
                    onPressed: _issuing ? null : _issuePin,
                    icon: const Icon(Icons.pin_outlined),
                    label: Text(_issuing ? 'جاري إصدار الرمز...'
                        : 'إظهار رمز التسليم بعد الاستلام'),
                  ),
                ],
                if (status == 'ready' && dispatched == null)
                  const Text('التاجر راح يعيّن مندوباً معتمداً لهذا الطلب.'),
                const SizedBox(height: 6),
                Text('رسوم التوصيل المسجلة لهذا الطلب: '
                    '${data['delivery_fee_iqd'] ?? 0} د.ع. '
                    'هذا لا يعني أن الدفع النقدي تم تحصيله.',
                    style: const TextStyle(fontSize: 12)),
              ],
            );
          },
        ),
      ),
    );
  }
}
