import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../text_comparison.dart';

/// The test-only comparison normalizer is hand-rolled (Dart ships no NFC, and `unorm_dart` is not
/// an approved package), so it is checked against Python's `unicodedata`
/// output rather than against hand-written expectations.
/// Regenerate the fixture with `python3 tools/gen_nfc_cases.py`.
void main() {
  test('matches the reference NFC implementation on every fixture case', () {
    final List<dynamic> cases =
        jsonDecode(File('test/fixtures/nfc_cases.json').readAsStringSync())
            as List<dynamic>;

    expect(cases, isNotEmpty);

    int changed = 0;
    for (final dynamic entry in cases) {
      final Map<String, dynamic> c = entry as Map<String, dynamic>;
      final String input = c['in'] as String;
      final String expected = c['out'] as String;
      if (input != expected) changed++;

      expect(
        input.toArabicNfc(),
        expected,
        reason:
            'NFC mismatch for ${_escape(input)}: '
            'expected ${_escape(expected)}, got ${_escape(input.toArabicNfc())}',
      );
    }

    // Guards against a fixture that silently degenerates into identity cases.
    expect(changed, greaterThan(1000));
  });

  test('is idempotent', () {
    final List<dynamic> cases =
        jsonDecode(File('test/fixtures/nfc_cases.json').readAsStringSync())
            as List<dynamic>;

    for (final dynamic entry in cases) {
      final String once = ((entry as Map<String, dynamic>)['in'] as String)
          .toArabicNfc();
      expect(once.toArabicNfc(), once);
    }
  });

  test('isArabicNfc reports the composed form as stable', () {
    const String decomposed = '\u{0627}\u{0653}'; // alef + maddah
    const String composed = '\u{0622}'; // alef with madda above

    expect(decomposed.isArabicNfc, isFalse);
    expect(composed.isArabicNfc, isTrue);
    expect(decomposed.toArabicNfc(), composed);
  });

  test('a mark of equal combining class blocks a later composition', () {
    // Hamza above and maddah both have combining class 230. The hamza reaches
    // the alef first, and the maddah cannot compose past it.
    const String input = '\u{0627}\u{0654}\u{0653}';
    const String expected = '\u{0623}\u{0653}';

    expect(input.toArabicNfc(), expected);
  });

  test('a lower-class mark does not block a higher-class one', () {
    // Kasra is class 32, maddah 230, so the maddah still reaches the alef and
    // the kasra is reordered ahead of it.
    const String input = '\u{0627}\u{0650}\u{0653}';
    const String expected = '\u{0622}\u{0650}';

    expect(input.toArabicNfc(), expected);
  });
}

String _escape(String s) => s.runes
    .map((int r) => 'U+${r.toRadixString(16).toUpperCase().padLeft(4, '0')}')
    .join(' ');
