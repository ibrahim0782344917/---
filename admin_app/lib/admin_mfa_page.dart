import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'admin_api.dart';

abstract final class AdminMfaPolicy {
  static const requiredForProduction = bool.fromEnvironment('ALANI_ADMIN_MFA_REQUIRED');
  static const productionUrl = 'https://ltwncrewggdrjevakwpb.supabase.co';
  static bool needsChallenge({required bool enabled, required String url,
    required bool aal2}) => enabled && url == productionUrl && !aal2;
  static bool get requiresSetupOrChallenge => needsChallenge(
    enabled: requiredForProduction,
    url: AdminApi.url,
    aal2: AdminApi.client.auth.mfa.getAuthenticatorAssuranceLevel().currentLevel ==
      AuthenticatorAssuranceLevels.aal2,
  );
  static bool validCode(String value) => RegExp(r'^[0-9]{6}$').hasMatch(value);
}

/// Uses only the signed-in user's Supabase Auth session. No service-role key.
class AdminMfaPage extends StatefulWidget {
  const AdminMfaPage({super.key, required this.onVerified});
  final VoidCallback onVerified;
  @override
  State<AdminMfaPage> createState() => _AdminMfaPageState();
}

class _AdminMfaPageState extends State<AdminMfaPage> {
  final _code = TextEditingController();
  late final String _actor;
  bool _busy = true;
  bool _loaded = false;
  String? _message;
  String? _secret;
  String? _pendingId;
  List<String> _verified = [];
  List<String> _unfinished = [];
  String? _selectedId;
  GoTrueClient get _auth => AdminApi.client.auth;
  bool get _sameActor => _auth.currentUser?.id == _actor;

  @override
  void initState() {
    super.initState();
    _actor = _auth.currentUser!.id;
    _load();
  }

  @override
  void dispose() {
    _secret = null;
    _code.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (!mounted || !_sameActor) return;
    setState(() { _busy = true; _message = null; _loaded = false; });
    try {
      final response = await _auth.getUser();
      final user = response.user;
      if (!mounted || !_sameActor || user?.id != _actor) return;
      final factors = user?.factors ?? [];
      final verified = factors.where((f) => f.factorType == FactorType.totp &&
        f.status == FactorStatus.verified).map((f) => f.id).toList();
      final unfinished = factors.where((f) => f.factorType == FactorType.totp &&
        f.status == FactorStatus.unverified).map((f) => f.id).toList();
      setState(() {
        _verified = verified; _unfinished = unfinished;
        _selectedId = verified.isEmpty ? null : verified.first;
        _loaded = true;
      });
    } catch (_) {
      if (mounted) setState(() => _message = 'تعذر قراءة إعدادات الأمان. أعد المحاولة.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _start() async {
    if (_busy || !_loaded || !_sameActor || _verified.isNotEmpty ||
        _unfinished.isNotEmpty || _pendingId != null) return;
    setState(() { _busy = true; _message = null; });
    try {
      final result = await _auth.mfa.enroll(factorType: FactorType.totp,
        issuer: 'AlAni Admin Production');
      if (!mounted || !_sameActor) return;
      final secret = result.totp?.secret;
      if (secret == null || secret.isEmpty) throw StateError('SETUP_FAILED');
      setState(() { _secret = secret; _pendingId = result.id; _selectedId = result.id; });
    } catch (_) {
      if (mounted) setState(() { _message = 'تعذر إنشاء مفتاح الإعداد. حدّث الشاشة قبل المحاولة مجدداً.'; _loaded = false; });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _cancelUnfinished() async {
    if (_busy || !_sameActor) return;
    final ids = {..._unfinished, if (_pendingId != null) _pendingId!};
    if (ids.isEmpty) return;
    final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('إلغاء الإعداد غير المكتمل'),
      content: const Text('سيُزال عامل التحقق غير المؤكد فقط. لا تُحذف العوامل المؤكدة أو الحساب.'),
      actions: [
        TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('رجوع')),
        FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('إلغاء الإعداد')),
      ],
    ));
    if (ok != true || !mounted || !_sameActor || _busy) return;
    setState(() { _busy = true; _message = null; });
    try {
      final user = (await _auth.getUser()).user;
      if (!_sameActor || user?.id != _actor) return;
      for (final factor in user?.factors ?? <Factor>[]) {
        if (ids.contains(factor.id) && factor.factorType == FactorType.totp &&
            factor.status == FactorStatus.unverified) {
          await _auth.mfa.unenroll(factor.id);
        }
      }
      if (!mounted) return;
      setState(() { _secret = null; _pendingId = null; _code.clear(); });
      await _load();
    } catch (_) {
      if (mounted) setState(() => _message = 'تعذر إلغاء الإعداد. أعد المحاولة.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _verify() async {
    final id = _selectedId;
    final value = _code.text.trim();
    if (_busy || !_sameActor || id == null || !AdminMfaPolicy.validCode(value)) return;
    setState(() { _busy = true; _message = null; });
    try {
      await _auth.mfa.challengeAndVerify(factorId: id, code: value);
      if (!mounted || !_sameActor) return;
      final level = _auth.mfa.getAuthenticatorAssuranceLevel().currentLevel;
      if (level != AuthenticatorAssuranceLevels.aal2) throw StateError('AAL2_REQUIRED');
      _code.clear();
      setState(() { _secret = null; _pendingId = null; });
      widget.onVerified();
    } catch (_) {
      if (mounted) {
        _code.clear();
        setState(() => _message = 'لم ينجح التحقق. تأكد من الوقت التلقائي للهاتف وأدخل الرمز الحالي.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('التحقق بخطوتين — الإدارة')),
    body: SafeArea(child: ListView(padding: const EdgeInsets.all(24), children: [
      const Icon(Icons.security, size: 58),
      const SizedBox(height: 12),
      const Text('حماية المدير العام', style: TextStyle(fontSize: 23,fontWeight: FontWeight.bold)),
      const Text('هذه الشاشة متصلة بالإنتاج. يُحفظ عامل التحقق في حسابك لدى Supabase.'),
      if (_busy) const LinearProgressIndicator(),
      if (_message != null) Padding(padding: const EdgeInsets.symmetric(vertical: 12),
        child: Text(_message!,style:TextStyle(color:Theme.of(context).colorScheme.error))),
      if (!_loaded && !_busy) OutlinedButton(onPressed:_load,child:const Text('إعادة المحاولة')),
      if (_loaded && _verified.isEmpty && _pendingId == null && _unfinished.isEmpty)
        FilledButton(onPressed:_busy?null:_start,child:const Text('إنشاء مفتاح Google Authenticator')),
      if (_secret != null) ...[
        const SizedBox(height: 16),
        const Text('افتح Google Authenticator ثم + ثم إدخال مفتاح إعداد. الاسم: العاني — الإدارة. النوع: حسب الوقت.'),
        const Text('اكتب المفتاح التالي داخل Authenticator فقط. لا ترسله ولا تلتقط صورة له.'),
        Card(child: Padding(padding:const EdgeInsets.all(12),
          child: SelectableText(_secret!,textDirection:TextDirection.ltr,
            style:const TextStyle(fontSize:18,fontWeight:FontWeight.bold)))),
      ],
      if (_verified.length > 1) DropdownButton<String>(
        value:_selectedId,
        items:[for(var i=0;i<_verified.length;i++) DropdownMenuItem(
          value:_verified[i],child:Text('جهاز التحقق ${i+1}'))],
        onChanged:_busy?null:(v)=>setState(()=>_selectedId=v)),
      if (_selectedId != null) ...[
        const SizedBox(height: 16),
        const Text('أدخل رمز Google Authenticator الحالي المكوّن من 6 أرقام.'),
        TextField(controller:_code,keyboardType:TextInputType.number,
          obscureText:true,autocorrect:false,enableSuggestions:false,
          textDirection:TextDirection.ltr,maxLength:6,
          inputFormatters:[FilteringTextInputFormatter.digitsOnly],
          decoration:const InputDecoration(labelText:'رمز التحقق',border:OutlineInputBorder()),
          enabled:!_busy,onChanged:(_)=>setState((){})),
        FilledButton(onPressed:_busy||!AdminMfaPolicy.validCode(_code.text)?null:_verify,
          child:const Text('تحقق ودخول الإدارة')),
      ],
      if (_unfinished.isNotEmpty || _pendingId != null)
        OutlinedButton(onPressed:_busy?null:_cancelUnfinished,child:const Text('إلغاء الإعداد غير المكتمل')),
      const SizedBox(height: 12),
      TextButton(onPressed:_busy?null:() async { await _auth.signOut(); },
        child:const Text('تسجيل الخروج')),
      const Text('قد يؤدي تأكيد عامل جديد إلى إنهاء جلسات حساب الإدارة الأخرى. احتفظ بإمكانية الوصول إلى Authenticator.'),
    ])),
  );
}
