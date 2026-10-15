import 'package:flutter_test/flutter_test.dart';
import 'package:mirqat/core/search/search_text.dart';
import 'package:sqflite_common/sqlite_api.dart';

import '../quran_db_fixtures.dart';

/// The two halves of search agree.
///
/// `tool/build_quran_data.py` computes `ayahs.text_search` at build time, and
/// `searchableQuery()` transforms what the user types. They implement one set
/// of rules in two languages, and a quiet divergence would make some ayahs
/// unfindable — so this replays the Dart side over the stored text of every
/// ayah in the shipped database and demands the Python side's answer. The
/// stored `text` itself is read, compared, and never altered (CLAUDE.md A.2
/// rule 1: this is a comparison helper under test/, the one place stripping
/// may live beside the build tool).
void main() {
  test('searchableQuery reproduces text_search for every ayah', () async {
    final Database db = await RepoQuranDatabase().open();
    final List<Map<String, Object?>> rows = await db.rawQuery(
      'SELECT surah, ayah, text, text_search FROM ayahs ORDER BY id',
    );
    expect(rows, hasLength(6236));
    for (final Map<String, Object?> row in rows) {
      expect(
        searchableQuery(row['text']! as String),
        row['text_search']! as String,
        reason:
            'Ayah ${row['surah']}:${row['ayah']}: searchableQuery() and the '
            'build tool disagree — their rules must change together.',
      );
    }
  });

  test('a typed query meets the stored key', () async {
    final Database db = await RepoQuranDatabase().open();
    Future<int> hits(String typed) async =>
        (await db.rawQuery(
          'SELECT COUNT(*) AS n FROM ayahs WHERE text_search LIKE ?',
          <Object>['%${searchableQuery(typed)}%'],
        )).single['n']! as int;

    // The rasm writes these with letters nobody types: superscript alef in
    // العالمين and الرحمن, hamza on the line in قرآن.
    expect(await hits('العالمين'), greaterThan(0));
    expect(await hits('الرحمن الرحيم'), greaterThan(0));
    expect(await hits('القرآن'), greaterThan(0));
    expect(await hits('قل هو الله أحد'), greaterThan(0));
    // Taa marbuta typed as ها, alef maksura typed as yeh.
    expect(await hits('الصلوة'), greaterThan(0));
  });

  test('pageNumberQuery reads digits in either script, and only digits', () {
    expect(pageNumberQuery('25'), 25);
    expect(pageNumberQuery(' ٢٥ '), 25);
    expect(pageNumberQuery('۶۰۴'), 604);
    expect(pageNumberQuery('25a'), isNull);
    expect(pageNumberQuery('صفحة 25'), isNull);
    expect(pageNumberQuery(''), isNull);
  });
}
