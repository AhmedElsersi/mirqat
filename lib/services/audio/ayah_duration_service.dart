import 'package:just_audio/just_audio.dart';

import '../../core/constants/asset_paths.dart';
import '../../core/error/exceptions.dart';
import '../../data/models/ayah_timing.dart';
import '../../data/models/reciter.dart';
import '../../data/models/surah.dart';
import '../../data/repositories/quran_repository.dart';

/// Real clip lengths, so the session summary is measured rather than guessed.
///
/// For a `single_file_with_timings` reciter the lengths come straight from the
/// timings file. For `per_ayah_files` each clip is opened once and its
/// duration cached for the life of the process.
class AyahDurationService {
  AyahDurationService({required QuranRepository quranRepository, this.probe})
    : _quran = quranRepository;

  final QuranRepository _quran;

  /// Injectable so tests can supply their own player.
  AudioPlayer? probe;

  final Map<String, Map<int, Duration>> _cache = <String, Map<int, Duration>>{};

  AudioPlayer get _prober => probe ??= AudioPlayer();

  /// Duration of every ayah of [surah] as recited by [reciter].
  Future<Map<int, Duration>> durationsFor({
    required Reciter reciter,
    required Surah surah,
  }) async {
    final String key = '${reciter.id}:${surah.number}';
    final Map<int, Duration>? cached = _cache[key];
    if (cached != null) return cached;

    final Map<int, Duration> durations = switch (reciter.audioMode) {
      AudioMode.singleFileWithTimings => await _fromTimings(reciter, surah),
      AudioMode.perAyahFiles => await _byProbing(reciter, surah),
    };

    return _cache[key] = Map<int, Duration>.unmodifiable(durations);
  }

  Future<Map<int, Duration>> _fromTimings(Reciter reciter, Surah surah) async {
    final result = await _quran.getTimings(
      reciterId: reciter.id,
      surahNumber: surah.number,
    );
    return result.fold(
      (failure) => throw SessionConfigException(failure.message),
      (SurahTimings timings) => <int, Duration>{
        for (final MapEntry<int, AyahTiming> e in timings.ayahs.entries)
          e.key: e.value.duration,
      },
    );
  }

  Future<Map<int, Duration>> _byProbing(Reciter reciter, Surah surah) async {
    final Map<int, Duration> durations = <int, Duration>{};

    for (int ayah = 1; ayah <= surah.ayahCount; ayah++) {
      final String path = AssetPaths.perAyahFile(
        reciter.basePath,
        surah.number,
        ayah,
      );
      final Duration? duration = await _prober.setAudioSource(
        AudioSource.asset(path),
        preload: true,
      );
      if (duration == null) {
        throw AssetNotFoundException(
          path,
          'Could not read the length of "$path", so the session summary '
          'cannot be computed.',
        );
      }
      durations[ayah] = duration;
    }

    return durations;
  }

  Future<void> dispose() async {
    await probe?.dispose();
    probe = null;
  }
}
