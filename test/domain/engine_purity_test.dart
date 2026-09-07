import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// CLAUDE.md A.3 requires the engine to be pure Dart so it stays fully
/// unit-testable. A stray `package:flutter` import would compile fine and
/// silently cost that, so it is checked rather than trusted.
void main() {
  test('the domain layer imports no Flutter', () {
    final List<File> sources = <File>[
      ...Directory('lib/domain').listSync(recursive: true).whereType<File>(),
    ].where((File f) => f.path.endsWith('.dart')).toList();

    expect(sources, isNotEmpty, reason: 'no domain sources found');

    final List<String> offenders = <String>[];
    for (final File file in sources) {
      for (final String line in file.readAsLinesSync()) {
        final String trimmed = line.trim();
        if (!trimmed.startsWith('import ') && !trimmed.startsWith('export ')) {
          continue;
        }
        if (trimmed.contains('package:flutter/') ||
            trimmed.contains('package:flutter_')) {
          offenders.add('${file.path}: $trimmed');
        }
      }
    }

    expect(offenders, isEmpty, reason: offenders.join('\n'));
  });

  test('the domain layer reaches into no other layer', () {
    // The engine takes the catalog's ayah count as a plain int rather than
    // importing a data model, so the dependency arrow only ever points inward.
    final List<File> sources = Directory('lib/domain')
        .listSync(recursive: true)
        .whereType<File>()
        .where((File f) => f.path.endsWith('.dart'))
        .toList();

    final List<String> offenders = <String>[];
    for (final File file in sources) {
      for (final String line in file.readAsLinesSync()) {
        final String trimmed = line.trim();
        if (!trimmed.startsWith('import ')) continue;
        if (trimmed.contains('/data/') ||
            trimmed.contains('/features/') ||
            trimmed.contains('/services/')) {
          offenders.add('${file.path}: $trimmed');
        }
      }
    }

    expect(offenders, isEmpty, reason: offenders.join('\n'));
  });
}
