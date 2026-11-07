import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:shitreed_customer/backend/marketplace_backend.dart';
import 'package:url_launcher/url_launcher.dart';

const _purple = Color(0xFF51159B);
const _darkPurple = Color(0xFF280B53);
const _orange = Color(0xFFFF811A);
const _baghdad = LatLng(33.3152, 44.3661);
const _mapsEnabled = bool.fromEnvironment('GOOGLE_MAPS_ENABLED',
    defaultValue: false);

class BaghdadMapPage extends StatefulWidget {
  const BaghdadMapPage({super.key});

  @override
  State<BaghdadMapPage> createState() => _BaghdadMapPageState();
}

class _BaghdadMapPageState extends State<BaghdadMapPage> {
  final _search = TextEditingController();
  GoogleMapController? _controller;
  Position? _position;
  List<MarketplaceStore> _stores = [];
  MarketplaceStore? _selected;
  bool _loading = false;
  bool _locating = false;
  String? _error;
  String _area = 'كل بغداد';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _controller?.dispose();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (!MarketplaceBackend.configured) {
      setState(() => _error = 'بيانات المتاجر تتطلب الاتصال بقاعدة شتريد.');
      return;
    }
    setState(() { _loading = true; _error = null; });
    try {
      final result = await MarketplaceBackend.approvedStores();
      if (mounted) setState(() => _stores = result);
    } catch (_) {
      if (mounted) setState(() => _error = 'تعذر تحميل المحلات. تحقق من الإنترنت.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<String> get _areas {
    final areas = _stores.map((s) => s.area).toSet().toList()..sort();
    return ['كل بغداد', ...areas];
  }

  double? _distance(MarketplaceStore s) {
    if (_position == null || s.latitude == null || s.longitude == null) {
      return null;
    }
    return Geolocator.distanceBetween(
      _position!.latitude, _position!.longitude, s.latitude!, s.longitude!,
    );
  }

  List<MarketplaceStore> get _visible {
    final keyword = _search.text.trim().toLowerCase();
    final result = _stores.where((s) {
      return (_area == 'كل بغداد' || s.area == _area) &&
        '${s.name} ${s.area} ${s.category}'
            .toLowerCase().contains(keyword);
    }).toList();
    if (_position != null) {
      result.sort((a, b) => (_distance(a) ?? double.infinity)
          .compareTo(_distance(b) ?? double.infinity));
    }
    return result;
  }

  Set<Marker> get _markers => _visible
      .where((s) => s.latitude != null && s.longitude != null)
      .map((s) => Marker(
        markerId: MarkerId(s.id),
        position: LatLng(s.latitude!, s.longitude!),
        infoWindow: InfoWindow(title: s.name, snippet: s.area),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueViolet),
        onTap: () => setState(() => _selected = s),
      )).toSet();

  void _toast(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _locate() async {
    if (_locating) return;
    setState(() => _locating = true);
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        _toast('فعّل الموقع من إعدادات الهاتف.');
        return;
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        _toast('الموقع اختياري؛ تگدر تبحث بدون مشاركة موقعك.');
        return;
      }
      final p = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 18),
        ),
      );
      if (!mounted) return;
      setState(() => _position = p);
      if (_mapsEnabled && _controller != null) {
        await _controller!.animateCamera(CameraUpdate.newLatLngZoom(
          LatLng(p.latitude, p.longitude), 14,
        ));
      }
      _toast('تم تحديد موقعك لهالجلسة وترتيب المحلات حسب المسافة.');
    } catch (_) {
      _toast('تعذر تحديد الموقع حالياً؛ حاول مرة ثانية.');
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  Future<void> _openUrl(Uri uri) async {
    try {
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        _toast('تعذر فتح خرائط Google على جهازك.');
      }
    } catch (_) {
      _toast('تعذر فتح خرائط Google على جهازك.');
    }
  }

  Future<void> _openBaghdad() => _openUrl(Uri.https(
    'www.google.com', '/maps/search/', {'api':'1', 'query':'بغداد العراق'},
  ));

  Future<void> _directions(MarketplaceStore store) async {
    if (store.latitude == null || store.longitude == null) {
      _toast('صاحب المتجر ما حدد الموقع الدقيق بعد.');
      return;
    }
    await _openUrl(Uri.https('www.google.com', '/maps/dir/', {
      'api': '1',
      'destination': '${store.latitude},${store.longitude}',
      'travelmode': 'driving',
    }));
  }

  Future<void> _focus(MarketplaceStore store) async {
    setState(() => _selected = store);
    if (_mapsEnabled && _controller != null &&
        store.latitude != null && store.longitude != null) {
      await _controller!.animateCamera(CameraUpdate.newLatLngZoom(
        LatLng(store.latitude!, store.longitude!), 15,
      ));
    }
  }

  Widget _header() => Container(
    padding: const EdgeInsets.fromLTRB(16, 18, 16, 22),
    decoration: const BoxDecoration(
      gradient: LinearGradient(colors: [_darkPurple, _purple]),
      borderRadius: BorderRadius.vertical(bottom: Radius.circular(24)),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const Row(children: [
        Icon(Icons.map_rounded, size: 29, color: _orange),
        SizedBox(width: 9),
        Expanded(child: Text('خريطة شتريد • بغداد', style: TextStyle(
          color: Colors.white, fontSize: 21, fontWeight: FontWeight.w900))),
      ]),
      const SizedBox(height: 9),
      const Text('دور على محلات قريبة، واوصل إلها بسهولة',
        style: TextStyle(color: Colors.white70, fontSize: 13)),
      const SizedBox(height: 17),
      TextField(
        controller: _search,
        onChanged: (_) => setState(() => _selected = null),
        decoration: InputDecoration(
          hintText: 'ابحث عن محل أو منطقة أو نوع خدمة',
          prefixIcon: const Icon(Icons.search, color: _purple),
          filled: true, fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide.none),
        ),
      ),
    ]),
  );

  Widget _map() => Container(
    margin: const EdgeInsets.symmetric(horizontal: 14),
    height: 260,
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(color: const Color(0xFFF0E6FC),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: const Color(0xFFD8C7EF))),
    child: _mapsEnabled
      ? GoogleMap(
          initialCameraPosition: const CameraPosition(target: _baghdad, zoom: 11),
          markers: _markers,
          myLocationEnabled: _position != null,
          myLocationButtonEnabled: false,
          zoomControlsEnabled: false,
          mapToolbarEnabled: false,
          onMapCreated: (c) => _controller = c,
          onTap: (_) => setState(() => _selected = null),
        )
      : Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Icon(Icons.map_outlined, size: 62, color: _purple),
          const SizedBox(height: 8),
          const Text('خريطة Google التفاعلية', style: TextStyle(
            fontSize: 18, fontWeight: FontWeight.w900)),
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 8, 20, 12),
            child: Text('واجهة الخرائط جاهزة. العرض داخل التطبيق يحتاج '
                'تفعيل Google Maps API.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Color(0xFF675979))),
          ),
          OutlinedButton.icon(
            onPressed: _openBaghdad,
            icon: const Icon(Icons.open_in_new),
            label: const Text('افتح خريطة بغداد في Google'),
          ),
        ]),
  );

  Widget _storeCard(MarketplaceStore store) {
    final distance = _distance(store);
    final hasPoint = store.latitude != null && store.longitude != null;
    return Card(
      color: Colors.white,
      margin: const EdgeInsets.only(bottom: 9),
      child: Padding(padding: const EdgeInsets.all(10),
        child: Column(children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const CircleAvatar(
              backgroundColor: Color(0xFFF0E2FF),
              child: Icon(Icons.storefront_outlined, color: _purple)),
            title: Text(store.name, style: const TextStyle(
                fontWeight: FontWeight.bold)),
            subtitle: Text('${store.area} • ${store.category}'
              '${distance == null ? '' : ' • ${(distance / 1000).toStringAsFixed(1)} كم'}'),
            trailing: Icon(hasPoint ? Icons.place : Icons.location_off,
              color: hasPoint ? _orange : Colors.grey),
            onTap: () => _focus(store),
          ),
          Row(children: [
            Expanded(child: OutlinedButton.icon(
              onPressed: hasPoint ? () => _focus(store) : null,
              icon: const Icon(Icons.place_outlined, size: 18),
              label: const Text('موقع المحل'))),
            const SizedBox(width: 8),
            Expanded(child: FilledButton.icon(
              onPressed: hasPoint ? () => _directions(store) : null,
              style: FilledButton.styleFrom(backgroundColor: _purple),
              icon: const Icon(Icons.directions, size: 18),
              label: const Text('الاتجاهات'))),
          ]),
          if (!hasPoint) const Text('بانتظار إضافة إحداثيات المحل من صاحبه',
            style: TextStyle(color: Colors.black54, fontSize: 12)),
        ])),
    );
  }

  @override
  Widget build(BuildContext context) {
    final visible = _visible;
    return RefreshIndicator(onRefresh: _load,
      child: ListView(children: [
        _header(),
        const SizedBox(height: 12),
        SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 13),
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            for (final area in _areas) Padding(
              padding: const EdgeInsets.only(left: 7),
              child: ChoiceChip(
                label: Text(area),
                selected: _area == area,
                selectedColor: const Color(0xFFEAD5FF),
                onSelected: (_) => setState(() {
                  _area = area;
                  _selected = null;
                })),
            ),
          ]),
        ),
        const SizedBox(height: 11),
        _map(),
        if (_selected != null) Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
          child: Card(color: const Color(0xFFFFF0E3),
            child: ListTile(
              title: Text(_selected!.name, style: const TextStyle(
                  fontWeight: FontWeight.bold)),
              subtitle: Text(_selected!.area),
              trailing: IconButton(
                tooltip: 'الاتجاهات',
                onPressed: () => _directions(_selected!),
                icon: const Icon(Icons.directions, color: _purple)),
            )),
        ),
        Padding(padding: const EdgeInsets.symmetric(
            horizontal: 14, vertical: 12),
          child: Row(children: [
            Expanded(child: OutlinedButton.icon(
              onPressed: _locating ? null : _locate,
              icon: _locating
                  ? const SizedBox(width: 16, height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.my_location),
              label: const Text('المحلات القريبة مني'))),
            const SizedBox(width: 9),
            IconButton.filledTonal(
              tooltip: 'تحديث المحلات',
              onPressed: _load,
              icon: const Icon(Icons.refresh)),
          ]),
        ),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text('المتاجر المعتمدة (${visible.length})',
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900,
              color: _darkPurple))),
        if (_loading) const Padding(
          padding: EdgeInsets.all(20),
          child: Center(child: CircularProgressIndicator())),
        if (_error != null) Padding(
          padding: const EdgeInsets.all(18),
          child: Text(_error!, textAlign: TextAlign.center)),
        if (!_loading && _error == null && visible.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20, vertical: 30),
            child: Column(children: [
              Icon(Icons.store_mall_directory_outlined, color: _purple,
                size: 48),
              SizedBox(height: 9),
              Text('ماكو متاجر معتمدة بهالمنطقة بعد',
                textAlign: TextAlign.center),
              SizedBox(height: 5),
              Text('تظهر المتاجر بعد تسجيل أصحابها واعتماد معلوماتها.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.black54, fontSize: 12)),
            ])),
        Padding(padding: const EdgeInsets.fromLTRB(13, 8, 13, 22),
          child: Column(children: [
            for (final store in visible) _storeCard(store),
            const Text('الموقع اختياري ولا نطلبه إلا عند الضغط على زر القرب. '
              'معلومات المحلات يقدمها أصحاب المتاجر، '
              'وليست بيانات Google Places بعد.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11, color: Colors.black54)),
          ])),
      ]));
  }
}
