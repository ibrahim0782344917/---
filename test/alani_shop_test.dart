import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shitreed_customer/alani/alani_content.dart';
import 'package:shitreed_customer/alani/alani_shop.dart';
import 'package:shitreed_customer/alani/alani_video.dart';
import 'package:shitreed_customer/alani/alani_video_upload.dart';
import 'package:shitreed_customer/alani/alani_reels.dart';

import 'package:shitreed_customer/alani/catalog_filters.dart';
import 'package:shitreed_customer/backend/marketplace_backend.dart';
void main() {
  test('customer catalog sorts by price and stock availability', () {
    final source = [
      const MarketplaceProduct(id:'a',name:'زيت',priceIqd:25000,
        storeId:AlAniSettings.storeId,stockQuantity:2),
      const MarketplaceProduct(id:'b',name:'عسل',priceIqd:20000,
        storeId:AlAniSettings.storeId,stockQuantity:0),
    ];
    final cheap=AlAniCatalogFilters.apply(source,sort:'price_asc');
    expect(cheap.map((p)=>p.id).toList(),['b','a']);
    expect(AlAniCatalogFilters.apply(source,inStockOnly:true).single.id,'a');
    expect(source.first.id,'a');
  });

  test('in-app video accepts direct HTTPS media only', () {
    expect(isDirectMediaUrl(Uri.parse('https://example.org/clip.mp4')), isTrue);
    expect(isDirectMediaUrl(Uri.parse('https://example.org/live.m3u8')), isTrue);
    expect(isDirectMediaUrl(Uri.parse('https://youtube.com/watch?v=abc')), isFalse);
    expect(isDirectMediaUrl(Uri.parse('http://example.org/video.mp4')), isFalse);
  });

  test('gallery upload rejects non-MP4, empty and oversized videos', () {
    expect(AlAniGalleryVideos.validationError('clip.mp4', 20), isNull);
    expect(AlAniGalleryVideos.validationError('clip.MP4', 20), isNull);
    expect(AlAniGalleryVideos.validationError('clip.exe', 20), isNotNull);
    expect(AlAniGalleryVideos.validationError('clip.mp4', 0), isNotNull);
    expect(AlAniGalleryVideos.validationError('clip.mp4',
      AlAniGalleryVideos.maxBytes + 1), isNotNull);
  });

  testWidgets('vertical reels feed shows honest empty state',
      (tester) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(
      body: AlAniReelsPanel(
        publications: Future.value(const <AlAniPublication>[]),
        onRefresh: () async {},
      ),
    )));
    await tester.pumpAndSettle();
    expect(find.text('لا توجد ريلز منشورة حتى الآن.'), findsOneWidget);
  });

  test('store flavor only points to the approved Al-Ani shop', () {
    expect(AlAniSettings.storeId, '25091ca2-c0da-416c-b634-81b188ee66be');
    expect(AlAniSettings.title, 'السيد إبراهيم العاني');
  });

  testWidgets('the herbal storefront shows its branded home and tabs',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: AlAniShopHome()));
    await tester.pumpAndSettle();
    expect(find.text('السيد إبراهيم العاني'), findsOneWidget);
    expect(find.text('من الطبيعة إلى بيتك'), findsOneWidget);

    await tester.tap(find.text('المتجر').last);
    await tester.pumpAndSettle();
    expect(find.text('الزيوت والأعشاب والمنتجات'), findsOneWidget);

    await tester.tap(find.text('وصفاتي').last);
    await tester.pumpAndSettle();
    expect(find.text('الوصفات والمدونة'), findsOneWidget);
  });
}
