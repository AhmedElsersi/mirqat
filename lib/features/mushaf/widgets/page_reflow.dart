import '../../../data/models/word.dart';
import '../cubit/mushaf_page.dart';

/// Below this share of the page's width, the last row of a passage is set
/// centred rather than stretched edge to edge: three words pulled apart
/// across a whole line read as three separate things.
const double kJustifyFromFill = 0.72;

/// A page's lines, re-broken to fit [maxWidth] at a text size larger than the
/// one its printed lines were set for.
///
/// At the size a page is drawn by default, each printed line exactly fills the
/// page's width — so at any larger size no printed line fits, and something
/// has to give. What gives is where the lines break, and nothing else: the
/// words, their order and the page they are on stay as they are, and every
/// word is still the same bytes from `quran.db` (CLAUDE.md A.2 rule 1). The
/// page grows taller and scrolls.
///
/// Passages are re-broken whole. A run of ordinary lines is one passage, its
/// words packed greedily into rows that are each justified like a printed
/// line; the last row is centred when it is too short to stretch. Lines the
/// layout centres — the close of a surah, the mushaf's two opening pages —
/// run together in the same way and stay centred, as does the basmala. A
/// surah's heading is left alone.
///
/// [widthOf] is a word's width at the size being drawn, [gap] the narrowest
/// space allowed between two words.
List<PageLine> reflowPage({
  required List<PageLine> lines,
  required double maxWidth,
  required double gap,
  required double Function(Word word) widthOf,
}) {
  final List<PageLine> out = <PageLine>[];
  final List<Word> passage = <Word>[];

  List<List<Word>> pack(List<Word> words) {
    // An ayah's end-marker never opens a row: it belongs on the line with the
    // word it closes. So words are packed in units — a word with whatever
    // markers follow it — and a unit is never split.
    final List<List<Word>> units = <List<Word>>[];
    for (final Word word in words) {
      if (word.isMarker && units.isNotEmpty) {
        units.last.add(word);
      } else {
        units.add(<Word>[word]);
      }
    }

    double widthOfUnit(List<Word> unit) =>
        unit.map(widthOf).fold<double>(0, (double a, double b) => a + b) +
        gap * (unit.length - 1);

    final List<List<Word>> rows = <List<Word>>[];
    List<Word> row = <Word>[];
    double used = 0;
    for (final List<Word> unit in units) {
      final double w = widthOfUnit(unit);
      if (row.isNotEmpty && used + gap + w > maxWidth) {
        rows.add(row);
        row = <Word>[];
        used = 0;
      }
      used = row.isEmpty ? w : used + gap + w;
      row.addAll(unit);
    }
    if (row.isNotEmpty) rows.add(row);
    return rows;
  }

  double fill(List<Word> row) =>
      (row.map(widthOf).fold<double>(0, (double a, double b) => a + b) +
          gap * (row.length - 1)) /
      maxWidth;

  // Whether the passage being gathered is one the layout centres.
  bool centredPassage = false;

  void flushPassage() {
    if (passage.isEmpty) return;
    final List<List<Word>> rows = pack(passage);
    for (int i = 0; i < rows.length; i++) {
      final bool last = i == rows.length - 1;
      out.add(
        AyahLine(
          words: rows[i],
          centered:
              centredPassage || (last && fill(rows[i]) < kJustifyFromFill),
        ),
      );
    }
    passage.clear();
  }

  for (final PageLine line in lines) {
    switch (line) {
      case AyahLine(:final List<Word> words, :final bool centered):
        // A change of kind ends the passage; lines of one kind run together.
        // Centred lines too: the mushaf's two opening pages are centred
        // throughout, and re-breaking each of their lines alone would leave a
        // stray word under every one.
        if (centered != centredPassage) flushPassage();
        centredPassage = centered;
        passage.addAll(words);
      case BasmalaLine(:final List<Word> words):
        flushPassage();
        if (words.isEmpty) {
          out.add(line);
        } else {
          for (final List<Word> row in pack(words)) {
            out.add(BasmalaLine(row));
          }
        }
      case SurahHeaderLine():
        flushPassage();
        out.add(line);
    }
  }
  flushPassage();
  return out;
}
