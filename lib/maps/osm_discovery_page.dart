// ignore_for_file: curly_braces_in_flow_control_structures, prefer_interpolation_to_compose_strings
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:shitreed_customer/backend/marketplace_backend.dart';
import 'package:shitreed_customer/maps/osm_discovery_service.dart';
import 'package:url_launcher/url_launcher.dart';

const green = Color(0xFF0C946B);
const dark = Color(0xFF153F32);
const gold = Color(0xFFE7A542);
const baghdad = ll.LatLng(33.3152, 44.3661);
const tileUrl = String.fromEnvironment('SHITREED_TILE_URL');
const demoTiles = bool.fromEnvironment('SHITREED_OSM_DEMO_TILES',
    defaultValue: false);

class OsmDiscoveryPage extends StatefulWidget {
  const OsmDiscoveryPage({super.key});
  @override
  State<OsmDiscoveryPage> createState() => _OsmDiscoveryPageState();
}

class _OsmDiscoveryPageState extends State<OsmDiscoveryPage> {
  final map = MapController();
  final search = TextEditingController();
  ll.LatLng center = baghdad;
  List<MarketplaceStore> merchants = [];
  List<OsmPlace> places = [];
  OsmPlace? selected;
  bool loading = false, discovering = false, locating = false;
  String? error, discoveryError;
  String filter = '';

  bool get tilesReady => demoTiles || tileUrl.startsWith('https://');

  @override
  void initState() { super.initState(); loadMerchants(); }

  @override
  void dispose() {
    search.dispose();
    map.dispose();
    super.dispose();
  }

  Future<void> loadMerchants() async {
    if (!MarketplaceBackend.configured) {
      if (mounted) setState(() =>
        error = 'يلزم ربط تطبيق شتريد بقاعدة Supabase.');
      return;
    }
    setState(() { loading = true; error = null; });
    try {
      final result = await MarketplaceBackend.approvedStores();
      if (mounted) setState(() => merchants = result);
    } catch (_) {
      if (mounted) setState(() =>
        error = 'تعذّر تحميل المتاجر المعتمدة. حاول مجدداً.');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> discover() async {
    if (discovering) return;
    if (!MarketplaceBackend.configured) {
      setState(() => discoveryError = 'يلزم اتصال Supabase بشتريد.');
      return;
    }
    setState(() { discovering = true; discoveryError = null; places = []; });
    try {
      final result = await OsmDiscoveryService.nearby(
        latitude: center.latitude, longitude: center.longitude);
      if (mounted) setState(() => places = result);
    } catch (e) {
      if (mounted) setState(() =>
        discoveryError = OsmDiscoveryService.friendlyError(e));
    } finally {
      if (mounted) setState(() => discovering = false);
    }
  }

  Future<void> locate() async {
    if (locating) return;
    setState(() => locating = true);
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        notify('الموقع مقفّل. تگدر تبحث بدون مشاركة موقعك.');
        return;
      }
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        notify('إذن الموقع اختياري. حرك الخريطة بنفسك.');
        return;
      }
      final p = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 16),
        ),
      );
      if (!mounted) return;
      center = ll.LatLng(p.latitude, p.longitude);
      if (tilesReady) map.move(center, 15);
      notify('تم تحديد الموقع لهالجلسة. اضغط اكتشف المحلات.');
    } catch (_) {
      notify('تعذّر تحديد الموقع. جرّب مرة ثانية.');
    } finally {
      if (mounted) setState(() => locating = false);
    }
  }

  void notify(String text) {
    if (mounted) ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> openOsm(double lat, double lon) async {
    final uri = Uri.https('www.openstreetmap.org', '/', {
      'mlat': lat.toStringAsFixed(6), 'mlon': lon.toStringAsFixed(6),
      'zoom': '17',
    });
    try {
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        notify('تعذّر فتح الخريطة الخارجية.');
      }
    } catch (_) { notify('تعذّر فتح الموقع.'); }
  }

  List<OsmPlace> get found => places.where((p) =>
      (p.name + ' ' + p.address + ' ' + p.category)
      .toLowerCase().contains(filter.toLowerCase())).toList();

  List<MarketplaceStore> get registered => merchants.where((p) =>
      (p.name + ' ' + p.area + ' ' + p.category)
      .toLowerCase().contains(filter.toLowerCase())).toList();

  List<Marker> get pins => [
    for (final p in registered)
      if (p.latitude != null && p.longitude != null)
        Marker(
          point: ll.LatLng(p.latitude!, p.longitude!),
          width: 46, height: 46,
          child: IconButton(
            tooltip: p.name,
            style: IconButton.styleFrom(backgroundColor: Colors.white),
            icon: const Icon(Icons.verified, color: green),
            onPressed: () => openOsm(p.latitude!, p.longitude!),
          ),
        ),
    for (final p in found)
      Marker(
        point: ll.LatLng(p.latitude, p.longitude),
        width: 43, height: 43,
        child: IconButton(
          tooltip: p.name,
          style: IconButton.styleFrom(backgroundColor: Colors.white),
          icon: const Icon(Icons.place, color: gold),
          onPressed: () => setState(() => selected = p),
        ),
      ),
  ];

  Widget showMap() => Container(
    height: 310,
    margin: const EdgeInsets.symmetric(horizontal: 14),
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(
      color: const Color(0xFFE7F2EB),
      borderRadius: BorderRadius.circular(19),
      border: Border.all(color: const Color(0xFFCAE1D3)),
    ),
    child: !tilesReady
        ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.map_outlined, size: 52, color: green),
          const Text('خريطة الإنتاج تحتاج مزود خرائط'),
          const Padding(
            padding: EdgeInsets.all(14),
            child: Text('البحث والمتاجر يعملان بشكل مستقل. '
              'تجهيز صور الخرائط يحتاج مزوداً مستقراً.',
              textAlign: TextAlign.center)),
          TextButton(
            onPressed: () => openOsm(baghdad.latitude, baghdad.longitude),
            child: const Text('فتح خريطة بغداد الخارجية')),
        ]))
        : FlutterMap(
          mapController: map,
          options: MapOptions(
            initialCenter: baghdad,
            initialZoom: 12,
            minZoom: 5, maxZoom: 19,
            onPositionChanged: (camera, gesture) => center = camera.center,
          ),
          children: [
            TileLayer(
              urlTemplate: tileUrl.startsWith('https://') ? tileUrl
                : 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.shitreed.shitreed_customer',
            ),
            MarkerLayer(markers: pins),
            RichAttributionWidget(attributions: [
              TextSourceAttribution('© OpenStreetMap contributors',
                onTap: () => launchUrl(
                  Uri.parse('https://www.openstreetmap.org/copyright'))),
            ]),
          ],
        ),
  );

  void showClaim(OsmPlace place) => showModalBottomSheet<void>(
    context: context, showDragHandle: true,
    builder: (ctx) => Padding(
      padding: const EdgeInsets.all(20),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.verified_user_outlined, size: 40, color: green),
        const SizedBox(height: 12),
        Text('هل أنت صاحب ' + place.name + '؟',
          style: const TextStyle(fontSize: 19,fontWeight: FontWeight.bold)),
        const SizedBox(height: 9),
        const Text('تقدر تسجل محلك من تطبيق شتريد تاجر، '
          'ثم تقدم طلب ملكية من صفحة الحساب. '
          'نشر المنتجات والبيع يحتاج إثبات ملكية وموافقة الإدارة.',
          textAlign: TextAlign.center),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: place.id));
            if (ctx.mounted) Navigator.pop(ctx);
            notify('تم نسخ معرّف المحل. الصقه في شتريد تاجر → حسابي → مطالبة ملكية.');
          },
          icon: const Icon(Icons.copy),
          label: const Text('نسخ معرّف المحل لتطبيق التاجر')),
        FilledButton(onPressed: () => Navigator.pop(ctx),
          child: const Text('إغلاق')),
      ]),
    ),
  );

  Widget placeCard(OsmPlace p) => Card(
    color: Colors.white,
    margin: const EdgeInsets.only(bottom: 9),
    child: Column(children: [
      ListTile(
        leading: const Icon(Icons.place, color: gold),
        title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(p.category + ' • ' + p.address),
        onTap: () {
          setState(() => selected = p);
          if (tilesReady) map.move(ll.LatLng(p.latitude,p.longitude),16);
        },
      ),
      const Text('OpenStreetMap • غير مسجّل للبيع داخل شتريد',
        style: TextStyle(fontSize: 11, color: Colors.black54)),
      Row(children: [
        Expanded(child: TextButton(onPressed: () => showClaim(p),
          child: const Text('هذا محلي'))),
        Expanded(child: OutlinedButton.icon(
          onPressed: () => openOsm(p.latitude,p.longitude),
          icon: const Icon(Icons.directions),
          label: const Text('الموقع'))),
      ]),
    ]),
  );

  Widget merchantCard(MarketplaceStore p) => Card(
    color: Colors.white,
    margin: const EdgeInsets.only(bottom: 9),
    child: ListTile(
      leading: const Icon(Icons.verified, color: green),
      title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.bold)),
      subtitle: Text('تاجر معتمد • ' + p.area + ' • ' + p.category),
      trailing: p.latitude == null || p.longitude == null
          ? const Icon(Icons.location_off)
          : IconButton(
              icon: const Icon(Icons.directions, color: green),
              onPressed: () => openOsm(p.latitude!,p.longitude!)),
    ),
  );

  @override
  Widget build(BuildContext context) => RefreshIndicator(
    onRefresh: loadMerchants,
    child: ListView(children: [
      Container(
        padding: const EdgeInsets.all(18),
        decoration: const BoxDecoration(
          gradient: LinearGradient(colors: [dark,green]),
          borderRadius: BorderRadius.vertical(bottom: Radius.circular(24)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('خريطة محلات العراق',
            style: TextStyle(fontSize: 24, color: Colors.white,
              fontWeight: FontWeight.w900)),
          const SizedBox(height: 7),
          const Text('اكتشف المحلات القريبة وميّز التجار المعتمدين',
            style: TextStyle(color: Colors.white70)),
          const SizedBox(height: 15),
          TextField(
            controller: search,
            onChanged: (x) => setState(() => filter = x),
            decoration: InputDecoration(
              hintText: 'اسم محل أو منطقة أو فئة',
              filled: true, fillColor: Colors.white,
              prefixIcon: const Icon(Icons.search),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none),
            ),
          ),
        ]),
      ),
      const SizedBox(height: 13),
      showMap(),
      if (selected != null) Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: placeCard(selected!)),
      Padding(
        padding: const EdgeInsets.fromLTRB(13, 8, 13, 2),
        child: OutlinedButton.icon(
          onPressed: discovering ? null : discover,
          icon: const Icon(Icons.travel_explore),
          label: Text(discovering
            ? 'جاري البحث...' : 'اكتشف المحلات بهذه المنطقة')),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 13),
        child: Row(children: [
          Expanded(child: FilledButton.tonalIcon(
            onPressed: locating ? null : locate,
            icon: const Icon(Icons.my_location),
            label: const Text('قريب مني'))),
          IconButton.filledTonal(onPressed: loadMerchants,
            icon: const Icon(Icons.refresh),
            tooltip: 'تحديث المتاجر المعتمدة'),
        ])),
      const SizedBox(height: 13),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 15),
        child: Text('محلات OpenStreetMap (' + found.length.toString() + ')',
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold,
            color: dark))),
      if (discoveryError != null) Padding(
        padding: const EdgeInsets.all(15),
        child: Text(discoveryError!, textAlign: TextAlign.center)),
      if (places.isEmpty && !discovering && discoveryError == null)
        const Padding(
          padding: EdgeInsets.all(16),
          child: Text('حرّك الخريطة واضغط اكتشف. '
            'البحث التجريبي محدود وقد تكون بيانات بعض المناطق ناقصة.',
            textAlign: TextAlign.center)),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 13),
        child: Column(children: [
          for (final p in found) placeCard(p),
        ]),
      ),
      const Padding(
        padding: EdgeInsets.symmetric(vertical: 10),
        child: Text('© OpenStreetMap contributors • ODbL',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 11, color: Colors.black54))),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 15),
        child: Text('متاجر شتريد المعتمدة (' +
            registered.length.toString() + ')',
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold,
            color: dark))),
      if (loading) const Center(child: CircularProgressIndicator()),
      if (error != null) Padding(
        padding: const EdgeInsets.all(14),
        child: Text(error!, textAlign: TextAlign.center)),
      Padding(
        padding: const EdgeInsets.fromLTRB(13, 9, 13, 25),
        child: Column(children: [
          for (final m in registered) merchantCard(m),
        ]),
      ),
    ]),
  );
}
