import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Password-based email authentication against a real Supabase project.
class CustomerAuthPage extends StatefulWidget {
  const CustomerAuthPage({super.key});

  @override
  State<CustomerAuthPage> createState() => _CustomerAuthPageState();
}

class _CustomerAuthPageState extends State<CustomerAuthPage> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _name = TextEditingController();
  bool _signup = false;
  bool _busy = false;
  String? _error;
  String? _notice;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate() || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    try {
      final client = Supabase.instance.client;
      final email = _email.text.trim();
      if (_signup) {
        final response = await client.auth.signUp(
          email: email,
          password: _password.text,
          data: {'display_name': _name.text.trim()},
        );
        if (!mounted) return;
        if (response.session != null) {
          Navigator.of(context).pop(true);
        } else {
          setState(() => _notice =
            'تم إرسال رسالة تأكيد إلى البريد، افتحها لتفعيل الحساب ثم سجّل دخولك.');
        }
      } else {
        final response = await client.auth.signInWithPassword(
          email: email,
          password: _password.text,
        );
        if (!mounted) return;
        if (response.session != null) {
          Navigator.of(context).pop(true);
        } else {
          setState(() => _error = 'تعذّر إكمال تسجيل الدخول.');
        }
      }
    } on AuthException catch (e) {
      if (mounted) {
        setState(() => _error = e.message);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'ما گدرنا نتصل بالخدمة، حاول مرة ثانية.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(_signup ? 'إنشاء حساب زبون' : 'دخول الزبون')),
    body: SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.verified_user_outlined,
                size: 68, color: Color(0xFF51159B)),
              const SizedBox(height: 18),
              Text(_signup ? 'سجّل حسابك في شتريد' : 'أهلاً بيك من جديد',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 24,
                  fontWeight: FontWeight.w800)),
              const SizedBox(height: 22),
              if (_signup) ...[
                TextFormField(
                  controller: _name,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(), labelText: 'الاسم الظاهر'),
                  validator: (v) => (v ?? '').trim().length < 2
                    ? 'اكتب اسماً من حرفين على الأقل' : null,
                ),
                const SizedBox(height: 14),
              ],
              TextFormField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email],
                decoration: const InputDecoration(
                  border: OutlineInputBorder(), labelText: 'البريد الإلكتروني'),
                validator: (v) {
                  final email = (v ?? '').trim();
                  return email.contains('@') && email.contains('.')
                    ? null : 'أدخل بريداً إلكترونياً صحيحاً';
                },
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _password,
                obscureText: true,
                autofillHints: [
                  _signup ? AutofillHints.newPassword : AutofillHints.password,
                ],
                decoration: const InputDecoration(
                  border: OutlineInputBorder(), labelText: 'كلمة المرور'),
                validator: (v) => (v ?? '').length < 8
                  ? 'كلمة المرور لازم تكون 8 أحرف أو أكثر' : null,
              ),
              if (_error != null) Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(_error!,
                  style: const TextStyle(color: Colors.red)),
              ),
              if (_notice != null) Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(_notice!,
                  style: const TextStyle(color: Colors.green)),
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _busy ? null : _submit,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF51159B),
                  padding: const EdgeInsets.symmetric(vertical: 14)),
                child: Text(_busy ? 'انتظر...' :
                  (_signup ? 'إنشاء حساب' : 'تسجيل الدخول')),
              ),
              TextButton(
                onPressed: _busy ? null : () => setState(() {
                  _signup = !_signup;
                  _error = null;
                  _notice = null;
                }),
                child: Text(_signup
                  ? 'عندك حساب؟ سجّل دخول'
                  : 'ما عندك حساب؟ سجّل الآن'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
