import 'package:equatable/equatable.dart';

import '../../core/error/exceptions.dart';
import '../../core/extensions/arabic_text_extensions.dart';

/// One ayah, loaded verbatim from `assets/data/ayahs/<surah>.json`.
///
/// The only transformations applied to [text] are Unicode NFC normalization
/// and the removal of U+0640 tatweel — both level encoding variance between
/// editions of identical text. Nothing here rewrites, re-diacritizes or
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

  factory Ayah.fromJson(
    Map<String, dynamic> json, {
    required int surahNumber,
    required String assetPath,
  }) {
    final int? number = json['number'] as int?;
    if (number == null || number < 1) {
      throw CatalogValidationException(
        assetPath,
        'Ayah entry has a missing or non-positive "number": ${json['number']}.',
      );
    }

    final Object? rawText = json['text'];
    if (rawText is! String || rawText.trim().isEmpty) {
      throw CatalogValidationException(
        assetPath,
        'Ayah $surahNumber:$number has missing or empty "text". '
        'Supply the verbatim text; it is never generated.',
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
