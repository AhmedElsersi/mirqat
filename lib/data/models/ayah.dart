import 'package:equatable/equatable.dart';

import '../../core/error/exceptions.dart';

/// One ayah, exactly as `quran.db` stores it.
///
/// [text] is never transformed — no tatweel removal, no mark reordering, no
/// Unicode normalization, no whitespace fixing. In this text a tatweel is
/// often the base a hamza or small yeh sits on; removing it moves the mark onto
/// the neighbouring letter, which is a change to the mushaf. Stripping belongs
/// only to comparison helpers under `test/` (CLAUDE.md A.2 rule 1).
class Ayah extends Equatable {
  const Ayah({
    required this.surahNumber,
    required this.number,
    required this.text,
  });

  final int surahNumber;
  final int number;

  /// Uthmani text, byte-for-byte as stored.
  final String text;

  /// Built from a row of `quran.db`'s `ayahs` table. Empty text is rejected,
  /// never filled.
  factory Ayah.fromDbRow(Map<String, Object?> row) {
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
    return Ayah(surahNumber: surahNumber, number: number, text: rawText);
  }

  @override
  List<Object?> get props => <Object?>[surahNumber, number, text];
}
