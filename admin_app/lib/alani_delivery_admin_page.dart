import 'alani_cod_page.dart';
import 'package:flutter/material.dart';
import 'package:shitreed_admin/admin_api.dart';

/// Only the verified super-admin sees dispatch controls.
/// The database independently checks the role for every operation.
abstract final class AlAniDeliveryAdminFeature {
  static const bool enabled =
      bool.fromEnvironment('ALANI_DELIVERY_WORKFLOW_ENABLED',
          defaultValue: false) &&
      (String.fromEnvironment('SUPABASE_URL') ==
              'https://tgvdwotbrnhcoykuxdpr.supabase.co' ||
          bool.fromEnvironment('ALANI_DELIVERY_PRODUCTION_APPROVED',
              defaultValue: false));
  static const storeId = '25091ca2-c0da-416c-b634-81b188ee66be';
}

class AlAniDeliveryAdminPage extends StatefulWidget {
  const AlAniDeliveryAdminPage({super.key});
  @override
  State<AlAniDeliveryAdminPage> createState() => _AlAniDeliveryAdminPageState();
}

class _AlAniDeliveryAdminPageState extends State<AlAniDeliveryAdminPage> {
  late Future<_DeliverySnapshot> _current;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _current = _read();
  }

  Future<_DeliverySnapshot> _read() async {
    if (!AlAniDeliveryAdminFeature.enabled) {
      throw StateError('TEST_ONLY');
    }
    final db = AdminApi.client;
    final couriers = await db.rpc('alani_list_delivery_couriers') as List;
    final jobs = await db.rpc('alani_owner_delivery_jobs') as List;
    final ready = await db.from('orders')
        .select('id,total_iqd,delivery_fee_iqd,status')
        .eq('store_id', AlAniDeliveryAdminFeature.storeId)
        .eq('status', 'ready').limit(50);
    return _DeliverySnapshot(
      couriers.map((e) => Map<String, dynamic>.from(e)).toList(),
      jobs.map((e) => Map<String, dynamic>.from(e)).toList(),
      ready.map((e) => Map<String, dynamic>.from(e)).toList(),
    );
  }

  Future<void> _reload() async {
    final next = _read();
    setState(() => _current = next);
    try { await next; } catch (_) { /* shown in UI */ }
  }

  void _notice(String value) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(value)));
  }

  Future<void> _run(Future<void> Function() task) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await task();
      if (mounted) {
        _notice('تم حفظ العملية في قاعدة الاختبار.');
        await _reload();
      }
    } catch (_) {
      if (mounted) _notice('تعذّرت العملية: تأكد من صلاحيات الإدارة وحالة الطلب.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _addCourier() async {
    final controller = TextEditingController();
    final id = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('اعتماد مندوب'),
        content: TextField(controller: controller,
          decoration: const InputDecoration(
            labelText: 'معرف حساب المندوب UUID',
            border: OutlineInputBorder())),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx),
              child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(ctx,controller.text.trim()),
              child: const Text('اعتماد')),
        ],
      ),
    );
    controller.dispose();
    if (id == null || !mounted) return;
    if (!RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-'
      r'[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
    ).hasMatch(id)) {
      _notice('المعرّف غير صحيح.');
      return;
    }
    await _run(() async {
      await AdminApi.client.rpc('alani_set_delivery_courier',
        params: {'p_courier_id': id, 'p_enabled': true});
    });
  }

  Future<void> _dispatch(String orderId,
      List<Map<String, dynamic>> couriers) async {
    final active = couriers.where((e) => e['enabled'] == true).toList();
    if (active.isEmpty) {
      _notice('لا توجد حسابات مندوبين معتمدة.');
      return;
    }
    var courierId = active.first['courier_id'].toString();
    final selected = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx,update) => AlertDialog(
          title: const Text('إسناد طلب للمندوب'),
          content: DropdownButtonFormField<String>(
            initialValue: courierId,
            decoration: const InputDecoration(
              labelText: 'المندوب المعتمد',border: OutlineInputBorder()),
            items: [
              for (final c in active) DropdownMenuItem<String>(
                value: c['courier_id'].toString(),
                child: Text('مندوب ${c['courier_id']
                    .toString().substring(0, 8)}')),
            ],
            onChanged: (v) => update(() => courierId = v ?? courierId),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx),
              child: const Text('رجوع')),
            FilledButton(onPressed: () => Navigator.pop(ctx,courierId),
              child: const Text('تأكيد الإرسال')),
          ],
        ),
      ),
    );
    if (selected == null || !mounted) return;
    await _run(() async {
      final response = await AdminApi.client.rpc('alani_dispatch_delivery',
        params: {'p_order_id': orderId, 'p_courier_id': selected});
      if (response != 'out_for_delivery') {
        throw StateError('NOT_DISPATCHED');
      }
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('إدارة التوصيل — العاني'),
      actions: [
        if (AlAniCodPage.enabled)
          IconButton(
            tooltip: 'تقارير التحصيل التجريبي',
            icon: const Icon(Icons.receipt_long),
            onPressed: () => Navigator.of(context).push<void>(
              MaterialPageRoute(builder: (_) => const AlAniCodPage(staff: true))),
          ),
        IconButton(onPressed: _reload,
        tooltip: 'تحديث',icon:const Icon(Icons.refresh))]),
    body: !AlAniDeliveryAdminFeature.enabled
        ? const Center(child: Text('نظام التوصيل غير مفعّل بالإنتاج.'))
        : FutureBuilder<_DeliverySnapshot>(
            future: _current,
            builder: (context,snapshot) {
              if (snapshot.hasError) return const Center(
                child: Text('صلاحية الإدارة غير كافية أو قاعدة TEST غير متاحة.'));
              if (!snapshot.hasData) return const Center(
                child: CircularProgressIndicator());
              final data = snapshot.data!;
              return RefreshIndicator(onRefresh: _reload,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(16),
                  children: [
                    const Text('توصيل ٥٬٠٠٠ دينار — دفع عند الاستلام',
                      style: TextStyle(fontSize: 18,
                        fontWeight: FontWeight.w900)),
                    const Text('هذه الصفحة للتجارب، ولا تمثّل إيصالاً '
                      'مالياً أو إثبات تحصيل. بيانات المندوبين محمية.'),
                    const SizedBox(height: 12),
                    FilledButton.icon(onPressed: _busy ? null : _addCourier,
                      icon: const Icon(Icons.person_add_alt_1),
                      label: const Text('اعتماد حساب مندوب')),
                    const SizedBox(height: 14),
                    const Text('المندوبون',
                      style: TextStyle(fontWeight: FontWeight.w900)),
                    for (final c in data.couriers)
                      ListTile(
                        title: Text('مندوب ${c['courier_id']
                            .toString().substring(0, 8)}'),
                        subtitle: Text(
                          'طلبات جارية: ${c['active_jobs']}'),
                        trailing: Switch(
                          value: c['enabled'] == true,
                          onChanged: _busy ? null : (enabled) =>
                            _run(() async {
                              await AdminApi.client.rpc('alani_set_delivery_courier',
                                params: {
                                  'p_courier_id': c['courier_id'],
                                  'p_enabled': enabled,
                                });
                            }),
                        ),
                      ),
                    const Divider(),
                    const Text('طلبات جاهزة للإرسال',
                      style: TextStyle(fontWeight: FontWeight.w900)),
                    if (data.ready.isEmpty)
                      const ListTile(title:Text('ماكو طلبات جاهزة.')),
                    for (final o in data.ready)
                      ListTile(
                        title: Text('طلب ${o['id']
                            .toString().substring(0, 8)}'),
                        subtitle: Text('الإجمالي: ${o['total_iqd']} د.ع'),
                        trailing: FilledButton(
                          onPressed: _busy ? null :
                            () => _dispatch(o['id'].toString(),data.couriers),
                          child: const Text('إرسال')),
                      ),
                    const Divider(),
                    const Text('الطلبات المرسلة',
                      style: TextStyle(fontWeight: FontWeight.w900)),
                    if (data.jobs.isEmpty)
                      const ListTile(title:Text('ماكو طلبات مسندة.')),
                    for (final j in data.jobs)
                      ListTile(
                        leading: Icon(j['status']=='delivered'
                          ? Icons.verified : Icons.delivery_dining),
                        title: Text('طلب ${j['order_id']
                            .toString().substring(0, 8)}'),
                        subtitle: Text(j['status']=='delivered'
                          ? 'تم التسليم برمز الزبون'
                          : j['picked_up_at']==null
                            ? 'بانتظار استلام المندوب'
                            : 'قيد التوصيل'),
                        trailing: const Icon(Icons.chevron_left),
                      ),
                  ],
                ),
              );
            },
          ),
  );
}

class _DeliverySnapshot {
  _DeliverySnapshot(this.couriers,this.jobs,this.ready);
  final List<Map<String,dynamic>> couriers;
  final List<Map<String,dynamic>> jobs;
  final List<Map<String,dynamic>> ready;
}
