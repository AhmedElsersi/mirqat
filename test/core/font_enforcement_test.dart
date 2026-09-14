import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Both needles are assembled at runtime rather than written out, so this file
/// does not itself become an occurrence and skew its own count.
final String _quranFamily = <String>['Quran', 'Uthmani'].join();
final String _ayahStyle = <String>['AppTextStyles', 'ayah'].join('.');

/// Every tracked source file: Dart under `lib/`, plus the manifest.
List<File> _sourceFiles() {
  final List<File> files = <File>[
    ...Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((File f) => f.path.endsWith('.dart')),
    File('pubspec.yaml'),
  ];
  files.sort((File a, File b) => a.path.compareTo(b.path));
  return files;
}

List<String> _filesContaining(String needle) => _sourceFiles()
    .where((File f) => f.readAsStringSync().contains(needle))
    .map((File f) => f.path.replaceAll(r'\', '/'))
    .toList();

void main() {
  // The failure this guards against is invisible. IBM Plex Sans Arabic
  // contains U+06E1, U+0671 and the rest of the Quranic mark repertoire, so an
  // ayah set in the UI font shows no tofu and throws no error — it renders
  // cleanly with diacritic placement that simply is not the mushaf's. Nobody
  // will catch it by looking at the screen, so it is caught here.

  test('the mushaf family is named in exactly two files', () {
    expect(_filesContaining(_quranFamily), <String>[
      'lib/core/theme/app_text_styles.dart',
      'pubspec.yaml',
    ]);
  });

  test('AyahText is the only file that reaches for the ayah style', () {
    expect(_filesContaining(_ayahStyle), <String>[
      'lib/core/widgets/ayah_text.dart',
    ]);
  });

  test('no AyahText constructor exposes a style or TextStyle escape hatch', () {
    final String source = File(
      'lib/core/widgets/ayah_text.dart',
    ).readAsStringSync();

    // A `style:` or `TextStyle` parameter would let a caller swap the family
    // back to the UI font, which is the exact mistake the widget exists to
    // prevent.
    //
    // Every constructor is checked, not just the unnamed one: `AyahText.flowing`
    // takes a list of ayahs and would be exactly as good a way in. Each
    // declaration is sliced from its name to the `;` that ends it, so an
    // initialiser list (`}) : ayahs = null;`) is covered too — slicing to a
    // literal `});` silently matched nothing once one was added, and a scan
    // that finds nothing passes for the wrong reason.
    final Iterable<Match> constructors = RegExp(
      r'const AyahText(\.\w+)?\(',
    ).allMatches(source);

    expect(
      constructors,
      hasLength(2),
      reason: 'expected the default and flowing constructors; a new one must '
          'be checked here too',
    );

    for (final Match match in constructors) {
      final int end = source.indexOf(';', match.start);
      expect(end, isNot(-1), reason: 'unterminated constructor declaration');
      final String declaration = source.substring(match.start, end);
      expect(
        declaration,
        isNot(contains('style')),
        reason: 'AyahText${match.group(1) ?? ''} takes a style parameter',
      );
    }

    expect(source, isNot(contains('TextStyle? ')));
    expect(source, isNot(contains('this.style')));
  });

  test('no widget outside AyahText renders with the mushaf family', () {
    final Iterable<File> others = _sourceFiles().where(
      (File f) =>
          f.path.endsWith('.dart') &&
          !f.path.replaceAll(r'\', '/').endsWith('core/theme/app_text_styles.dart'),
    );

    for (final File f in others) {
      expect(
        f.readAsStringSync(),
        isNot(contains(_quranFamily)),
        reason: '${f.path} names the mushaf font family directly',
      );
    }
  });
}
