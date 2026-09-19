import 'package:equatable/equatable.dart';

import '../../core/error/exceptions.dart';
import 'audio_manifest.dart';

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

/// A reciter: bundled (`assets/data/reciters.json`), remote (the audio
/// manifest), or both when the manifest extends a bundled reciter by id.
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
    required this.hasBismillah,
    this.imagePath,
    this.imageUrl,
    this.remote,
    this.remoteSurahs = const <int>{},
  });

  /// A reciter known only from the audio manifest.
  factory Reciter.remoteOnly(
    ManifestReciter manifest, {
    Set<int>? surahs,
    String? imageUrl,
  }) => Reciter(
        id: manifest.id,
        nameAr: manifest.nameAr,
        nameEn: manifest.nameEn,
        audioMode: AudioMode.perAyahFiles,
        basePath: '',
        bundled: false,
        availableSurahs: const <int>[],
        hasIstiadhah: false,
        hasBismillah: false,
      ).withRemote(manifest, surahs: surahs, imageUrl: imageUrl);

  final String id;
  final String nameAr;
  final String nameEn;
  final AudioMode audioMode;
  final String basePath;

  /// Whether the audio ships inside the app bundle. Milestone 1 is offline, so
  /// every reciter is bundled.
  final bool bundled;

  final List<int> availableSurahs;

  /// Whether this reciter has a standalone isti'adhah clip, at
  /// `<basePath>/istiadhah.mp3`. It is a preamble, never an ayah, and must not
  /// enter the playback queue as one.
  final bool hasIstiadhah;

  /// Whether this reciter has a standalone bismillah clip, at
  /// `<basePath>/bismillah.mp3`.
  ///
  /// Both preambles are surah-independent — same words, same reciter, same
  /// session — so one file each covers every surah. A reciter may supply
  /// either, both, or neither; the two flags are deliberately symmetric.
  final bool hasBismillah;

  /// Asset path of the reciter's photograph, or null when there is none.
  ///
  /// Nullable on purpose: a reciter may be catalogued long before a usable,
  /// licensable portrait exists, and the UI must render the same either way.
  /// The path comes from the catalog so a photo is dropped in as data —
  /// nothing in Dart knows a reciter's file name (CLAUDE.md A.2 rule 2).
  final String? imagePath;

  /// The portrait on the CDN, for a reciter the app does not ship.
  ///
  /// A bundled [imagePath] wins where there is one — it costs no request and
  /// works offline on first run. This is what a reciter added to the manifest
  /// alone is drawn with.
  final String? imageUrl;

  /// The manifest entry serving this reciter's non-bundled surahs, if any.
  final ManifestReciter? remote;

  /// Surahs the manifest offers, after checking each against the text catalog.
  /// Held separately from [remote]'s own list so a surah recorded against the
  /// wrong ayah count is never reachable.
  final Set<int> remoteSurahs;

  bool hasSurah(int surahNumber) =>
      isBundledSurah(surahNumber) || remoteSurahs.contains(surahNumber);

  /// Whether [surahNumber]'s audio ships inside the app.
  bool isBundledSurah(int surahNumber) =>
      bundled && availableSurahs.contains(surahNumber);

  /// Whether this reciter has a basmala to play before ayah 1 of
  /// [surahNumber].
  ///
  /// Two layouts answer the same question. A bundled reciter ships one
  /// `bismillah.mp3` that serves every surah, and declares it with
  /// [hasBismillah]. A manifest reciter's basmala is ayah 0 inside the surah
  /// itself, so having the surah is having the basmala — unless the manifest
  /// says otherwise, which is authoritative: a remote file's absence cannot be
  /// discovered without a request (CLAUDE.md A.5).
  /// Whether a session *plays* it is `SessionPreambles`' decision, keyed on
  /// the surah's `bismillahMode`.
  bool hasBasmala(int surahNumber) =>
      hasBismillah ||
      (remoteSurahs.contains(surahNumber) &&
          remote?.surah(surahNumber)?.hasBasmala != false);

  /// This reciter extended by [manifest]. [surahs] limits which of its surahs
  /// are offered; null offers all of them.
  /// [imageUrl] is resolved by the caller, which is the one place holding the
  /// manifest's `baseUrl` — a reciter cannot resolve its own portrait.
  Reciter withRemote(
    ManifestReciter manifest, {
    Set<int>? surahs,
    String? imageUrl,
  }) => Reciter(
    id: id,
    nameAr: nameAr,
    nameEn: nameEn,
    audioMode: audioMode,
    basePath: basePath,
    bundled: bundled,
    availableSurahs: availableSurahs,
    hasIstiadhah: hasIstiadhah,
    hasBismillah: hasBismillah,
    imagePath: imagePath,
    imageUrl: imageUrl ?? this.imageUrl,
    remote: manifest,
    remoteSurahs: Set<int>.unmodifiable(
      surahs ?? manifest.surahs.map((ManifestSurah s) => s.number),
    ),
  );

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
      hasBismillah: json['hasBismillah'] as bool? ?? false,
      // Absent and explicitly null mean the same thing: no photo. An empty
      // string does too, rather than becoming a path that can never load.
      imagePath: switch (json['imagePath']) {
        final String path when path.isNotEmpty => path,
        _ => null,
      },
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
    hasBismillah,
    imagePath,
    imageUrl,
    remote,
    remoteSurahs,
  ];
}
