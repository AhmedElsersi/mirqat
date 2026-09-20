import '../../data/models/word.dart';
import '../mushaf/cubit/mushaf_page.dart';
import '../mushaf/reading_section.dart';

/// What pressing play means when the reader has chosen nothing.
///
///  * Reading one surah: that surah, whole.
///  * Otherwise — the mushaf, or one juz — from the first ayah that *begins*
///    on the page to the end of its surah. An ayah carried over from the page
///    before is not where anyone would start; but where a single long ayah
///    fills the page and none begins on it, that ayah is the only candidate.
///
/// [endOfSurah] is the catalog's answer; no ayah count is known here. Null
/// when the page has no words to go by.
({AyahRef from, AyahRef to})? suggestedRange({
  required MushafPage page,
  required ReadingSection? section,
  required AyahRef? Function(int surah) endOfSurah,
}) {
  if (section != null && section.kind == SectionKind.surah) {
    return (from: section.first, to: section.last);
  }

  final List<Word> words = page.lines
      .whereType<AyahLine>()
      .expand((AyahLine l) => l.words)
      .where((Word w) => !w.isMarker && (section?.holds(w.ref) ?? true))
      .toList(growable: false);
  if (words.isEmpty) return null;

  final Word opening = words.firstWhere(
    (Word w) => w.position == 1,
    orElse: () => words.first,
  );
  final AyahRef? end = endOfSurah(opening.surahNumber);
  return end == null ? null : (from: opening.ref, to: end);
}
