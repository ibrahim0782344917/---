import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shitreed_customer/alani/alani_content.dart';
import 'package:shitreed_customer/alani/alani_shop.dart';
import 'package:shitreed_customer/alani/alani_video.dart';

void main() {
  test('in-app video accepts direct HTTPS media only', () {
    expect(isDirectMediaUrl(Uri.parse('https://example.org/clip.mp4')), isTrue);
    expect(isDirectMediaUrl(Uri.parse('https://example.org/live.m3u8')), isTrue);
    expect(isDirectMediaUrl(Uri.parse('https://youtube.com/watch?v=abc')), isFalse);
    expect(isDirectMediaUrl(Uri.parse('http://example.org/video.mp4')), isFalse);
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
