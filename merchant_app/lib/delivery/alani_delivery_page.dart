import 'alani_cod_page.dart';
import 'alani_courier_location_page.dart';
import 'alani_evidence_page.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Courier permissions and database changes are always enforced by SQL RPCs.
/// Production requires explicit approval and the server independently verifies each action.
abstract final class AlAniDeliveryFeature {
  static const storeId = '25091ca2-c0da-416c-b634-81b188ee66be';
  static const enabled =
      bool.fromEnvironment('ALANI_DELIVERY_WORKFLOW_ENABLED', defaultValue: false) &&
      (String.fromEnvironment('SUPABASE_URL') ==
              'https://tgvdwotbrnhcoykuxdpr.supabase.co' ||
          bool.fromEnvironment('ALANI_DELIVERY_PRODUCTION_APPROVED',
              defaultValue: false));
}

abstract final class AlAniDeliveryService {
  static SupabaseClient get _db => Supabase.instance.client;

  static Future<List<Map<String, dynamic>>> approvedCouriers() async {
    final rows = await _db.rpc('alani_list_delivery_couriers');
    return (rows as List).map((x) => Map<String, dynamic>.from(x)).toList();
  }

  static Future<List<Map<String, dynamic>>> readyOrders() async {
    final rows = await _db.from('orders')
        .select('id,status,total_iqd,delivery_fee_iqd,created_at')
        .eq('store_id', AlAniDeliveryFeature.storeId)
        .eq('status', 'ready')
        .order('created_at', ascending: false).limit(60);
    return rows.map((x) => Map<String, dynamic>.from(x)).toList();
  }

  static Future<List<Map<String, dynamic>>> ownerDeliveries() async {
    final rows = await _db.rpc('alani_owner_delivery_jobs');
    return (rows as List).map((x) => Map<String, dynamic>.from(x)).toList();
  }

  static Future<List<Map<String, dynamic>>> myDeliveries() async {
    final rows = await _db.rpc('alani_my_delivery_tasks');
    return (rows as List).map((x) => Map<String, dynamic>.from(x)).toList();
  }

  static Future<void> setCourier(String userId, bool active) async {
    await _db.rpc('alani_set_delivery_courier', params: {
      'p_courier_id': userId, 'p_enabled': active,
    });
  }

  static Future<void> dispatch(String orderId, String courierId) async {
    final status = await _db.rpc('alani_dispatch_delivery', params: {
      'p_order_id': orderId, 'p_courier_id': courierId,
    });
    if (status != 'out_for_delivery') {
      throw StateError('DISPATCH_NOT_CONFIRMED');
    }
  }

  static Future<void> pickup(String orderId) async {
    final result = await _db.rpc('alani_courier_pickup',
        params: {'p_order_id': orderId});
    if (result == null) throw StateError('PICKUP_NOT_CONFIRMED');
  }

  static Future<String> complete(
      String orderId, String pin, String note) async {
    final result = await _db.rpc('alani_courier_complete_delivery', params: {
      'p_order_id': orderId,
      'p_code': pin,
      'p_note': note.trim(),
    });
    return result.toString();
  }
}

class AlAniDeliveryManagerPage extends StatefulWidget {
  const AlAniDeliveryManagerPage({super.key});
  @override
  State<AlAniDeliveryManagerPage> createState() =>
      _AlAniDeliveryManagerPageState();
}

class _AlAniDeliveryManagerPageState extends State<AlAniDeliveryManagerPage> {
  late Future<_DeliveryOverview> _overview;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _overview = _fetch();
  }

  Future<_DeliveryOverview> _fetch() async {
    if (!AlAniDeliveryFeature.enabled) {
      throw StateError('DELIVERY_DISABLED');
    }
    // Each RPC verifies store ownership or the authorized admin role.
    final couriers = await AlAniDeliveryService.approvedCouriers();
    final ready = await AlAniDeliveryService.readyOrders();
    final jobs = await AlAniDeliveryService.ownerDeliveries();
    return _DeliveryOverview(couriers, ready, jobs);
  }

  Future<void> _reload() async {
    final future = _fetch();
    setState(() => _overview = future);
    try { await future; } catch (_) { /* FutureBuilder displays failure. */ }
  }

  Future<void> _registerCourier() async {
    final controller = TextEditingController();
    final userId = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('اعتماد مندوب توصيل'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('اكتب معرّف حساب المندوب في Supabase. '
              'لن يظهر رقم الزبون أو بياناته في قائمة المندوبين.'),
          const SizedBox(height: 12),
          TextField(
            controller: controller,
            decoration: const InputDecoration(
                labelText: 'معرّف حساب المندوب UUID',
                border: OutlineInputBorder()),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx),
              child: const Text('إلغاء')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('اعتماد'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (userId == null || !mounted) return;
    if (!RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-'
      r'[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
    ).hasMatch(userId)) {
      _notice('معرّف الحساب غير صحيح.');
      return;
    }
    await _write(() => AlAniDeliveryService.setCourier(userId, true),
        'تم اعتماد حساب المندوب.');
  }

  Future<void> _dispatch(
      Map<String, dynamic> order, List<Map<String, dynamic>> couriers) async {
    final active = couriers.where((c) => c['enabled'] == true).toList();
    if (active.isEmpty) {
      _notice('اعتمد حساب مندوب أولاً.');
      return;
    }
    var selected = active.first['courier_id'].toString();
    final picked = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, update) => AlertDialog(
        title: const Text('إرسال طلب للمندوب'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('الطلب ${order['id'].toString().substring(0, 8)} '
              'جاهز للتسليم. عند الإرسال يتحول إلى «خرج للتوصيل».'),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: selected,
            decoration: const InputDecoration(
                labelText: 'المندوب المعتمد', border: OutlineInputBorder()),
            items: [
              for (final courier in active)
                DropdownMenuItem<String>(
                  value: courier['courier_id'].toString(),
                  child: Text('مندوب ${courier['courier_id'].toString().substring(0, 8)}'),
                ),
            ],
            onChanged: (value) => update(() => selected = value ?? selected),
          ),
          const SizedBox(height: 12),
          const Text('لا تُعتبر الطلبية مسلّمة أو مدفوعة '
              'لمجرد خروجها للتوصيل.'),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx),
              child: const Text('رجوع')),
          FilledButton(onPressed: () => Navigator.pop(ctx, selected),
              child: const Text('إرسال للمندوب')),
        ],
      )),
    );
    if (picked == null || !mounted) return;
    await _write(
      () => AlAniDeliveryService.dispatch(order['id'].toString(), picked),
      'تم إرسال الطلب للمندوب وتحديث حالته.',
    );
  }

  Future<void> _write(Future<void> Function() action, String success) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await action();
      if (mounted) {
        _notice(success);
        await _reload();
      }
    } catch (_) {
      if (mounted) _notice('تعذّر إجراء العملية. تحقق من حالة الطلب وصلاحيات الحساب.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _notice(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('إدارة التوصيل'),
      actions: [
        if (AlAniCodPage.enabled)
          IconButton(
            tooltip: 'تقارير التحصيل التجريبي',
            icon: const Icon(Icons.receipt_long),
            onPressed: () => Navigator.of(context).push<void>(
              MaterialPageRoute(builder: (_) => const AlAniCodPage(staff: true))),
          ),
        IconButton(onPressed: _reload,
        tooltip: 'تحديث', icon: const Icon(Icons.refresh))]),
    body: !AlAniDeliveryFeature.enabled
        ? const Center(child: Text(
            'إدارة المندوبين غير مفعّلة في هذا الإصدار.'))
        : FutureBuilder<_DeliveryOverview>(
            future: _overview,
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                if (snapshot.hasError) {
                  return const Center(child: Text(
                      'تعذّر فتح إدارة التوصيل. يلزم مالك المتجر أو الإدارة.'));
                }
                return const Center(child: CircularProgressIndicator());
              }
              final data = snapshot.data!;
              return RefreshIndicator(
                onRefresh: _reload,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(16),
                  children: [
                    const Text('التوصيل: ٥٬٠٠٠ دينار عراقي',
                      style: TextStyle(fontWeight: FontWeight.w900, fontSize: 20)),
                    const Text('الرسوم تُحسب عند الشراء على الخادم. '
                        'لا يتم إثبات تحصيل النقود تلقائياً.'),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: _saving ? null : _registerCourier,
                      icon: const Icon(Icons.person_add_alt_1),
                      label: const Text('اعتماد مندوب بحسابه')),
                    const SizedBox(height: 12),
                    const Text('المندوبون المعتمدون',
                      style: TextStyle(fontWeight: FontWeight.w800)),
                    if (data.couriers.isEmpty)
                      const ListTile(title: Text('لا يوجد مندوب معتمد بعد.')),
                    for (final courier in data.couriers)
                      Card(child: ListTile(
                        title: Text('حساب مندوب ${courier['courier_id']
                            .toString().substring(0, 8)}'),
                        subtitle: Text('طلبات قيد التوصيل: '
                            '${courier['active_jobs']}'),
                        trailing: Switch(
                          value: courier['enabled'] == true,
                          onChanged: _saving ? null : (enabled) => _write(
                            () => AlAniDeliveryService.setCourier(
                              courier['courier_id'].toString(), enabled),
                            enabled ? 'تم تفعيل المندوب.' : 'تم إيقاف المندوب.',
                          ),
                        ),
                      )),
                    const SizedBox(height: 18),
                    const Text('طلبات جاهزة للإرسال',
                        style: TextStyle(fontWeight: FontWeight.w800)),
                    if (data.ready.isEmpty)
                      const ListTile(title: Text('ماكو طلبات جاهزة حالياً.')),
                    for (final order in data.ready)
                      Card(child: ListTile(
                        title: Text('طلب ${order['id']
                            .toString().substring(0, 8)}'),
                        subtitle: Text('الإجمالي: ${order['total_iqd']} د.ع'),
                        trailing: FilledButton(
                          onPressed: _saving ? null :
                              () => _dispatch(order, data.couriers),
                          child: const Text('إرسال')),
                      )),
                    const SizedBox(height: 18),
                    const Text('تتبع الطلبات المرسلة',
                        style: TextStyle(fontWeight: FontWeight.w800)),
                    if (data.jobs.isEmpty)
                      const ListTile(title: Text('ماكو طلبات مرسلة حالياً.')),
                    for (final job in data.jobs)
                      Card(child: ListTile(
                        leading: Icon(job['status'] == 'delivered'
                            ? Icons.check_circle_outline
                            : Icons.delivery_dining),
                        title: Text('طلب ${job['order_id']
                            .toString().substring(0, 8)}'),
                        subtitle: Text(job['status'] == 'delivered'
                            ? 'تم التسليم برمز الزبون'
                            : job['picked_up_at'] == null
                                ? 'بانتظار استلام المندوب'
                                : 'استلمه المندوب وهو قيد التوصيل'),
                        trailing: Text('مندوب ${job['courier_id']
                            .toString().substring(0, 8)}'),
                        onTap: AlAniEvidence.enabled ? ()=>Navigator.of(context).push<void>(MaterialPageRoute(builder:(_)=>AlAniEvidencePage(kind:'delivery',id:job['order_id'].toString()))) : null,
                      )),
                  ],
                ),
              );
            },
          ),
  );
}

class _DeliveryOverview {
  _DeliveryOverview(this.couriers, this.ready, this.jobs);
  final List<Map<String, dynamic>> couriers;
  final List<Map<String, dynamic>> ready;
  final List<Map<String, dynamic>> jobs;
}

class AlAniCourierTasksPage extends StatefulWidget {
  const AlAniCourierTasksPage({super.key});
  @override
  State<AlAniCourierTasksPage> createState() => _AlAniCourierTasksPageState();
}

class _AlAniCourierTasksPageState extends State<AlAniCourierTasksPage> {
  late Future<List<Map<String, dynamic>>> _tasks;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _tasks = _fetch();
  }
  Future<List<Map<String, dynamic>>> _fetch() async {
    if (!AlAniDeliveryFeature.enabled) return [];
    return AlAniDeliveryService.myDeliveries();
  }
  Future<void> _reload() async {
    final next = _fetch();
    setState(() => _tasks = next);
    try { await next; } catch (_) { /* UI displays failure. */ }
  }
  void _notice(String message) => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(message)));

  Future<void> _pickup(String id) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await AlAniDeliveryService.pickup(id);
      if (mounted) {
        _notice('تم إثبات استلام المندوب للطلب من المتجر.');
        await _reload();
      }
    } catch (_) {
      if (mounted) _notice('تعذّر تسجيل الاستلام. تحقق من صلاحية المندوب.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _complete(String id) async {
    final pin = TextEditingController();
    final note = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('إثبات تسليم الطلب'),
        content: SingleChildScrollView(child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('اطلب رمز التسليم من شاشة الزبون بعد أن '
                'يتأكد من استلام المنتج. لا تطلب كلمة مرور حسابه.'),
            const SizedBox(height: 12),
            TextField(controller: pin, maxLength: 6,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'رمز تسليم الزبون (6 أرقام)',
                border: OutlineInputBorder())),
            TextField(controller: note, maxLength: 300,
              decoration: const InputDecoration(
                labelText: 'ملاحظة التسليم (اختيارية)',
                border: OutlineInputBorder())),
          ],
        )),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true),
              child: const Text('تحقق من الرمز')),
        ],
      ),
    );
    final code = pin.text.trim();
    final details = note.text.trim();
    pin.dispose();
    note.dispose();
    if (confirmed != true || !mounted) return;
    if (!RegExp(r'^[0-9]{6}$').hasMatch(code)) {
      _notice('يجب إدخال رمز مكوّن من 6 أرقام.');
      return;
    }
    setState(() => _busy = true);
    try {
      final result = await AlAniDeliveryService.complete(id, code, details);
      if (!mounted) return;
      const problems = <String, String>{
        'WRONG_CODE': 'الرمز غير صحيح. المحاولات محدودة.',
        'CODE_LOCKED': 'انتهت محاولات الرمز. اطلب رمزاً جديداً من الزبون.',
        'CODE_EXPIRED': 'انتهت صلاحية الرمز. اطلب رمزاً جديداً.',
        'CODE_NOT_ISSUED': 'الزبون لم ينشئ رمز التسليم بعد.',
      };
      if (result == 'delivered') {
        _notice('تم إثبات تسليم الطلب. التحصيل النقدي غير مثبت تلقائياً.');
        await _reload();
      } else {
        _notice(problems[result] ?? 'تعذّر تأكيد التسليم.');
      }
    } catch (_) {
      if (mounted) _notice('تعذّر تأكيد التسليم من الخادم.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('مهامي كمندوب'),
      actions: [
        if (AlAniCodPage.enabled)
          IconButton(
            tooltip: 'تحصيل النقد التجريبي',
            icon: const Icon(Icons.receipt_long),
            onPressed: () => Navigator.of(context).push<void>(
              MaterialPageRoute(builder: (_) => const AlAniCodPage(staff: false))),
          ),
        IconButton(onPressed: _reload,
        tooltip: 'تحديث', icon: const Icon(Icons.refresh))]),
    body: !AlAniDeliveryFeature.enabled
        ? const Center(child: Text('التوصيل التجريبي غير مفعّل.'))
        : FutureBuilder<List<Map<String, dynamic>>>(
            future: _tasks,
            builder: (context, snapshot) {
              if (snapshot.hasError) return const Center(
                child: Text('ما گدرنا نحمّل مهامك. تحقق من الحساب.'));
              if (!snapshot.hasData) return const Center(
                child: CircularProgressIndicator());
              final tasks = snapshot.data!;
              return RefreshIndicator(
                onRefresh: _reload,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(16),
                  children: [
                    const Text('طلباتك المعيّنة فقط',
                      style: TextStyle(fontSize: 21,
                          fontWeight: FontWeight.w900)),
                    const Text('يمكنك رؤية عنوان التوصيل فقط للطلبات '
                        'المسندة لحسابك. لا تظهر أرقام هواتف الزبائن.'),
                    const SizedBox(height: 12),
                    if (tasks.isEmpty) const ListTile(
                      title: Text('لا توجد مهام توصيل مسندة لك حالياً.')),
                    for (final task in tasks)
                      Card(child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text('طلب ${task['order_id']
                                .toString().substring(0, 8)}',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w900)),
                            Text('العنوان: ${task['delivery_address']}'),
                            Text('الإجمالي عند الاستلام: '
                                '${task['total_iqd']} د.ع'),
                            Text('أجرة التوصيل ضمن المجموع: '
                                '${task['delivery_fee_iqd']} د.ع'),
                            const SizedBox(height: 8),
                            if (AlAniCourierLocationPage.enabled && task['picked_up_at'] != null)
                              OutlinedButton.icon(
                                onPressed: _busy ? null : () => Navigator.of(context).push<void>(
                                  MaterialPageRoute(builder: (_) => AlAniCourierLocationPage(orderId:task['order_id'].toString()))),
                                icon: const Icon(Icons.location_on_outlined),
                                label: const Text('مشاركة موقع التوصيل'),
                              ),
                            if (AlAniEvidence.enabled && task['picked_up_at'] != null)
                              OutlinedButton.icon(onPressed:_busy?null:()=>Navigator.of(context).push<void>(MaterialPageRoute(builder:(_)=>AlAniEvidencePage(kind:'delivery',id:task['order_id'].toString(),allowUpload:true))),icon:const Icon(Icons.camera_alt_outlined),label:const Text('صورة التسليم الخاصة')),
                            task['picked_up_at'] == null
                                ? FilledButton.icon(
                                    onPressed: _busy ? null :
                                        () => _pickup(task['order_id'].toString()),
                                    icon: const Icon(Icons.inventory_2_outlined),
                                    label: const Text('استلمت الطلب من المتجر'),
                                  )
                                : FilledButton.icon(
                                    onPressed: _busy ? null :
                                        () => _complete(task['order_id'].toString()),
                                    icon: const Icon(Icons.verified_outlined),
                                    label: const Text('تأكيد تسليم برمز الزبون'),
                                  ),
                          ],
                        ),
                      )),
                  ],
                ),
              );
            },
          ),
  );
}
