import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// TEST-only cash reconciliation. A recorded/confirmed amount is simulated,
/// not a payment or an accounting settlement. All permissions are server-side.
class AlAniCodPage extends StatefulWidget {
  const AlAniCodPage({super.key, required this.staff});
  final bool staff;
  static const enabled =
      bool.fromEnvironment('ALANI_DELIVERY_WORKFLOW_ENABLED', defaultValue: false) &&
      String.fromEnvironment('SUPABASE_URL') ==
          'https://tgvdwotbrnhcoykuxdpr.supabase.co';

  @override
  State<AlAniCodPage> createState() => _AlAniCodPageState();
}

class _AlAniCodPageState extends State<AlAniCodPage> {
  late Future<Map<String, dynamic>> _report;
  bool _busy = false;
  SupabaseClient get _db => Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    _report = _load();
  }

  Future<Map<String, dynamic>> _load() async {
    if (!AlAniCodPage.enabled) throw StateError('TEST_ONLY');
    final data = await _db.rpc('alani_cod_report_test',
        params: {'p_mode': widget.staff ? 'staff' : 'courier'});
    return Map<String, dynamic>.from(data as Map);
  }

  void _refresh() {
    setState(() => _report = _load());
  }

  String _money(dynamic amount) => (amount ?? 0).toString() + ' د.ع';
  String _status(dynamic status) {
    switch (status) {
      case 'unrecorded': return 'لم يُسجل التحصيل';
      case 'recorded': return 'مسجل، بانتظار التأكيد';
      case 'confirmed': return 'مؤكد تجريبياً';
      default: return 'غير معروف';
    }
  }

  Future<void> _act(Map<String, dynamic> row) async {
    if (_busy || !AlAniCodPage.enabled) return;
    final amount = int.tryParse(row['total_iqd'].toString());
    if (amount == null || amount <= 0) return;
    String entered = '';
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(widget.staff ? 'تأكيد التحصيل التجريبي' : 'تسجيل التحصيل التجريبي'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('مبلغ الفاتورة: ' + _money(amount)),
            const Text('هذه محاكاة في TEST فقط، ولا تنقل أموالاً.'),
            if (!widget.staff)
              TextField(
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'أدخل المبلغ المستلم تجريبياً'),
                onChanged: (v) => entered = v.trim(),
              ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false),
              child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(context, true),
              child: const Text('تأكيد')),
        ],
      ),
    );
    if (!mounted || accepted != true || _busy) return;
    final recordedAmount = widget.staff ? amount : int.tryParse(entered);
    if (recordedAmount != amount) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('المبلغ يجب أن يطابق الفاتورة.')));
      return;
    }
    setState(() => _busy = true);
    try {
      final result = await _db.rpc(
        widget.staff ? 'alani_confirm_cod_test' : 'alani_record_cod_test',
        params: {
          'p_order_id': row['order_id'],
          if (!widget.staff) 'p_amount_iqd': recordedAmount,
        },
      );
      if (result != 'recorded' && result != 'confirmed') {
        throw StateError('COD_NOT_CONFIRMED');
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم حفظ العملية التجريبية.')));
      _refresh();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تعذرت العملية. تحقق من الصلاحية وحالة الطلب.')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.staff ? 'تقارير التحصيل - TEST' : 'تحصيل المندوب - TEST'),
      actions: [IconButton(onPressed: _busy ? null : _refresh,
          tooltip: 'تحديث', icon: const Icon(Icons.refresh))],
    ),
    body: !AlAniCodPage.enabled
        ? const Center(child: Text('التحصيل التجريبي غير مفعل.'))
        : FutureBuilder<Map<String, dynamic>>(
            future: _report,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError || !snapshot.hasData) {
                return Center(child: TextButton(
                    onPressed: _busy ? null : _refresh,
                    child: const Text('تعذر تحميل التقرير - إعادة المحاولة')));
              }
              final data = snapshot.data!;
              final rows = (data['items'] as List? ?? const [])
                  .map((e) => Map<String, dynamic>.from(e as Map)).toList();
              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  const Text('محاكاة التحصيل فقط؛ لا توجد مدفوعات أو تسويات مالية حقيقية.'),
                  const SizedBox(height: 12),
                  Card(child: Column(children: [
                    ListTile(title: const Text('غير مسجل'),
                        trailing: Text(_money(data['unrecorded_iqd']))),
                    ListTile(title: const Text('بانتظار التأكيد'),
                        trailing: Text(_money(data['recorded_iqd']))),
                    ListTile(title: const Text('مؤكد تجريبياً'),
                        trailing: Text(_money(data['confirmed_iqd']))),
                  ])),
                  Text('عدد الطلبات: ' + (data['total_count'] ?? 0).toString() +
                      ' • عرض آخر 100 طلب'),
                  if (rows.isEmpty) const Padding(padding: EdgeInsets.all(16),
                      child: Text('لا توجد طلبات مسلمة ضمن صلاحياتك.')),
                  for (final row in rows)
                    Card(child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('الطلب: ' + row['order_id'].toString()),
                        Text(_money(row['total_iqd'])),
                        Text(_status(row['status'])),
                        if ((int.tryParse(row['approved_returns'].toString()) ?? 0) > 0)
                          const Text('استرجاع معتمد مرتبط؛ لم يُصرف تعويض.'),
                        if ((!widget.staff && row['status'] == 'unrecorded') ||
                            (widget.staff && row['can_confirm'] == true))
                          FilledButton(
                            onPressed: _busy ? null : () => _act(row),
                            child: Text(widget.staff ? 'تأكيد التحصيل' : 'تسجيل التحصيل'),
                          ),
                      ]),
                    )),
                ],
              );
            },
          ),
  );
}
