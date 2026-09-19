import 'dart:convert';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mirqat/core/extensions/number_extensions.dart';

const List<String> _localeFiles = <String>[
  'assets/translations/ar.json',
  'assets/translations/en.json',
];

/// Every leaf string in a translation file, keyed by its dotted path.
Map<String, String> _strings(String path) {
  final Object? decoded = jsonDecode(File(path).readAsStringSync());
  final Map<String, String> out = <String, String>{};

  void walk(Object? node, String prefix) {
    if (node is Map<String, dynamic>) {
      node.forEach(
        (String k, Object? v) => walk(v, prefix.isEmpty ? k : '$prefix.$k'),
      );
    } else if (node is String) {
      out[prefix] = node;
    }
  }

  walk(decoded, '');
  return out;
}

bool _isEmoji(int rune) =>
    (rune >= 0x1F300 && rune <= 0x1FAFF) || (rune >= 0x2600 && rune <= 0x27BF);

void main() {
  group('no emoji in any string file', () {
    // docs/BRAND_GUIDE.md §6: no emoji anywhere near an ayah, and every string
    // in this app is near an ayah.
    for (final String path in _localeFiles) {
      test(path, () {
        _strings(path).forEach((String key, String value) {
          final Iterable<int> found = value.runes.where(_isEmoji);
          expect(
            found,
            isEmpty,
            reason:
                '$key contains '
                '${found.map((int r) => 'U+${r.toRadixString(16).toUpperCase()}').join(', ')}',
          );
        });
      });
    }
  });

  test('no streak, no guilt mechanics, anywhere', () {
    // Not a copy preference. Pressuring someone back to worship through
    // loss-aversion is a dark pattern pointed at their relationship with the
    // Quran. If a ticket ever asks for streaks, that is a product decision to
    // escalate — not a feature to add, and not a test to delete.
    final Iterable<File> sources = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((File f) => f.path.endsWith('.dart'));

    for (final File f in <File>[...sources, ...(_localeFiles.map(File.new))]) {
      final String text = f.readAsStringSync().toLowerCase();
      for (final String banned in <String>[
        'streak',
        'انقطعت',
        'consecutiveday',
      ]) {
        expect(
          text.contains(banned),
          isFalse,
          reason: '${f.path} mentions "$banned"',
        );
      }
    }
  });

  test('completion copy is flat', () {
    for (final String path in _localeFiles) {
      _strings(path).forEach((String key, String value) {
        expect(value, isNot(contains('!!')), reason: key);
        expect(
          value,
          isNot(matches(RegExp(r'[A-Z]{4,}'))),
          reason: '$key shouts',
        );
      });
    }
  });

  group('counters use the locale numeral system', () {
    test('Arabic renders Arabic-Indic digits', () {
      Intl.defaultLocale = 'ar';
      expect(3.toLocalisedString(), '٣');
      expect(5.toLocalisedString(), '٥');
      expect(12.toLocalisedString(), '١٢');
    });

    test('English renders Western digits', () {
      Intl.defaultLocale = 'en';
      expect(3.toLocalisedString(), '3');
      expect(12.toLocalisedString(), '12');
      expect(1.5.toLocalisedFixed(2), '1.50');
    });

    tearDown(() => Intl.defaultLocale = null);
  });
}
