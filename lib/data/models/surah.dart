import 'package:equatable/equatable.dart';

import '../../core/error/exceptions.dart';

/// Where the Bismillah sits in a surah's numbering. Values are `quran.db`'s
/// `surahs.basmala_mode`.
enum BismillahMode {
  /// Al-Fatiha: the Bismillah is ayah 1 in Hafs numbering.
  countedAsAyah1('first_ayah'),

  /// Most surahs: recited before ayah 1 but not numbered, so it needs its own
  /// audio clip.
  separatePreamble('separate'),

  /// At-Tawbah: no Bismillah at all.
  none('none');

  const BismillahMode(this.dbValue);

  final String dbValue;

  static BismillahMode fromDb(String value) {
    for (final BismillahMode mode in BismillahMode.values) {
      if (mode.dbValue == value) return mode;
    }
    throw CatalogValidationException(
      _source,
      'Unknown basmala_mode "$value". Expected one of: '
      '${BismillahMode.values.map((BismillahMode m) => m.dbValue).join(', ')}.',
    );
  }
}

enum RevelationPlace {
  makkah('makkah'),
  madinah('madinah');

  const RevelationPlace(this.dbValue);

  final String dbValue;

  static RevelationPlace fromDb(String value) {
    for (final RevelationPlace place in RevelationPlace.values) {
      if (place.dbValue == value) return place;
    }
    throw CatalogValidationException(
      _source,
      'Unknown revelation "$value". Expected one of: '
      '${RevelationPlace.values.map((RevelationPlace p) => p.dbValue).join(', ')}.',
    );
  }
}

const String _source = 'quran.db';

/// One row of `quran.db`'s `surahs` table.
class Surah extends Equatable {
  const Surah({
    required this.number,
    required this.nameAr,
    required this.nameEn,
    required this.ayahCount,
    required this.revelationPlace,
    required this.bismillahMode,
  });

  final int number;
  final String nameAr;

  /// The Latin transliteration ("Al-Fatihah"), from `name_translit`. Not a
  /// translation — the source carries none, and none is invented.
  final String nameEn;

  final int ayahCount;
  final RevelationPlace revelationPlace;
  final BismillahMode bismillahMode;

  /// True when the surah needs a standalone Bismillah clip before ayah 1.
  bool get needsBismillahPreamble =>
      bismillahMode == BismillahMode.separatePreamble;

  factory Surah.fromDbRow(Map<String, Object?> row) {
    final int number = row['id']! as int;
    final int ayahCount = row['ayah_count']! as int;
    if (ayahCount < 1) {
      throw CatalogValidationException(
        _source,
        'Surah $number has a non-positive ayah_count: $ayahCount.',
      );
    }
    final Object? revelation = row['revelation'];
    if (revelation is! String) {
      throw CatalogValidationException(
        _source,
        'Surah $number has no revelation place.',
      );
    }

    return Surah(
      number: number,
      nameAr: row['name_ar']! as String,
      nameEn: row['name_translit']! as String,
      ayahCount: ayahCount,
      revelationPlace: RevelationPlace.fromDb(revelation),
      bismillahMode: BismillahMode.fromDb(row['basmala_mode']! as String),
    );
  }

  @override
  List<Object?> get props => <Object?>[
    number,
    nameAr,
    nameEn,
    ayahCount,
    revelationPlace,
    bismillahMode,
  ];
}
