import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shitreed_customer/alani/alani_design_system.dart';

void main() {
  test('Al-Ani premium design uses consistent accessible Material 3 identity', () {
    final light = AlAniDesignSystem.theme();
    final dark = AlAniDesignSystem.theme(brightness: Brightness.dark);
    expect(light.useMaterial3, isTrue);
    expect(dark.useMaterial3, isTrue);
    expect(light.colorScheme.primary, AlAniDesignSystem.forest);
    expect(light.scaffoldBackgroundColor, AlAniDesignSystem.ivory);
    expect(light.colorScheme.onPrimary, Colors.white);
    expect(dark.colorScheme.brightness, Brightness.dark);
    expect(dark.colorScheme.onPrimary, isNot(Colors.white));
    expect(light.navigationBarTheme.height, 78);
    expect(light.filledButtonTheme.style?.minimumSize?.resolve({}),
      const Size(48, 48));
  });
}
