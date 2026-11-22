import 'package:flutter/material.dart';
import 'package:shitreed_customer/alani/alani_content.dart';
import 'package:shitreed_customer/alani/alani_editor.dart';
import 'package:shitreed_customer/alani/alani_video.dart';
import 'package:shitreed_customer/alani/alani_reels.dart';
import 'package:shitreed_customer/alani/alani_product.dart';
import 'package:shitreed_customer/alani/catalog_filters.dart';
import 'package:shitreed_customer/alani/alani_pages.dart';
import 'package:shitreed_customer/alani/alani_cart.dart';
import 'package:shitreed_customer/alani/alani_campaign_banner.dart';
import 'package:shitreed_customer/profile/shitreed_profile_page.dart';
import 'package:shitreed_customer/alani/alani_branch.dart';
import 'package:shitreed_customer/auth/customer_auth_page.dart';
import 'package:shitreed_customer/backend/marketplace_backend.dart';
import 'package:shitreed_customer/commerce/commerce_service.dart';
import 'package:shitreed_customer/commerce/customer_commerce_pages.dart';

import 'package:url_launcher/url_launcher.dart';

const _pine = Color(0xFF01BE5F);
const _deep = Color(0xFF1F1F39);
const _cream = Color(0xFFFFFFFF);
const _gold = Color(0xFFF6A609);

/// Al-Ani's own storefront. The shared Shitreed customer/merchant/admin
/// implementation remains intact in the repository.
class _ProfileAppBar extends StatelessWidget implements PreferredSizeWidget {
  const _ProfileAppBar();
  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
  @override
  Widget build(BuildContext context) => AppBar(
    title: const Text('حسابي وبروفايلي'),
  );
}

class AlAniShopHome extends StatefulWidget {
  const AlAniShopHome({super.key});

  @override
  State<AlAniShopHome> createState() => _AlAniShopHomeState();
}

class _AlAniShopHomeState extends State<AlAniShopHome> {
  int _tab = 0;
  String _query = '';
  String _category = 'الكل';
  String _sort = 'default';
  bool _onlyAvailable = false;
  late Future<List<MarketplaceProduct>> _products;
  late Future<List<AlAniPublication>> _publications;
  late Future<bool> _canEdit;

  @override
  void initState() {
    super.initState();
    _products = AlAniStoreData.products();
    _publications = AlAniStoreData.publications();
    _canEdit = AlAniEditorService.isOwner();
  }

  Future<void> _refresh() async {
    setState(() {
      _products = AlAniStoreData.products();
      _publications = AlAniStoreData.publications();
    });
    try {
      await Future.wait<dynamic>([_products, _publications]);
    } catch (_) {
      // Each FutureBuilder shows its own diagnostic state.
    }
  }

  void _showOrders() {
    Navigator.of(context).push<void>(MaterialPageRoute(
      builder: (_) => const Scaffold(
        appBar: _OrdersAppBar(),
        body: OrderHistoryPage(),
      ),
    ));
  }

  Future<void> _openProfile() async {
    if (MarketplaceBackend.currentUser == null) {
      await Navigator.of(context).push<bool>(MaterialPageRoute(
        builder: (_) => const CustomerAuthPage(),
      ));
    }
    if (!mounted) return;
    if (MarketplaceBackend.currentUser != null) {
      await Navigator.of(context).push<void>(MaterialPageRoute(
        builder: (_) => const Scaffold(
          appBar: _ProfileAppBar(),
          body: ShitreedProfilePage(),
        ),
      ));
    }
    if (mounted) setState(() => _canEdit = AlAniEditorService.isOwner());
  }

  void _add(MarketplaceProduct product) {
    final added = CommerceCart.instance.add(product);
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    messenger.showSnackBar(SnackBar(
      duration: const Duration(seconds: 3),
      content: Text(added
          ? 'تمت إضافة المنتج إلى سلة متجر السيد إبراهيم العاني'
          : 'تعذرت الإضافة: تحقق من المخزون أو أفرغ سلة متجر آخر.'),
      action: added ? SnackBarAction(
        label: 'السلة',
        onPressed: () {
          messenger.removeCurrentSnackBar();
          if (mounted) setState(() => _tab = 4);
        },
      ) : null,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: Theme.of(context).copyWith(
        colorScheme: ColorScheme.fromSeed(seedColor: _pine),
        scaffoldBackgroundColor: _cream,
        appBarTheme: const AppBarTheme(
          backgroundColor: _cream, foregroundColor: _deep, elevation: 0,
        ),
      ),
      child: Scaffold(
        backgroundColor: _cream,
        drawer: const AlAniStoreDrawer(),
        appBar: AppBar(
          titleSpacing: 12,
          title: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(AlAniSettings.title, style: TextStyle(
                fontSize: 18, fontWeight: FontWeight.w900,
              )),
              Text('متجر المنتجات الطبيعية', style: TextStyle(fontSize: 11)),
            ],
          ),
          actions: [
            FutureBuilder<bool>(
              future: _canEdit,
              builder: (context, snapshot) => snapshot.data == true
                ? IconButton(
                    tooltip: 'إدارة الفيديوهات والمدونة',
                    icon: const Icon(Icons.edit_note_outlined),
                    onPressed: () async {
                      await Navigator.of(context).push<void>(MaterialPageRoute(
                        builder: (_) => const AlAniEditorPage(),
                      ));
                      if (mounted) await _refresh();
                    },
                  )
                : const SizedBox.shrink(),
            ),
            IconButton(
              tooltip: 'خرائط Google',
              onPressed: () => Navigator.of(context).push<void>(
                MaterialPageRoute(builder: (_) => const AlAniBranchPage()),
              ),
              icon: const Icon(Icons.map_outlined),
            ),
            IconButton(
              tooltip: 'طلباتي',
              onPressed: _showOrders,
              icon: const Icon(Icons.receipt_long_outlined),
            ),
            IconButton(
              tooltip: 'حسابي والبروفايل',
              onPressed: _openProfile,
              icon: const Icon(Icons.person_outline),
            ),
          ],
        ),
        body: SafeArea(
          child: IndexedStack(index: _tab, children: [
            _home(),
            _catalog(),
            AlAniReelsPanel(publications: _publications, onRefresh: _refresh),
            _contentPanel({'recipe', 'article', 'post'}, 'الوصفات والمدونة'),
            const AlAniCartPage(),
          ]),
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _tab,
          onDestinationSelected: (value) {
            ScaffoldMessenger.of(context).hideCurrentSnackBar();
            setState(() => _tab = value);
          },
          indicatorColor: const Color(0xFFD5E9DD),
          destinations: const [
            NavigationDestination(icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home), label: 'الرئيسية'),
            NavigationDestination(icon: Icon(Icons.storefront_outlined),
              selectedIcon: Icon(Icons.storefront), label: 'المتجر'),
            NavigationDestination(icon: Icon(Icons.play_circle_outline),
              selectedIcon: Icon(Icons.play_circle), label: 'الفيديو'),
            NavigationDestination(icon: Icon(Icons.menu_book_outlined),
              selectedIcon: Icon(Icons.menu_book), label: 'وصفاتي'),
            NavigationDestination(icon: Icon(Icons.shopping_bag_outlined),
              selectedIcon: Icon(Icons.shopping_bag), label: 'السلة'),
          ],
        ),
      ),
    );
  }

  Widget _home() => RefreshIndicator(
    onRefresh: _refresh,
    child: ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 30),
      children: [
        Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [_deep, _pine]),
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.eco_outlined, color: _gold, size: 38),
              const SizedBox(height: 12),
              const Text('من الطبيعة إلى بيتك',
                style: TextStyle(fontWeight: FontWeight.w900,
                    color: Colors.white, fontSize: 26)),
              const SizedBox(height: 7),
              const Text(AlAniSettings.subtitle,
                style: TextStyle(color: Colors.white, height: 1.6)),
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed: () => setState(() => _tab = 1),
                style: FilledButton.styleFrom(
                  backgroundColor: _gold, foregroundColor: _deep,
                ),
                icon: const Icon(Icons.shopping_basket_outlined),
                label: const Text('تسوق منتجاتنا'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        const AlAniCampaignBanner(),
        _heading('تسوق حسب القسم'),
        const SizedBox(height: 10),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            _categoryButton('الزيوت', Icons.water_drop_outlined),
            _categoryButton('الأعشاب', Icons.grass_outlined),
            _categoryButton('العسل', Icons.spa_outlined),
            _categoryButton('العناية', Icons.local_florist_outlined),
          ]),
        ),
        const SizedBox(height: 23),
        _heading('منتجات المتجر', onMore: () => setState(() => _tab = 1)),
        const SizedBox(height: 10),
        _productResults(limit: 4),
        const SizedBox(height: 21),
        _heading('فيديوهات ووصفات', onMore: () => setState(() => _tab = 2)),
        const SizedBox(height: 9),
        _publicationPreview(),
        const SizedBox(height: 12),
        Card(
          child: ListTile(
            leading: const Icon(Icons.local_shipping_outlined, color: _pine),
            title: const Text('الدفع نقداً عند الاستلام'),
            subtitle: const Text('التوصيل ٥٬٠٠٠ د.ع — إرجاع اختياري ٥٬٠٠٠ د.ع'),
            trailing: const Icon(Icons.chevron_left),
            onTap: () => Navigator.push(context, MaterialPageRoute<void>(
              builder: (_) => const AlAniInfoPage(type: 'payments'))),
          ),
        ),
        Card(
          child: ListTile(
            leading: const Icon(Icons.assignment_return_outlined, color: _pine),
            title: const Text('الاسترجاع والتعويض عن الكسر'),
            subtitle: const Text('راجع الشروط وقدّم طلب استرجاع'),
            trailing: const Icon(Icons.chevron_left),
            onTap: () => Navigator.push(context, MaterialPageRoute<void>(
              builder: (_) => const AlAniInfoPage(type: 'returns'))),
          ),
        ),
        const SizedBox(height: 18),
        Card(
          color: Colors.white, elevation: 0,
          child: ListTile(
            leading: const Icon(Icons.place_outlined, color: _pine),
            title: const Text(AlAniSettings.area),
            subtitle: const Text('شاهد موقع المحل والمتاجر على الخرائط'),
            trailing: const Icon(Icons.chevron_left),
            onTap: () => Navigator.of(context).push<void>(
              MaterialPageRoute(builder: (_) => const AlAniBranchPage()),
            ),
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          'المعلومات عن الأعشاب والوصفات للتثقيف ولا تحل محل نصيحة الطبيب.',
          style: TextStyle(color: Colors.black54, fontSize: 11),
          textAlign: TextAlign.center,
        ),
      ],
    ),
  );

  Widget _categoryButton(String label, IconData icon) => Padding(
    padding: const EdgeInsetsDirectional.only(end: 10),
    child: InkWell(
      onTap: () => setState(() {
        _category = label;
        _query = '';
        _tab = 1;
      }),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: 94,
        height: 104,
        padding: const EdgeInsets.all(9),
        decoration: BoxDecoration(
          color: const Color(0xFFF7F7FC),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 34, color: _pine),
            const SizedBox(height: 10),
            Text(label, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12, color: _deep, fontWeight: FontWeight.w700,
              )),
          ],
        ),
      ),
    ),
  );

  Widget _heading(String title, {VoidCallback? onMore}) => Row(
    children: [
      Expanded(child: Text(title, style: const TextStyle(
        color: _deep, fontSize: 19, fontWeight: FontWeight.w900,
      ))),
      if (onMore != null) TextButton(
        onPressed: onMore, child: const Text('عرض الكل'),
      ),
    ],
  );

  Widget _catalog() => RefreshIndicator(
    onRefresh: _refresh,
    child: ListView(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 26),
      children: [
        _heading('الزيوت والأعشاب والمنتجات'),
        const SizedBox(height: 10),
        TextField(
          onChanged: (value) => setState(() => _query = value.trim()),
          decoration: InputDecoration(
            hintText: 'ابحث عن منتج طبيعي...',
            prefixIcon: const Icon(Icons.search),
            filled: true, fillColor: Colors.white,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        const SizedBox(height: 12),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            for (final category in const [
              'الكل', 'الزيوت', 'الأعشاب', 'العسل', 'العناية',
            ]) Padding(
              padding: const EdgeInsets.only(left: 7),
              child: ChoiceChip(
                label: Text(category), selected: _category == category,
                onSelected: (_) => setState(() => _category = category),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: DropdownButtonFormField<String>(
            initialValue: _sort,
            decoration: const InputDecoration(
              labelText: 'ترتيب المنتجات',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            items: const [
              DropdownMenuItem(value: 'default', child: Text('الترتيب الأصلي')),
              DropdownMenuItem(value: 'price_asc', child: Text('السعر: الأقل أولاً')),
              DropdownMenuItem(value: 'price_desc', child: Text('السعر: الأعلى أولاً')),
              DropdownMenuItem(value: 'name', child: Text('حسب الاسم')),
            ],
            onChanged: (value) => setState(() => _sort = value ?? 'default'),
          )),
          const SizedBox(width: 8),
          FilterChip(
            label: const Text('المتوفر فقط'),
            selected: _onlyAvailable,
            onSelected: (value) => setState(() => _onlyAvailable = value),
          ),
        ]),
        const SizedBox(height: 14),
        _productResults(),
      ],
    ),
  );

  bool _categoryMatch(MarketplaceProduct product) {
    if (_category == 'الكل') return true;
    final text = ('${product.name} ${product.description}').toLowerCase();
    switch (_category) {
      case 'الزيوت': return text.contains('زيت') || text.contains('زيوت');
      case 'الأعشاب': return text.contains('عشب') || text.contains('أعشاب');
      case 'العسل': return text.contains('عسل');
      case 'العناية': return text.contains('عناية') || text.contains('صابون');
      default: return true;
    }
  }

  Widget _productResults({int? limit}) {
    return FutureBuilder<List<MarketplaceProduct>>(
      future: _products,
      builder: (context, snapshot) {
        if (!MarketplaceBackend.configured) {
          return _notice('بيانات الاتصال لم تُجهز لهذا البناء بعد.');
        }
        if (snapshot.connectionState != ConnectionState.done) {
          return const Padding(
            padding: EdgeInsets.all(30),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasError) {
          return _notice('تعذّر تحميل منتجات المحل. اسحب للأسفل للمحاولة.');
        }
        var filtered = (snapshot.data ?? []).where((product) =>
          _categoryMatch(product) &&
          (_query.isEmpty || ('${product.name} ${product.description}')
              .toLowerCase().contains(_query.toLowerCase())), 
        ).toList();
        filtered = AlAniCatalogFilters.apply(
          filtered,
          sort: _sort,
          inStockOnly: _onlyAvailable,
        );
        if (limit != null) {
          filtered = filtered.take(limit).toList();
        }
        if (filtered.isEmpty) {
          return _notice(
            'لا توجد منتجات منشورة مطابقة حالياً. '
            'تظهر هنا منتجات السيد إبراهيم العاني المعتمدة فقط.',
          );
        }
        return LayoutBuilder(builder: (context, constraints) {
          final count = constraints.maxWidth > 540 ? 3 : 2;
          return GridView.builder(
            physics: const NeverScrollableScrollPhysics(),
            shrinkWrap: true, itemCount: filtered.length,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: count, mainAxisSpacing: 10,
              crossAxisSpacing: 10, childAspectRatio: 0.69,
            ),
            itemBuilder: (context, i) => _productCard(filtered[i]),
          );
        });
      },
    );
  }

  Widget _productCard(MarketplaceProduct product) => Card(
    color: Colors.white, elevation: 0, clipBehavior: Clip.antiAlias,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(17)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Expanded(child: InkWell(
        onTap: () => Navigator.of(context).push<void>(MaterialPageRoute(
          builder: (_) => AlAniProductDetailsPage(product: product),
        )),
        child: product.imageUrl != null &&
              product.imageUrl!.startsWith('https://')
          ? Image.network(product.imageUrl!, fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => const Icon(
                Icons.eco_outlined, color: _pine, size: 45))
          : const Center(child: Icon(
              Icons.eco_outlined, color: _pine, size: 45)))),
      Padding(
        padding: const EdgeInsets.fromLTRB(9, 8, 9, 2),
        child: Text(product.name, maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w800)),
      ),
      Padding(padding: const EdgeInsets.symmetric(horizontal: 9),
        child: Text(priceText(product.priceIqd),
          style: const TextStyle(color: _pine, fontWeight: FontWeight.w700))),
      Padding(
        padding: const EdgeInsets.fromLTRB(7, 4, 7, 8),
        child: SizedBox(height: 35, child: FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: _pine, padding: EdgeInsets.zero,
          ),
          onPressed: product.stockQuantity > 0 ? () => _add(product) : null,
          icon: const Icon(Icons.add_shopping_cart, size: 15),
          label: Text(product.stockQuantity > 0 ? 'أضف للسلة' : 'نفد المخزون',
              style: const TextStyle(fontSize: 11)),
        )),
      ),
    ]),
  );

  Widget _publicationPreview() => FutureBuilder<List<AlAniPublication>>(
    future: _publications,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return _notice('قسم المحتوى قيد الربط بقاعدة البيانات.');
      }
      if (!snapshot.hasData) {
        return const Padding(padding: EdgeInsets.all(15),
          child: Center(child: CircularProgressIndicator()));
      }
      final items = snapshot.data!;
      if (items.isEmpty) {
        return _notice('ستظهر هنا الفيديوهات والوصفات بعد نشرها من الإدارة.');
      }
      return Column(children: [
        for (final item in items.take(2)) _publicationCard(item),
      ]);
    },
  );

  Widget _contentPanel(Set<String> kinds, String title) => RefreshIndicator(
    onRefresh: _refresh,
    child: ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 30),
      children: [
        _heading(title),
        const SizedBox(height: 9),
        if (kinds.contains('recipe')) const Padding(
          padding: EdgeInsets.only(bottom: 10),
          child: Text('مقالات ووصفات ومنشورات توعوية؛ '
              'يُرجى مراجعة التحذيرات قبل استخدام الأعشاب.'),
        ),
        FutureBuilder<List<AlAniPublication>>(
          future: _publications,
          builder: (context, snapshot) {
            if (!MarketplaceBackend.configured) {
              return _notice('خدمة المقالات غير متصلة بعد.');
            }
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Card(
                color: Colors.white,
                child: Padding(
                  padding: const EdgeInsets.all(22),
                  child: Column(children: [
                    const Icon(Icons.library_books_outlined,
                      size: 48, color: _pine),
                    const SizedBox(height: 12),
                    const Text('المحتوى غير متاح حالياً',
                      style: TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w900)),
                    const SizedBox(height: 10),
                    const Text('تعذّر تحميل المحتوى حالياً. تحقق من اتصال الإنترنت '
                      'أو حاول تحديث الصفحة. المنشورات غير المنشورة '
                      'تبقى خاصة بصاحب المتجر.',
                      textAlign: TextAlign.center,
                      style: TextStyle(height: 1.6)),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: _refresh,
                      icon: const Icon(Icons.refresh_outlined),
                      label: const Text('إعادة المحاولة'),
                    ),
                  ]),
                ),
              );
            }
            final items = (snapshot.data ?? [])
                .where((item) => kinds.contains(item.kind)).toList();
            if (items.isEmpty) {
              return _notice('لم تُنشر مواد في هذا القسم حتى الآن.');
            }
            return Column(children: [
              for (final item in items) _publicationCard(item),
            ]);
          },
        ),
      ],
    ),
  );

  Widget _publicationCard(AlAniPublication item) => Card(
    color: Colors.white, elevation: 0, margin: const EdgeInsets.only(bottom: 9),
    child: ListTile(
      contentPadding: const EdgeInsets.all(12),
      leading: CircleAvatar(
        backgroundColor: const Color(0xFFE5EEE4),
        child: Icon(_kindIcon(item.kind), color: _pine),
      ),
      title: Text(item.title, maxLines: 2, overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.bold)),
      subtitle: Text('${_kindTitle(item.kind)} • ${item.body}',
        maxLines: 2, overflow: TextOverflow.ellipsis),
      trailing: const Icon(Icons.chevron_left),
      onTap: () => Navigator.of(context).push<void>(
        MaterialPageRoute(builder: (_) => AlAniPublicationPage(item: item)),
      ),
    ),
  );

  Widget _notice(String message) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(22),
    decoration: BoxDecoration(
      color: Colors.white, borderRadius: BorderRadius.circular(16),
    ),
    child: Column(children: [
      const Icon(Icons.info_outline, color: _pine, size: 30),
      const SizedBox(height: 8),
      Text(message, textAlign: TextAlign.center,
        style: const TextStyle(color: Colors.black54)),
    ]),
  );
}

class _OrdersAppBar extends StatelessWidget implements PreferredSizeWidget {
  const _OrdersAppBar();
  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
  @override
  Widget build(BuildContext context) =>
      AppBar(title: const Text('حسابي وطلباتي'));
}

IconData _kindIcon(String kind) {
  switch (kind) {
    case 'video': return Icons.play_circle_outline;
    case 'recipe': return Icons.receipt_long_outlined;
    case 'post': return Icons.notes_outlined;
    default: return Icons.article_outlined;
  }
}

String _kindTitle(String kind) {
  switch (kind) {
    case 'video': return 'فيديو';
    case 'recipe': return 'وصفة';
    case 'post': return 'منشور';
    default: return 'مقال';
  }
}

class AlAniPublicationPage extends StatelessWidget {
  final AlAniPublication item;
  const AlAniPublicationPage({super.key, required this.item});

  Future<void> _openVideo(BuildContext context) async {
    final uri = Uri.tryParse(item.videoUrl ?? '');
    if (uri == null || uri.scheme != 'https') {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('رابط الفيديو غير صالح أو غير متوفر.'),
      ));
      return;
    }
    if (isDirectMediaUrl(uri)) {
      await Navigator.of(context).push<void>(MaterialPageRoute(
        builder: (_) => AlAniVideoPage(title: item.title, url: uri),
      ));
      return;
    }
    try {
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!opened && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('تعذر فتح الفيديو.'),
        ));
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('تعذر فتح رابط الفيديو.'),
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(_kindTitle(item.kind))),
    body: ListView(
      padding: const EdgeInsets.all(18),
      children: [
        if (item.imageUrl != null &&
            item.imageUrl!.startsWith('https://')) ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Image.network(item.imageUrl!, height: 200,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => const SizedBox.shrink()),
        ),
        const SizedBox(height: 12),
        Text(item.title, style: const TextStyle(
          fontSize: 24, color: _deep, fontWeight: FontWeight.w900)),
        const SizedBox(height: 14),
        if (item.ingredients.trim().isNotEmpty) ...[
          const Text('المكونات', style: TextStyle(
            color: _pine, fontWeight: FontWeight.w800)),
          SelectableText(item.ingredients),
          const SizedBox(height: 12),
        ],
        SelectableText(item.body, style: const TextStyle(
          fontSize: 16, height: 1.7)),
        if (item.safetyNote.trim().isNotEmpty) ...[
          const SizedBox(height: 20),
          Card(color: const Color(0xFFFFF2DE),
            child: Padding(padding: const EdgeInsets.all(14),
              child: Text('تنبيه: ${item.safetyNote}'))),
        ],
        if (item.kind == 'recipe') const Padding(
          padding: EdgeInsets.only(top: 16),
          child: Text('المحتوى للتثقيف فقط وليس تشخيصاً أو علاجاً طبياً.'),
        ),
        if (item.kind == 'video') Padding(
          padding: const EdgeInsets.only(top: 16),
          child: FilledButton.icon(
            onPressed: () => _openVideo(context),
            icon: const Icon(Icons.play_arrow),
            label: const Text('مشاهدة الفيديو'),
          ),
        ),
      ],
    ),
  );
}
