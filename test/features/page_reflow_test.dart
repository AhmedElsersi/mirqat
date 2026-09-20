import 'package:flutter_test/flutter_test.dart';
import 'package:mirqat/data/datasources/quran_local_data_source.dart';
import 'package:mirqat/data/datasources/quran_pages_local_data_source.dart';
import 'package:mirqat/data/models/surah.dart';
import 'package:mirqat/data/models/word.dart';
import 'package:mirqat/data/repositories/quran_pages_repository.dart';
import 'package:mirqat/data/repositories/quran_repository.dart';
import 'package:mirqat/features/mushaf/cubit/mushaf_cubit.dart';
import 'package:mirqat/features/mushaf/cubit/mushaf_page.dart';
import 'package:mirqat/features/mushaf/widgets/page_reflow.dart';

import '../quran_db_fixtures.dart';

int _id = 0;

Word w(int ayah, {bool marker = false, int surah = 2}) => Word(
  id: ++_id,
  surahNumber: surah,
  ayahNumber: ayah,
  position: 1,
  text: marker ? '١' : 'كلمة',
  isMarker: marker,
  page: 1,
  line: 1,
);

/// Ten units to a word, four to a marker, two between.
double widthOf(Word word) => word.isMarker ? 4 : 10;
const double kGap = 2;

List<PageLine> reflow(List<PageLine> lines, double maxWidth) =>
    reflowPage(lines: lines, maxWidth: maxWidth, gap: kGap, widthOf: widthOf);

Iterable<Word> wordsOf(Iterable<PageLine> lines) => lines.expand(
  (PageLine l) => switch (l) {
    AyahLine(:final List<Word> words) => words,
    BasmalaLine(:final List<Word> words) => words,
    SurahHeaderLine() => const <Word>[],
  },
);

double rowWidth(List<Word> row) =>
    row.map(widthOf).fold<double>(0, (double a, double b) => a + b) +
    kGap * (row.length - 1);

void main() {
  group('re-breaking a page for larger text', () {
    test('changes where the lines break, and nothing else', () {
      final List<PageLine> page = <PageLine>[
        AyahLine(
          words: <Word>[w(1), w(1), w(1), w(1, marker: true)],
          centered: false,
        ),
        AyahLine(words: <Word>[w(2), w(2), w(2), w(2)], centered: false),
      ];
      final List<PageLine> out = reflow(page, 26);

      // The same word objects, in the same order — the bytes are untouched
      // because the words are.
      expect(
        wordsOf(out).map((Word x) => x.id).toList(),
        wordsOf(page).map((Word x) => x.id).toList(),
      );
      expect(out.length, greaterThan(page.length));
    });

    test('no row is wider than the page', () {
      final List<PageLine> out = reflow(<PageLine>[
        AyahLine(
          words: <Word>[for (int i = 0; i < 40; i++) w(i ~/ 5 + 1)],
          centered: false,
        ),
      ], 47);
      for (final AyahLine row in out.whereType<AyahLine>()) {
        expect(rowWidth(row.words), lessThanOrEqualTo(47));
      }
    });

    test('an ayah\'s end-marker never opens a row', () {
      // Two words fill a row of 22 exactly; the marker after them would be
      // the first thing on the next one.
      final List<PageLine> out = reflow(<PageLine>[
        AyahLine(
          words: <Word>[w(1), w(1), w(1, marker: true), w(2), w(2)],
          centered: false,
        ),
      ], 22);
      for (final AyahLine row in out.whereType<AyahLine>()) {
        expect(row.words.first.isMarker, isFalse);
      }
      // It stayed with the word it closes.
      final AyahLine withMarker = out.whereType<AyahLine>().firstWhere(
        (AyahLine r) => r.words.any((Word x) => x.isMarker),
      );
      final int at = withMarker.words.indexWhere((Word x) => x.isMarker);
      expect(withMarker.words[at - 1].ayahNumber, 1);
    });

    test('consecutive lines are one passage; its short last row is centred '
        'rather than stretched', () {
      final List<PageLine> out = reflow(<PageLine>[
        AyahLine(words: <Word>[w(1), w(1), w(1)], centered: false),
        AyahLine(words: <Word>[w(1), w(1), w(1), w(1)], centered: false),
      ], 34);
      final List<AyahLine> rows = out.whereType<AyahLine>().toList();
      // Seven words, three to a row: 3 + 3 + 1.
      expect(rows.map((AyahLine r) => r.words.length), <int>[3, 3, 1]);
      expect(rows[0].centered, isFalse);
      expect(rows[1].centered, isFalse);
      expect(rows[2].centered, isTrue);
    });

    test('a surah\'s heading, its basmala and a centred close keep their place '
        'and their kind', () {
      const Surah surah = Surah(
        number: 2,
        nameAr: 'س',
        nameEn: 'S',
        ayahCount: 3,
        revelationPlace: RevelationPlace.makkah,
        bismillahMode: BismillahMode.separatePreamble,
      );
      final List<PageLine> out = reflow(<PageLine>[
        AyahLine(words: <Word>[w(9, surah: 1), w(9, surah: 1)], centered: true),
        const SurahHeaderLine(surah),
        BasmalaLine(<Word>[w(0), w(0), w(0), w(0)]),
        AyahLine(words: <Word>[w(1), w(1), w(1)], centered: false),
      ], 22);

      expect(out.map((PageLine l) => l.runtimeType).toList(), <Type>[
        AyahLine, // the close of the surah before, still centred
        SurahHeaderLine,
        BasmalaLine,
        BasmalaLine, // four words, two to a row
        AyahLine,
        AyahLine,
      ]);
      expect((out.first as AyahLine).centered, isTrue);
      // The heading separates passages: nothing of surah 1 shares a row with
      // surah 2.
      for (final AyahLine row in out.whereType<AyahLine>()) {
        expect(row.words.map((Word x) => x.surahNumber).toSet(), hasLength(1));
      }
    });

    test('centred lines run together too — the opening pages are centred '
        'throughout, and must not leave a stray word under every line', () {
      final List<PageLine> out = reflow(<PageLine>[
        AyahLine(words: <Word>[w(1), w(1), w(1)], centered: true),
        AyahLine(words: <Word>[w(1), w(1), w(1)], centered: true),
        AyahLine(words: <Word>[w(2), w(2), w(2)], centered: true),
      ], 22);
      final List<AyahLine> rows = out.whereType<AyahLine>().toList();
      // Nine words, two to a row: five rows, not three stragglers.
      expect(rows.map((AyahLine r) => r.words.length), <int>[2, 2, 2, 2, 1]);
      expect(rows.every((AyahLine r) => r.centered), isTrue);
    });

    test('a centred close is not run into the justified lines beside it', () {
      final List<PageLine> out = reflow(<PageLine>[
        AyahLine(words: <Word>[w(1), w(1), w(1), w(1)], centered: false),
        AyahLine(words: <Word>[w(2)], centered: true),
        AyahLine(words: <Word>[w(3), w(3), w(3), w(3)], centered: false),
        // Four words and three gaps: exactly a full row each.
      ], 46);
      expect(out, hasLength(3));
      expect(out.whereType<AyahLine>().map((AyahLine r) => r.centered), <bool>[
        false,
        true,
        false,
      ]);
    });

    test('a page wide enough for its lines comes back as it went in', () {
      final List<PageLine> page = <PageLine>[
        AyahLine(words: <Word>[w(1), w(1)], centered: false),
      ];
      expect(wordsOf(reflow(page, 1000)).length, 2);
      expect(reflow(page, 1000), hasLength(1));
    });
  });

  test('every page of the real mushaf re-breaks without losing, adding or '
      'reordering a word', () async {
    final RepoQuranDatabase database = RepoQuranDatabase();
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

    for (int p = 1; p <= cubit.state.pageCount; p++) {
      await cubit.ensurePage(p);
      final List<PageLine> lines = cubit.state.pages[p]!.lines;
      // Every word as wide as its text is long: crude, and enough to make
      // nearly every printed line break somewhere new.
      final List<PageLine> out = reflowPage(
        lines: lines,
        maxWidth: 60,
        gap: 1,
        widthOf: (Word x) => x.text.length.toDouble(),
      );
      expect(
        wordsOf(out).map((Word x) => x.id).toList(),
        wordsOf(lines).map((Word x) => x.id).toList(),
        reason: 'page $p',
      );
      expect(
        out.whereType<SurahHeaderLine>().length,
        lines.whereType<SurahHeaderLine>().length,
        reason: 'page $p',
      );
    }
  });
}
