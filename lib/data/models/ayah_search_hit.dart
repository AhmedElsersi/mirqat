import 'package:equatable/equatable.dart';

import '../../core/error/exceptions.dart';

/// One ayah a search found: where it is, and its text to show in the result.
///
/// [text] is the `text` column verbatim, byte-for-byte (CLAUDE.md A.2
/// rule 1) — the match was made against the `text_search` column, which is
/// never shown to anyone.
class AyahSearchHit extends Equatable {
  const AyahSearchHit({
    required this.surahNumber,
    required this.number,
    required this.text,
    required this.page,
  });

  final int surahNumber;
  final int number;

  /// Uthmani text, byte-for-byte as stored. Shown whole, never truncated
  /// (CLAUDE.md A.2 rule 7).
  final String text;

  /// The mushaf page the ayah begins on — where tapping the result opens.
  final int page;

  factory AyahSearchHit.fromDbRow(Map<String, Object?> row) {
    final int surahNumber = row['surah']! as int;
    final int number = row['ayah']! as int;
    final Object? rawText = row['text'];
    if (rawText is! String || rawText.trim().isEmpty) {
      throw CatalogValidationException(
        'quran.db',
        'Ayah $surahNumber:$number has missing or empty text. Supply the '
            'verbatim text; it is never generated.',
      );
    }
    return AyahSearchHit(
      surahNumber: surahNumber,
      number: number,
      text: rawText,
      page: row['page']! as int,
    );
  }

  @override
  List<Object?> get props => <Object?>[surahNumber, number, text, page];
}
