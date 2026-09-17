import 'package:equatable/equatable.dart';

/// One row of `quran.db`'s `words` table — a single glyph run of the
/// word-by-word Uthmani script, placed on a mushaf page and line.
///
/// Ayah-number markers (the Arabic-Indic digit glyph that closes every ayah
/// on the printed page) are rows in this same table, distinguished only by
/// [isMarker] — never split into a separate model, since they occupy a real
/// position in the line and must render in place.
class Word extends Equatable {
  const Word({
    required this.id,
    required this.surahNumber,
    required this.ayahNumber,
    required this.position,
    required this.text,
    required this.isMarker,
    required this.page,
    required this.line,
  });

  final int id;
  final int surahNumber;
  final int ayahNumber;

  /// 1-based position of this word within its ayah.
  final int position;

  /// Uthmani glyph text, verbatim from the database — never re-diacritized
  /// or normalised beyond what the source already applied.
  final String text;

  /// True for the Arabic-Indic ayah-number glyph that closes an ayah on the
  /// page, false for a recited word.
  final bool isMarker;

  final int page;
  final int line;

  factory Word.fromRow(Map<String, Object?> row) => Word(
    id: row['id']! as int,
    surahNumber: row['surah']! as int,
    ayahNumber: row['ayah']! as int,
    position: row['position']! as int,
    text: row['text']! as String,
    isMarker: (row['is_marker']! as int) != 0,
    page: row['page']! as int,
    line: row['line']! as int,
  );

  @override
  List<Object?> get props => <Object?>[
    id,
    surahNumber,
    ayahNumber,
    position,
    text,
    isMarker,
    page,
    line,
  ];
}
