import 'package:flutter_test/flutter_test.dart';
import 'package:mirqat/core/extensions/arabic_normalization_tables.dart';
import 'package:mirqat/core/extensions/arabic_text_extensions.dart';
import 'package:mirqat/data/datasources/asset_reader.dart';
import 'package:mirqat/data/datasources/quran_local_data_source.dart';
import 'package:mirqat/data/models/ayah.dart';
import 'package:mirqat/data/models/surah.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'quran_db_fixtures.dart';

/// Encoding variance in ayah text, at the loader boundary.
///
/// `quran.db` ships as its source published it — not NFC-ordered, and with
/// tatweel in places — and it is never edited. So the question is not "is the
/// asset clean" but "does the loader level encoding and *only* encoding":
/// an edition that arrives in NFD, or carrying tatweel, must compare equal to
/// what is already loaded, and nothing beyond that may change.
///
/// No Quranic text is written in this file. Every fixture is derived from the
/// shipped rows by a mechanical transform of their *encoding*; the letters,
/// the diacritics and their order are the asset's own.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late RepoQuranDatabase shipped;
  late QuranLocalDataSource loader;
  late List<AyahDbRow> rows;

  setUpAll(() async {
    shipped = RepoQuranDatabase();
    loader = QuranLocalDataSourceImpl(_NoAssets(), shipped);
    final Database db = await shipped.open();
    rows = <AyahDbRow>[
      for (final Map<String, Object?> r in await db.query(
        'ayahs',
        orderBy: 'surah, ayah',
      ))
        AyahDbRow(r['surah']! as int, r['ayah']! as int, r['text']! as String),
    ];
  });

  test('the repair is a levelling, never an edit', () async {
    // Canonical equivalence is the whole allowance: the loaded text must be
    // the stored text with tatweel dropped and marks canonically ordered —
    // not one letter or mark more or less.
    int index = 0;
    for (final Surah surah in await loader.getSurahs()) {
      for (final Ayah ayah in await loader.getAyahs(surah.number)) {
        final AyahDbRow row = rows[index++];
        expect(
          ayah.text,
          row.text.replaceAll('ـ', '').toArabicNfc(),
          reason:
              '${row.surah}:${row.ayah} came back from the loader with more '
              'than an encoding change. The loader levels encoding variance; '
              'it must never change the text.',
        );
      }
    }
    expect(index, rows.length, reason: 'every stored ayah was compared');
  });

  test('loaded text is stable under a second normalisation', () async {
    for (final Surah surah in await loader.getSurahs()) {
      for (final Ayah ayah in await loader.getAyahs(surah.number)) {
        expect(
          ayah.text.isArabicNfc,
          isTrue,
          reason: '${ayah.surahNumber}:${ayah.number}',
        );
        expect(ayah.text.contains('ـ'), isFalse);
      }
    }
  });

  group('what the loader repairs', () {
    test('the stored text loaded in NFD comes back identical', () async {
      await _expectSameAfter(loader, rows, _toNfd);
    });

    test('the NFD fixture is a real one, not an identity transform', () {
      expect(
        rows.where((AyahDbRow r) => _toNfd(r.text) != r.text),
        isNotEmpty,
        reason:
            'no stored ayah changed under decomposition, so the test above '
            'proved nothing. Check the decomposition table.',
      );
    });

    test(
      'the stored text with tatweel injected comes back identical',
      () async {
        await _expectSameAfter(loader, rows, _injectTatweel);
      },
    );

    test('the tatweel fixture actually carries tatweel', () {
      expect(_injectTatweel(rows.first.text).contains('ـ'), isTrue);
    });

    test('both repairs at once still land on the same text', () async {
      await _expectSameAfter(
        loader,
        rows,
        (String s) => _injectTatweel(_toNfd(s)),
      );
    });
  });
}

/// Loads every surah from a copy of the stored rows with each text put
/// through [transform], and expects exactly what the real loader returns.
/// The shipped database is never touched.
Future<void> _expectSameAfter(
  QuranLocalDataSource original,
  List<AyahDbRow> rows,
  String Function(String) transform,
) async {
  final List<Surah> surahs = await original.getSurahs();
  final QuranLocalDataSource patched = QuranLocalDataSourceImpl(
    _NoAssets(),
    FixtureQuranDatabase(
      surahs: <SurahDbRow>[
        for (final Surah s in surahs)
          SurahDbRow(
            id: s.number,
            ayahCount: s.ayahCount,
            nameAr: s.nameAr,
            nameTranslit: s.nameEn,
            revelation: s.revelationPlace.dbValue,
            basmalaMode: s.bismillahMode.dbValue,
          ),
      ],
      ayahs: <AyahDbRow>[
        for (final AyahDbRow r in rows)
          AyahDbRow(r.surah, r.ayah, transform(r.text)),
      ],
    ),
  );

  for (final Surah surah in surahs) {
    expect(
      (await patched.getAyahs(surah.number)).map((Ayah a) => a.text),
      (await original.getAyahs(surah.number)).map((Ayah a) => a.text),
      reason:
          'surah ${surah.number} did not come back equal after an encoding '
          'change. Anything keyed on ayah text would miss across the two.',
    );
  }
}

/// Canonical decomposition — NFD — using the app's own generated table, so a
/// composed character arrives at the loader taken apart.
String _toNfd(String text) {
  final StringBuffer out = StringBuffer();
  for (final int cp in text.runes) {
    final List<int>? parts = arabicCanonicalDecomposition[cp];
    if (parts == null) {
      out.writeCharCode(cp);
    } else {
      for (final int part in parts) {
        out.writeCharCode(part);
      }
    }
  }
  return out.toString();
}

/// Sprinkles U+0640 through the text the way a justified edition does.
///
/// Position is deliberately arbitrary — including between a letter and its
/// mark — because the loader must strip the tatweel *before* it composes, or a
/// mark it separated would fail to rejoin its base.
String _injectTatweel(String text) {
  final StringBuffer out = StringBuffer();
  int i = 0;
  for (final int cp in text.runes) {
    out.writeCharCode(cp);
    if (i.isEven) out.write('ـ');
    i++;
  }
  return out.toString();
}

/// Ayah text never touches the asset bundle any more.
class _NoAssets implements AssetReader {
  @override
  Future<String> loadString(String path) =>
      throw UnimplementedError('no asset read expected: $path');
}
