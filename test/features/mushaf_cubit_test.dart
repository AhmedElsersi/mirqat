import 'package:flutter_test/flutter_test.dart';
import 'package:mirqat/core/state/load_status.dart';
import 'package:mirqat/data/datasources/quran_local_data_source.dart';
import 'package:mirqat/data/datasources/quran_pages_local_data_source.dart';
import 'package:mirqat/data/models/word.dart';
import 'package:mirqat/data/repositories/quran_pages_repository.dart';
import 'package:mirqat/data/repositories/quran_repository.dart';
import 'package:mirqat/features/mushaf/cubit/mushaf_cubit.dart';
import 'package:mirqat/features/mushaf/cubit/mushaf_page.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../quran_db_fixtures.dart';

/// The mushaf's pages, built from quran.db and checked against it. No page
/// or surah number is typed here: every case is found in the data.
void main() {
  late RepoQuranDatabase database;
  late Database db;

  setUpAll(() async {
    database = RepoQuranDatabase();
    db = await database.open();
  });

  MushafCubit newCubit() => MushafCubit(
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

  Future<int> scalar(
    String sql, [
    List<Object?> args = const <Object?>[],
  ]) async => (await db.rawQuery(sql, args)).single.values.single! as int;

  Future<MushafCubit> ready() async {
    final MushafCubit cubit = newCubit();
    addTearDown(cubit.close);
    await cubit.init();
    expect(cubit.state.status, LoadStatus.ready);
    return cubit;
  }

  Future<MushafPage> pageOf(MushafCubit cubit, int page) async {
    await cubit.ensurePage(page);
    return cubit.state.pages[page]!;
  }

  test('every page builds, with exactly its lines from the layout', () async {
    final MushafCubit cubit = await ready();
    expect(cubit.state.pageCount, await scalar('SELECT MAX(page) FROM lines'));

    int lines = 0;
    for (int p = 1; p <= cubit.state.pageCount; p++) {
      final MushafPage page = await pageOf(cubit, p);
      expect(
        page.lines,
        hasLength(
          await scalar('SELECT COUNT(*) FROM lines WHERE page = ?', <int>[p]),
        ),
        reason: 'page $p',
      );
      lines += page.lines.length;
    }
    expect(cubit.state.failedPages, isEmpty);
    expect(lines, await scalar('SELECT COUNT(*) FROM lines'));
  });

  test(
    'ayah lines hold their word range, in id order, markers included',
    () async {
      final MushafCubit cubit = await ready();
      final List<Map<String, Object?>> rows = await db.query(
        'lines',
        where: "line_type = 'ayah' AND page = 3",
        orderBy: 'line',
      );
      final List<AyahLine> built = (await pageOf(
        cubit,
        3,
      )).lines.whereType<AyahLine>().toList();

      expect(built, hasLength(rows.length));
      for (int i = 0; i < rows.length; i++) {
        final int first = rows[i]['first_word_id']! as int;
        final int last = rows[i]['last_word_id']! as int;
        expect(built[i].words.map((Word w) => w.id), <int>[
          for (int id = first; id <= last; id++) id,
        ]);
      }
    },
  );

  group('basmala lines, driven by basmala_mode', () {
    Future<int> startPage(String mode) => scalar(
      'SELECT start_page FROM surahs WHERE basmala_mode = ? ORDER BY id LIMIT 1',
      <String>[mode],
    );

    test(
      "'separate': a basmala line of the stored first-ayah basmala",
      () async {
        final MushafCubit cubit = await ready();
        final MushafPage page = await pageOf(
          cubit,
          await startPage('separate'),
        );
        final List<BasmalaLine> basmala = page.lines
            .whereType<BasmalaLine>()
            .toList();
        expect(basmala, isNotEmpty);

        final int source = await scalar(
          "SELECT id FROM surahs WHERE basmala_mode = 'first_ayah'",
        );
        final List<String> stored = <String>[
          for (final Map<String, Object?> r in await db.query(
            'words',
            where: 'surah = ? AND ayah = 1 AND is_marker = 0',
            whereArgs: <int>[source],
            orderBy: 'id',
          ))
            r['text']! as String,
        ];
        expect(
          basmala.first.words.map((Word w) => w.text.codeUnits),
          stored.map((String t) => t.codeUnits),
        );
      },
    );

    test(
      "'first_ayah': no basmala line; ayah 1 is an ordinary ayah line",
      () async {
        final MushafCubit cubit = await ready();
        final int surah = await scalar(
          "SELECT id FROM surahs WHERE basmala_mode = 'first_ayah'",
        );
        final MushafPage page = await pageOf(
          cubit,
          await startPage('first_ayah'),
        );
        final int header = page.lines.indexWhere(
          (PageLine l) => l is SurahHeaderLine && l.surah.number == surah,
        );
        expect(page.lines[header + 1], isA<AyahLine>());
        expect(
          (page.lines[header + 1] as AyahLine).words.first,
          isA<Word>()
              .having((Word w) => w.surahNumber, 'surah', surah)
              .having((Word w) => w.ayahNumber, 'ayah', 1),
        );
      },
    );

    test(
      "'none': the surah header is followed straight by ayah text",
      () async {
        final MushafCubit cubit = await ready();
        final int surah = await scalar(
          "SELECT id FROM surahs WHERE basmala_mode = 'none'",
        );
        final MushafPage page = await pageOf(cubit, await startPage('none'));
        final int header = page.lines.indexWhere(
          (PageLine l) => l is SurahHeaderLine && l.surah.number == surah,
        );
        expect(header, isNot(-1));
        expect(page.lines[header + 1], isNot(isA<BasmalaLine>()));
      },
    );
  });

  test('a short page is laid out for the fullest page\'s line count', () async {
    final MushafCubit cubit = await ready();
    expect(
      cubit.state.linesPerFullPage,
      await scalar(
        'SELECT MAX(c) FROM (SELECT COUNT(*) c FROM lines GROUP BY page)',
      ),
    );
  });

  group('selection', () {
    test('a word selects its whole ayah; a marker selects nothing', () async {
      final MushafCubit cubit = await ready();
      final List<Word> words = (await pageOf(
        cubit,
        1,
      )).lines.whereType<AyahLine>().expand((AyahLine l) => l.words).toList();

      cubit.selectWord(words.firstWhere((Word w) => w.isMarker));
      expect(cubit.state.selected, isNull);

      final Word word = words.firstWhere((Word w) => !w.isMarker);
      cubit.selectWord(word);
      expect(cubit.state.selected, AyahRef(word.surahNumber, word.ayahNumber));

      cubit.clearSelection();
      expect(cubit.state.selected, isNull);
    });
  });

  group('public API', () {
    test('highlightAyah marks that ayah', () async {
      final MushafCubit cubit = await ready();
      cubit.highlightAyah(2, 255);
      expect(cubit.state.highlighted, const AyahRef(2, 255));
      cubit.clearHighlight();
      expect(cubit.state.highlighted, isNull);
    });

    test('goToAyah requests its page, already built', () async {
      final MushafCubit cubit = await ready();
      final int expected = await scalar(
        'SELECT page FROM ayahs WHERE surah = 2 AND ayah = 255',
      );

      await cubit.goToAyah(2, 255);

      expect(cubit.state.pageRequest?.page, expected);
      expect(cubit.state.pages, contains(expected));

      final int first = cubit.state.pageRequest!.token;
      await cubit.goToAyah(2, 255);
      expect(
        cubit.state.pageRequest!.token,
        isNot(first),
        reason: 'asking again for the same page is a new request',
      );
    });

    test('init on an ayah opens its page with it highlighted', () async {
      final MushafCubit cubit = newCubit();
      addTearDown(cubit.close);
      await cubit.init(initialAyah: const AyahRef(18, 10));

      expect(
        cubit.state.currentPage,
        await scalar('SELECT page FROM ayahs WHERE surah = 18 AND ayah = 10'),
      );
      expect(cubit.state.highlighted, const AyahRef(18, 10));
    });
  });
}
