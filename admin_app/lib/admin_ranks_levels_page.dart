import 'package:flutter/material.dart';
import 'admin_api.dart';

const _navy = Color(0xFF192A43);
const _blue = Color(0xFF416FC4);

/// Admin-only controls. Every write is re-authorized by Supabase:
/// super_admin role + verified MFA AAL2 + immutable audit entry.
class AdminRanksAndLevelsPage extends StatefulWidget {
  const AdminRanksAndLevelsPage({super.key});
  @override
  State<AdminRanksAndLevelsPage> createState() => _AdminRanksAndLevelsPageState();
}

class _AdminRanksAndLevelsPageState extends State<AdminRanksAndLevelsPage> {
  final email = TextEditingController();
  final badgeName = TextEditingController(text: 'حساب موثّق');
  final badgeReason = TextEditingController();
  final levelReason = TextEditingController();
  final levelXp = TextEditingController();
  String? userId;
  String badgeKind = 'verified_identity';
  int selectedLevel = 25;
  bool grantBadge = true, busy = false, loading = true;
  String? error;
  List<Map<String, dynamic>> levels = [], rules = [];

  @override
  void initState() { super.initState(); reload(); }

  @override
  void dispose() {
    email.dispose(); badgeName.dispose(); badgeReason.dispose();
    levelReason.dispose(); levelXp.dispose();
    super.dispose();
  }

  Future<void> reload() async {
    if (mounted) setState(() { loading = true; error = null; });
    try {
      final a = await AdminApi.client.from('shitreed_level_thresholds')
          .select('level,min_xp').order('level');
      final b = await AdminApi.client.from('shitreed_xp_rules')
          .select('event_type,points,enabled').order('event_type');
      if (mounted) setState(() {
        levels = a; rules = b; loading = false;
        levelXp.text = (levels.firstWhere(
          (row) => row['level'] == selectedLevel,
          orElse: () => {'min_xp': 0})['min_xp']).toString();
      });
    } catch (_) {
      if (mounted) setState(() {
        loading = false;
        error = 'تعذر قراءة إعدادات مستويات شتريد. راجع الاتصال والصلاحيات.';
      });
    }
  }

  String safeError(Object e) {
    final s = e.toString();
    if (s.contains('MFA_REQUIRED')) {
      return 'هذه العملية تتطلب تفعيل المصادقة الثنائية MFA وتسجيل الدخول بمستوى AAL2.';
    }
    if (s.contains('PERMISSION_DENIED')) {
      return 'هذه العملية للمدير العام فقط.';
    }
    if (s.contains('LEVEL_THRESHOLD_OUT_OF_ORDER')) {
      return 'الحد الجديد يجب أن يكون أعلى من المستوى السابق وأقل من المستوى التالي.';
    }
    return 'تعذر الحفظ. راجع البيانات أو حاول لاحقاً.';
  }

  void notice(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)));
  }

  Future<void> findUser() async {
    if (busy || !email.text.contains('@')) {
      notice('اكتب بريد مستخدم مسجّل بشكل صحيح.');
      return;
    }
    setState(() => busy = true);
    try {
      final user = await AdminApi.findUser(email.text.trim());
      if (!mounted) return;
      setState(() => userId = user?['id']?.toString());
      notice(userId == null ? 'لم نجد هذا الحساب.' : 'تم تحديد الحساب بنجاح.');
    } catch (e) {
      notice(safeError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> setBadge() async {
    final id = userId;
    if (id == null || badgeName.text.trim().length < 2 ||
        badgeReason.text.trim().length < 12 || busy) {
      notice('ابحث عن المستخدم واكتب اسم اللقب وسبب قرار لا يقل عن 12 حرفاً.');
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context, builder: (ctx) => AlertDialog(
        title: Text(grantBadge ? 'تأكيد منح الشارة' : 'تأكيد سحب الشارة'),
        content: Text('سيُسجل اسم المدير وتاريخ العملية وسببها. '
            'اللقب لا يمنح صلاحيات إدارية.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
              child: const Text('رجوع')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true),
              child: const Text('تأكيد')),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => busy = true);
    try {
      final icon = badgeKind.startsWith('verified') ? '🔵' :
          badgeKind == 'king' ? '👑' : '⭐';
      await AdminApi.client.rpc('shitreed_admin_set_badge', params: {
        'p_user_id': id,
        'p_badge_kind': badgeKind,
        'p_label': badgeName.text.trim(),
        'p_icon': icon,
        'p_enabled': grantBadge,
        'p_reason': badgeReason.text.trim(),
      });
      notice(grantBadge ? 'تم منح اللقب وتسجيل القرار' : 'تم سحب اللقب');
    } catch (e) {
      notice(safeError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> setLevel() async {
    final value = int.tryParse(levelXp.text.trim());
    if (busy || selectedLevel < 2 || value == null ||
        levelReason.text.trim().length < 12) {
      notice('اكتب عتبة XP صحيحة وسبب التغيير من 12 حرفاً على الأقل.');
      return;
    }
    setState(() => busy = true);
    try {
      await AdminApi.client.rpc('shitreed_admin_set_level_threshold', params: {
        'p_level': selectedLevel,
        'p_min_xp': value,
        'p_reason': levelReason.text.trim(),
      });
      notice('تم تعديل عتبة المستوى، وستظهر للمستخدمين بعد التحديث.');
      await reload();
    } catch (e) {
      notice(safeError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> editRule(Map<String, dynamic> row) async {
    final points = TextEditingController(text: row['points'].toString());
    final reason = TextEditingController();
    bool enabled = row['enabled'] == true;
    try {
      final ok = await showDialog<bool>(
        context: context, builder: (ctx) => StatefulBuilder(
          builder: (ctx, redraw) => AlertDialog(
            title: Text('قاعدة ' + (row['event_type'] ?? '').toString()),
            content: SingleChildScrollView(child: Column(
              mainAxisSize: MainAxisSize.min, children: [
                TextField(controller: points,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'قيمة XP (0–1000)')),
                SwitchListTile(
                  title: const Text('تفعيل القاعدة'),
                  value: enabled,
                  onChanged: (value) => redraw(() => enabled = value)),
                TextField(controller: reason, minLines: 2, maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'سبب التعديل (12 حرفاً على الأقل)')),
                const Text('تفعيل القاعدة لا يمنح النقاط تلقائياً؛ '
                  'يجب التحقق من حدث الشراء أو البيع على الخادم أولاً.',
                  style: TextStyle(fontSize: 12)),
              ])),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('رجوع')),
              FilledButton(onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('اعتماد')),
            ],
          ),
        ),
      );
      if (ok != true || busy) return;
      final amount = int.tryParse(points.text.trim());
      if (amount == null || amount < 0 || amount > 1000 ||
          reason.text.trim().length < 12) {
        notice('راجع قيمة XP واكتب سبباً كافياً.');
        return;
      }
      setState(() => busy = true);
      try {
        await AdminApi.client.rpc('shitreed_admin_set_xp_rule', params: {
          'p_event_type': row['event_type'],
          'p_points': amount,
          'p_enabled': enabled,
          'p_reason': reason.text.trim(),
        });
        await reload();
        notice('تم حفظ قاعدة XP الجديدة.');
      } catch (e) {
        notice(safeError(e));
      } finally {
        if (mounted) setState(() => busy = false);
      }
    } finally {
      points.dispose(); reason.dispose();
    }
  }

  Widget panel(Widget body) => Card(
    color: Colors.white,
    margin: const EdgeInsets.only(bottom: 15),
    child: Padding(padding: const EdgeInsets.all(17), child: body),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('الرتب والمستويات والتوثيق'),
      backgroundColor: _navy),
    body: loading ? const Center(child: CircularProgressIndicator())
        : error != null ? Center(child: Text(error!))
        : ListView(padding: const EdgeInsets.all(16), children: [
            const Text('صلاحية المدير العام فقط • عمليات موثقة بـMFA',
              style: TextStyle(color: _blue, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            panel(Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Text('منح وسحب الألقاب والتوثيق',
                style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900)),
              TextField(controller: email,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: 'بريد المستخدم')),
              const SizedBox(height: 7),
              OutlinedButton.icon(onPressed: busy ? null : findUser,
                icon: const Icon(Icons.search),
                label: const Text('ابحث عن الحساب')),
              if (userId != null) const Text('✓ تم تحديد الحساب',
                style: TextStyle(color: _blue)),
              DropdownButtonFormField<String>(
                value: badgeKind,
                decoration: const InputDecoration(labelText: 'نوع الشارة'),
                items: const [
                  DropdownMenuItem(value: 'verified_identity',
                    child: Text('توثيق هوية 🔵')),
                  DropdownMenuItem(value: 'verified_merchant',
                    child: Text('توثيق تاجر 🔵')),
                  DropdownMenuItem(value: 'gold', child: Text('عضو ذهبي ⭐')),
                  DropdownMenuItem(value: 'king', child: Text('ملك شتريد 👑')),
                  DropdownMenuItem(value: 'merchant_pro',
                    child: Text('تاجر محترف 🏆')),
                  DropdownMenuItem(value: 'custom',
                    child: Text('لقب خاص ✨')),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => badgeKind = value);
                },
              ),
              TextField(controller: badgeName, maxLength: 80,
                decoration: const InputDecoration(labelText: 'اسم اللقب')),
              TextField(controller: badgeReason, maxLength: 500, maxLines: 2,
                decoration: const InputDecoration(labelText: 'سبب القرار')),
              SwitchListTile(title: const Text('منح / تفعيل الشارة'),
                subtitle: const Text('أوقفها لسحب الشارة الحالية'),
                value: grantBadge,
                onChanged: (v) => setState(() => grantBadge = v)),
              FilledButton.icon(onPressed: busy ? null : setBadge,
                icon: const Icon(Icons.verified_user),
                label: const Text('اعتماد قرار الشارة')),
            ])),
            panel(Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Text('إدارة عتبات المستويات',
                style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900)),
              DropdownButtonFormField<int>(
                value: selectedLevel,
                decoration: const InputDecoration(labelText: 'المستوى'),
                items: [
                  for (var n = 2; n <= 100; n++)
                    DropdownMenuItem(value: n, child: Text('Level ' + n.toString()))
                ],
                onChanged: (value) {
                  if (value == null) return;
                  setState(() {
                    selectedLevel = value;
                    levelXp.text = (levels.firstWhere(
                      (item) => item['level'] == value,
                      orElse: () => {'min_xp': 0})['min_xp']).toString();
                  });
                },
              ),
              TextField(controller: levelXp,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'الحد الأدنى XP')),
              TextField(controller: levelReason, maxLength: 500,
                decoration: const InputDecoration(labelText: 'سبب التعديل')),
              const SizedBox(height: 8),
              FilledButton.icon(onPressed: busy ? null : setLevel,
                icon: const Icon(Icons.stairs),
                label: const Text('حفظ المستوى')),
              const Text('يجب أن تكون كل عتبة أعلى من السابقة وأقل من التالية.',
                style: TextStyle(fontSize: 12, color: Colors.black54)),
            ])),
            panel(Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Text('قواعد كسب XP',
                style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900)),
              for (final rule in rules) ListTile(
                leading: Icon(rule['enabled'] == true
                  ? Icons.check_circle : Icons.pause_circle_outline,
                  color: rule['enabled'] == true ? Colors.green : Colors.grey),
                title: Text((rule['event_type'] ?? '').toString()),
                subtitle: Text((rule['points'] ?? 0).toString() + ' XP'),
                trailing: const Icon(Icons.edit_outlined),
                onTap: () => editRule(rule),
              ),
            ])),
            const SizedBox(height: 14),
            const Text('التوثيق ليس ضمان جودة. منح نقاط البيع والشراء لا '
                'يبدأ حتى تكتمل إثباتات التسليم والتحصيل لمنع الاحتيال.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.black54)),
          ]),
  );
}
