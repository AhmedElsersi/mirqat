import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/publish_surah.dart';

/// Both of these were real bugs, one after the other, and each one cost a
/// publish: the first published a flag's value as a surah, the second dropped
/// a surah that was asked for. The rule is small enough to state exactly, so
/// it is stated exactly.
void main() {
  group('surahArguments', () {
    test('bare numbers are surahs', () {
      expect(surahArguments(<String>['35', '39', '41']), <int>[35, 39, 41]);
    });

    test('a boolean flag does not swallow the surah after it', () {
      // `--align 35` published nothing at all until this was fixed.
      expect(surahArguments(<String>['--align', '35']), <int>[35]);
      expect(surahArguments(<String>['--dry-run', '3']), <int>[3]);
      expect(surahArguments(<String>['--align', '35', '39', '41', '42']), <int>[
        35,
        39,
        41,
        42,
      ]);
    });

    test("a value flag's value is not a surah", () {
      // `--min-silence 350` used to queue surah 350.
      expect(surahArguments(<String>['--min-silence', '350']), isEmpty);
      expect(surahArguments(<String>['--adopt', '3']), isEmpty);
      expect(surahArguments(<String>['--align-min', '400', '12']), <int>[12]);
    });

    test('every flag read with indexOf is registered as taking a value', () {
      // The set is the only thing telling the parser that `--repair-pack 21`
      // means "repair 21", not "repair, and also publish surah 21". Adding a
      // flag and forgetting the set is the exact mistake that made a repair
      // run process surah 21 twice, and iterating the set cannot catch it —
      // so this reads the source for the flags instead.
      final String source = File('tool/publish_surah.dart').readAsStringSync();
      final Iterable<String> withValues = RegExp(
        r"args\.indexOf\('(--[a-z-]+)'\)",
      ).allMatches(source).map((RegExpMatch m) => m.group(1)!);

      expect(withValues, isNotEmpty);
      for (final String flag in withValues) {
        expect(
          kFlagsTakingAValue,
          contains(flag),
          reason:
              '$flag takes a value but is not in kFlagsTakingAValue, so '
              'its value will be parsed as a surah number',
        );
      }
    });

    test('every value-taking flag is covered', () {
      for (final String flag in kFlagsTakingAValue) {
        expect(
          surahArguments(<String>[flag, '100']),
          isEmpty,
          reason: '$flag leaks its value as a surah number',
        );
      }
    });

    test('a reciter id is not mistaken for a number', () {
      expect(
        surahArguments(<String>['--reciter', 'ahmed_khalil_shaheen', '58']),
        <int>[58],
      );
    });

    test('numbers longer than three digits are not surahs', () {
      expect(surahArguments(<String>['1000']), isEmpty);
    });
  });
}
