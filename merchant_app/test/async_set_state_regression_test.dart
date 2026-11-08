import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('async merchant loaders never return a Future from setState', () {
    final files = <String>[
      'lib/merchant/merchant_dashboard.dart',
      'lib/reports/merchant_reports.dart',
    ];
    final badFutureAssignment = RegExp(
      r'setState\s*\(\s*\(\s*\)\s*=>\s*'
      r'_(?:stores|orders|products|report)\s*=',
      multiLine: true,
    );
    final asyncSetState = RegExp(
      r'setState\s*\(\s*\(\s*\)\s*async\b',
      multiLine: true,
    );

    for (final path in files) {
      final source = File(path).readAsStringSync();
      expect(badFutureAssignment.hasMatch(source), isFalse,
          reason: '$path: setState must not return an async loader Future');
      expect(asyncSetState.hasMatch(source), isFalse,
          reason: '$path: setState callback must never be async');
    }
  });
}
