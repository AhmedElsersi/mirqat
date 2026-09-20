import 'package:equatable/equatable.dart';

import '../../../data/models/surah.dart';
import '../../../data/models/word.dart';
import '../../../domain/entities/ayah_ref.dart';

export '../../../domain/entities/ayah_ref.dart';

/// Whether a word on the page belongs to an ayah. The ref itself lives in the
/// domain layer, which knows nothing of words.
extension AyahRefWords on AyahRef {
  bool contains(Word word) =>
      word.surahNumber == surah && word.ayahNumber == ayah;
}

extension WordAyahRef on Word {
  AyahRef get ref => AyahRef(surahNumber, ayahNumber);
}

/// One printed line of a mushaf page, in the shape the renderer draws it.
sealed class PageLine extends Equatable {
  const PageLine();
}

/// `line_type = 'surah_name'`: the decorated header opening a surah.
class SurahHeaderLine extends PageLine {
  const SurahHeaderLine(this.surah);

  final Surah surah;

  @override
  List<Object?> get props => <Object?>[surah];
}

/// `line_type = 'basmallah'`: the basmala ahead of a surah that recites it
/// unnumbered. It belongs to no ayah, so nothing on it is tappable.
///
/// [words] are the basmala as `quran.db` itself stores it — the first ayah of
/// the surah whose basmala *is* its ayah 1 — never typed. Empty when no such
/// source exists, and then the line is drawn blank rather than invented.
class BasmalaLine extends PageLine {
  const BasmalaLine(this.words);

  final List<Word> words;

  @override
  List<Object?> get props => <Object?>[words];
}

/// `line_type = 'ayah'`: the words `first_word_id..last_word_id`, by id.
class AyahLine extends PageLine {
  const AyahLine({required this.words, required this.centered});

  final List<Word> words;

  /// `lines.is_centered`: drawn centred rather than justified edge to edge.
  final bool centered;

  @override
  List<Object?> get props => <Object?>[words, centered];
}

class MushafPage extends Equatable {
  const MushafPage({
    required this.number,
    required this.lines,
    this.surah,
    this.juz,
    this.hizb,
    this.partial = false,
  });

  final int number;
  final List<PageLine> lines;

  /// Whether lines of the printed page were left out because they belong to
  /// a neighbouring surah or juz. A partial page is set from the top, like
  /// the opening of a chapter; a page that is simply short — the mushaf's
  /// first two — keeps its lines centred, as they are printed.
  final bool partial;

  /// The surah, juz and hizb the page opens in — what the frame writes in its
  /// borders. Null when the catalog could not say; the border then simply
  /// carries no label there.
  final Surah? surah;
  final int? juz;
  final int? hizb;

  @override
  List<Object?> get props => <Object?>[
    number,
    lines,
    surah,
    juz,
    hizb,
    partial,
  ];
}
