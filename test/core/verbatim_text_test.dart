import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mirqat/data/datasources/asset_reader.dart';
import 'package:mirqat/data/datasources/quran_local_data_source.dart';
import 'package:mirqat/data/models/ayah.dart';
import 'package:mirqat/data/models/surah.dart';

import '../quran_db_fixtures.dart';
import '../text_comparison.dart';

/// quran.db text reaches the app byte-for-byte.
///
/// In this text U+0640 TATWEEL is often the base a hamza or small yeh sits on.
/// Removing it does not remove the mark — the mark reattaches to the letter
/// beside it, which is a change to the mushaf. So there is no normalization,
/// no stripping and no whitespace fixing anywhere between the database and the
/// renderer; comparison-only stripping lives in `test/text_comparison.dart`.
void main() {
  late QuranLocalDataSource loader;
  late List<AyahDbRow> rows;

  setUpAll(() async {
    final RepoQuranDatabase db = RepoQuranDatabase();
    loader = QuranLocalDataSourceImpl(_NoAssets(), db);
    rows = <AyahDbRow>[
      for (final Map<String, Object?> r in await (await db.open()).query(
        'ayahs',
        orderBy: 'surah, ayah',
      ))
        AyahDbRow(r['surah']! as int, r['ayah']! as int, r['text']! as String),
    ];
  });

  test(
    'every loaded ayah is its stored text, code unit for code unit',
    () async {
      int index = 0;
      for (final Surah surah in await loader.getSurahs()) {
        for (final Ayah ayah in await loader.getAyahs(surah.number)) {
          final AyahDbRow row = rows[index++];
          expect(
            ayah.text.codeUnits,
            row.text.codeUnits,
            reason:
                '${row.surah}:${row.ayah} changed between quran.db and the app',
          );
        }
      }
      expect(index, rows.length);
    },
  );

  test('the tatweel-seated marks are part of what was compared', () {
    // Guards the guard: if the text ever lost its tatweel upstream, the test
    // above would pass without exercising the case it exists for.
    final Iterable<AyahDbRow> seated = rows.where(
      (AyahDbRow r) => r.text.contains('\u0640'),
    );
    expect(seated, isNotEmpty);
    expect(
      seated.where(
        (AyahDbRow r) => RegExp('\u0640[\u0654\u06E7]').hasMatch(r.text),
      ),
      isNotEmpty,
      reason: 'expected a hamza or small yeh seated on a tatweel',
    );
  });

  test('the loader does not normalise, even when it could', () async {
    // Text a normalizer would rewrite — decomposed, marks out of canonical
    // order, a seated hamza — must come back exactly as stored.
    const List<String> texts = <String>[
      '\u0627\u0653', // alef + maddah, not U+0622
      '\u0628\u0651\u064E', // shadda before fatha
      '\u064A\u0640\u0654', // hamza on tatweel
    ];
    final QuranLocalDataSource fixture = QuranLocalDataSourceImpl(
      _NoAssets(),
      FixtureQuranDatabase(
        surahs: const <SurahDbRow>[SurahDbRow(id: 1, ayahCount: 3)],
        ayahs: <AyahDbRow>[
          for (int i = 0; i < texts.length; i++) AyahDbRow(1, i + 1, texts[i]),
        ],
      ),
    );

    final List<Ayah> loaded = await fixture.getAyahs(1);
    for (int i = 0; i < texts.length; i++) {
      expect(loaded[i].text.codeUnits, texts[i].codeUnits);
    }
  });

  test('lib/ holds no text-transform code', () {
    // Structural, like the font enforcement scan: a normalizer or a tatweel
    // strip reachable from lib/ is one call away from the display path.
    final RegExp forbidden = RegExp(
      r'toArabicNfc|isArabicNfc|withoutTatweel|toCanonicalQuranicText|'
      r'skeletonForComparison|arabic_normalization_tables|text_comparison|'
      r'\\u0640|\u0640',
    );
    final List<String> hits = <String>[
      for (final FileSystemEntity f in Directory(
        'lib',
      ).listSync(recursive: true))
        if (f is File && f.path.endsWith('.dart'))
          for (final (int i, String line) in f.readAsLinesSync().indexed)
            if (forbidden.hasMatch(line)) '${f.path}:${i + 1}: ${line.trim()}',
    ];
    expect(hits, isEmpty, reason: hits.join('\n'));
  });

  group('skeletonForComparison', () {
    test('ignores a tatweel seat, mark order and decomposition', () {
      expect(
        skeletonForComparison('\u064A\u0640\u0654'),
        skeletonForComparison('\u064A\u0654'),
      );
      expect(
        skeletonForComparison('\u0628\u0651\u064E'),
        skeletonForComparison('\u0628\u064E\u0651'),
      );
      expect(
        skeletonForComparison('\u0622'),
        skeletonForComparison('\u0627\u0653'),
      );
    });

    test('still tells different letters apart', () {
      expect(
        skeletonForComparison('\u0628'),
        isNot(skeletonForComparison('\u062A')),
      );
    });

    test('is destructive, which is why it never renders', () {
      const String seated = '\u064A\u0640\u0654';
      expect(skeletonForComparison(seated), isNot(seated));
    });
  });
}

class _NoAssets implements AssetReader {
  @override
  Future<String> loadString(String path) =>
      throw UnimplementedError('no asset read expected: $path');
}
