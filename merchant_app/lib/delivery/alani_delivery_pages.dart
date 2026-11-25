import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Explicit TEST gate. Backend RPCs also verify actual user permissions.
abstract final class AlAniMerchantDeliveryGate {
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

String _iqd(Object? amount) {
  final value = (amount is num ? amount.toInt() : 0).toString();
  return value.replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
      (m) => '${m[1]},') + ' د.ع';
}

/// Owner/admin: registers approved user accounts as couriers, then assigns
/// an explicitly selected courier to a READY order. Never accepts free-form
/// order status writes or discloses a buyer's one-time handoff code.
class AlAniMerchantDeliveryPage extends StatefulWidget {
  const AlAniMerchantDeliveryPage({super.key, required this.storeId});
  final String storeId;

  @override
  State<AlAniMerchantDeliveryPage> createState() =>
      _AlAniMerchantDeliveryPageState();
}

class _AlAniMerchantDeliveryPageState
    extends State<AlAniMerchantDeliveryPage> {
  late Future<List<Map<String, dynamic>>> _couriers;
  late Future<List<Map<String, dynamic>>> _orders;
  bool busy = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<List<Map<String, dynamic>>> _loadCouriers() async {
    final rows = await Supabase.instance.client.rpc(
      'alani_list_delivery_couriers');
    return (rows as List<dynamic>)
      .map((x) => Map<String, dynamic>.from(x as Map)).toList();
  }

  Future<List<Map<String, dynamic>>> _loadOrders() async {
    final rows = await Supabase.instance.client.from('orders')
        .select('id,buyer_id,total_iqd,delivery_fee_iqd,status')
        .eq('store_id', widget.storeId)
        .inFilter('status', ['ready', 'out_for_delivery'])
        .order('created_at', ascending: false).limit(60);
    return rows.map((x) => Map<String, dynamic>.from(x)).toList();
  }

  void _reload() {
    setState(() {
      _couriers = _loadCouriers();
      _orders = _loadOrders();
    });
  }

  void _notice(String message) {
    if (mounted) ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _authorizeCourier() async {
    final id = TextEditingController();
    final approved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('اعتماد مندوب للتوصيل'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('أدخل معرّف حساب المندوب المسجل بالنظام. '
            'يجب أن يكون حساباً مستقلاً عن الزبون والتاجر. '
            'لا تشارك كلمات المرور.'),
          const SizedBox(height: 12),
          TextField(
            controller: id,
            decoration: const InputDecoration(
              labelText: 'معرّف حساب المندوب (UUID)',
              border: OutlineInputBorder()),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('اعتماد')),
        ],
      ),
    );
    final courierId = id.text.trim();
    id.dispose();
    if (approved != true || !mounted) return;
    if (!RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
    ).hasMatch(courierId)) {
      _notice('معرّف حساب المندوب غير صحيح.');
      return;
    }
    await _call('alani_set_delivery_courier',
      {'p_courier_id': courierId, 'p_enabled': true},
      'تم اعتماد حساب المندوب.');
  }

  Future<void> _call(String method, Map<String, dynamic> params,
      String success) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await Supabase.instance.client.rpc(method, params: params);
      _notice(success);
      _reload();
    } catch (_) {
      _notice('تعذّرت العملية. تحقق من صلاحيات المتجر '
        'وحالة الطلب والاتصال.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _dispatch(String orderId, String courierId) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تسليم الطلب للمندوب؟'),
        content: const Text('تأكد أن الطلب جاهز وأن المندوب معتمد. '
            'بعد التعيين يستطيع المندوب تسجيل الاستلام من المتجر '
            'ولا يتم تسجيل التحصيل النقدي تلقائياً.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
            child: const Text('رجوع')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true),
            child: const Text('تعيين المندوب')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await _call('alani_dispatch_delivery',
      {'p_order_id': orderId, 'p_courier_id': courierId},
      'تم تحويل الطلب إلى حالة خرج للتوصيل.');
  }

  @override
  Widget build(BuildContext context) {
    if (!AlAniMerchantDeliveryGate.enabled ||
      widget.storeId != AlAniMerchantDeliveryGate.storeId) {
      return Scaffold(appBar: AppBar(title: const Text('إدارة التوصيل')),
        body: const Center(child: Text(
          'إدارة توصيل العاني متاحة فقط بقاعدة TEST المعتمدة.')));
    }
    return Scaffold(
      appBar: AppBar(title: const Text('إدارة توصيل الطلبات'),
        actions: [IconButton(tooltip: 'تحديث',onPressed: _reload,
          icon: const Icon(Icons.refresh))]),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('خطوات الطلب: تجهيز ← تعيين مندوب ← '
            'استلام من المتجر ← رمز الزبون ← تسليم',
            style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          const Text('رسوم الطلبات الجديدة المعتمدة ٥٬٠٠٠ د.ع. '
            'الطلبات الأقدم قد تحمل رسوماً مختلفة؛ راجع قيمة كل فاتورة '
            'ولا تعتبرها إثبات تحصيل نقدي.'),
          const SizedBox(height: 15),
          FilledButton.icon(onPressed: busy ? null : _authorizeCourier,
            icon: const Icon(Icons.person_add_alt_1_outlined),
            label: const Text('اعتماد حساب مندوب')),
          const SizedBox(height: 15),
          const Text('المندوبون المعتمدون',
            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
          FutureBuilder<List<Map<String, dynamic>>>(
            future: _couriers,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const LinearProgressIndicator();
              }
              if (snap.hasError) {
                return const Text('تعذّر تحميل المندوبين. تأكد من صلاحيات حسابك.');
              }
              final couriers = snap.data ?? [];
              if (couriers.isEmpty) {
                return const Text('ماكو مندوب معتمد حتى الآن.');
              }
              return Column(children: [
                for (final courier in couriers)
                  ListTile(
                    title: Text('حساب: ${courier['courier_id'].toString().substring(0, 8)}'),
                    subtitle: Text(
                      'الطلبات النشطة: ${courier['active_jobs'] ?? 0}'),
                    trailing: courier['enabled'] == true
                      ? OutlinedButton(
                          onPressed: busy ? null : () => _call(
                            'alani_set_delivery_courier',
                            {'p_courier_id': courier['courier_id'],
                             'p_enabled': false},
                            'تم تعطيل المندوب.'),
                          child: const Text('تعطيل'),
                        )
                      : OutlinedButton(
                          onPressed: busy ? null : () => _call(
                            'alani_set_delivery_courier',
                            {'p_courier_id': courier['courier_id'],
                             'p_enabled': true},
                            'تم تفعيل المندوب.'),
                          child: const Text('تفعيل'),
                        ),
                  ),
              ]);
            },
          ),
          const Divider(height: 32),
          const Text('طلبات جاهزة للتوصيل',
            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
          FutureBuilder<List<List<Map<String, dynamic>>>>(
            future: Future.wait<List<Map<String, dynamic>>>([_orders, _couriers]),
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const LinearProgressIndicator();
              }
              if (snap.hasError) {
                return const Text('تعذّر تحميل الطلبات. اسحب للتحديث.');
              }
              final orders = snap.data![0];
              final couriers = snap.data![1]
                  .where((x) => x['enabled'] == true).toList();
              final own = Supabase.instance.client.auth.currentUser?.id;
              final relevant = orders.where(
                (o) => o['buyer_id']?.toString() != own).toList();
              if (relevant.isEmpty) return const Text('لا توجد طلبات جاهزة.');
              return Column(children: [
                for (final order in relevant) Card(
                  child: Padding(padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text('طلب #${order['id'].toString().substring(0, 8)}',
                          style: const TextStyle(fontWeight: FontWeight.w900)),
                        Text('الإجمالي: ${_iqd(order['total_iqd'])} '
                          '• التوصيل: ${_iqd(order['delivery_fee_iqd'])}'),
                        if (order['status'] == 'ready') ...[
                          if (couriers.isEmpty)
                            const Text('اعتمد مندوباً أولاً.')
                          else
                            for (final courier in couriers)
                              OutlinedButton.icon(
                                onPressed: busy ? null : () => _dispatch(
                                  order['id'].toString(),
                                  courier['courier_id'].toString()),
                                icon: const Icon(Icons.local_shipping_outlined),
                                label: Text('تعيين المندوب ${courier['courier_id'].toString().substring(0, 8)}'),
                              ),
                        ] else
                          const Text('تم إرساله للمندوب؛ تابع حالة التسليم.'),
                      ],
                    ),
                  ),
                ),
              ]);
            },
          ),
        ],
      ),
    );
  }
}

/// Authenticated courier only. Tasks are filtered by an RLS-guarded RPC;
/// buyer phone numbers and handoff secrets never appear in task responses.
class AlAniCourierTasksPage extends StatefulWidget {
  const AlAniCourierTasksPage({super.key});

  @override
  State<AlAniCourierTasksPage> createState() => _AlAniCourierTasksPageState();
}

class _AlAniCourierTasksPageState extends State<AlAniCourierTasksPage> {
  late Future<List<Map<String, dynamic>>> _tasks;
  bool busy = false;
  @override
  void initState() {
    super.initState();
    _tasks = _load();
  }

  Future<List<Map<String, dynamic>>> _load() async {
    final rows = await Supabase.instance.client
        .rpc('alani_my_delivery_tasks');
    return (rows as List<dynamic>)
        .map((x) => Map<String, dynamic>.from(x as Map)).toList();
  }

  Future<void> _refresh() async {
    final value = _load();
    setState(() => _tasks = value);
    await value;
  }

  void _notice(String message) {
    if (mounted) ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _pickup(String orderId) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await Supabase.instance.client.rpc(
        'alani_courier_pickup', params: {'p_order_id': orderId});
      _notice('تم تسجيل استلام المنتجات من المتجر.');
      await _refresh();
    } catch (_) {
      _notice('تعذّر تسجيل الاستلام. تحقق من التكليف وحالة الطلب.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _complete(String orderId) async {
    final code = TextEditingController();
    final note = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('إثبات تسليم الطلب'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('لا تطلب رمز الزبون إلا بعد تسليم المنتجات. '
            'خمسة أخطاء تقفل الرمز حتى يصدر الزبون رمزاً جديداً.'),
          TextField(controller: code, keyboardType: TextInputType.number,
            maxLength: 6,
            decoration: const InputDecoration(
              labelText: 'رمز الزبون (6 أرقام)')),
          TextField(controller: note,maxLength: 300,
            decoration: const InputDecoration(
              labelText: 'ملاحظة التسليم (اختياري)')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
            child: const Text('رجوع')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true),
            child: const Text('تأكيد التسليم')),
        ],
      ),
    );
    final pin = code.text.trim(), details = note.text.trim();
    code.dispose();
    note.dispose();
    if (ok != true || !mounted) return;
    if (!RegExp(r'^[0-9]{6}$').hasMatch(pin)) {
      _notice('أدخل رمزاً صحيحاً مكوناً من 6 أرقام.');
      return;
    }
    if (busy) return;
    setState(() => busy = true);
    try {
      final result = await Supabase.instance.client.rpc(
        'alani_courier_complete_delivery',
        params: {'p_order_id': orderId, 'p_code': pin, 'p_note': details},
      );
      if (result == 'delivered') {
        _notice('تم توثيق التسليم برمز الزبون.');
        await _refresh();
      } else {
        _notice(switch (result?.toString()) {
          'WRONG_CODE' => 'الرمز غير صحيح.',
          'CODE_LOCKED' => 'تم قفل الرمز بعد 5 محاولات خاطئة.',
          'CODE_EXPIRED' => 'انتهت صلاحية الرمز. اطلب رمزاً جديداً من الزبون.',
          'CODE_NOT_ISSUED' => 'الزبون لم يصدر رمز التسليم بعد.',
          _ => 'لم يتم تأكيد التسليم من الخادم.',
        });
      }
    } catch (_) {
      _notice('تعذّر توثيق التسليم. تحقق من حالة الطلب والصلاحيات.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!AlAniMerchantDeliveryGate.enabled) {
      return Scaffold(appBar: AppBar(title: const Text('مهام المندوب')),
        body: const Center(child: Text(
          'واجهة المندوب متاحة فقط على قاعدة الاختبار.')));
    }
    return Scaffold(
      appBar: AppBar(title: const Text('مهام المندوب'),
        actions: [IconButton(onPressed: _refresh,
          tooltip: 'تحديث',icon: const Icon(Icons.refresh))]),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(padding: const EdgeInsets.all(16),
          children: [
            const Text('لن تظهر لك إلا طلبات التوصيل المسندة '
              'إلى حسابك المعتمد.',
              style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 14),
            FutureBuilder<List<Map<String, dynamic>>>(
              future: _tasks,
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snap.hasError) {
                  return const Text('تعذّر جلب المهام. تحقق من حساب المندوب.');
                }
                final tasks = snap.data ?? [];
                if (tasks.isEmpty) {
                  return const Text('ماكو مهام مسندة إلك حالياً.');
                }
                return Column(children: [
                  for (final job in tasks) Card(
                    child: Padding(padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text('طلب #${job['order_id'].toString().substring(0,8)}',
                            style: const TextStyle(
                              fontSize: 17,fontWeight: FontWeight.w900)),
                          const SizedBox(height: 7),
                          Text('العنوان: ${job['delivery_address'] ?? ''}'),
                          Text('الإجمالي عند الاستلام: ${_iqd(job['total_iqd'])}'),
                          Text('أجر التوصيل ضمن الإجمالي: '
                            '${_iqd(job['delivery_fee_iqd'])}'),
                          const SizedBox(height: 12),
                          if (job['picked_up_at'] == null)
                            FilledButton.icon(
                              onPressed: busy ? null : () => _pickup(
                                job['order_id'].toString()),
                              icon: const Icon(Icons.inventory_2_outlined),
                              label: const Text('استلمت المنتجات من المتجر'))
                          else
                            FilledButton.icon(
                              onPressed: busy ? null : () => _complete(
                                job['order_id'].toString()),
                              icon: const Icon(Icons.verified_outlined),
                              label: const Text('تسليم برمز الزبون')),
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
