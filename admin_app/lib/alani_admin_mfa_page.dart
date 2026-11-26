import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Explicit, local TOTP setup. Never log or persist the enrollment secret.
class AlAniAdminMfaPage extends StatefulWidget {
  const AlAniAdminMfaPage({super.key});
  @override
  State<AlAniAdminMfaPage> createState() => _AlAniAdminMfaPageState();
}
class _AlAniAdminMfaPageState extends State<AlAniAdminMfaPage> {
  final _code=TextEditingController();
  final _auth=Supabase.instance.client.auth;
  String? _factor;
  String? _secret;
  String? _error;
  bool _busy=false;
  bool _loaded=false;
  bool _verified=false;
  bool _hasFactor=false;
  @override
  void initState(){super.initState();_load();}
  @override
  void dispose(){_secret=null;_code.dispose();super.dispose();}
  Future<void> _load() async {
    if(_busy)return;
    setState((){_busy=true;_error=null;});
    try{
      final assurance=_auth.mfa.getAuthenticatorAssuranceLevel();
      final factors=await _auth.mfa.listFactors();
      if(!mounted)return;
      setState((){
        _verified=assurance.currentLevel==AuthenticatorAssuranceLevels.aal2;
        _hasFactor=factors.totp.isNotEmpty;
        _factor=_hasFactor?factors.totp.first.id:null;
        _loaded=true;
      });
    }catch(_){if(mounted)setState(()=>_error='تعذر فحص التحقق بخطوتين.');}
    finally{if(mounted)setState(()=>_busy=false);}
  }
  Future<void> _enroll() async {
    if(_busy||_hasFactor||_factor!=null)return;
    setState((){_busy=true;_error=null;});
    try{
      final r=await _auth.mfa.enroll(factorType:FactorType.totp,issuer:'AlAni TEST');
      if(!mounted)return;
      final secret=r.totp?.secret;
      if(secret==null||secret.isEmpty)throw StateError('No TOTP');
      setState((){_factor=r.id;_secret=secret;});
    }catch(_){if(mounted)setState(()=>_error='تعذر إعداد عامل التحقق. تحقق من إعدادات المشروع.');}
    finally{if(mounted)setState(()=>_busy=false);}
  }
  Future<void> _verify() async {
    final id=_factor;
    if(_busy||id==null||!RegExp(r'^[0-9]{6}$').hasMatch(_code.text.trim()))return;
    setState((){_busy=true;_error=null;});
    try{
      await _auth.mfa.challengeAndVerify(factorId:id,code:_code.text.trim());
      final a=_auth.mfa.getAuthenticatorAssuranceLevel();
      if(a.currentLevel!=AuthenticatorAssuranceLevels.aal2)throw StateError('MFA not confirmed');
      if(mounted)setState((){_secret=null;_code.clear();_verified=true;});
    }catch(_){if(mounted)setState(()=>_error='لم ينجح التحقق. أدخل الرمز الحالي من تطبيق المصادقة.');}
    finally{if(mounted)setState(()=>_busy=false);}
  }
  @override
  Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:const Text('التحقق بخطوتين — TEST')),
    body:ListView(padding:const EdgeInsets.all(20),children:[
      const Icon(Icons.security,size:64),
      const SizedBox(height:16),
      const Text('حماية حساب الإدارة والاستيراد الخاص',style:TextStyle(fontSize:21,fontWeight:FontWeight.bold)),
      const SizedBox(height:12),
      if(_busy)const LinearProgressIndicator(),
      if(_error!=null)Text(_error!),
      if(!_loaded&&!_busy)TextButton(onPressed:_load,child:const Text('إعادة الفحص')),
      if(_verified)...[
        const ListTile(leading:Icon(Icons.verified_user_outlined),title:Text('الجلسة موثقة بخطوتين')),
        FilledButton(onPressed:()=>Navigator.pop(context,true),child:const Text('متابعة')),
      ]else if(_loaded)...[
        if(_factor==null)FilledButton(onPressed:_busy?null:_enroll,child:const Text('إعداد تطبيق المصادقة')),
        if(_secret!=null)...[
          const Text('أضف المفتاح التالي يدوياً في تطبيق مصادقة موثوق، اختر رمزاً مستنداً إلى الوقت. لا تشارك المفتاح أو تلتقط صورة له.'),
          SelectableText(_secret!,textDirection:TextDirection.ltr),
        ],
        if(_factor!=null)...[
          const Text('أدخل رمز تطبيق المصادقة المكون من ستة أرقام.'),
          TextField(controller:_code,keyboardType:TextInputType.number,
            inputFormatters:[FilteringTextInputFormatter.digitsOnly,LengthLimitingTextInputFormatter(6)],
            obscureText:true,autocorrect:false,enableSuggestions:false,
            decoration:const InputDecoration(labelText:'رمز المصادقة')),
          FilledButton(onPressed:_busy?null:_verify,child:const Text('تحقق')),
        ],
      ],
    ]));
}
