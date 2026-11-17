// ignore_for_file: prefer_interpolation_to_compose_strings
import 'package:flutter/material.dart';
import 'package:shitreed_merchant/commerce/commerce_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Merchants can request ownership review for an OSM-listed place.
/// Submission does NOT approve a store or allow unverified sales.
class MerchantOsmClaimsPage extends StatefulWidget {
  const MerchantOsmClaimsPage({super.key});
  @override
  State<MerchantOsmClaimsPage> createState() => _MerchantOsmClaimsPageState();
}

class _MerchantOsmClaimsPageState extends State<MerchantOsmClaimsPage> {
  final osmId = TextEditingController();
  final note = TextEditingController();
  List<Map<String, dynamic>> stores = [], claims = [];
  String? storeId, error;
  bool loading = true, busy = false;

  SupabaseClient get db => Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    refresh();
  }

  @override
  void dispose() {
    osmId.dispose();
    note.dispose();
    super.dispose();
  }

  Future<void> refresh() async {
    final uid = db.auth.currentUser?.id;
    if (uid == null) {
      if (mounted) setState(() {
        error = 'سجّل الدخول بحساب التاجر أولاً.';
        loading = false;
      });
      return;
    }
    if (mounted) setState(() { loading = true; error = null; });
    try {
      final ownStores = await CommerceService.myStores();
      final ownClaims = await db.from('shitreed_osm_claim_requests')
          .select('id,store_id,osm_object_id,note,status,review_reason,created_at')
          .order('created_at', ascending: false)
          .limit(30);
      if (mounted) setState(() {
        stores = ownStores;
        claims = ownClaims;
        if (!stores.any((s) => s['id'] == storeId)) {
          storeId = stores.isEmpty ? null : stores.first['id'] as String;
        }
        loading = false;
      });
    } catch (_) {
      if (mounted) setState(() {
        loading = false;
        error = 'تعذر تحميل بيانات مطالبات المتاجر. حاول لاحقاً.';
      });
    }
  }

  Future<void> submit() async {
    if (busy || storeId == null) return;
    final id = osmId.text.trim();
    final details = note.text.trim();
    if (!RegExp(r'^(node|way|relation)/[1-9][0-9]{0,17}$').hasMatch(id)) {
      _notify('اكتب معرّف OSM مثل node/12345 أو way/12345.');
      return;
    }
    if (details.length < 12) {
      _notify('اكتب شرحاً لإثبات علاقتك بالمحل (12 حرفاً على الأقل).');
      return;
    }
    final okay = await showDialog<bool>(context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تأكيد إرسال طلب الملكية'),
        content: const Text('هذا مجرد طلب مراجعة. '
          'ما يصير المحل موثّق أو معتمداً للبيع قبل مراجعة الإدارة.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
            child: const Text('رجوع')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true),
            child: const Text('إرسال الطلب')),
        ],
      ));
    if (okay != true || !mounted) return;
    setState(() => busy = true);
    try {
      await db.from('shitreed_osm_claim_requests').insert({
        'store_id': storeId!,
        'osm_object_id': id,
        'note': details,
      });
      osmId.clear();
      note.clear();
      await refresh();
      _notify('تم إرسال الطلب؛ بانتظار مراجعة إدارة شتريد.');
    } on PostgrestException catch (_) {
      _notify('لم يُقبل الطلب. قد يكون مكرراً أو ما عندك صلاحية لهذا المحل.');
    } catch (_) {
      _notify('تعذر إرسال المطالبة. تحقق من الإنترنت.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void _notify(String text) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(text)));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('مطالبات ملكية المحلات')),
    body: loading
      ? const Center(child: CircularProgressIndicator())
      : RefreshIndicator(onRefresh: refresh,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          const Card(child: Padding(
            padding: EdgeInsets.all(15),
            child: Text('المحلات الموجودة على OpenStreetMap مو بالضرورة '
              'مسجلة بشتريد. إذا المحل إلك، احفظ معرفه من تطبيق الزبون '
              'وارسل طلب ملكية باسم متجرك؛ تتطلب المراجعة إثباتات إضافية.'),
          )),
          if (error != null) Padding(
            padding: const EdgeInsets.all(8),
            child: Text(error!)),
          if (stores.isEmpty)
            const Text('أولاً سجّل متجرك داخل شتريد تاجر حتى تقدم مطالبة.'),
          if (stores.isNotEmpty) ...[
            DropdownButtonFormField<String>(
              value: storeId,
              decoration: const InputDecoration(labelText: 'متجري'),
              items: [
                for (final store in stores)
                  DropdownMenuItem(
                    value: store['id'] as String,
                    child: Text((store['name'] ?? 'متجر').toString()),
                  ),
              ],
              onChanged: (v) => setState(() => storeId = v),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: osmId, maxLength: 32,
              decoration: const InputDecoration(
                labelText: 'معرّف المحل في OpenStreetMap',
                hintText: 'node/12345 أو way/12345',
              ),
            ),
            TextField(
              controller: note, maxLines: 3, maxLength: 600,
              decoration: const InputDecoration(
                labelText: 'اشرح علاقتك بالمحل وكيف تثبت ملكيته'),
            ),
            FilledButton.icon(
              onPressed: busy ? null : submit,
              icon: const Icon(Icons.send_outlined),
              label: const Text('إرسال طلب مراجعة الملكية')),
          ],
          const SizedBox(height: 22),
          const Text('طلباتي السابقة', style: TextStyle(
            fontWeight: FontWeight.w900,fontSize: 19)),
          if (claims.isEmpty)
            const Padding(padding: EdgeInsets.all(12),
              child: Text('ما عندك طلبات ملكية بعد.')),
          for (final claim in claims)
            Card(child: ListTile(
              leading: const Icon(Icons.business_outlined),
              title: Text((claim['osm_object_id'] ?? '').toString()),
              subtitle: Text('الحالة: ' +
                (claim['status'] ?? '').toString() +
                (claim['review_reason'] == null ? ''
                  : '\n' + claim['review_reason'].toString())),
            )),
          const SizedBox(height: 50),
        ]),
      ),
  );
}
