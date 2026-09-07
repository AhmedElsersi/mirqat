import 'package:equatable/equatable.dart';

import '../../core/error/exceptions.dart';

/// A [startMs, endMs) window inside a whole-surah recording.
class AyahTiming extends Equatable {
  const AyahTiming({
    required this.number,
    required this.startMs,
    required this.endMs,
  });

  /// Ayah number, or `null` for the isti'adhah preamble, which is not an ayah.
  final int? number;
  final int startMs;
  final int endMs;

  Duration get start => Duration(milliseconds: startMs);
  Duration get end => Duration(milliseconds: endMs);
  Duration get duration => Duration(milliseconds: endMs - startMs);

  factory AyahTiming.fromJson(
    Map<String, dynamic> json, {
    required String assetPath,
    int? forcedNumber,
    bool numberRequired = true,
  }) {
    final int? number = forcedNumber ?? json['number'] as int?;
    if (numberRequired && (number == null || number < 1)) {
      throw CatalogValidationException(
        assetPath,
        'Timing entry has a missing or non-positive "number": '
        '${json['number']}.',
      );
    }

    final Object? startMs = json['startMs'];
    final Object? endMs = json['endMs'];
    if (startMs is! int || endMs is! int) {
      throw CatalogValidationException(
        assetPath,
        'Timing entry ${number ?? '(preamble)'} needs integer "startMs" and '
        '"endMs"; got $startMs and $endMs.',
      );
    }
    if (startMs < 0 || endMs <= startMs) {
      throw CatalogValidationException(
        assetPath,
        'Timing entry ${number ?? '(preamble)'} has an empty or negative '
        'window: startMs=$startMs, endMs=$endMs.',
      );
    }

    return AyahTiming(number: number, startMs: startMs, endMs: endMs);
  }

  @override
  List<Object?> get props => <Object?>[number, startMs, endMs];
}

/// The parsed contents of `assets/data/timings/<reciter>/<surah>.json`.
///
/// Only consulted for [AudioMode.singleFileWithTimings] reciters.
class SurahTimings extends Equatable {
  const SurahTimings({
    required this.surahNumber,
    required this.istiadhah,
    required this.ayahs,
  });

  final int surahNumber;

  /// The isti'adhah window, when the recording opens with one.
  final AyahTiming? istiadhah;

  /// Ayah timings keyed by ayah number.
  final Map<int, AyahTiming> ayahs;

  AyahTiming? timingFor(int ayahNumber) => ayahs[ayahNumber];

  factory SurahTimings.fromJson(
    Map<String, dynamic> json, {
    required int expectedSurahNumber,
    required String assetPath,
  }) {
    final Object? surah = json['surah'];
    if (surah != expectedSurahNumber) {
      throw CatalogValidationException(
        assetPath,
        'Timings file declares surah $surah but was loaded for surah '
        '$expectedSurahNumber.',
      );
    }

    final Object? rawAyahs = json['ayahs'];
    if (rawAyahs is! List) {
      throw CatalogValidationException(
        assetPath,
        'Timings file for surah $expectedSurahNumber is missing an "ayahs" '
        'list.',
      );
    }

    final Map<int, AyahTiming> ayahs = <int, AyahTiming>{};
    for (final Object? entry in rawAyahs) {
      if (entry is! Map<String, dynamic>) {
        throw CatalogValidationException(
          assetPath,
          'Timings file for surah $expectedSurahNumber has a non-object entry '
          'in "ayahs".',
        );
      }
      final AyahTiming timing = AyahTiming.fromJson(
        entry,
        assetPath: assetPath,
      );
      if (ayahs.containsKey(timing.number)) {
        throw CatalogValidationException(
          assetPath,
          'Timings file for surah $expectedSurahNumber lists ayah '
          '${timing.number} more than once.',
        );
      }
      ayahs[timing.number!] = timing;
    }

    final Object? rawIstiadhah = json['istiadhah'];
    final AyahTiming? istiadhah = rawIstiadhah is Map<String, dynamic>
        ? AyahTiming.fromJson(
            rawIstiadhah,
            assetPath: assetPath,
            numberRequired: false,
          )
        : null;

    return SurahTimings(
      surahNumber: expectedSurahNumber,
      istiadhah: istiadhah,
      ayahs: Map<int, AyahTiming>.unmodifiable(ayahs),
    );
  }

  @override
  List<Object?> get props => <Object?>[surahNumber, istiadhah, ayahs];
}
