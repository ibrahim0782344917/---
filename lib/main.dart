import 'package:flutter/material.dart';
import 'package:shitreed_customer/auth/customer_auth_page.dart';
import 'package:shitreed_customer/backend/marketplace_backend.dart';
import 'package:shitreed_customer/maps/baghdad_map_page.dart';
import 'package:shitreed_customer/commerce/commerce_service.dart';
import 'package:shitreed_customer/commerce/customer_commerce_pages.dart';
import 'package:shitreed_customer/merchant/merchant_dashboard.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await MarketplaceBackend.initialize();
  runApp(const ShitreedApp());
}

const purple = Color(0xFF51159B);
const darkPurple = Color(0xFF280B53);
const orange = Color(0xFFFF811A);
const canvas = Color(0xFFF9F6FC);

class Store {
  final String name, area, type, emoji;
  final bool isDemo;
  final String? id;
  const Store(this.name, this.area, this.type, this.emoji,
      {this.isDemo = true, this.id});
}

class Product {
  final String title, emoji;
  final int price;
  const Product(this.title, this.emoji, this.price);
}

const stores = <Store>[
  Store('موبايل بغداد - نموذج', 'المنصور', 'موبايلات', '📱'),
  Store('سوبر ماركت - نموذج', 'الغزالية', 'مواد غذائية', '🛒'),
  Store('أزياء بغداد - نموذج', 'الكرادة', 'ملابس', '👕'),
  Store('مستلزمات البيت - نموذج', 'الأعظمية', 'أجهزة منزلية', '🏠'),
  Store('مطعم بغداد - نموذج', 'زيونة', 'مطاعم', '🍔'),
  Store('صيدلية - نموذج', 'الدورة', 'صيدليات', '💊'),
  Store('مول تجريبي', 'بغداد الجديدة', 'مولات', '🏬'),
];

const products = <Product>[
  Product('سماعة لاسلكية - نموذج', '🎧', 75000),
  Product('هاتف ذكي - نموذج', '📱', 599000),
  Product('حقيبة - نموذج', '👜', 28000),
];

String dinars(int value) {
  final s = value.toString();
  return '${s.replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+(?!\d))'), (m) => '${m[1]},')} د.ع';
}

class ShitreedApp extends StatelessWidget {
  const ShitreedApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'شتريد؟ موجود!',
        debugShowCheckedModeBanner: false,
        locale: const Locale('ar'),
        builder: (context, child) => Directionality(
          textDirection: TextDirection.rtl,
          child: child ?? const SizedBox.shrink(),
        ),
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(seedColor: purple),
          scaffoldBackgroundColor: canvas,
          appBarTheme: const AppBarTheme(
            backgroundColor: darkPurple, foregroundColor: Colors.white),
        ),
        home: const WelcomePage(),
      );
}

class WelcomePage extends StatelessWidget {
  const WelcomePage({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [darkPurple, purple, Color(0xFF1B113C)]),
      ),
      child: SafeArea(child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(children: [
          const Spacer(),
          const Icon(Icons.shopping_bag_rounded, color: orange, size: 104),
          const Text('شتريد؟', style: TextStyle(
            color: Colors.white, fontSize: 56, fontWeight: FontWeight.w900)),
          const Text('موجود!', style: TextStyle(
            color: orange, fontSize: 45, fontWeight: FontWeight.w900)),
          const SizedBox(height: 14),
          const Text('كل أسواق بغداد بين إيديك',
            style: TextStyle(color: Colors.white, fontSize: 21)),
          const Spacer(),
          SizedBox(width: double.infinity, height: 55,
            child: FilledButton(
              style: FilledButton.styleFrom(backgroundColor: orange),
              onPressed: () => Navigator.pushReplacement(context,
                MaterialPageRoute<void>(builder: (_) => const CustomerHome())),
              child: const Text('ابدأ الآن', style: TextStyle(
                fontWeight: FontWeight.w900, fontSize: 19)),
            ),
          ),
          const SizedBox(height: 18),
          Text(MarketplaceBackend.configured
              ? 'متاجر حقيقية • الدفع عند الاستلام'
              : 'نسخة تجريبية — بدون طلبات حقيقية',
            style: const TextStyle(color: Colors.white70)),
          const SizedBox(height: 15),
        ]),
      )),
    ),
  );
}

class CustomerHome extends StatefulWidget {
  const CustomerHome({super.key});
  @override
  State<CustomerHome> createState() => _CustomerHomeState();
}

class _CustomerHomeState extends State<CustomerHome> {
  int tab = 0;
  String query = '';
  String district = 'كل بغداد';
  String category = 'الكل';
  final Map<int, int> cart = {};
  List<Store> remoteStores = [];
  List<MarketplaceProduct> remoteProducts = [];
  bool remoteLoading = false;
  String? remoteError;

  @override
  void initState() {
    super.initState();
    if (MarketplaceBackend.configured) {
      _loadRealStores();
    }
  }

  Future<void> _loadRealStores() async {
    setState(() {
      remoteLoading = true;
      remoteError = null;
    });
    try {
      final results = await MarketplaceBackend.approvedStores();
      final published = await MarketplaceBackend.publishedProducts();
      if (!mounted) return;
      setState(() {
        remoteProducts = published;
        remoteStores = results.map((store) => Store(
          store.name,
          store.area,
          store.category,
          '🏪',
          isDemo: false,
          id: store.id,
        )).toList();
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => remoteError =
        'تعذّر تحميل المحلات. تأكد من الإنترنت وقاعدة البيانات.');
    } finally {
      if (mounted) setState(() => remoteLoading = false);
    }
  }

  static const districts = [
    'كل بغداد', 'الغزالية', 'المنصور', 'الكرادة', 'الأعظمية',
    'زيونة', 'الدورة', 'الكاظمية', 'بغداد الجديدة', 'السيدية',
  ];

  static const categories = <(String, String)>[
    ('المتاجر','🏪'), ('الخدمات','🛠️'), ('المولات','🏬'),
    ('العروض','🏷️'), ('موبايلات','📱'), ('ملابس','👕'),
    ('أجهزة منزلية','🧺'), ('مطاعم','🍔'), ('صيدليات','💊'),
    ('مواد غذائية','🛒'), ('قطع غيار','⚙️'), ('المزيد','•••')
  ];

  List<Store> get filtered =>
    (MarketplaceBackend.configured ? remoteStores : stores).where((s) {
    return (district == 'كل بغداد' || s.area == district) &&
      (category == 'الكل' || s.type == category) &&
      '${s.name} ${s.area} ${s.type}'.toLowerCase()
        .contains(query.trim().toLowerCase());
  }).toList();

  int get cartCount => cart.values.fold<int>(0, (s, value) => s + value);

  void message(String value) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(value)));
  }

  void add(int index) {
    setState(() => cart[index] = (cart[index] ?? 0) + 1);
    message('انضاف للسلة التجريبية');
  }

  Widget title(String value) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Text(value, style: const TextStyle(
      fontSize: 21, fontWeight: FontWeight.w900)),
  );

  Widget storeTile(Store s) => Card(
    color: Colors.white,
    margin: const EdgeInsets.only(bottom: 9),
    child: ListTile(
      leading: CircleAvatar(
        radius: 26, backgroundColor: const Color(0xFFEAD8FF),
        child: Text(s.emoji, style: const TextStyle(fontSize: 26))),
      title: Text(s.name, style: const TextStyle(fontWeight: FontWeight.w800)),
      subtitle: Text(s.isDemo
        ? '${s.area} • ${s.type} • بيانات تجريبية'
        : '${s.area} • ${s.type} • متجر منشور'),
      trailing: const Icon(Icons.chevron_left, color: purple),
      onTap: () => Navigator.push(context, MaterialPageRoute<void>(
        builder: (_) => s.id != null
          ? LiveStorePage(storeId: s.id!, name: s.name, area: s.area)
          : StorePage(store: s))),
    ),
  );

  Widget coloredHeader() => Container(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 22),
    decoration: const BoxDecoration(
      gradient: LinearGradient(colors: [darkPurple, purple, Color(0xFF8626B9)]),
      borderRadius: BorderRadius.vertical(bottom: Radius.circular(26))),
    child: Column(children: [
      Row(children: [
        const Icon(Icons.shopping_bag_rounded, color: orange, size: 40),
        const SizedBox(width: 7),
        const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('شتريد؟', style: TextStyle(color: Colors.white,
            fontSize: 24, fontWeight: FontWeight.w900)),
          Text('موجود!', style: TextStyle(color: orange,
            fontSize: 16, fontWeight: FontWeight.w900)),
        ]),
        const Spacer(),
        PopupMenuButton<String>(
          icon: const Icon(Icons.location_on, color: Colors.white),
          tooltip: 'اختيار منطقة بغداد',
          onSelected: (value) => setState(() => district = value),
          itemBuilder: (_) => [
            for (final d in districts) PopupMenuItem(value: d, child: Text(d))
          ],
        ),
        Flexible(child: Text(district, maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Colors.white))),
      ]),
      const SizedBox(height: 15),
      TextField(
        onChanged: (v) => setState(() => query = v),
        onTap: () => setState(() => tab = 1),
        decoration: InputDecoration(
          hintText: 'شتريد اليوم؟ ابحث عن متجر أو منتج',
          hintStyle: const TextStyle(fontSize: 13),
          filled: true, fillColor: Colors.white,
          prefixIcon: const Icon(Icons.search, color: purple),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(28),
            borderSide: BorderSide.none),
        ),
      ),
    ]),
  );

  Widget categoryTile((String, String) c) => InkWell(
    onTap: () {
      setState(() {
        tab = 1;
        category = ['المتاجر','العروض','الخدمات','المزيد','قطع غيار']
          .contains(c.$1) ? 'الكل' : c.$1;
      });
    },
    child: Container(
      width: 82, constraints: const BoxConstraints(minHeight: 92),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.white, borderRadius: BorderRadius.circular(16)),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Text(c.$2, style: const TextStyle(fontSize: 28)),
        const SizedBox(height: 8),
        Text(c.$1, textAlign: TextAlign.center, maxLines: 2,
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
      ]),
    ),
  );

  Widget home() => ListView(children: [
    coloredHeader(),
    Padding(padding: const EdgeInsets.all(14), child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Wrap(alignment: WrapAlignment.spaceBetween, spacing: 6, runSpacing: 8,
          children: [for (final c in categories) categoryTile(c)]),
        const SizedBox(height: 13),
        InkWell(
          onTap: () => setState(() => tab = 2),
          borderRadius: BorderRadius.circular(17),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
            decoration: BoxDecoration(
              color: const Color(0xFFF0E1FF),
              borderRadius: BorderRadius.circular(17),
            ),
            child: const Row(children: [
              Icon(Icons.map_rounded, color: purple, size: 31),
              SizedBox(width: 12),
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('استكشف محلات بغداد على الخريطة',
                    style: TextStyle(color: darkPurple,
                      fontWeight: FontWeight.w900, fontSize: 14)),
                  Text('الموقع اختياري • الاتجاهات عبر خرائط Google',
                    style: TextStyle(fontSize: 11, color: Colors.black54)),
                ],
              )),
              Icon(Icons.chevron_left, color: purple),
            ]),
          ),
        ),
        const SizedBox(height: 17),
        Container(
          height: 130, padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            gradient: const LinearGradient(colors: [
              Color(0xFFE85FAD), orange, purple])),
          child: const Row(children: [
            Icon(Icons.local_offer, size: 55, color: Colors.white),
            SizedBox(width: 18),
            Expanded(child: Text('أحدث العروض\nفي بغداد',
              style: TextStyle(color: Colors.white,
                fontWeight: FontWeight.w900, fontSize: 22))),
          ]),
        ),
        const SizedBox(height: 22),
        title(MarketplaceBackend.configured
          ? 'منتجات منشورة' : 'منتجات تجريبية'),
        if (MarketplaceBackend.configured)
          SizedBox(
            height: 205,
            child: remoteProducts.isEmpty
              ? Center(child: Text(remoteLoading
                  ? 'جاري تحميل المنتجات...'
                  : 'ماكو منتجات منشورة بعد. أول ما يسجل أصحاب المتاجر تظهر هنا.'))
              : ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    for (final p in remoteProducts)
                      Container(
                        width: 158,
                        margin: const EdgeInsets.only(left: 10),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20)),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const Icon(Icons.inventory_2_outlined,
                              size: 49, color: purple),
                            const SizedBox(height: 10),
                            Text(p.name, maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold)),
                            const SizedBox(height: 10),
                            Text(dinars(p.priceIqd),
                              style: const TextStyle(color: purple,
                                fontWeight: FontWeight.w800)),
                            const Spacer(),
                            FilledButton.tonal(
                              onPressed: p.stockQuantity < 1 ? null : () {
                                final added = CommerceCart.instance.add(p);
                                if (added) setState(() {});
                                message(added
                                  ? 'انضافت السلعة للسلة'
                                  : 'السلة لمتجر واحد أو المخزون انتهى.');
                              },
                              child: const Text('+ للسلة'),
                            ),
                          ]),
                      ),
                  ],
                ),
          ),
        if (!MarketplaceBackend.configured)
          SizedBox(height: 258, child: ListView(
          scrollDirection: Axis.horizontal,
          children: [
            for (var i = 0; i < products.length; i++)
              Container(width: 150,
                margin: const EdgeInsets.only(left: 10),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: Colors.white,
                  borderRadius: BorderRadius.circular(20)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Text(products[i].emoji,
                      style: const TextStyle(fontSize: 46),
                      textAlign: TextAlign.center),
                    const SizedBox(height: 10),
                    Text(products[i].title, maxLines: 2,
                      style: const TextStyle(fontSize: 12,
                        fontWeight: FontWeight.bold)),
                    const SizedBox(height: 7),
                    Text(dinars(products[i].price),
                      style: const TextStyle(color: purple,
                        fontWeight: FontWeight.bold)),
                    const Spacer(),
                    FilledButton.tonal(onPressed: () => add(i),
                      child: const Text('+ للسلة')),
                  ]),
              ),
          ],
        )),
        const SizedBox(height: 21),
        title('متاجر من مناطق بغداد'),
        if (remoteLoading) const Center(child: CircularProgressIndicator()),
        if (remoteError != null)
          Text(remoteError!, style: const TextStyle(color: Colors.red)),
        for (final s in filtered.take(5)) storeTile(s),
        if (filtered.isEmpty && !remoteLoading && remoteError == null)
          Text(MarketplaceBackend.configured
            ? 'ماكو متاجر منشورة بهالمنطقة لحد الآن'
            : 'ماكو نتائج تجريبية مطابقة'),
        if (MarketplaceBackend.configured)
          OutlinedButton.icon(
            onPressed: _loadRealStores,
            icon: const Icon(Icons.refresh),
            label: const Text('تحديث المحلات'),
          ),
        OutlinedButton(onPressed: () => setState(() => tab = 1),
          child: const Text('استكشف كل المحلات')),
        const Padding(
          padding: EdgeInsets.only(top: 8),
          child: Text('العروض الحالية للتصميم والتجربة فقط. '
            'الشراء المباشر ما زال قيد التطوير.',
            style: TextStyle(fontSize: 12, color: Colors.black54)),
        ),
      ]),
    ),
  ]);

  Widget searchPage() => ListView(
    padding: const EdgeInsets.all(15),
    children: [
      title('دور على أي متجر في بغداد'),
      TextField(
        onChanged: (v) => setState(() => query = v),
        decoration: const InputDecoration(
          filled: true, fillColor: Colors.white,
          prefixIcon: Icon(Icons.search), labelText: 'محل، خدمة أو منطقة',
          border: OutlineInputBorder()),
      ),
      const SizedBox(height: 12),
      Wrap(spacing: 6, runSpacing: 5, children: [
        for (final d in districts)
          ChoiceChip(label: Text(d), selected: district == d,
            onSelected: (_) => setState(() => district = d)),
      ]),
      const SizedBox(height: 18),
      title('النتائج: ${filtered.length}'),
      if (remoteLoading) const Center(child: CircularProgressIndicator()),
      if (remoteError != null)
        Text(remoteError!, style: const TextStyle(color: Colors.red)),
      for (final s in filtered) storeTile(s),
      if (filtered.isEmpty && !remoteLoading && remoteError == null)
        Text(MarketplaceBackend.configured
          ? 'ماكو متاجر منشورة مطابقة حالياً'
          : 'لا توجد نتائج تجريبية مطابقة'),
      const SizedBox(height: 20),
      InkWell(
      onTap: () => setState(() => tab = 2),
      borderRadius: BorderRadius.circular(20),
      child: Container(padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(color: const Color(0xFFEEDFFF),
          borderRadius: BorderRadius.circular(20)),
        child: const Column(children: [
          Icon(Icons.map_outlined, size: 52, color: purple),
          SizedBox(height: 9),
          Text('خريطة محلات بغداد',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
          Text('استكشف المحلات المعتمدة ومواقعها. '
            'موقعك ينطلب فقط بعد موافقتك.',
            textAlign: TextAlign.center),
        ]),
      )),
    ],
  );

  Widget cartPage() {
    var total = 0;
    for (final e in cart.entries) {
      total += products[e.key].price * e.value;
    }
    return ListView(padding: const EdgeInsets.all(15), children: [
      title('سلتي'),
      if (cart.isEmpty)
        const Padding(padding: EdgeInsets.all(30),
          child: Center(child: Text('السلة فارغة حالياً 🛒'))),
      for (final e in cart.entries)
        Card(child: ListTile(
          leading: Text(products[e.key].emoji,
            style: const TextStyle(fontSize: 28)),
          title: Text(products[e.key].title),
          subtitle: Text(dinars(products[e.key].price)),
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            IconButton(icon: const Icon(Icons.remove_circle_outline),
              onPressed: () => setState(() {
                final n = (cart[e.key] ?? 0) - 1;
                if (n < 1) {
                  cart.remove(e.key);
                } else {
                  cart[e.key] = n;
                }
              })),
            Text('${e.value}'),
            IconButton(icon: const Icon(Icons.add_circle_outline),
              onPressed: () => add(e.key)),
          ]),
        )),
      const SizedBox(height: 12),
      Text('المجموع التجريبي: ${dinars(total)}',
        style: const TextStyle(fontSize: 19, fontWeight: FontWeight.bold)),
      const SizedBox(height: 12),
      FilledButton(
        onPressed: cart.isEmpty ? null :
          () => message('هذه سلة تجريبية؛ إرسال الطلبات غير مفعّل بعد'),
        child: const Text('إتمام الطلب (قريباً)')),
    ]);
  }

  Widget profilePage() {
    if (!MarketplaceBackend.configured) {
      return emptyPage('الحساب الحقيقي',
        'تسجيل الدخول جاهز برمجياً، لكنه يحتاج ربط Supabase '
        'بمشروع مستقل قبل ما نفعّله على نسختك.',
        Icons.lock_outline);
    }
    final user = MarketplaceBackend.currentUser;
    if (user == null) {
      return Center(child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.account_circle_outlined, size: 75, color: purple),
          const SizedBox(height: 15),
          const Text('سجّل حتى تحفظ حسابك',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 14),
          FilledButton(
            onPressed: () async {
              await Navigator.of(context).push<bool>(
                MaterialPageRoute(builder: (_) => const CustomerAuthPage()));
              if (mounted) setState(() {});
            },
            child: const Text('دخول / إنشاء حساب'),
          ),
        ],
      ));
    }
    return ListView(padding: const EdgeInsets.all(20), children: [
      const Icon(Icons.verified_user, color: purple, size: 75),
      const SizedBox(height: 14),
      const Text('حسابك متصل', textAlign: TextAlign.center,
        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 22)),
      const SizedBox(height: 9),
      Text(user.email ?? 'بريد غير متوفر', textAlign: TextAlign.center),
      const SizedBox(height: 20),
      FilledButton.icon(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) =>
            const MerchantDashboardPage())),
        icon: const Icon(Icons.storefront_outlined),
        label: const Text('أنا صاحب متجر — إدارة متجري'),
      ),
      const SizedBox(height: 10),
      OutlinedButton.icon(
        onPressed: () async {
          try {
            await MarketplaceBackend.signOut();
            if (mounted) setState(() {});
          } catch (_) {
            if (mounted) message('تعذّر تسجيل الخروج، حاول مرة ثانية');
          }
        },
        icon: const Icon(Icons.logout),
        label: const Text('تسجيل الخروج'),
      ),
    ]);
  }

  Widget emptyPage(String heading, String detail, IconData icon) => Center(
    child: Padding(padding: const EdgeInsets.all(24), child: Column(
      mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, color: purple, size: 65),
        const SizedBox(height: 12),
        Text(heading, style: const TextStyle(
          fontSize: 24, fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        Text(detail, textAlign: TextAlign.center),
      ]),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final pages = [
      home(),
      searchPage(),
      const BaghdadMapPage(),
      MarketplaceBackend.configured ? const LiveCartPage() : cartPage(),
      MarketplaceBackend.configured
        ? const OrderHistoryPage()
        : emptyPage('طلباتي', 'الطلبات تحتاج ربط قاعدة البيانات.',
          Icons.receipt_long_outlined),
      profilePage(),
    ];
    return Scaffold(
      appBar: tab == 0 ? null : AppBar(
        title: Text(['الرئيسية','البحث','الخريطة','السلة','الطلبات','حسابي'][tab])),
      body: pages[tab],
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        backgroundColor: Colors.white,
        indicatorColor: const Color(0xFFEEE1FC),
        onDestinationSelected: (value) => setState(() => tab = value),
        destinations: [
          const NavigationDestination(icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home, color: purple), label: 'الرئيسية'),
          const NavigationDestination(icon: Icon(Icons.search), label: 'البحث'),
          const NavigationDestination(
            icon: Icon(Icons.map_outlined),
            selectedIcon: Icon(Icons.map, color: purple),
            label: 'الخريطة'),
          NavigationDestination(icon: const Icon(Icons.shopping_cart_outlined),
            label: MarketplaceBackend.configured
              ? (CommerceCart.instance.count == 0
                ? 'السلة' : 'السلة (${CommerceCart.instance.count})')
              : (cartCount == 0 ? 'السلة' : 'السلة ($cartCount)')),
          const NavigationDestination(icon: Icon(Icons.receipt_long_outlined),
            label: 'الطلبات'),
          const NavigationDestination(icon: Icon(Icons.person_outline),
            label: 'حسابي'),
        ],
      ),
    );
  }
}

class StorePage extends StatelessWidget {
  final Store store;
  const StorePage({super.key, required this.store});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('تفاصيل المتجر')),
    body: ListView(padding: const EdgeInsets.all(17), children: [
      Container(height: 170, alignment: Alignment.center,
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [darkPurple, purple]),
          borderRadius: BorderRadius.circular(20)),
        child: Text(store.emoji, style: const TextStyle(fontSize: 78))),
      const SizedBox(height: 18),
      Text(store.name, style: const TextStyle(
        fontSize: 25, fontWeight: FontWeight.w900)),
      const SizedBox(height: 10),
      Text('بغداد • ${store.area} • ${store.type}'),
      const SizedBox(height: 14),
      Chip(label: Text(store.isDemo
        ? 'متجر تجريبي غير موثق' : 'متجر منشور في شتريد')),
      const SizedBox(height: 17),
      const Text('معلومات المتجر، الصور، أوقات الدوام والتقييمات '
        'راح تنعرض بعد الربط المصرح به والتحقق من البيانات.'),
      const SizedBox(height: 22),
      const Text('المنتجات والأسعار والتوصيل راح يضيفها صاحب المتجر '
        'بعد تأكيد الملكية.'),
      const SizedBox(height: 17),
      FilledButton(onPressed: () =>
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('مطالبة ملكية المتجر قيد التطوير'))),
        child: const Text('هل أنت صاحب هذا المتجر؟')),
    ]),
  );
}
