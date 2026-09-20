import 'package:flutter_test/flutter_test.dart';
import 'package:mirqat/core/state/load_status.dart';
import 'package:mirqat/data/datasources/quran_local_data_source.dart';
import 'package:mirqat/data/datasources/quran_pages_local_data_source.dart';
import 'package:mirqat/data/models/word.dart';
import 'package:mirqat/data/repositories/quran_pages_repository.dart';
import 'package:mirqat/data/repositories/quran_repository.dart';
import 'package:mirqat/features/mushaf/cubit/mushaf_cubit.dart';
import 'package:mirqat/features/mushaf/cubit/mushaf_page.dart';
import 'package:mirqat/features/mushaf/reading_section.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../quran_db_fixtures.dart';

/// One surah, or one juz, read on its own in the mushaf's page layout. Every
/// number here is found in quran.db; none is typed.
void main() {
  late RepoQuranDatabase database;
  late Database db;

  setUpAll(() async {
    database = RepoQuranDatabase();
    db = await database.open();
  });

  Future<int> scalar(
    String sql, [
    List<Object?> args = const <Object?>[],
  ]) async => (await db.rawQuery(sql, args)).single.values.single! as int;

  Future<MushafCubit> open(SectionRequest section) async {
    final MushafCubit cubit = MushafCubit(
      pagesRepository: QuranPagesRepositoryImpl(
        QuranPagesLocalDataSourceImpl(database),
      ),
      quranRepository: QuranRepositoryImpl(
        QuranLocalDataSourceImpl(
          FakeAssetReader(const <String, String>{}),
          database,
        ),
      ),
    );
    addTearDown(cubit.close);
    await cubit.init(section: section);
    expect(cubit.state.status, LoadStatus.ready);
    return cubit;
  }

  /// Every page of the section on show, built.
  Future<List<MushafPage>> pagesOf(MushafCubit cubit) async {
    final List<MushafPage> pages = <MushafPage>[];
    for (int p = cubit.state.firstPage; p <= cubit.state.lastPage; p++) {
      await cubit.ensurePage(p);
      pages.add(cubit.state.pages[p]!);
    }
    return pages;
  }

  Iterable<Word> wordsOf(Iterable<MushafPage> pages) => pages
      .expand((MushafPage p) => p.lines)
      .whereType<AyahLine>()
      .expand((AyahLine l) => l.words)
      .where((Word w) => !w.isMarker);

  group('one surah at a time', () {
    test('every surah shows all of its own words and nobody else\'s', () async {
      final int surahs = await scalar('SELECT COUNT(*) FROM surahs');
      for (int n = 1; n <= surahs; n++) {
        final MushafCubit cubit = await open(SectionRequest.surah(n));
        final List<Word> shown = wordsOf(await pagesOf(cubit)).toList();

        expect(
          shown.every((Word w) => w.surahNumber == n),
          isTrue,
          reason: 'surah $n shows a word of another surah',
        );
        expect(
          shown.length,
          await scalar(
            'SELECT COUNT(*) FROM words WHERE surah = ? AND is_marker = 0',
            <Object?>[n],
          ),
          reason: 'surah $n',
        );
        await cubit.close();
      }
    });

    test('a surah that begins part-way down a page starts at its heading, '
        'and the page is labelled as its own', () async {
      // The second surah to open on some page: found, not named.
      final Map<String, Object?> row = (await db.rawQuery(
        'SELECT l.page AS page, l.surah_number AS surah_number FROM lines l '
        'JOIN ayahs a ON a.surah = l.surah_number AND a.ayah = 1 AND '
        "a.page = l.page WHERE l.line_type = 'surah_name' AND l.line > 1 "
        'ORDER BY l.page LIMIT 1',
      )).single;
      final int surah = row['surah_number']! as int;

      final MushafCubit cubit = await open(SectionRequest.surah(surah));
      final MushafPage first = (await pagesOf(cubit)).first;

      expect(first.number, row['page']);
      expect(first.partial, isTrue);
      expect(first.lines.first, isA<SurahHeaderLine>());
      expect((first.lines.first as SurahHeaderLine).surah.number, surah);
    });

    test('every surah is shown with its heading, even where the heading is '
        'the last line of the page before its first ayah', () async {
      final List<Map<String, Object?>> early = await db.rawQuery(
        'SELECT l.surah_number AS surah, l.page AS page FROM lines l JOIN '
        'ayahs a ON a.surah = l.surah_number AND a.ayah = 1 WHERE '
        "l.line_type = 'surah_name' AND l.page <> a.page",
      );
      expect(early, isNotEmpty, reason: 'the layout has such surahs');

      final int surahs = await scalar('SELECT COUNT(*) FROM surahs');
      for (int n = 1; n <= surahs; n++) {
        final MushafCubit cubit = await open(SectionRequest.surah(n));
        final List<SurahHeaderLine> headings = (await pagesOf(cubit))
            .expand((MushafPage p) => p.lines)
            .whereType<SurahHeaderLine>()
            .toList();
        expect(headings, hasLength(1), reason: 'surah $n');
        expect(headings.single.surah.number, n);
        await cubit.close();
      }

      // Such a surah opens on its first ayah's page, with the heading
      // brought over to the top of it — not on a page bare but for a name.
      final int surah = early.first['surah']! as int;
      final MushafCubit cubit = await open(SectionRequest.surah(surah));
      expect(cubit.state.section!.leadPage, early.first['page']);
      expect(
        cubit.state.firstPage,
        await scalar(
          'SELECT page FROM ayahs WHERE surah = ? AND ayah = 1',
          <Object?>[surah],
        ),
      );
      final MushafPage first = (await pagesOf(cubit)).first;
      expect(first.lines.first, isA<SurahHeaderLine>());
      expect(first.lines.whereType<AyahLine>(), isNotEmpty);
      expect(first.partial, isTrue);
    });

    test('a page shown from part-way down is labelled as the surah on show, '
        'not as the one above it', () async {
      // A surah whose first ayah shares a page with the end of another.
      final Map<String, Object?> row = (await db.rawQuery(
        'SELECT a.surah AS surah FROM ayahs a JOIN ayahs b ON b.page = a.page '
        'AND b.surah = a.surah - 1 WHERE a.ayah = 1 ORDER BY a.surah LIMIT 1',
      )).single;
      final int surah = row['surah']! as int;
      final MushafCubit cubit = await open(SectionRequest.surah(surah));
      final MushafPage page = (await pagesOf(cubit)).firstWhere(
        (MushafPage p) => p.lines.any((PageLine l) => l is AyahLine),
      );
      expect(page.surah?.number, surah);
    });

    test('its basmala comes with it, and only its own', () async {
      final int surah = await scalar(
        "SELECT id FROM surahs WHERE basmala_mode = 'separate' ORDER BY id "
        'LIMIT 1',
      );
      final MushafCubit cubit = await open(SectionRequest.surah(surah));
      final List<PageLine> lines = (await pagesOf(
        cubit,
      )).expand((MushafPage p) => p.lines).toList();

      expect(lines.whereType<SurahHeaderLine>(), hasLength(1));
      expect(lines.whereType<BasmalaLine>(), hasLength(1));
    });

    test('knows the one before and the one after, from the catalog', () async {
      final int surahs = await scalar('SELECT COUNT(*) FROM surahs');
      final ReadingSection first = (await open(
        const SectionRequest.surah(1),
      )).state.section!;
      final ReadingSection last = (await open(
        SectionRequest.surah(surahs),
      )).state.section!;

      expect(first.previous, isNull);
      expect(first.next, const SectionRequest.surah(2));
      expect(last.next, isNull);
      expect(last.previous, SectionRequest.surah(surahs - 1));
    });
  });

  group('one juz at a time', () {
    test('every juz shows exactly its own ayahs, and the thirty of them '
        'leave nothing out', () async {
      final int ajzaa = await scalar('SELECT MAX(juz) FROM ayahs');
      int total = 0;
      AyahRef? previousLast;

      for (int n = 1; n <= ajzaa; n++) {
        final MushafCubit cubit = await open(SectionRequest.juz(n));
        final ReadingSection section = cubit.state.section!;
        final List<MushafPage> pages = await pagesOf(cubit);
        final int own = wordsOf(
          pages,
        ).where((Word w) => section.holds(w.ref)).length;

        expect(
          own,
          await scalar(
            'SELECT COUNT(*) FROM words w JOIN ayahs a ON a.surah = w.surah '
            'AND a.ayah = w.ayah WHERE a.juz = ? AND w.is_marker = 0',
            <Object?>[n],
          ),
          reason: 'juz $n',
        );

        // Each juz takes up exactly where the last one stopped.
        if (previousLast != null) {
          final int gap = await scalar(
            'SELECT COUNT(*) FROM ayahs WHERE (surah > ? OR (surah = ? AND '
            'ayah > ?)) AND (surah < ? OR (surah = ? AND ayah < ?))',
            <Object?>[
              previousLast.surah,
              previousLast.surah,
              previousLast.ayah,
              section.first.surah,
              section.first.surah,
              section.first.ayah,
            ],
          );
          expect(gap, 0, reason: 'between juz ${n - 1} and juz $n');
          expect(section.first > previousLast, isTrue);
        }
        previousLast = section.last;
        total += own;
        await cubit.close();
      }

      expect(
        total,
        await scalar('SELECT COUNT(*) FROM words WHERE is_marker = 0'),
      );
    });

    test('a line shared with the neighbouring juz is shown whole, and only '
        'on the pages where the two meet', () async {
      final int ajzaa = await scalar('SELECT MAX(juz) FROM ayahs');
      for (int n = 1; n <= ajzaa; n++) {
        final MushafCubit cubit = await open(SectionRequest.juz(n));
        final ReadingSection section = cubit.state.section!;
        for (final MushafPage page in await pagesOf(cubit)) {
          for (final AyahLine line in page.lines.whereType<AyahLine>()) {
            // No line is on show without a word of this juz on it.
            expect(
              line.words.any((Word w) => !w.isMarker && section.holds(w.ref)),
              isTrue,
              reason: 'juz $n page ${page.number}',
            );
          }
          final bool borrows = wordsOf(<MushafPage>[
            page,
          ]).any((Word w) => !section.holds(w.ref));
          if (borrows) {
            expect(
              page.number,
              anyOf(section.firstPage, section.lastPage),
              reason: 'juz $n borrows words on an inner page',
            );
          }
        }
        await cubit.close();
      }
    });

    test('the last juz ends where the mushaf does', () async {
      final int ajzaa = await scalar('SELECT MAX(juz) FROM ayahs');
      final ReadingSection last = (await open(
        SectionRequest.juz(ajzaa),
      )).state.section!;
      final int surah = await scalar('SELECT MAX(id) FROM surahs');
      expect(
        last.last,
        AyahRef(
          surah,
          await scalar('SELECT ayah_count FROM surahs WHERE id = ?', <Object?>[
            surah,
          ]),
        ),
      );
      expect(last.next, isNull);
      expect(last.lastPage, await scalar('SELECT MAX(page) FROM lines'));
    });
  });

  group('moving between them', () {
    test('opening the next one replaces the run of pages', () async {
      final MushafCubit cubit = await open(const SectionRequest.surah(2));
      final int epoch = cubit.state.epoch;
      await cubit.ensurePage(cubit.state.lastPage);

      await cubit.openSection(cubit.state.section!.next!);

      expect(cubit.state.section!.number, 3);
      expect(cubit.state.epoch, epoch + 1);
      expect(cubit.state.currentPage, cubit.state.section!.firstPage);
      // Nothing filtered for the old surah survives into the new one.
      expect(
        cubit.state.pages.keys.every(
          (int p) => p >= cubit.state.firstPage && p <= cubit.state.lastPage,
        ),
        isTrue,
      );
      expect(
        wordsOf(cubit.state.pages.values).every((Word w) => w.surahNumber == 3),
        isTrue,
      );
    });

    test(
      'an ayah outside the surah on show opens the surah that holds it',
      () async {
        final MushafCubit cubit = await open(const SectionRequest.surah(112));
        await cubit.goToAyah(113, 2);

        expect(cubit.state.section!.request, const SectionRequest.surah(113));
        expect(cubit.state.section!.holds(const AyahRef(113, 2)), isTrue);
      },
    );

    test(
      'an ayah outside the juz on show opens the juz that holds it',
      () async {
        final MushafCubit cubit = await open(const SectionRequest.juz(1));
        final ReadingSection first = cubit.state.section!;
        // The ayah straight after this juz: by definition the next one's first.
        final Map<String, Object?> row = (await db.rawQuery(
          'SELECT surah, ayah FROM ayahs WHERE juz = 2 ORDER BY id LIMIT 1',
        )).single;
        final AyahRef next = AyahRef(row['surah']! as int, row['ayah']! as int);
        expect(first.holds(next), isFalse);

        await cubit.goToAyah(next.surah, next.ayah);

        expect(cubit.state.section!.request, const SectionRequest.juz(2));
        expect(cubit.state.section!.first, next);
      },
    );

    test('pages outside the one on show are never built', () async {
      final MushafCubit cubit = await open(const SectionRequest.surah(112));
      await cubit.ensurePage(1);
      expect(cubit.state.pages.containsKey(1), isFalse);
    });

    test('the whole mushaf is untouched: no section, every page, no page '
        'partial', () async {
      final MushafCubit cubit = MushafCubit(
        pagesRepository: QuranPagesRepositoryImpl(
          QuranPagesLocalDataSourceImpl(database),
        ),
        quranRepository: QuranRepositoryImpl(
          QuranLocalDataSourceImpl(
            FakeAssetReader(const <String, String>{}),
            database,
          ),
        ),
      );
      addTearDown(cubit.close);
      await cubit.init();
      expect(cubit.state.section, isNull);
      expect(cubit.state.firstPage, 1);
      expect(cubit.state.visiblePageCount, cubit.state.pageCount);
      await cubit.ensurePage(cubit.state.pageCount);
      expect(cubit.state.pages[cubit.state.pageCount]!.partial, isFalse);
    });
  });
}
