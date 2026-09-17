import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mirqat/core/extensions/arabic_normalization_tables.dart';
import 'package:mirqat/core/extensions/arabic_text_extensions.dart';
import 'package:mirqat/data/datasources/bundle_asset_reader.dart';
import 'package:mirqat/data/datasources/quran_database.dart';
import 'package:mirqat/data/datasources/quran_db_local_data_source.dart';
import 'package:mirqat/data/datasources/quran_local_data_source.dart';
import 'package:mirqat/data/datasources/quran_pages_local_data_source.dart';
import 'package:mirqat/data/models/ayah.dart';
import 'package:mirqat/data/models/surah.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Guards the switch of `QuranRepository` from the per-surah JSON files to
/// `quran.db`.
///
/// Saved progress is keyed by surah and ayah, so what must not move is the
/// structure those keys point into: which surahs exist and in what order, how
/// many ayahs each has, which page each ayah sits on, and the letters of every
/// ayah. Those fail hard.
///
/// Diacritic encoding is not in that set. The two sources are different
/// KFGQPC releases, each paired with its own font, and they legitimately
/// encode the same marks differently (open tanween, mark order, a space after
/// ۞). Those differences are printed as warnings with codepoints and never
/// fail the test — and neither source is ever edited to make them go away.
///
/// Scope: `surahs.json` is a stub holding exactly [_legacySurahs], so every
/// assertion here covers those five and nothing else. Whole-mushaf counts
/// belong to `quran_database_test.dart`, never to a comparison with the stub.
///
/// Field mapping, stub -> quran.db `surahs`:
///   number -> id, nameAr -> name_ar, nameEn -> name_translit (spelling
///   intentionally not compared: the app takes quran.db's convention),
///   ayahCount -> ayah_count, revelationPlace -> revelation,
///   bismillahMode -> basmala_mode per [_basmalaModeFor].
const List<int> _legacySurahs = <int>[1, 58, 112, 113, 114];

const Map<BismillahMode, String> _basmalaModeFor = <BismillahMode, String>{
  BismillahMode.countedAsAyah1: 'first_ayah',
  BismillahMode.separatePreamble: 'separate',
  BismillahMode.none: 'none',
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  late Directory storageDir;
  late QuranDatabase database;
  late QuranLocalDataSourceImpl legacy;
  late QuranDbLocalDataSource migrated;
  late QuranPagesLocalDataSourceImpl pages;

  setUp(() {
    storageDir = Directory.systemTemp.createTempSync('quran_migration_test');
    database = QuranDatabase(
      factory: databaseFactoryFfi,
      resolveStorageDirectory: () async => storageDir,
    );
    legacy = QuranLocalDataSourceImpl(BundleAssetReader());
    migrated = QuranDbLocalDataSource(
      database: database,
      legacyJsonSource: legacy,
    );
    pages = QuranPagesLocalDataSourceImpl(database);
  });

  tearDown(() {
    if (storageDir.existsSync()) storageDir.deleteSync(recursive: true);
  });

  test('the stub holds exactly the five surahs this test is scoped to', () async {
    expect(
      (await legacy.getSurahs()).map((Surah s) => s.number).toList(),
      _legacySurahs,
    );
  });

  test('the mapping covers every BismillahMode case', () {
    expect(_basmalaModeFor.keys.toSet(), BismillahMode.values.toSet());
  });

  test(
    'ayah count, revelation place and bismillah placement match quran.db',
    () async {
      final Database db = await database.open();

      for (final int number in _legacySurahs) {
        final Surah stub = await legacy.getSurah(number);
        final Map<String, Object?> row = (await db.query(
          'surahs',
          where: 'id = ?',
          whereArgs: <int>[number],
        )).single;

        expect(row['ayah_count'], stub.ayahCount, reason: '$number ayahCount');
        expect(
          row['revelation'],
          stub.revelationPlace.jsonValue,
          reason: '$number revelationPlace',
        );
        expect(
          row['basmala_mode'],
          _basmalaModeFor[stub.bismillahMode],
          reason: '$number bismillahMode ${stub.bismillahMode.jsonValue}',
        );
      }
    },
  );

  test('the migrated source serves the same five, in order', () async {
    final List<Surah> fromDb = await migrated.getSurahs();
    expect(fromDb.map((Surah s) => s.number).toList(), _legacySurahs);

    final Database db = await database.open();
    for (final Surah surah in fromDb) {
      expect(
        surah.nameEn,
        (await db.query(
          'surahs',
          columns: <String>['name_translit'],
          where: 'id = ?',
          whereArgs: <int>[surah.number],
        )).single['name_translit'],
        reason: '${surah.number} nameEn comes from name_translit',
      );
      final Surah stub = await legacy.getSurah(surah.number);
      expect(surah.ayahCount, stub.ayahCount, reason: '${surah.number}');
      expect(surah.revelationPlace, stub.revelationPlace);
      expect(surah.bismillahMode, stub.bismillahMode);
      expect(
        (await migrated.getAyahs(surah.number)).length,
        (await legacy.getAyahs(surah.number)).length,
        reason: '${surah.number} loaded ayah count',
      );
    }
  });

  test('every progress key resolves to a page, in reading order', () async {
    // The JSON source carries no page numbers, so this pins quran.db's pages
    // for exactly the keys saved progress can hold.
    final Database db = await database.open();

    for (final int number in _legacySurahs) {
      final Surah surah = await legacy.getSurah(number);
      final int startPage = (await db.query(
        'surahs',
        columns: <String>['start_page'],
        where: 'id = ?',
        whereArgs: <int>[surah.number],
      )).single['start_page']! as int;

      int previous = 0;
      for (final Ayah ayah in await legacy.getAyahs(surah.number)) {
        final String key = '${surah.number}:${ayah.number}';
        final int page = await pages.pageForAyah(surah.number, ayah.number);

        expect(page, inInclusiveRange(1, 604), reason: '$key page');
        expect(
          page,
          greaterThanOrEqualTo(previous),
          reason: '$key goes back a page',
        );
        if (ayah.number == 1) {
          expect(page, startPage, reason: '$key is not on start_page');
        }
        previous = page;
      }
    }
  });

  test(
    'ayah letters are identical; diacritic encoding differences are warnings',
    () async {
      final List<String> letterMismatches = <String>[];
      final List<String> warnings = <String>[];

      for (final int number in _legacySurahs) {
        final Surah surah = await legacy.getSurah(number);
        final List<Ayah> oldAyahs = await legacy.getAyahs(surah.number);
        final List<Ayah> newAyahs = await migrated.getAyahs(surah.number);

        for (int i = 0; i < oldAyahs.length; i++) {
          final String key = '${surah.number}:${oldAyahs[i].number}';
          final String oldText = oldAyahs[i].text;
          final String newText = newAyahs[i].text;
          if (oldText == newText) continue;

          if (_skeleton(oldText) != _skeleton(newText)) {
            letterMismatches.add('$key\n  json: $oldText\n  db:   $newText');
          } else {
            warnings.add('$key ${_describeDifference(oldText, newText)}');
          }
        }
      }

      if (warnings.isNotEmpty) {
        // ignore: avoid_print
        print(
          'WARNING: ${warnings.length} ayah(s) differ in diacritic encoding '
          'only (letters identical):\n${warnings.join('\n')}',
        );
      }
      if (letterMismatches.isNotEmpty) {
        fail(
          '${letterMismatches.length} ayah(s) differ in their letters:\n'
          '${letterMismatches.join('\n')}',
        );
      }
    },
  );

  test('the letter skeleton ignores encoding, not letters', () {
    // Precomposed alef-madda and alef + combining madda are the same text.
    expect(_skeleton('آ'), _skeleton('آ'));
    // Open and closed tanween are both marks.
    expect(_skeleton('بࣱ'), _skeleton('بٌ'));
    // A different letter is still a different letter.
    expect(_skeleton('ب'), isNot(_skeleton('ت')));
  });

}

/// Letters only: canonically decomposed, then every combining mark, every
/// small high Quranic sign (U+06D6..U+06EC, which includes ۞) and all
/// whitespace removed. Mirrors `skeleton()` in `tool/diff_ayah_text.py`.
String _skeleton(String text) {
  final StringBuffer out = StringBuffer();
  for (final int cp in _decompose(text.toArabicNfc().runes)) {
    if (arabicCcc(cp) != 0) continue;
    if (cp >= 0x06D6 && cp <= 0x06EC) continue;
    if (String.fromCharCode(cp).trim().isEmpty) continue;
    out.writeCharCode(cp);
  }
  return out.toString();
}

Iterable<int> _decompose(Iterable<int> codePoints) sync* {
  for (final int cp in codePoints) {
    final List<int>? parts = arabicCanonicalDecomposition[cp];
    if (parts == null) {
      yield cp;
    } else {
      yield* _decompose(parts);
    }
  }
}

/// Every differing site, as codepoints, from a longest-common-subsequence
/// alignment — so an ayah that differs in three places reports three short
/// sites rather than one span running from the first to the last.
String _describeDifference(String a, String b) {
  final List<int> x = a.runes.toList();
  final List<int> y = b.runes.toList();

  final List<List<int>> lcs = List<List<int>>.generate(
    x.length + 1,
    (_) => List<int>.filled(y.length + 1, 0),
  );
  for (int i = x.length - 1; i >= 0; i--) {
    for (int j = y.length - 1; j >= 0; j--) {
      lcs[i][j] = x[i] == y[j]
          ? lcs[i + 1][j + 1] + 1
          : (lcs[i + 1][j] > lcs[i][j + 1] ? lcs[i + 1][j] : lcs[i][j + 1]);
    }
  }

  String hex(List<int> cps) => cps
      .map((int c) => 'U+${c.toRadixString(16).toUpperCase().padLeft(4, '0')}')
      .join(' ');

  final List<String> sites = <String>[];
  final List<int> onlyX = <int>[];
  final List<int> onlyY = <int>[];
  void flush() {
    if (onlyX.isEmpty && onlyY.isEmpty) return;
    sites.add('json[${hex(onlyX)}] db[${hex(onlyY)}]');
    onlyX.clear();
    onlyY.clear();
  }

  int i = 0;
  int j = 0;
  while (i < x.length || j < y.length) {
    if (i < x.length && j < y.length && x[i] == y[j]) {
      flush();
      i++;
      j++;
    } else if (j < y.length && (i == x.length || lcs[i][j + 1] >= lcs[i + 1][j])) {
      onlyY.add(y[j++]);
    } else {
      onlyX.add(x[i++]);
    }
  }
  flush();
  return sites.join(', ');
}
