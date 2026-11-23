import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shitreed_customer/alani/alani_campaign_banner.dart';
import 'package:shitreed_customer/alani/alani_content.dart';
import 'package:shitreed_customer/alani/alani_product.dart';
import 'package:shitreed_customer/backend/marketplace_backend.dart';
import 'package:shitreed_customer/commerce/commerce_service.dart';

/// True only for the isolated test project until the release review is done.
class AlAniOffersGate {
  const AlAniOffersGate._();
  static const enabled =
    bool.fromEnvironment('SHITREED_CAMPAIGNS_ENABLED', defaultValue: false) &&
    (String.fromEnvironment('SUPABASE_URL') ==
      'https://tgvdwotbrnhcoykuxdpr.supabase.co' ||
     bool.fromEnvironment('ALANI_CAMPAIGNS_PRODUCTION_APPROVED',
       defaultValue: false));
}

class AlAniOffersPage extends StatefulWidget {
  const AlAniOffersPage({super.key});
  @override
  State<AlAniOffersPage> createState() => _AlAniOffersPageState();
}

class _AlAniOffersPageState extends State<AlAniOffersPage> {
  late Future<List<Map<String, dynamic>>> _offers;
  Timer? _clock;

  @override
  void initState() {
    super.initState();
    _offers = _load();
    _clock = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    super.dispose();
  }

  Future<List<Map<String, dynamic>>> _load() async {
    if (!AlAniOffersGate.enabled || !MarketplaceBackend.configured) return [];
    final rows = await Supabase.instance.client
      .from('shitreed_store_campaigns')
      .select('id,title,description,starts_at,ends_at,is_published,'
        'product_id,image_url')
      .eq('store_id', AlAniSettings.storeId)
      .eq('is_published', true)
      .order('ends_at', ascending: true).limit(80);
    return rows.map((v) => Map<String, dynamic>.from(v)).toList();
  }

  Future<void> _refresh() async {
    setState(() => _offers = _load());
    try { await _offers; } catch (_) { /* Error in FutureBuilder */ }
  }

  Future<void> _openProduct(String? productId) async {
    if (productId == null || productId.isEmpty) return;
    try {
      final products = await CommerceService.storeProducts(AlAniSettings.storeId);
      if (!mounted) return;
      for (final product in products) {
        if (product.id == productId) {
          await Navigator.of(context).push<void>(MaterialPageRoute(
            builder: (_) => AlAniProductDetailsPage(product: product)));
          return;
        }
      }
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('المنتج المرتبط بهذا العرض غير متوفر حالياً.')));
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('تعذّر تحميل بيانات المنتج. حاول مرة ثانية.')));
    }
  }

  String _remaining(DateTime end) {
    final value = end.difference(DateTime.now().toUtc());
    if (value.isNegative || value == Duration.zero) return 'انتهى العرض';
    final days = value.inDays;
    final hours = value.inHours.remainder(24);
    final mins = value.inMinutes.remainder(60);
    if (days > 0) return 'باقي $days يوم و$hours ساعة';
    return 'باقي $hours ساعة و$mins دقيقة';
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('عروض لفترة محدودة')),
    body: !AlAniOffersGate.enabled
      ? const Center(child: Text('العروض قيد التفعيل.'))
      : RefreshIndicator(onRefresh: _refresh,
          child: FutureBuilder<List<Map<String, dynamic>>>(
            future: _offers,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return ListView(children: [
                  const SizedBox(height: 90),
                  const Center(child: Text('تعذّر تحميل العروض.')),
                  TextButton(onPressed: _refresh,
                    child: const Text('إعادة المحاولة')),
                ]);
              }
              final now = DateTime.now().toUtc();
              final live = (snapshot.data ?? []).where((v) {
                final from = DateTime.tryParse(v['starts_at']?.toString() ?? '');
                final until = DateTime.tryParse(v['ends_at']?.toString() ?? '');
                return v['is_published'] == true && from != null && until != null
                  && AlAniCampaignWindow.visible(from, until, now);
              }).toList();
              if (live.isEmpty) return ListView(children: [
                const SizedBox(height: 100),
                const Center(child: Icon(Icons.local_offer_outlined, size: 54)),
                const Padding(padding: EdgeInsets.all(20),
                  child: Center(child: Text('ماكو عروض محدودة الوقت حالياً.'))),
              ]);
              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  const Text('عروض السيد إبراهيم العاني',
                    style: TextStyle(fontSize: 23,
                      fontWeight: FontWeight.w900)),
                  const Text('تظهر العروض المنشورة خلال مدتها فقط. '
                    'السعر المعتمد هو الذي يظهر في السلة وعند تأكيد الطلب.',
                    style: TextStyle(height: 1.6)),
                  const SizedBox(height: 14),
                  for (final row in live) _card(row),
                ],
              );
            },
          )),
  );

  Widget _card(Map<String, dynamic> row) {
    final until = DateTime.tryParse(row['ends_at']?.toString() ?? '');
    final image = row['image_url']?.toString();
    final productId = row['product_id']?.toString();
    return Card(
      clipBehavior: Clip.antiAlias,
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (image != null && image.startsWith('https://'))
          Image.network(image, fit: BoxFit.cover, height: 170,
            errorBuilder: (_, __, ___) => const SizedBox.shrink()),
        Container(
          color: const Color(0xFFEAF9EF),
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('⏳ عرض لفترة محدودة',
              style: TextStyle(color: Color(0xFF137047),
                fontWeight: FontWeight.w800)),
            const SizedBox(height: 9),
            Text(row['title']?.toString() ?? '',
              style: const TextStyle(fontSize: 20,
                fontWeight: FontWeight.w900)),
            const SizedBox(height: 7),
            Text(row['description']?.toString() ?? '',
              style: const TextStyle(height: 1.6)),
            const SizedBox(height: 10),
            if (until != null)
              Text(_remaining(until),
                style: const TextStyle(color: Color(0xFF9F5311),
                  fontWeight: FontWeight.w800)),
            if (productId != null) ...[
              const SizedBox(height: 8),
              FilledButton.icon(onPressed: () => _openProduct(productId),
                icon: const Icon(Icons.shopping_bag_outlined),
                label: const Text('مشاهدة المنتج وسعره')),
            ],
          ]),
        ),
      ]),
    );
  }
}
