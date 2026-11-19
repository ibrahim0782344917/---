import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shitreed_customer/profile/shitreed_profile_page.dart';

void main() {
  testWidgets('profile avatar has Material ancestor even without Scaffold',
      (tester) async {
    var taps = 0;
    await tester.pumpWidget(MaterialApp(
      home: ShitreedAvatarButton(imageUrl: '', onTap: () => taps++),
    ));
    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('profile-avatar-button')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('profile-avatar-button')));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(taps, 1);
  });

  testWidgets('read-only avatar never invokes an upload action',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: ShitreedAvatarButton(imageUrl: '', onTap: null),
    ));
    await tester.tap(find.byKey(const ValueKey('profile-avatar-button')));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
