import 'package:flutter_test/flutter_test.dart';
import 'package:mirqat/data/datasources/quran_pages_local_data_source.dart';
import 'package:mirqat/data/models/juz_info.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../quran_db_fixtures.dart';

/// The juz a surah begins and ends in, worked out from quran.db's own juz
/// starts — never a table of surahs (CLAUDE.md A.2 rule 2).
void main() {
  late List<JuzInfo> juzs;
  late Map<int, int> ayahCounts;

  setUpAll(() async {
    final RepoQuranDatabase opener = RepoQuranDatabase();
    juzs = await QuranPagesLocalDataSourceImpl(opener).juzList();
    final Database db = await opener.open();
    ayahCounts = <int, int>{
      for (final Map<String, Object?> r in await db.query('surahs'))
        r['id']! as int: r['ayah_count']! as int,
    };
  });

  ({int first, int last}) span(int surah) =>
      juzSpan(juzs, surah, ayahCounts[surah]!)!;

  test('as the mushaf divides them', () {
    expect(span(1), (first: 1, last: 1));
    expect(span(2), (first: 1, last: 3));
    expect(span(3), (first: 3, last: 4));
    expect(span(9), (first: 10, last: 11));
    expect(span(67), (first: 29, last: 29));
    expect(span(114), (first: 30, last: 30));
  });

  test('over all 114, in order, every juz reached and none skipped', () {
    int previousLast = 1;
    final Set<int> reached = <int>{};
    for (int s = 1; s <= 114; s++) {
      final ({int first, int last}) j = span(s);
      expect(j.first, lessThanOrEqualTo(j.last), reason: 'surah $s');
      expect(
        j.first,
        inInclusiveRange(previousLast, previousLast + 1),
        reason: 'surah $s',
      );
      for (int n = j.first; n <= j.last; n++) {
        reached.add(n);
      }
      previousLast = j.last;
    }
    expect(reached, <int>{for (int n = 1; n <= 30; n++) n});
  });

  test('no juz starts known: nothing said', () {
    expect(juzSpan(const <JuzInfo>[], 1, 7), isNull);
  });
}
