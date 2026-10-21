import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mirqat/core/state/load_status.dart';
import 'package:mirqat/core/theme/quran_font.dart';
import 'package:mirqat/core/widgets/ayah_text.dart';
import 'package:mirqat/data/datasources/quran_local_data_source.dart';
import 'package:mirqat/data/datasources/quran_pages_local_data_source.dart';
import 'package:mirqat/data/models/mushaf_line.dart';
import 'package:mirqat/data/models/word.dart';
import 'package:mirqat/data/repositories/quran_pages_repository.dart';
import 'package:mirqat/data/repositories/quran_repository.dart';
import 'package:mirqat/features/mushaf/cubit/mushaf_cubit.dart';
import 'package:mirqat/features/mushaf/cubit/mushaf_page.dart';
import 'package:mirqat/features/mushaf/widgets/mushaf_page_view.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../quran_db_fixtures.dart';

/// The QPC V2 print laid over quran.db: its glyphs, its pages, its lines.
/// Every page and ayah named here is found in the database, never typed.
void main() {
  late RepoQuranDatabase database;
  late Database db;

  setUpAll(() async {
    database = RepoQuranDatabase();
    db = await database.open();
  });

  Future<Object?> one(
    String sql, [
    List<Object?> args = const <Object?>[],
  ]) async => (await db.rawQuery(sql, args)).single.values.single;

  Future<MushafCubit> open(MushafLayout layout, int page) async {
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
    await cubit.init(initialPage: page, layout: layout);
    expect(cubit.state.status, LoadStatus.ready);
    return cubit;
  }

  List<Word> wordsOf(MushafPage page) => <Word>[
    for (final PageLine l in page.lines)
      if (l is AyahLine) ...l.words,
  ];

  group('quran.db', () {
    test('every word has its V2 glyph, page and line; the text is the same '
        'column every other face draws', () async {
      expect(
        await one(
          'SELECT COUNT(*) FROM words WHERE glyph_v2 IS NULL '
          'OR page_v2 IS NULL OR line_v2 IS NULL',
        ),
        0,
      );
      expect(await one('SELECT COUNT(DISTINCT page) FROM lines_v2'), 604);
    });

    test('three words are drawn by the glyph before them: each «مَا» after '
        '«بَعۡدَ», which the V2 print sets as one', () async {
      final List<Map<String, Object?>> joined = await db.rawQuery(
        "SELECT w.surah, w.ayah, w.text, p.text AS before, p.glyph_v2 AS g "
        "FROM words w JOIN words p ON p.id = w.id - 1 WHERE w.glyph_v2 = ''",
      );
      expect(joined, hasLength(3));
      for (final Map<String, Object?> row in joined) {
        expect(row['text'], 'مَا');
        expect(row['before'], 'بَعۡدَ');
        expect(row['g'], isNotEmpty);
      }
    });

    test('a V2 ayah line is one run of words, all on that page', () async {
      expect(
        await one(
          "SELECT COUNT(*) FROM lines_v2 l WHERE l.line_type = 'ayah' AND "
          '(SELECT COUNT(*) FROM words w WHERE w.id BETWEEN l.first_word_id '
          'AND l.last_word_id AND w.page_v2 = l.page AND w.line_v2 = l.line) '
          '<> l.last_word_id - l.first_word_id + 1',
        ),
        0,
      );
    });
  });

  group('the reading view in the V2 layout', () {
    test('a page holds the words the V2 print puts on it — where the prints '
        'break a page differently, too', () async {
      // A word the V2 print sets a page earlier than V1 does.
      final Map<String, Object?> moved = (await db.rawQuery(
        'SELECT page, page_v2 FROM words WHERE page_v2 < page ORDER BY id '
        'LIMIT 1',
      )).single;
      final int page = moved['page_v2']! as int;

      final MushafCubit v2 = await open(MushafLayout.qpcV2, page);
      await v2.ensurePage(page);
      final List<Word> words = wordsOf(v2.state.pages[page]!);
      expect(words.every((Word w) => w.pageV2 == page), isTrue);
      expect(words.any((Word w) => w.page != page), isTrue);

      final MushafCubit v1 = await open(MushafLayout.hafs, page);
      await v1.ensurePage(page);
      expect(
        wordsOf(v1.state.pages[page]!).every((Word w) => w.page == page),
        isTrue,
      );
    });

    test(
      'changing the face lays the open page out again in the other print',
      () async {
        final MushafCubit cubit = await open(MushafLayout.hafs, 3);
        await cubit.ensurePage(3);
        final int epoch = cubit.state.epoch;
        await cubit.setLayout(MushafLayout.qpcV2);
        expect(cubit.state.epoch, epoch + 1);
        expect(cubit.state.currentPage, 3);
        expect(cubit.layout, MushafLayout.qpcV2);
        expect(
          cubit.state.pages[3]!.lines.length,
          await one('SELECT COUNT(*) FROM lines_v2 WHERE page = 3'),
        );
      },
    );
  });

  group('a page drawn in the V2 face', () {
    Future<List<AyahText>> draw(
      WidgetTester tester,
      MushafPage page, {
      required QuranFont font,
      required Set<int> glyphPages,
    }) async {
      await tester.pumpWidget(
        ScreenUtilInit(
          designSize: const Size(390, 844),
          builder: (_, _) => MaterialApp(
            home: QuranFontScope(
              font: font,
              child: Scaffold(
                body: MushafPageView(
                  page: page,
                  linesPerFullPage: 15,
                  highlighted: null,
                  selected: null,
                  onWordLongPress: (_) {},
                  glyphPages: glyphPages,
                ),
              ),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      return tester.widgetList<AyahText>(find.byType(AyahText)).toList();
    }

    testWidgets('its words are glyphs once its font is in, and text until '
        'then; a joined word is not drawn twice', (WidgetTester tester) async {
      final int page =
          (await tester.runAsync(
                () => one(
                  "SELECT page_v2 FROM words WHERE glyph_v2 = '' LIMIT 1",
                ),
              ))!
              as int;
      final MushafCubit cubit = (await tester.runAsync(() async {
        final MushafCubit c = await open(MushafLayout.qpcV2, page);
        await c.ensurePage(page);
        return c;
      }))!;
      final MushafPage built = cubit.state.pages[page]!;
      final List<Word> words = wordsOf(built);

      final List<AyahText> waiting = await draw(
        tester,
        built,
        font: QuranFont.qpcV2,
        glyphPages: const <int>{},
      );
      expect(waiting.where((AyahText t) => t.glyph != null), isEmpty);
      expect(waiting, hasLength(words.length));

      final List<AyahText> drawn = await draw(
        tester,
        built,
        font: QuranFont.qpcV2,
        glyphPages: <int>{page},
      );
      expect(drawn.every((AyahText t) => t.glyphPage == page), isTrue);
      expect(drawn, hasLength(words.length - 1), reason: 'one word joined');

      final List<AyahText> bundled = await draw(
        tester,
        built,
        font: QuranFont.hafsV22,
        glyphPages: <int>{page},
      );
      expect(bundled.where((AyahText t) => t.glyph != null), isEmpty);
    });
  });
}
