import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mirqat/core/constants/asset_paths.dart';
import 'package:mirqat/data/models/mutashabihat.dart';
import 'package:mirqat/domain/entities/ayah_ref.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../quran_db_fixtures.dart';

/// The shipped mutashabihat file, held to the shipped text: every reference
/// the reader can be shown names an ayah of quran.db and words inside it.
/// tool/build_mutashabihat.py checks the same when it writes the file; this
/// keeps a hand edit, or a quran.db rebuild, from slipping past it.
void main() {
  final File file = File(AssetPaths.mutashabihat);

  test('reads as a full index, with nothing the app would skip', () {
    final Object? json = jsonDecode(file.readAsStringSync());
    final MutashabihatIndex index = MutashabihatIndex.fromJson(json);
    expect(index.isEmpty, isFalse);

    final List<dynamic> phrases =
        (json! as Map<String, dynamic>)['phrases'] as List<dynamic>;
    expect(phrases, hasLength(greaterThan(500)));
    // Every phrase the file holds is one the index kept.
    for (final dynamic p in phrases) {
      final List<dynamic> rows =
          (p as Map<String, dynamic>)['ayahs'] as List<dynamic>;
      final List<dynamic> first = rows.first as List<dynamic>;
      expect(
        index.hasSimilar(AyahRef(first[0] as int, first[1] as int)),
        isTrue,
        reason: 'phrase ${p['id']}',
      );
    }
  });

  test('every reference lies inside its ayah\'s recited words', () async {
    final Database db = await RepoQuranDatabase().open();
    final Map<String, int> words = <String, int>{
      for (final Map<String, Object?> r in await db.rawQuery(
        'SELECT surah, ayah, COUNT(*) AS n FROM words '
        'WHERE is_marker = 0 GROUP BY surah, ayah',
      ))
        '${r['surah']}:${r['ayah']}': r['n']! as int,
    };

    final Map<String, dynamic> json =
        jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    final List<String> wrong = <String>[];
    for (final dynamic p in json['phrases'] as List<dynamic>) {
      for (final dynamic row
          in (p as Map<String, dynamic>)['ayahs'] as List<dynamic>) {
        final List<int> r = (row as List<dynamic>).cast<int>();
        final int? n = words['${r[0]}:${r[1]}'];
        if (n == null || r[2] < 1 || r[2] > r[3] || r[3] > n) {
          wrong.add('phrase ${p['id']}: $r');
        }
      }
    }
    expect(wrong, isEmpty);
  });

  test('the one known error in the source stays left out', () {
    // QUL records "فسيؤتيه أجرا عظيما" in 48:10 as words 23-27; the ayah
    // has 25. See tool/build_mutashabihat.py.
    final Object? json = jsonDecode(file.readAsStringSync());
    final Map<String, dynamic> phrase =
        ((json! as Map<String, dynamic>)['phrases'] as List<dynamic>)
            .cast<Map<String, dynamic>>()
            .singleWhere((Map<String, dynamic> p) => p['id'] == 4970);
    expect(
      (phrase['ayahs'] as List<dynamic>).map(
        (dynamic r) => '${(r as List<dynamic>)[0]}:${r[1]}',
      ),
      isNot(contains('48:10')),
    );
    // The phrase keeps the ayahs QUL had right.
    final MutashabihatIndex index = MutashabihatIndex.fromJson(json);
    expect(
      index.similarTo(const AyahRef(4, 74)).map((SimilarAyah s) => s.ref),
      containsAll(<AyahRef>[const AyahRef(4, 114), const AyahRef(4, 162)]),
    );
  });
}
