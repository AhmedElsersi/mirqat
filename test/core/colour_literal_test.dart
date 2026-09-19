import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Assembled at runtime so this file is not itself an occurrence.
/// The lookbehind is what keeps `AppColors.gold` from reading as `Colors.gold`.
final RegExp _literal = RegExp(
  '(?<![A-Za-z])(${<String>['Colo', 'rs'].join()}\\.[A-Za-z]'
  '|${<String>['Colo', 'r'].join()}\\(0x)',
);

const String _tokenFile = 'lib/core/theme/app_colors.dart';

void main() {
  test('colour literals live only in AppColors', () {
    // CLAUDE.md A.3: widgets read colour from Theme.of(context) or from the
    // AppColors tokens. A literal anywhere else is a colour that no contrast
    // test can see and no theme switch can follow.
    final Iterable<File> sources = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where(
          (File f) =>
              f.path.endsWith('.dart') &&
              f.path.replaceAll(r'\', '/') != _tokenFile,
        );

    final List<String> offenders = <String>[];
    for (final File f in sources) {
      final List<String> lines = f.readAsLinesSync();
      for (int i = 0; i < lines.length; i++) {
        final String line = lines[i];
        // Doc comments name tokens freely; only code counts.
        if (line.trimLeft().startsWith('//')) continue;
        if (_literal.hasMatch(line)) {
          offenders.add('${f.path}:${i + 1}: ${line.trim()}');
        }
      }
    }

    expect(offenders, isEmpty, reason: offenders.join('\n'));
  });
}
