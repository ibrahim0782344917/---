import 'package:flutter/material.dart';
import 'admin_api.dart';

/// The bars are derived only from the actual orders table, never mock data.
class WeeklyOrdersChart extends StatelessWidget {
  final List<Map<String, dynamic>> daily;
  const WeeklyOrdersChart({super.key, required this.daily});

  @override
  Widget build(BuildContext context) {
    var maxCount = 0;
    for (final day in daily) {
      final count = (day['orders'] as num?)?.toInt() ?? 0;
      if (count > maxCount) maxCount = count;
    }
    return Card(
      child: Padding(padding: const EdgeInsets.all(18), child:
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('حركة الطلبات خلال 7 أيام', style: TextStyle(
            fontSize: 17, fontWeight: FontWeight.w800)),
          const SizedBox(height: 5),
          const Text('طلبات فعلية حسب تاريخ الإنشاء؛ ليست أرباحاً محصّلة.',
            style: TextStyle(color: Colors.black54, fontSize: 12)),
          const SizedBox(height: 18),
          SizedBox(height: 145, child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: daily.map((day) {
              final count = (day['orders'] as num?)?.toInt() ?? 0;
              final name = day['date']?.toString() ?? '';
              final height = maxCount == 0
                ? 4.0 : 5.0 + 100.0 * count / maxCount;
              return Expanded(child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(count.toString(), style: const TextStyle(
                      fontWeight: FontWeight.w800, fontSize: 11)),
                    const SizedBox(height: 3),
                    Container(height: height, decoration: BoxDecoration(
                      color: count == 0
                        ? const Color(0xFFDDE1F7) : const Color(0xFF595FCB),
                      borderRadius: BorderRadius.circular(6))),
                    const SizedBox(height: 7),
                    Text(name.length >= 10 ? name.substring(5) : name,
                      style: const TextStyle(fontSize: 10)),
                  ],
                ),
              ));
            }).toList(),
          )),
        ]),
      ),
    );
  }
}

class AdminProDialogs {
  static String date(Object? value) {
    final raw = value?.toString() ?? '';
    final parsed = DateTime.tryParse(raw)?.toLocal();
    if (parsed == null) return raw;
    String two(int n) => n.toString().padLeft(2, '0');
    return parsed.year.toString() + '/' + two(parsed.month) + '/' +
      two(parsed.day) + ' ' + two(parsed.hour) + ':' + two(parsed.minute);
  }

  static Future<bool> editProduct(BuildContext context,
      Map<String, dynamic> product, {required bool price}) async {
    final amount = TextEditingController();
    final reason = TextEditingController();
    String? error;
    final confirmation = await showDialog<(int, String)>(
      context: context, builder: (dialog) => StatefulBuilder(
        builder: (dialog, redraw) => AlertDialog(
          title: Text(price ? 'تعديل السعر' : 'تسوية المخزون'),
          content: SingleChildScrollView(child:
            Column(mainAxisSize: MainAxisSize.min, children: [
              Text(product['name']?.toString() ?? 'المنتج'),
              const SizedBox(height: 10),
              Text(price
                ? 'السعر الحالي: ' + product['price_iqd'].toString() + ' د.ع'
                : 'المخزون الحالي: ' + product['stock_quantity'].toString(),
                style: const TextStyle(color: Colors.black54)),
              const SizedBox(height: 12),
              TextField(controller: amount,
                keyboardType: const TextInputType.numberWithOptions(signed: true),
                decoration: InputDecoration(border: const OutlineInputBorder(),
                  labelText: price ? 'السعر الجديد بالدينار'
                    : 'الفرق (+ إضافة / - خصم)')),
              const SizedBox(height: 12),
              TextField(controller: reason, maxLines: 3, maxLength: 1000,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'سبب التعديل (20 حرفاً على الأقل)')),
              if (error != null) Text(error!,
                style: const TextStyle(color: Colors.red)),
            ])),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialog),
              child: const Text('إلغاء')),
            FilledButton(onPressed: () {
              final parsed = int.tryParse(amount.text.trim());
              final valid = parsed != null && reason.text.trim().length >= 20 &&
                (price ? parsed >= 0 && parsed <= 100000000
                  : parsed != 0 && parsed >= -10000 && parsed <= 10000);
              if (!valid) {
                redraw(() => error = 'تأكد من القيمة والسبب؛ لا يمكن حفظ إدخال غير صحيح.');
                return;
              }
              Navigator.pop(dialog, (parsed!, reason.text.trim()));
            }, child: const Text('تأكيد وتسجيل العملية')),
          ],
        ),
      ),
    );
    amount.dispose();
    reason.dispose();
    if (confirmation == null || !context.mounted) return false;
    try {
      if (price) {
        await AdminApi.setPrice(
          productId: product['id'].toString(), priceIqd: confirmation.$1,
          reason: confirmation.$2);
      } else {
        await AdminApi.adjustStock(
          productId: product['id'].toString(), delta: confirmation.$1,
          reason: confirmation.$2);
      }
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم حفظ التعديل في قاعدة البيانات وسجل الإدارة')));
      }
      return true;
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تعذر تنفيذ التعديل: ' + e.toString())));
      }
      return false;
    }
  }

  static Future<void> showOrder(BuildContext context, String id) async {
    try {
      final data = await AdminApi.orderDetail(id);
      if (!context.mounted) return;
      final order = Map<String, dynamic>.from(data['order'] as Map);
      final products = data['items'] as List<dynamic>? ?? [];
      final history = data['history'] as List<dynamic>? ?? [];
      await showModalBottomSheet<void>(
        context: context, isScrollControlled: true, showDragHandle: true,
        builder: (sheet) => SafeArea(child: FractionallySizedBox(
          heightFactor: 0.82,
          child: ListView(padding: const EdgeInsets.all(22), children: [
            const Text('تفاصيل الطلب', style: TextStyle(
              fontWeight: FontWeight.w900, fontSize: 22)),
            const SizedBox(height: 12),
            SelectableText('الرقم: ' + id),
            Text('الحالة: ' + (order['status'] ?? '—').toString()),
            Text('الإجمالي: ' + (order['total_iqd'] ?? 0).toString() + ' د.ع'),
            SelectableText('العنوان: ' +
                (order['delivery_address'] ?? '').toString()),
            SelectableText('الهاتف: ' +
                (order['phone'] ?? '').toString()),
            if ((order['notes'] ?? '').toString().isNotEmpty)
              Text('الملاحظات: ' + order['notes'].toString()),
            const Divider(),
            const Text('محتويات الطلب', style: TextStyle(
              fontWeight: FontWeight.bold, fontSize: 17)),
            if (products.isEmpty) const Text('لا توجد عناصر مسجّلة لهذا الطلب.'),
            for (final item in products)
              ListTile(
                title: Text((item as Map)['product_name']?.toString() ?? ''),
                subtitle: Text('الكمية: ' + item['quantity'].toString()),
                trailing: Text(item['line_total_iqd'].toString() + ' د.ع'),
              ),
            const Divider(),
            const Text('سجل انتقالات الحالة', style: TextStyle(
              fontWeight: FontWeight.bold, fontSize: 17)),
            if (history.isEmpty)
              const Text('لم تُسجّل انتقالات بعد.'),
            for (final event in history)
              ListTile(
                leading: const Icon(Icons.history),
                title: Text((event as Map)['new_status']?.toString() ?? ''),
                subtitle: Text(date(event['changed_at'])),
              ),
          ]),
        )),
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('تعذر فتح تفاصيل الطلب: ' + e.toString())));
      }
    }
  }
}
