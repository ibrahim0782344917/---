import 'package:flutter/material.dart';

void main() => runApp(const ShitreedApp());

class ShitreedApp extends StatelessWidget {
  const ShitreedApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'شتريد؟ موجود!',
    theme: ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF5935A9)),
      scaffoldBackgroundColor: const Color(0xFFF8F6FC),
    ),
    home: const Directionality(
      textDirection: TextDirection.rtl,
      child: CustomerHome(),
    ),
  );
}

class Store {
  final String name, area, type;
  const Store(this.name, this.area, this.type);
}

const demoStores = [
  Store('متجر موبايلات تجريبي', 'المنصور', 'إلكترونيات'),
  Store('متجر ملابس تجريبي', 'الغزالية', 'أزياء'),
  Store('متجر منزل تجريبي', 'الكرادة', 'منزل'),
  Store('متجر أغذية تجريبي', 'الأعظمية', 'مواد غذائية'),
];

class CustomerHome extends StatefulWidget {
  const CustomerHome({super.key});
  @override
  State<CustomerHome> createState() => _CustomerHomeState();
}

class _CustomerHomeState extends State<CustomerHome> {
  String query = '';
  String category = 'الكل';
  final categories = ['الكل', 'إلكترونيات', 'أزياء', 'منزل', 'مواد غذائية'];
  @override
  Widget build(BuildContext context) {
    final filtered = demoStores.where((s) =>
      (category == 'الكل' || s.type == category) &&
      ('${s.name} ${s.area} ${s.type}'.contains(query.trim()))).toList();
    return Scaffold(
      appBar: AppBar(title: const Text('شتريد؟ موجود!'), centerTitle: true),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        const Text('شتريد اليوم؟', style: TextStyle(fontSize: 29, fontWeight: FontWeight.bold)),
        const Text('كل بغداد بجيبك • نسخة أولية تجريبية'),
        const SizedBox(height: 18),
        TextField(
          decoration: const InputDecoration(
            hintText: 'دور على محل، منتج أو منطقة',
            prefixIcon: Icon(Icons.search),
            border: OutlineInputBorder(),
          ),
          onChanged: (value) => setState(() => query = value),
        ),
        const SizedBox(height: 14),
        Wrap(spacing: 8, children: [
          for (final c in categories)
            ChoiceChip(label: Text(c), selected: category == c,
              onSelected: (_) => setState(() => category = c)),
        ]),
        const SizedBox(height: 22),
        Text('المتاجر (${filtered.length})', style: Theme.of(context).textTheme.titleLarge),
        for (final store in filtered)
          Card(child: ListTile(
            leading: const CircleAvatar(child: Icon(Icons.store)),
            title: Text(store.name),
            subtitle: Text('${store.area} • ${store.type}'),
            trailing: const Icon(Icons.chevron_left),
            onTap: () => Navigator.push(context, MaterialPageRoute(
              builder: (_) => Directionality(
                textDirection: TextDirection.rtl,
                child: Scaffold(
                  appBar: AppBar(title: Text(store.name)),
                  body: Padding(padding: const EdgeInsets.all(20),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(store.name, style: Theme.of(context).textTheme.headlineSmall),
                      const SizedBox(height: 12),
                      Text('المنطقة: ${store.area}'),
                      Text('القسم: ${store.type}'),
                      const SizedBox(height: 20),
                      const Text('هذا متجر تجريبي. سيتم إضافة بيانات المتاجر الحقيقية بعد الربط المصرح به.'),
                    ])),
                ),
              ),
            )),
          )),
        if (filtered.isEmpty) const Padding(
          padding: EdgeInsets.all(24), child: Text('ماكو نتائج مطابقة')),
        const SizedBox(height: 12),
        const Text('تنبيه: جميع المتاجر المعروضة تجريبية وليست بيانات حقيقية.',
          style: TextStyle(fontSize: 12)),
      ]),
    );
  }
}
