import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'admin_api.dart';

const purple = Color(0xFF572B90);
const orange = Color(0xFFFF9B39);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AdminApi.initialize();
  runApp(const ShitreedAdminApp());
}

class ShitreedAdminApp extends StatelessWidget {
  const ShitreedAdminApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'شتريد — الإدارة',
    debugShowCheckedModeBanner: false,
    locale: const Locale('ar'),
    builder: (_, child) => Directionality(
      textDirection: TextDirection.rtl,
      child: child ?? const SizedBox.shrink(),
    ),
    theme: ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: purple),
      scaffoldBackgroundColor: const Color(0xFFF8F5FC),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFF28183E), foregroundColor: Colors.white),
    ),
    home: const AdminGate(),
  );
}

class AdminGate extends StatefulWidget {
  const AdminGate({super.key});
  @override
  State<AdminGate> createState() => _AdminGateState();
}

class _AdminGateState extends State<AdminGate> {
  StreamSubscription<AuthState>? _subscription;
  bool loading = true;
  String? role;
  String? error;

  @override
  void initState() {
    super.initState();
    if (AdminApi.configured) {
      _subscription = AdminApi.client.auth.onAuthStateChange.listen((_) {
        unawaited(checkAccess());
      });
      unawaited(checkAccess());
    } else {
      loading = false;
    }
  }

  Future<void> checkAccess() async {
    if (!mounted) return;
    setState(() { loading = true; error = null; });
    if (AdminApi.client.auth.currentUser == null) {
      if (mounted) setState(() { role = null; loading = false; });
      return;
    }
    try {
      final result = await AdminApi.currentRole();
      if (mounted) setState(() { role = result; loading = false; });
    } catch (_) {
      if (mounted) setState(() {
        role = null;
        loading = false;
        error = 'تعذر التحقق من صلاحية المدير. تحقق من اتصال الخادم والترحيل.';
      });
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!AdminApi.configured) {
      return const Scaffold(body: Center(child: Padding(
        padding: EdgeInsets.all(24),
        child: Text('يجب ربط APK بمشروع Supabase الخاص بشتريد '
            'باستخدام المفتاح العلني فقط.', textAlign: TextAlign.center),
      )));
    }
    if (loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (AdminApi.client.auth.currentUser == null) {
      return AdminLogin(onSuccess: checkAccess);
    }
    if (role == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('صلاحيات الإدارة')),
        body: Center(child: Column(
          mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.lock_outline, size: 60, color: purple),
            const SizedBox(height: 12),
            Padding(padding: const EdgeInsets.all(18),
              child: Text(error ?? 'هذا الحساب غير مفوض للإدارة.',
                textAlign: TextAlign.center)),
            TextButton(onPressed: checkAccess,
              child: const Text('إعادة التحقق')),
            TextButton(onPressed: () => AdminApi.client.auth.signOut(),
              child: const Text('تسجيل الخروج')),
          ],
        )),
      );
    }
    return AdminHome(role: role!);
  }
}

class AdminLogin extends StatefulWidget {
  final VoidCallback onSuccess;
  const AdminLogin({super.key, required this.onSuccess});
  @override
  State<AdminLogin> createState() => _AdminLoginState();
}

class _AdminLoginState extends State<AdminLogin> {
  final email = TextEditingController();
  final password = TextEditingController();
  bool busy = false;
  String? message;

  @override
  void dispose() {
    email.dispose();
    password.dispose();
    super.dispose();
  }

  Future<void> login() async {
    if (email.text.trim().isEmpty || password.text.isEmpty || busy) return;
    setState(() { busy = true; message = null; });
    try {
      await AdminApi.client.auth.signInWithPassword(
        email: email.text.trim(), password: password.text,
      );
      if (mounted) widget.onSuccess();
    } on AuthException catch (e) {
      if (mounted) setState(() => message = e.message);
    } catch (_) {
      if (mounted) setState(() => message = 'تعذر الاتصال بالخادم.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(child: Center(child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 450),
      child: ListView(shrinkWrap: true, padding: const EdgeInsets.all(25),
        children: [
          Container(
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF28183E), purple]),
              borderRadius: BorderRadius.circular(22)),
            child: const Column(children: [
              Icon(Icons.admin_panel_settings_rounded,
                size: 72, color: orange),
              Text('شتريد | الإدارة', style: TextStyle(
                fontSize: 27, color: Colors.white,
                fontWeight: FontWeight.bold)),
              Text('تحكم آمن في متاجر وطلبات شتريد',
                style: TextStyle(color: Colors.white70)),
            ]),
          ),
          const SizedBox(height: 25),
          TextField(
            controller: email,
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.email],
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              labelText: 'البريد الإلكتروني'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: password,
            obscureText: true,
            decoration: const InputDecoration(
              border: OutlineInputBorder(), labelText: 'كلمة المرور'),
          ),
          if (message != null) Padding(
            padding: const EdgeInsets.all(12),
            child: Text(message!, style: const TextStyle(color: Colors.red)),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(onPressed: busy ? null : login,
            icon: const Icon(Icons.login),
            label: Text(busy ? 'جارٍ الدخول...' : 'تسجيل دخول المدير')),
          const SizedBox(height: 10),
          const Text('لا يمكن إنشاء حساب مدير من داخل التطبيق. '
            'تمنح الصلاحيات من المدير العام فقط.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.black54, fontSize: 12)),
        ],
      ),
    ))),
  );
}

class AdminHome extends StatefulWidget {
  final String role;
  const AdminHome({super.key, required this.role});
  @override
  State<AdminHome> createState() => _AdminHomeState();
}

class _AdminHomeState extends State<AdminHome> {
  String section = 'overview';
  int offset = 0;
  bool loading = true;
  bool working = false;
  String? error;
  Map<String, dynamic> summary = {};
  List<Map<String, dynamic>> items = [];

  @override
  void initState() {
    super.initState();
    unawaited(load());
  }

  Future<void> load() async {
    if (!mounted) return;
    setState(() { loading = true; error = null; });
    try {
      if (section == 'overview') {
        final result = await AdminApi.dashboard();
        if (mounted) setState(() => summary = result);
      } else {
        final result = await AdminApi.rows(section, offset: offset);
        if (mounted) setState(() => items = result);
      }
    } catch (_) {
      if (mounted) setState(() => error =
          'تعذر تحميل البيانات. راجع اتصال Supabase وصلاحيات الإدارة.');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  void changeSection(String next) {
    if (next == section) return;
    setState(() { section = next; offset = 0; items = []; });
    unawaited(load());
  }

  void notify(String value) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(value)));
    }
  }

  String short(Object? value) {
    final s = value?.toString() ?? '';
    return s.length > 8 ? s.substring(0, 8) : s;
  }

  String title(Map<String, dynamic> row) {
    if (section == 'stores' || section == 'products') {
      return row['name']?.toString() ?? 'غير معروف';
    }
    if (section == 'orders') return 'الطلب ' + short(row['id']);
    if (section == 'customers') {
      return row['display_name']?.toString() ?? 'مستخدم';
    }
    if (section == 'staff') {
      return AdminAccess.roleLabels[row['staff_role']] ?? 'موظف';
    }
    return (row['section'] ?? '') .toString() +
        ' — ' + (row['action'] ?? '').toString();
  }

  String details(Map<String, dynamic> row) {
    switch (section) {
      case 'stores':
        return 'المنطقة: ' + (row['area'] ?? '').toString() +
            ' | التصنيف: ' + (row['category'] ?? '').toString() +
            '\nالحالة: ' + (row['status'] ?? '').toString() +
            '\nالعنوان: ' + (row['address'] ?? '').toString() +
            '\nالهاتف: ' + (row['phone'] ?? '-').toString();
      case 'products':
        return 'السعر: ' + (row['price_iqd'] ?? '').toString() +
            ' د.ع | المخزون: ' + (row['stock_quantity'] ?? '').toString() +
            ' | ظاهر: ' + (row['is_active'] == true ? 'نعم' : 'لا') +
            '\nمعرّف المتجر: ' + short(row['store_id']);
      case 'orders':
        return 'الحالة: ' + (row['status'] ?? '').toString() +
            ' | المبلغ: ' + (row['total_iqd'] ?? '').toString() +
            ' د.ع\nالهاتف: ' + (row['phone'] ?? '').toString() +
            '\nالعنوان: ' + (row['delivery_address'] ?? '').toString();
      case 'customers':
        return 'معرّف الحساب: ' + (row['id'] ?? '').toString() +
            '\nتاريخ التسجيل: ' + (row['created_at'] ?? '').toString();
      case 'staff':
        return 'المعرف: ' + (row['user_id'] ?? '').toString() +
            '\nالحالة: ' + (row['enabled'] == true ? 'نشط' : 'معطل');
      case 'audit':
        return 'العملية: ' + (row['action'] ?? '').toString() +
            '\nالسابق: ' + (row['before_state'] ?? '-').toString() +
            ' | الجديد: ' + (row['after_state'] ?? '-').toString() +
            '\nالسبب: ' + (row['reason'] ?? '').toString() +
            '\nالمدير: ' + short(row['actor_id']) +
            ' | الوقت: ' + (row['created_at'] ?? '').toString();
      default: return '';
    }
  }

  Map<String, String> actions(Map<String, dynamic> row) {
    if (!AdminAccess.canChange(widget.role, section)) return {};
    final state = row['status']?.toString();
    if (section == 'stores') {
      if (state == 'pending') return {'approve': 'اعتماد المتجر'};
      if (state == 'approved') return {'suspend': 'إيقاف المتجر'};
      if (state == 'suspended') return {'reopen': 'إعادة للمراجعة'};
    }
    if (section == 'products') {
      return row['is_active'] == true
          ? {'disable': 'إخفاء المنتج'} : {'enable': 'نشر المنتج'};
    }
    if (section == 'orders') {
      if (state == 'placed') return {
        'accept': 'قبول', 'reject': 'رفض', 'cancel': 'إلغاء'};
      if (state == 'accepted') return {
        'prepare': 'بدء التحضير', 'cancel': 'إلغاء'};
      if (state == 'preparing') return {
        'ready': 'جاهز للتسليم', 'cancel': 'إلغاء'};
    }
    return {};
  }

  Future<String?> askReason(String action) async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, update) =>
        AlertDialog(
          title: Text(action),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('هذا الإجراء يؤثر على سجلات حقيقية. '
              'تحقق من التفاصيل قبل المتابعة.'),
            const SizedBox(height: 10),
            TextField(
              controller: controller, maxLength: 1000, maxLines: 3,
              onChanged: (_) => update(() {}),
              decoration: const InputDecoration(
                labelText: 'السبب (12 حرفاً على الأقل)',
                border: OutlineInputBorder()),
            ),
          ]),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('رجوع')),
            FilledButton(
              onPressed: controller.text.trim().length < 12
                  ? null : () => Navigator.pop(ctx, controller.text.trim()),
              child: const Text('تأكيد')),
          ],
        )),
    );
    controller.dispose();
    return result;
  }

  Future<void> runAction(
    Map<String, dynamic> row, String action, String label) async {
    if (working) return;
    final reason = await askReason(label);
    if (reason == null || !mounted) return;
    setState(() => working = true);
    try {
      await AdminApi.action(section, row['id'].toString(), action, reason);
      notify('تم تنفيذ العملية وحفظها في السجل');
      await load();
    } catch (e) {
      notify('فشل التنفيذ: ' + e.toString());
    } finally {
      if (mounted) setState(() => working = false);
    }
  }

  Future<void> editStaff([Map<String, dynamic>? current]) async {
    final id = TextEditingController(
      text: current?['user_id']?.toString() ?? '');
    final reason = TextEditingController();
    final form = GlobalKey<FormState>();
    String role = current?['staff_role']?.toString() ?? 'viewer';
    bool enabled = current?['enabled'] != false;
    bool busy = false;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, redraw) =>
        AlertDialog(
          title: Text(current == null ? 'منح دور لموظف' : 'تعديل دور موظف'),
          content: SizedBox(width: 400,
            child: SingleChildScrollView(child: Form(key: form,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                TextFormField(
                  controller: id, readOnly: current != null,
                  decoration: const InputDecoration(
                    labelText: 'معرف المستخدم UUID'),
                  validator: (v) => AdminAccess.isUuid((v ?? '').trim())
                      ? null : 'معرّف المستخدم غير صحيح'),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: role,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'الدور'),
                  items: AdminAccess.roleLabels.entries
                    .where((e) => e.key != 'super_admin')
                    .map((e) => DropdownMenuItem<String>(
                      value: e.key, child: Text(e.value))).toList(),
                  onChanged: busy ? null : (v) {
                    if (v != null) redraw(() => role = v);
                  }),
                CheckboxListTile(
                  title: const Text('الموظف مفعل'),
                  value: enabled, contentPadding: EdgeInsets.zero,
                  onChanged: busy ? null : (v) =>
                      redraw(() => enabled = v ?? false)),
                TextFormField(
                  controller: reason, maxLines: 2, maxLength: 1000,
                  decoration: const InputDecoration(labelText: 'سبب التغيير'),
                  validator: (v) => (v ?? '').trim().length >= 12
                      ? null : 'اكتب سبباً من 12 حرفاً'),
              ])))),
          actions: [
            TextButton(onPressed: busy ? null : () => Navigator.pop(ctx),
              child: const Text('إلغاء')),
            FilledButton(
              onPressed: busy ? null : () async {
                if (!form.currentState!.validate()) return;
                redraw(() => busy = true);
                try {
                  await AdminApi.setStaff(
                    userId: id.text.trim(), role: role,
                    enabled: enabled, reason: reason.text.trim());
                  if (!ctx.mounted) return;
                  Navigator.pop(ctx);
                  notify('تم حفظ صلاحية الموظف');
                  await load();
                } catch (e) {
                  if (ctx.mounted) {
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      SnackBar(content: Text('تعذر الحفظ: ' + e.toString())));
                    redraw(() => busy = false);
                  }
                }
              },
              child: Text(busy ? 'جارٍ الحفظ...' : 'حفظ')),
          ],
        )),
    );
    id.dispose();
    reason.dispose();
  }

  Widget overviewBody() {
    final widgets = <(String, String, IconData)>[
      ('جميع المتاجر', 'stores', Icons.storefront),
      ('بانتظار الاعتماد', 'pending_stores', Icons.pending_actions),
      ('المتاجر المعتمدة', 'approved_stores', Icons.verified),
      ('المنتجات', 'products', Icons.inventory_2_outlined),
      ('المنتجات المنشورة', 'active_products', Icons.visibility_outlined),
      ('جميع الطلبات', 'orders', Icons.receipt_long),
      ('الطلبات المفتوحة', 'open_orders', Icons.timer_outlined),
      ('الزبائن', 'customers', Icons.people_outline),
      ('قيمة الطلبات غير الملغاة (د.ع)',
        'order_value_iqd', Icons.paid_outlined),
    ];
    return ListView(padding: const EdgeInsets.all(14), children: [
      Text('نظرة عامة', style: Theme.of(context).textTheme.headlineSmall),
      const Text('قيمة الطلبات ليست أرباحاً أو مدفوعات محصلة.',
        style: TextStyle(color: Colors.black54)),
      const SizedBox(height: 12),
      LayoutBuilder(builder: (ctx, constraints) {
        final width = constraints.maxWidth < 600
            ? (constraints.maxWidth - 12) / 2 : 210.0;
        return Wrap(spacing: 8, runSpacing: 8,
          children: widgets.map((record) => SizedBox(
            width: width, child: Card(child: Padding(
              padding: const EdgeInsets.all(15),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(record.$3, color: purple),
                  const SizedBox(height: 8),
                  Text((summary[record.$2] ?? '—').toString(),
                    style: const TextStyle(
                      fontSize: 23, fontWeight: FontWeight.bold)),
                  Text(record.$1),
                ]),
            )))).toList());
      }),
    ]);
  }

  Widget itemsBody() {
    if (items.isEmpty) {
      return const Center(child: Text('لا توجد سجلات بهذه الصفحة.'));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final row = items[index];
        return Card(child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title(row), style: const TextStyle(
                color: purple, fontSize: 17, fontWeight: FontWeight.bold)),
              const SizedBox(height: 7),
              SelectableText(details(row)),
              if (actions(row).isNotEmpty) Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Wrap(spacing: 8, runSpacing: 5,
                  children: actions(row).entries.map((a) =>
                    OutlinedButton(
                      onPressed: working
                        ? null : () => runAction(row, a.key, a.value),
                      child: Text(a.value))).toList())),
              if (section == 'staff' && widget.role == 'super_admin')
                TextButton.icon(
                  onPressed: () => editStaff(row),
                  icon: const Icon(Icons.manage_accounts),
                  label: const Text('تعديل الصلاحية')),
            ]),
        ));
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final sections = AdminAccess.sectionsFor(widget.role);
    return Scaffold(
      appBar: AppBar(
        title: const Text('شتريد | لوحة الإدارة'),
        actions: [
          IconButton(onPressed: loading ? null : load,
            tooltip: 'تحديث', icon: const Icon(Icons.refresh)),
          IconButton(onPressed: () => AdminApi.client.auth.signOut(),
            tooltip: 'تسجيل الخروج', icon: const Icon(Icons.logout)),
        ]),
      body: SafeArea(child: Center(child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1100),
        child: Column(children: [
          Container(width: double.infinity,
            padding: const EdgeInsets.all(12),
            color: const Color(0xFFF1E8FA),
            child: Text('الصلاحية: ' +
              (AdminAccess.roleLabels[widget.role] ?? widget.role))),
          SizedBox(height: 55, child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
            scrollDirection: Axis.horizontal,
            children: sections.map((key) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: ChoiceChip(
                label: Text(AdminAccess.sectionLabels[key] ?? key),
                selected: key == section,
                selectedColor: const Color(0xFFFFE0B6),
                onSelected: (_) => changeSection(key)))).toList())),
          if (section == 'staff' && widget.role == 'super_admin')
            Align(alignment: Alignment.centerRight,
              child: Padding(padding: const EdgeInsets.all(8),
                child: FilledButton.icon(
                  onPressed: () => editStaff(),
                  icon: const Icon(Icons.person_add),
                  label: const Text('إضافة موظف')))),
          Expanded(child: loading
            ? const Center(child: CircularProgressIndicator())
            : error != null
              ? Center(child: Column(
                  mainAxisSize: MainAxisSize.min, children: [
                    Text(error!, textAlign: TextAlign.center),
                    TextButton(onPressed: load,
                      child: const Text('إعادة المحاولة')),
                  ]))
              : section == 'overview' ? overviewBody() : itemsBody()),
          if (section != 'overview') Row(children: [
            const SizedBox(width: 8),
            OutlinedButton(onPressed: loading || offset == 0 ? null : () {
              setState(() => offset -= 30);
              unawaited(load());
            }, child: const Text('السابق')),
            const SizedBox(width: 12),
            Text('صفحة ' + ((offset ~/ 30) + 1).toString()),
            const SizedBox(width: 12),
            OutlinedButton(
              onPressed: loading || items.length < 30 ? null : () {
                setState(() => offset += 30);
                unawaited(load());
              }, child: const Text('التالي')),
          ]),
        ]),
      ))),
    );
  }
}
