import 'package:flutter/material.dart';

/// One design language for Al-Ani customers, merchants and staff.
///
/// All visual changes are local: this theme never changes database privileges
/// or enables checkout, payments, Maps billing or publishing.
abstract final class AlAniDesignSystem {
  static const forest = Color(0xFF17583D);
  static const emerald = Color(0xFF12845A);
  static const gold = Color(0xFFC49B45);
  static const ivory = Color(0xFFF7F9F5);
  static const ink = Color(0xFF17372B);
  static const outline = Color(0xFFD8E5DA);

  static ThemeData theme({Brightness brightness = Brightness.light}) {
    final dark = brightness == Brightness.dark;
    final surface = dark ? const Color(0xFF17271F) : Colors.white;
    final background = dark ? const Color(0xFF111C17) : ivory;
    final foreground = dark ? const Color(0xFFF1F6F0) : ink;
    final scheme = ColorScheme.fromSeed(
      seedColor: emerald,
      brightness: brightness,
    ).copyWith(
      primary: dark ? const Color(0xFF91E0B5) : forest,
      onPrimary: dark ? const Color(0xFF082917) : Colors.white,
      secondary: dark ? const Color(0xFFE7C87E) : gold,
      surface: surface,
      onSurface: foreground,
      outline: dark ? const Color(0xFF687B70) : outline,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: background,
      appBarTheme: AppBarTheme(
        backgroundColor: surface,
        foregroundColor: foreground,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontSize: 19,
          fontWeight: FontWeight.w800,
          color: foreground,
        ),
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: scheme.outlineVariant),
          borderRadius: BorderRadius.circular(20),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: scheme.outline),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: surface,
        height: 78,
        indicatorColor: scheme.primaryContainer,
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: surface,
        indicatorColor: scheme.primaryContainer,
        selectedIconTheme: IconThemeData(color: scheme.primary),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(48, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(48, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
      ),
      dividerTheme: DividerThemeData(color: scheme.outlineVariant),
    );
  }
}
