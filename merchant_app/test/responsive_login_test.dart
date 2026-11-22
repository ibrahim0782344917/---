// ignore_for_file: prefer_interpolation_to_compose_strings
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shitreed_merchant/main.dart';

void main() {
  for (final size in [
    const Size(320, 640),
    const Size(360, 740),
    const Size(393, 852),
    const Size(600, 960),
    const Size(800, 1200),
  ]) {
    testWidgets('merchant auth fits ' + size.width.toString() +
        'px screen without backend access', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(MaterialApp(
        home: MerchantLoginPage(onSuccess: () {}),
      ));
      await tester.pumpAndSettle();
      expect(find.byType(Scaffold), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
