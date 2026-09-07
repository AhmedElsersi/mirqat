import 'package:equatable/equatable.dart';

import '../../core/error/exceptions.dart';

/// How a reciter's audio is laid out on disk.
///
/// Both modes are implemented so a reciter whose assets arrive in the other
/// shape needs no Dart changes (CLAUDE.md A.5, A.6).
enum AudioMode {
  /// One file per ayah: `<basePath>/001/001.mp3`.
  perAyahFiles('per_ayah_files'),

  /// One file per surah plus a timings JSON: `<basePath>/001.mp3`.
  singleFileWithTimings('single_file_with_timings');

  const AudioMode(this.jsonValue);

  final String jsonValue;

  static AudioMode fromJson(String value, String assetPath) {
    for (final AudioMode mode in AudioMode.values) {
      if (mode.jsonValue == value) return mode;
    }
    throw CatalogValidationException(
      assetPath,
      'Unknown audioMode "$value". Expected one of: '
      '${AudioMode.values.map((AudioMode m) => m.jsonValue).join(', ')}.',
    );
  }
}

/// One entry in `assets/data/reciters.json`.
class Reciter extends Equatable {
  const Reciter({
    required this.id,
    required this.nameAr,
    required this.nameEn,
    required this.audioMode,
    required this.basePath,
    required this.bundled,
    required this.availableSurahs,
    required this.hasIstiadhah,
  });

  final String id;
  final String nameAr;
  final String nameEn;
  final AudioMode audioMode;
  final String basePath;

  /// Whether the audio ships inside the app bundle. Milestone 1 is offline, so
  /// every reciter is bundled.
  final bool bundled;

  final List<int> availableSurahs;

  /// Whether this reciter has a standalone isti'adhah clip. It is a preamble,
  /// never an ayah, and must not enter the playback queue as one.
  final bool hasIstiadhah;

  bool hasSurah(int surahNumber) => availableSurahs.contains(surahNumber);

  factory Reciter.fromJson(Map<String, dynamic> json, String assetPath) {
    final String id = _requireString(json, 'id', assetPath);

    final Object? rawSurahs = json['availableSurahs'];
    if (rawSurahs is! List) {
      throw CatalogValidationException(
        assetPath,
        'Reciter "$id" is missing an "availableSurahs" list.',
      );
    }
    final List<int> availableSurahs = <int>[];
    for (final Object? entry in rawSurahs) {
      if (entry is! int || entry < 1) {
        throw CatalogValidationException(
          assetPath,
          'Reciter "$id" has a non-positive surah number in '
          '"availableSurahs": $entry.',
        );
      }
      availableSurahs.add(entry);
    }

    return Reciter(
      id: id,
      nameAr: _requireString(json, 'nameAr', assetPath),
      nameEn: _requireString(json, 'nameEn', assetPath),
      audioMode: AudioMode.fromJson(
        _requireString(json, 'audioMode', assetPath),
        assetPath,
      ),
      basePath: _requireString(json, 'basePath', assetPath),
      bundled: json['bundled'] as bool? ?? true,
      availableSurahs: List<int>.unmodifiable(availableSurahs),
      hasIstiadhah: json['hasIstiadhah'] as bool? ?? false,
    );
  }

  static String _requireString(
    Map<String, dynamic> json,
    String key,
    String assetPath,
  ) {
    final Object? value = json[key];
    if (value is! String || value.isEmpty) {
      throw CatalogValidationException(
        assetPath,
        'Reciter entry is missing a non-empty "$key".',
      );
    }
    return value;
  }

  @override
  List<Object?> get props => <Object?>[
    id,
    nameAr,
    nameEn,
    audioMode,
    basePath,
    bundled,
    availableSurahs,
    hasIstiadhah,
  ];
}
