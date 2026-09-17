import 'package:equatable/equatable.dart';

import '../../core/error/exceptions.dart';
import '../../core/extensions/arabic_text_extensions.dart';

/// One ayah, loaded verbatim from `quran.db`.
///
/// The only transformations applied to [text] are Unicode NFC normalization
/// and the removal of U+0640 tatweel. Nothing here rewrites, re-diacritizes or
/// repairs scripture (CLAUDE.md A.2 rule 1).
class Ayah extends Equatable {
  const Ayah({
    required this.surahNumber,
    required this.number,
    required this.text,
  });

  final int surahNumber;
  final int number;

  /// Uthmani text in canonical form: tatweel-free and NFC-normalised.
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
    return Ayah(
      surahNumber: surahNumber,
      number: number,
      text: rawText.toCanonicalQuranicText(),
    );
  }

  @override
  List<Object?> get props => <Object?>[surahNumber, number, text];
}
