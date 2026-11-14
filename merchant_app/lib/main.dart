import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shitreed_merchant/backend/marketplace_backend.dart';
import 'package:shitreed_merchant/navigation/merchant_shell.dart';
import 'package:shitreed_merchant/account/merchant_legal_pages.dart';
import 'package:shitreed_merchant/shared/merchant_widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await MarketplaceBackend.initialize();
  runApp(const ShitreedMerchantApp());
}

class ShitreedMerchantApp extends StatelessWidget {
  const ShitreedMerchantApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'شتريد تاجر',
    debugShowCheckedModeBanner: false,
    locale: const Locale('ar'),
    builder: (context, child) => Directionality(
      textDirection: TextDirection.rtl,
      child: child ?? const SizedBox.shrink(),
    ),
    theme: ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: merchantPurple),
      scaffoldBackgroundColor: merchantCanvas,
      appBarTheme: const AppBarTheme(
        backgroundColor: merchantDark, foregroundColor: Colors.white),
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
      ),
    ),
    home: const MerchantAuthGate(),
  );
}

class MerchantAuthGate extends StatefulWidget {
  const MerchantAuthGate({super.key});

  @override
  State<MerchantAuthGate> createState() => _MerchantAuthGateState();
}

class _MerchantAuthGateState extends State<MerchantAuthGate> {
  StreamSubscription<AuthState>? _authSubscription;
  bool _signedIn = MarketplaceBackend.currentUser != null;

  @override
  void initState() {
    super.initState();
    if (MarketplaceBackend.configured) {
      _authSubscription = Supabase.instance.client.auth.onAuthStateChange
          .listen((event) {
        if (!mounted) return;
        setState(() => _signedIn =
          Supabase.instance.client.auth.currentUser != null);
      });
    }
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!MarketplaceBackend.configured) {
      return const Scaffold(body: SafeArea(
        child: Center(child: Padding(
          padding: EdgeInsets.all(28),
          child: Text(
            'تطبيق شتريد تاجر يحتاج اتصال Supabase. '
            'استخدم APK المبني عبر GitHub Actions مع إعدادات شتريد.',
            textAlign: TextAlign.center,
          ),
        )),
      ));
    }
    return _signedIn
        ? const MerchantShellPage()
        : MerchantLoginPage(onSuccess: () {
            if (mounted) setState(() => _signedIn = true);
          });
  }
}

class MerchantLoginPage extends StatefulWidget {
  final VoidCallback onSuccess;
  const MerchantLoginPage({super.key, required this.onSuccess});

  @override
  State<MerchantLoginPage> createState() => _MerchantLoginPageState();
}

class _MerchantLoginPageState extends State<MerchantLoginPage> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _name = TextEditingController();
  bool _register = false;
  bool _busy = false;
  String? _message;
  bool _error = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || !_form.currentState!.validate()) return;
    setState(() { _busy = true; _message = null; _error = false; });
    try {
      final auth = Supabase.instance.client.auth;
      if (_register) {
        final result = await auth.signUp(
          email: _email.text.trim(),
          password: _password.text,
          data: {'display_name': _name.text.trim()},
        );
        if (!mounted) return;
        if (result.session != null) {
          widget.onSuccess();
        } else {
          setState(() {
            _message = 'تحقق من بريدك الإلكتروني لتأكيد الحساب، '
                'وبعدها ارجع وسجّل دخولك.';
          });
        }
      } else {
        final result = await auth.signInWithPassword(
          email: _email.text.trim(),
          password: _password.text,
        );
        if (!mounted) return;
        if (result.session != null) {
          widget.onSuccess();
        }
      }
    } on AuthException catch (error) {
      if (mounted) {
        setState(() {
          _error = true;
          _message = error.message;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = true;
          _message = 'تعذر الاتصال بخدمة شتريد. حاول مرة ثانية.';
        });
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(child: ListView(
      padding: const EdgeInsets.all(22),
      children: [
        Container(
          padding: const EdgeInsets.symmetric(vertical: 25, horizontal: 18),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [merchantDark, merchantPurple]),
            borderRadius: BorderRadius.circular(24),
          ),
          child: const Column(children: [
            Icon(Icons.storefront_rounded, size: 79, color: merchantOrange),
            SizedBox(height: 8),
            Text('شتريد تاجر', style: TextStyle(
              color: Colors.white, fontSize: 29,
              fontWeight: FontWeight.w900,
            )),
            SizedBox(height: 6),
            Text('كل متجرك ومبيعاتك بين إيديك',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70)),
          ]),
        ),
        const SizedBox(height: 27),
        Text(_register ? 'افتح حساب تاجر' : 'أهلاً بيك يا تاجر',
          style: const TextStyle(
            fontSize: 24, color: merchantDark,
            fontWeight: FontWeight.w900,
          )),
        const SizedBox(height: 7),
        const Text(
          'سجّل الدخول، وبعدها أضف متجرك وانتظر موافقة الإدارة '
          'حتى يظهر للزبائن.',
          style: TextStyle(color: Colors.black54),
        ),
        const SizedBox(height: 22),
        Form(
          key: _form,
          child: Column(children: [
            if (_register) ...[
              TextFormField(
                controller: _name,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'اسم صاحب المتجر',
                  prefixIcon: Icon(Icons.person_outline),
                ),
                validator: (value) =>
                  (value ?? '').trim().length >= 2
                    ? null : 'اكتب الاسم الصحيح',
              ),
              const SizedBox(height: 12),
            ],
            TextFormField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              decoration: const InputDecoration(
                labelText: 'البريد الإلكتروني',
                prefixIcon: Icon(Icons.email_outlined),
              ),
              validator: (value) {
                final email = (value ?? '').trim();
                return email.contains('@') && email.contains('.')
                    ? null : 'أدخل بريداً صحيحاً';
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _password,
              obscureText: true,
              autofillHints: [
                _register
                    ? AutofillHints.newPassword
                    : AutofillHints.password,
              ],
              decoration: const InputDecoration(
                labelText: 'كلمة المرور',
                prefixIcon: Icon(Icons.lock_outline),
              ),
              validator: (value) => (value ?? '').length >= 8
                  ? null : 'كلمة المرور 8 أحرف أو أكثر',
            ),
          ]),
        ),
        if (_message != null) Padding(
          padding: const EdgeInsets.symmetric(vertical: 13),
          child: Text(_message!,
            style: TextStyle(
              color: _error ? Colors.red : Colors.green.shade800)),
        ),
        const SizedBox(height: 23),
        FilledButton.icon(
          onPressed: _busy ? null : _submit,
          style: FilledButton.styleFrom(
            backgroundColor: merchantPurple,
            padding: const EdgeInsets.symmetric(vertical: 15),
          ),
          icon: const Icon(Icons.login),
          label: Text(_busy ? 'لحظة...' :
            (_register ? 'إنشاء حساب تاجر' : 'تسجيل الدخول')),
        ),
        TextButton(
          onPressed: _busy ? null : () => setState(() {
            _register = !_register;
            _error = false;
            _message = null;
          }),
          child: Text(_register
              ? 'عندك حساب؟ سجّل دخول'
              : 'ما عندك حساب تاجر؟ افتح حساب'),
        ),
        const SizedBox(height: 18),
        Wrap(alignment: WrapAlignment.center, spacing: 6,
          children: [
            TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) =>
                  const MerchantLegalPage(
                    title: 'سياسة الخصوصية',
                    sections: merchantPrivacySections))),
              child: const Text('سياسة الخصوصية')),
            TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) =>
                  const MerchantLegalPage(
                    title: 'الشروط والأحكام',
                    sections: merchantTermsSections))),
              child: const Text('الشروط')),
            TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) =>
                  const MerchantAboutPage())),
              child: const Text('معلومات المطوّر')),
          ],
        ),
        const Text(
          'التطبيق خاص بأصحاب المحلات. حساب التاجر لا يمنح '
          'موافقة تلقائية على المتجر أو صلاحيات الإدارة.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, color: Colors.black54),
        ),
      ],
    )),
  );
}
