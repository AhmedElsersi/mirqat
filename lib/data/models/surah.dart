import 'package:equatable/equatable.dart';

import '../../core/error/exceptions.dart';

/// Where the Bismillah sits in a surah's numbering.
///
/// Milestone 1 only ships [countedAsAyah1], but every layer handles all three
/// so surahs 2+ drop in as data (CLAUDE.md A.5).
enum BismillahMode {
  /// Al-Fatiha: the Bismillah is ayah 1 in Hafs numbering.
  countedAsAyah1('counted_as_ayah_1'),

  /// Most surahs: recited before ayah 1 but not numbered, so it needs its own
  /// audio clip.
  separatePreamble('separate_preamble'),

  /// At-Tawbah: no Bismillah at all.
  none('none');

  const BismillahMode(this.jsonValue);

  final String jsonValue;

  static BismillahMode fromJson(String value, String assetPath) {
    for (final BismillahMode mode in BismillahMode.values) {
      if (mode.jsonValue == value) return mode;
    }
    throw CatalogValidationException(
      assetPath,
      'Unknown bismillahMode "$value". Expected one of: '
      '${BismillahMode.values.map((BismillahMode m) => m.jsonValue).join(', ')}.',
    );
  }
}

enum RevelationPlace {
  makkah('makkah'),
  madinah('madinah');

  const RevelationPlace(this.jsonValue);

  final String jsonValue;

  static RevelationPlace fromJson(String value, String assetPath) {
    for (final RevelationPlace place in RevelationPlace.values) {
      if (place.jsonValue == value) return place;
    }
    throw CatalogValidationException(
      assetPath,
      'Unknown revelationPlace "$value". Expected one of: '
      '${RevelationPlace.values.map((RevelationPlace p) => p.jsonValue).join(', ')}.',
    );
  }
}

/// One entry in `assets/data/surahs.json`.
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
  final String nameEn;
  final int ayahCount;
  final RevelationPlace revelationPlace;
  final BismillahMode bismillahMode;

  /// True when the surah needs a standalone Bismillah clip before ayah 1.
  bool get needsBismillahPreamble =>
      bismillahMode == BismillahMode.separatePreamble;

  factory Surah.fromJson(Map<String, dynamic> json, String assetPath) {
    final int? number = json['number'] as int?;
    if (number == null || number < 1) {
      throw CatalogValidationException(
        assetPath,
        'Surah entry has a missing or non-positive "number": ${json['number']}.',
      );
    }

    final int? ayahCount = json['ayahCount'] as int?;
    if (ayahCount == null || ayahCount < 1) {
      throw CatalogValidationException(
        assetPath,
        'Surah $number has a missing or non-positive "ayahCount": '
        '${json['ayahCount']}.',
      );
    }

    return Surah(
      number: number,
      nameAr: _requireString(json, 'nameAr', number, assetPath),
      nameEn: _requireString(json, 'nameEn', number, assetPath),
      ayahCount: ayahCount,
      revelationPlace: RevelationPlace.fromJson(
        _requireString(json, 'revelationPlace', number, assetPath),
        assetPath,
      ),
      bismillahMode: BismillahMode.fromJson(
        _requireString(json, 'bismillahMode', number, assetPath),
        assetPath,
      ),
    );
  }

  static String _requireString(
    Map<String, dynamic> json,
    String key,
    int surahNumber,
    String assetPath,
  ) {
    final Object? value = json[key];
    if (value is! String || value.isEmpty) {
      throw CatalogValidationException(
        assetPath,
        'Surah $surahNumber is missing a non-empty "$key".',
      );
    }
    return value;
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
