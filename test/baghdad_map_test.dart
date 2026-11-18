import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shitreed_customer/main.dart';

void main() {
  testWidgets('Al-Ani exposes Google Maps without requiring map credentials at startup',
      (tester) async {
    await tester.pumpWidget(const ShitreedApp());
    await tester.pumpAndSettle();

    // The real map screen is kept; no plugin platform view is launched
    // in unit tests because that requires an Android/iOS environment.
    expect(find.byTooltip('خرائط Google'), findsOneWidget);
    expect(find.byIcon(Icons.map_outlined), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);
  });
}
