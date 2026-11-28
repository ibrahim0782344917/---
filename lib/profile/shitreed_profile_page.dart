// ignore_for_file: curly_braces_in_flow_control_structures, prefer_interpolation_to_compose_strings
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:shitreed_customer/alani/alani_premium_widgets.dart';
import 'package:shitreed_customer/alani/alani_customer_extras.dart';
import 'package:shitreed_customer/account/customer_delete_account_page.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Resolve only a locator belonging to the currently signed-in account.
abstract final class AlAniAvatarPath {
  static String? ownPath(String locator,String actor,{required String projectUrl}){
    for(final ext in const ['jpg','png','webp']){
      final path='$actor/avatar.$ext';
      if(locator==path || locator=='$projectUrl/storage/v1/object/public/shitreed-avatars/$path')return path;
    }
    return null;
  }
}

const _green = Color(0xFF0C946B);
const _dark = Color(0xFF163E32);

/// Profile records are owned through Supabase RLS. The client never writes XP,
/// levels, administrator ranks or blue verification badges.
/// This profile is also used as a standalone Navigator route without a
/// Scaffold. Keep the InkWell inside its own Material, even in a ListView.
class ShitreedAvatarButton extends StatelessWidget {
  const ShitreedAvatarButton({
    super.key, required this.imageUrl, required this.onTap, this.imageBytes,
  });
  final String imageUrl;
  final Uint8List? imageBytes;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Material(
    type: MaterialType.transparency,
    child: InkWell(
      key: const ValueKey('profile-avatar-button'),
      onTap: onTap,
      borderRadius: BorderRadius.circular(45),
      child: CircleAvatar(
        radius: 43, backgroundColor: Colors.white,
        backgroundImage: imageBytes==null?null:MemoryImage(imageBytes!),
        child: imageBytes!=null ? null
            : const Icon(Icons.person, size: 46, color: _green),
      ),
    ),
  );
}

class ShitreedProfilePage extends StatefulWidget {
  const ShitreedProfilePage({super.key, this.onMerchantTap, this.merchantMode = false});
  final VoidCallback? onMerchantTap;
  final bool merchantMode;

  @override
  State<ShitreedProfilePage> createState() => _ShitreedProfilePageState();
}

class _ShitreedProfilePageState extends State<ShitreedProfilePage> {
  SupabaseClient get db => Supabase.instance.client;
  String? get uid => db.auth.currentUser?.id;
  Map<String, dynamic>? profile;
  Uint8List? _avatarBytes;
  String? _loadedActor;
  void _clearAvatar(){
    final old=_avatarBytes;
    _avatarBytes=null;
    if(old!=null)MemoryImage(old).evict();
  }
  @override
  void dispose(){_clearAvatar();super.dispose();}
  List<Map<String, dynamic>> addresses = [], badges = [], events = [], thresholds = [];
  bool loading = true, saving = false;
  String? error;

  @override
  void initState() { super.initState(); refresh(); }

  Future<void> refresh() async {
    final user = uid;
    if (user == null) {
      if (mounted) setState(() { error = 'سجّل الدخول أولاً'; loading = false; });
      return;
    }
    if (mounted) setState(() { _clearAvatar(); loading = true; error = null; });
    try {
      final p = await db.from('shitreed_profiles')
          .select('user_id,display_name,bio,city,avatar_url')
          .eq('user_id', user).maybeSingle();
      final a = await db.from('shitreed_saved_addresses')
          .select('id,label,address_text,contact_phone')
          .eq('user_id', user).order('created_at', ascending: false).limit(30);
      final b = await db.from('shitreed_user_badges')
          .select('badge_kind,label,icon,expires_at,active')
          .eq('user_id', user).eq('active', true);
      final x = await db.from('shitreed_xp_events')
          .select('event_type,points,created_at')
          .eq('user_id', user).order('created_at', ascending: false).limit(200);
      final lifetimeXp = await db.rpc('shitreed_my_xp_total');
      final t = await db.from('shitreed_level_thresholds')
          .select('level,min_xp').order('level');
      Uint8List? avatar;
      final path=AlAniAvatarPath.ownPath((p?['avatar_url']??'').toString(),user,
        projectUrl:const String.fromEnvironment('SUPABASE_URL'));
      if(path!=null && uid==user){
        try{
          final data=await db.storage.from('shitreed-avatars').download(path);
          if(data.isNotEmpty && data.lengthInBytes<=2097152)avatar=data;
        }catch(_){ /* Missing or unauthorized image must not block the profile. */ }
      }
      if (mounted && uid==user) setState(() {
        _loadedActor=user;
        _avatarBytes=avatar;
        profile = p;
        addresses = a;
        badges = b;
        events = x;
        xpTotal = (lifetimeXp as num).toInt();
        thresholds = t;
        loading = false;
      });
    } catch (_) {
      if (mounted) setState(() {
        error = 'تعذر تحميل بيانات البروفايل. جرّب التحديث.';
        loading = false;
      });
    }
  }

  String get displayName {
    final saved = (profile?['display_name'] ?? '').toString();
    final signup = (db.auth.currentUser?.userMetadata?['display_name'] ?? '').toString();
    return saved.isNotEmpty ? saved : (signup.isNotEmpty ? signup : 'عضو شتريد');
  }

  int xpTotal = 0;
  int get totalXp => xpTotal;
  int get level {
    int value = 1;
    for (final row in thresholds) {
      if (totalXp >= (row['min_xp'] as num).toInt()) {
        value = (row['level'] as num).toInt();
      }
    }
    return value;
  }
  int get levelStart {
    for (final row in thresholds) {
      if (row['level'] == level) return (row['min_xp'] as num).toInt();
    }
    return 0;
  }
  int get levelEnd {
    for (final row in thresholds) {
      if (row['level'] == level + 1) return (row['min_xp'] as num).toInt();
    }
    return levelStart + 100;
  }
  String get rank {
    if (level >= 100) return 'نخبة شتريد';
    if (level >= 76) return 'أسطوري';
    if (level >= 51) return 'محترف';
    if (level >= 26) return 'مميز';
    if (level >= 11) return 'نشيط';
    return 'مبتدئ';
  }

  void notice(String s) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));
  }

  Future<void> edit() async {
    final name = TextEditingController(text: displayName);
    final city = TextEditingController(text: (profile?['city'] ?? '').toString());
    final bio = TextEditingController(text: (profile?['bio'] ?? '').toString());
    final form = GlobalKey<FormState>();
    try {
      final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
        title: const Text('تعديل بروفايلي'),
        content: SingleChildScrollView(child: Form(key: form, child: Column(
          mainAxisSize: MainAxisSize.min, children: [
            TextFormField(controller: name, maxLength: 80,
              decoration: const InputDecoration(labelText: 'الاسم الظاهر'),
              validator: (v) => (v ?? '').trim().length < 2 ? 'اكتب اسم صحيح' : null),
            TextFormField(controller: city, maxLength: 80,
              decoration: const InputDecoration(labelText: 'المدينة / المنطقة')),
            TextFormField(controller: bio, maxLength: 500, maxLines: 3,
              decoration: const InputDecoration(labelText: 'نبذة عني')),
            const Text('أول إكمال للبروفايل يمنح 20 XP مرة واحدة فقط.',
              style: TextStyle(fontSize: 12, color: Colors.black54)),
          ]))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
              child: const Text('رجوع')),
          FilledButton(onPressed: () {
            if (form.currentState?.validate() == true) Navigator.pop(ctx, true);
          }, child: const Text('حفظ')),
        ],
      ));
      if (ok != true || uid == null || saving) return;
      setState(() => saving = true);
      final values = {
        'display_name': name.text.trim(),
        'city': city.text.trim(),
        'bio': bio.text.trim(),
      };
      if (profile == null) {
        await db.from('shitreed_profiles').insert({'user_id': uid!, ...values});
      } else {
        await db.from('shitreed_profiles').update(values).eq('user_id', uid!);
      }
      await refresh();
      notice('تم حفظ بروفايلك');
    } catch (_) {
      notice('تعذر حفظ البروفايل. حاول مجدداً.');
    } finally {
      name.dispose(); city.dispose(); bio.dispose();
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> uploadAvatar() async {
    if (uid == null || profile == null || saving) {
      notice('احفظ بروفايلك قبل رفع الصورة.');
      return;
    }
    try {
      final actor=uid;
      final picked = await ImagePicker().pickImage(
          source: ImageSource.gallery, imageQuality: 80, maxWidth: 800);
      if (picked == null || !mounted || actor==null || uid!=actor) return;
      final bytes = await picked.readAsBytes();
      if (bytes.isEmpty || bytes.lengthInBytes > 2097152) {
        notice('حجم الصورة لازم يكون أقل من 2 ميگابايت.');
        return;
      }
      final lower = picked.name.toLowerCase();
      final ext = lower.endsWith('.png') ? 'png' :
          lower.endsWith('.webp') ? 'webp' : 'jpg';
      final mime = ext == 'png' ? 'image/png' :
          ext == 'webp' ? 'image/webp' : 'image/jpeg';
      if(!mounted || uid!=actor)return;
      setState(() => saving = true);
      final path = actor + '/avatar.' + ext;
      await db.storage.from('shitreed-avatars').uploadBinary(
        path, bytes, fileOptions: FileOptions(contentType: mime, upsert: true, cacheControl: '0'));
      if(!mounted || uid!=actor)return;
      // Legacy database locator; the app never fetches its public URL.
      final locator = db.storage.from('shitreed-avatars').getPublicUrl(path);
      await db.from('shitreed_profiles').update({'avatar_url': locator})
          .eq('user_id', actor);
      await refresh();
      notice('تم تحديث صورة الحساب');
    } catch (_) {
      notice('تعذر رفع الصورة. جرّب صورة أصغر.');
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> addAddress() async {
    if (uid == null) return;
    final label = TextEditingController(text: 'البيت');
    final address = TextEditingController();
    final phone = TextEditingController();
    final form = GlobalKey<FormState>();
    try {
      final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
        title: const Text('عنوان توصيل جديد'),
        content: Form(key: form, child: SingleChildScrollView(child: Column(
          mainAxisSize: MainAxisSize.min, children: [
            TextFormField(controller: label, maxLength: 60,
              decoration: const InputDecoration(labelText: 'اسم العنوان'),
              validator: (v) => (v ?? '').trim().length < 2 ? 'اكتب اسماً' : null),
            TextFormField(controller: address, maxLength: 300, maxLines: 2,
              decoration: const InputDecoration(labelText: 'العنوان الكامل'),
              validator: (v) => (v ?? '').trim().length < 8 ? 'اكتب العنوان' : null),
            TextFormField(controller: phone, maxLength: 25,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'الهاتف (اختياري)')),
          ]))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء')),
          FilledButton(onPressed: () {
            if (form.currentState?.validate() == true) Navigator.pop(ctx, true);
          }, child: const Text('حفظ')),
        ],
      ));
      if (ok != true) return;
      await db.from('shitreed_saved_addresses').insert({
        'user_id': uid!, 'label': label.text.trim(),
        'address_text': address.text.trim(), 'contact_phone': phone.text.trim(),
      });
      await refresh();
      notice('تم حفظ العنوان');
    } catch (_) {
      notice('ما گدرنا نحفظ العنوان.');
    } finally {
      label.dispose(); address.dispose(); phone.dispose();
    }
  }

  Future<void> deleteAddress(String addressId) async {
    if (uid == null) return;
    final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('حذف العنوان'),
      content: const Text('تريد تحذف العنوان؟'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false),
            child: const Text('رجوع')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true),
            child: const Text('تأكيد الحذف')),
      ],
    ));
    if (ok != true) return;
    try {
      await db.from('shitreed_saved_addresses').delete()
          .eq('id', addressId).eq('user_id', uid!);
      await refresh();
    } catch (_) { notice('تعذر حذف العنوان.'); }
  }

  Future<void> requestAccountDeletion() async {
    if (uid == null || !mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => const CustomerDeleteAccountPage()));
  }

  Widget box(Widget child) => Card(
    child: Padding(padding: const EdgeInsets.all(17), child: child),
  );

  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).scaffoldBackgroundColor,
    child: _profileBody(context),
  );

  Widget _profileBody(BuildContext context) {
    if (loading) return const Center(child: CircularProgressIndicator());
    if (error != null) {
      return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(error!, textAlign: TextAlign.center),
        TextButton.icon(onPressed: refresh, icon: const Icon(Icons.refresh),
            label: const Text('إعادة المحاولة')),
      ]));
    }
    final xp = totalXp, start = levelStart, end = levelEnd;
    final progress = end > start
        ? ((xp - start) / (end - start)).clamp(0.0, 1.0).toDouble() : 1.0;
    final image = _loadedActor==uid?_avatarBytes:null;
    final visibleBadges = badges.where((b) {
      final expiry = DateTime.tryParse((b['expires_at'] ?? '').toString());
      return expiry == null || expiry.isAfter(DateTime.now());
    }).toList();

    return RefreshIndicator(onRefresh: refresh, child: ListView(
      padding: const EdgeInsets.all(16), children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(24),
            gradient: const LinearGradient(colors: [_dark, _green])),
          child: Column(children: [
            ShitreedAvatarButton(
              imageUrl: '', imageBytes:image, onTap: saving ? null : uploadAvatar),
            const SizedBox(height: 9),
            Text(displayName, textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 24, color: Colors.white,
                fontWeight: FontWeight.w900)),
            Text(db.auth.currentUser?.email ?? 'حساب شتريد',
              style: const TextStyle(color: Colors.white70)),
            const SizedBox(height: 8),
            Wrap(spacing: 7, runSpacing: 7, children: [
              Chip(label: Text(widget.merchantMode ? '🏪 تاجر' : '🛍️ زبون')),
              for (final badge in visibleBadges)
                Chip(avatar: Icon(
                  (badge['badge_kind'] ?? '').toString().startsWith('verified')
                      ? Icons.verified : Icons.stars,
                  color: Colors.blue, size: 18),
                  label: Text((badge['label'] ?? '').toString())),
            ]),
            OutlinedButton.icon(
              onPressed: saving ? null : edit,
              style: OutlinedButton.styleFrom(foregroundColor: Colors.white,
                side: const BorderSide(color: Colors.white60)),
              icon: const Icon(Icons.edit_outlined),
              label: const Text('تعديل البروفايل')),
          ]),
        ),
        const SizedBox(height: 12),
        const AlAniSectionTitle('مستواي ومكافآتي',icon:Icons.stars_outlined),
        box(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.auto_awesome, color: _green),
            const SizedBox(width: 8),
            Expanded(child:Text('المستوى ' + level.toString() + ' • ' + rank,
              style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900))),
          ]),
          const SizedBox(height: 10),
          LinearProgressIndicator(value: progress, color: _green,
            minHeight: 10, borderRadius: BorderRadius.circular(5)),
          const SizedBox(height: 5),
          Text(xp.toString() + ' / ' + end.toString() + ' XP'),
          const Text('XP للخبرة فقط، مو أموال ولا قابلة للسحب.',
            style: TextStyle(color: Colors.black54, fontSize: 12)),
        ])),
        const SizedBox(height: 10),
        box(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const AlAniSectionTitle('معلومات البروفايل',icon:Icons.person_outline),
          const SizedBox(height: 8),
          Text('المدينة: ' + (profile?['city'] ?? 'غير محددة').toString()),
          Text('النبذة: ' + (profile?['bio'] ?? 'أضف نبذة عن نفسك').toString()),
        ])),
        const SizedBox(height: 10),
        box(Column(children: [
          Row(children: [
            const Expanded(child: Text('عناويني',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900))),
            TextButton.icon(onPressed: addAddress,
              icon: const Icon(Icons.add_location_alt),
              label: const Text('إضافة')),
          ]),
          if (addresses.isEmpty) const Text('ما عندك عناوين محفوظة بعد.'),
          for (final a in addresses)
            ListTile(
              leading: const Icon(Icons.location_on_outlined, color: _green),
              title: Text((a['label'] ?? '').toString()),
              subtitle: Text((a['address_text'] ?? '').toString()),
              trailing: IconButton(
                tooltip: 'حذف العنوان',
                icon: const Icon(Icons.delete_outline),
                onPressed: () => deleteAddress((a['id'] ?? '').toString())),
            ),
        ])),
        const SizedBox(height: 10),
        box(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const AlAniSectionTitle('نشاطي ونقاط XP',icon:Icons.timeline_outlined),
          if (events.isEmpty) const Text('ما كسبت نقاط بعد.'),
          for (final event in events.take(8)) ListTile(
            dense: true, contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.stars_outlined, color: _green),
            title: Text(_label((event['event_type'] ?? '').toString())),
            trailing: Text('+' + (event['points'] ?? '').toString() + ' XP',
              style: const TextStyle(color: _green, fontWeight: FontWeight.bold)),
          ),
        ])),
        if (widget.onMerchantTap != null) ...[
          const SizedBox(height: 12),
          FilledButton.icon(onPressed: widget.onMerchantTap,
            icon: const Icon(Icons.storefront_outlined),
            label: const Text('إدارة متجري')),
        ],
        if (!widget.merchantMode && AlAniCustomerExtras.enabled)
          FilledButton.icon(
            onPressed: () => Navigator.of(context).push<void>(MaterialPageRoute(builder: (_) => const AlAniCustomerExtrasPage())),
            icon: const Icon(Icons.favorite_outline),
            label: const Text('المفضلة ونقاط الشراء ودعوة الأصدقاء')),
        if (!widget.merchantMode)
          TextButton.icon(
            onPressed: requestAccountDeletion,
            icon: const Icon(Icons.person_remove_outlined),
            label: const Text('طلب حذف الحساب والبيانات')),
        const SizedBox(height: 25),
        const Text('الشارة الزرقاء تعتمدها الإدارة فقط بعد التحقق. '
          'الرتب الشكلية لا تعطي صلاحيات إدارية.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, color: Colors.black54)),
        const SizedBox(height: 65),
      ],
    ));
  }

  String _label(String key) => switch (key) {
    'profile_completed' => 'اكتمال البروفايل',
    'verified_purchase' => 'شراء مكتمل وموثق',
    'verified_review' => 'تقييم حقيقي',
    'merchant_completed_sale' => 'بيع مكتمل وموثق',
    'qualified_share' => 'مشاركة مؤهلة',
    'daily_eligible_activity' => 'نشاط مؤهل',
    _ => 'نشاط من شتريد',
  };
}
