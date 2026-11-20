import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('UI never displays raw exception strings', () {
    final offenders = <String>[];
    for (final file in Directory('lib').listSync(recursive: true)) {
      if (file is! File || !file.path.endsWith('.dart')) continue;
      final source = file.readAsStringSync();
      if (source.contains("AppSnackbar.error(context, '\$e')") ||
          source.contains("_error = '\$e'") ||
          source.contains('(medicinesState.error ?? stockState.error).toString()')) {
        offenders.add(file.path);
      }
    }
    expect(offenders, isEmpty, reason: 'Raw errors found in: ${offenders.join(', ')}');
  });
}
