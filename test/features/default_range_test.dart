import 'package:flutter_test/flutter_test.dart';
import 'package:mirqat/data/models/word.dart';
import 'package:mirqat/features/mushaf/cubit/mushaf_page.dart';
import 'package:mirqat/features/mushaf/reading_section.dart';
import 'package:mirqat/features/session/default_range.dart';

int _id = 0;

Word word(int surah, int ayah, int position, {bool marker = false}) => Word(
  id: ++_id,
  surahNumber: surah,
  ayahNumber: ayah,
  position: position,
  text: 'ك',
  isMarker: marker,
  page: 1,
  line: 1,
);

MushafPage pageOf(List<Word> words) => MushafPage(
  number: 1,
  lines: <PageLine>[AyahLine(words: words, centered: false)],
);

/// Ten ayahs to every surah, for a catalog that is only asked where one ends.
AyahRef? endOfSurah(int surah) => AyahRef(surah, 10);

/// What pressing play means before the reader has chosen anything.
void main() {
  test('reading one surah: that surah, whole, whatever page is on show', () {
    const ReadingSection surah = ReadingSection(
      kind: SectionKind.surah,
      number: 5,
      first: AyahRef(5, 1),
      last: AyahRef(5, 10),
      firstPage: 1,
      lastPage: 3,
      total: 114,
    );
    final ({AyahRef from, AyahRef to})? range = suggestedRange(
      page: pageOf(<Word>[word(5, 7, 3), word(5, 8, 1)]),
      section: surah,
      endOfSurah: endOfSurah,
    );
    expect(range, (from: const AyahRef(5, 1), to: const AyahRef(5, 10)));
  });

  test('the mushaf: from the first ayah that begins on the page to the end '
      'of its surah', () {
    // The page opens with the tail of 2:4, carried over from the page before.
    final ({AyahRef from, AyahRef to})? range = suggestedRange(
      page: pageOf(<Word>[
        word(2, 4, 6),
        word(2, 4, 7),
        word(2, 4, 8, marker: true),
        word(2, 5, 1),
        word(2, 5, 2),
      ]),
      section: null,
      endOfSurah: endOfSurah,
    );
    expect(range, (from: const AyahRef(2, 5), to: const AyahRef(2, 10)));
  });

  test('a page one long ayah fills has only that ayah to offer', () {
    final ({AyahRef from, AyahRef to})? range = suggestedRange(
      page: pageOf(<Word>[word(2, 9, 40), word(2, 9, 41)]),
      section: null,
      endOfSurah: endOfSurah,
    );
    expect(range?.from, const AyahRef(2, 9));
  });

  test('a marker is never where a session starts', () {
    final ({AyahRef from, AyahRef to})? range = suggestedRange(
      page: pageOf(<Word>[word(2, 4, 1, marker: true), word(2, 5, 1)]),
      section: null,
      endOfSurah: endOfSurah,
    );
    expect(range?.from, const AyahRef(2, 5));
  });

  test('reading one juz: words borrowed from the neighbour are not the '
      'start', () {
    const ReadingSection juz = ReadingSection(
      kind: SectionKind.juz,
      number: 2,
      first: AyahRef(2, 6),
      last: AyahRef(3, 4),
      firstPage: 1,
      lastPage: 9,
      total: 30,
    );
    // The line is shared: 2:5 belongs to the juz before, and begins here.
    final ({AyahRef from, AyahRef to})? range = suggestedRange(
      page: pageOf(<Word>[word(2, 5, 1), word(2, 5, 2), word(2, 6, 1)]),
      section: juz,
      endOfSurah: endOfSurah,
    );
    expect(range, (from: const AyahRef(2, 6), to: const AyahRef(2, 10)));
  });

  test('a page with no words, or a surah the catalog cannot place, offers '
      'nothing', () {
    expect(
      suggestedRange(
        page: const MushafPage(number: 1, lines: <PageLine>[]),
        section: null,
        endOfSurah: endOfSurah,
      ),
      isNull,
    );
    expect(
      suggestedRange(
        page: pageOf(<Word>[word(2, 5, 1)]),
        section: null,
        endOfSurah: (_) => null,
      ),
      isNull,
    );
  });
}
