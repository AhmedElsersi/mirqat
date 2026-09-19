import 'package:flutter_test/flutter_test.dart';
import 'package:mirqat/data/datasources/quran_pages_local_data_source.dart';
import 'package:mirqat/data/models/juz_info.dart';
import 'package:mirqat/data/models/page_info.dart';

import '../quran_db_fixtures.dart';

/// Read from the real `assets/data/quran.db`: the ajzaa list and what each
/// page's borders say are catalogue facts, and nothing about them is written
/// down in the app (CLAUDE.md A.2 rule 2).
void main() {
  late QuranPagesLocalDataSource pages;

  setUpAll(() => pages = QuranPagesLocalDataSourceImpl(RepoQuranDatabase()));

  test('thirty ajzaa, in order, the first opening the mushaf', () async {
    final List<JuzInfo> ajzaa = await pages.juzList();
    expect(ajzaa.map((JuzInfo j) => j.number), <int>[
      for (int n = 1; n <= 30; n++) n,
    ]);
    expect(ajzaa.first.surahNumber, 1);
    expect(ajzaa.first.ayahNumber, 1);
    expect(ajzaa.first.page, 1);
  });

  test('each juz begins after the one before it', () async {
    final List<JuzInfo> ajzaa = await pages.juzList();
    for (int i = 1; i < ajzaa.length; i++) {
      expect(
        ajzaa[i].page,
        greaterThan(ajzaa[i - 1].page),
        reason: 'juz ${ajzaa[i].number}',
      );
    }
    // Juz 30 opens with An-Naba'.
    expect(ajzaa.last.surahNumber, 78);
    expect(ajzaa.last.ayahNumber, 1);
  });

  test('the juz list is read once and kept', () async {
    expect(identical(await pages.juzList(), await pages.juzList()), isTrue);
  });

  test('a page says where it opens: the first word on it, not the first '
      'ayah to start on it', () async {
    final PageInfo? first = await pages.pageInfo(1);
    expect(first, const PageInfo(surahNumber: 1, juz: 1, hizb: 1));

    // Page 22 is where juz 2 begins.
    final PageInfo? p22 = await pages.pageInfo(22);
    expect(p22?.surahNumber, 2);
    expect(p22?.juz, 2);

    // The last page holds three surahs and opens with the first of them.
    final PageInfo? last = await pages.pageInfo(604);
    expect(last?.surahNumber, 112);
    expect(last?.juz, 30);
    expect(last?.hizb, 60);
  });

  test('a page that does not exist says nothing', () async {
    expect(await pages.pageInfo(9999), isNull);
  });
}
