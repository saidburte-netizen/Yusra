import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('UI never displays raw exception strings', () {
    final offenders = <String>[];
    final banned = <RegExp>[
      RegExp(r'''\b[ce]\.toString\(\)'''),
      RegExp(r'''\berror\.toString\(\)'''),
      RegExp(r'''\bexception\.toString\(\)'''),
      RegExp(r'''\$e\b'''),
      RegExp(r'''Text\([^)]*\.error!'''),
      RegExp(r'''AppSnackbar\.error\([^)]*\.error!'''),
    ];
    for (final file in Directory('lib').listSync(recursive: true)) {
      if (file is! File || !file.path.endsWith('.dart')) continue;
      final source = file.readAsStringSync();
      final lines = source.split('\n');
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        if (line.trimLeft().startsWith('//')) continue;
        // These are inspections/formatting, not user-facing error rendering.
        if (line.contains('.toString().contains(') ||
            line.contains('map((e) => e.toString())')) {
          continue;
        }
        for (final pattern in banned) {
          if (pattern.hasMatch(line)) {
            offenders.add('${file.path}:${i + 1}: ${line.trim()}');
          }
        }
      }
    }
    expect(offenders, isEmpty,
        reason: 'Raw errors found in:\n${offenders.join('\n')}');
  });
}
