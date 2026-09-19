import 'package:just_audio/just_audio.dart';

import '../../core/error/exceptions.dart';
import '../../data/models/ayah_timing.dart';
import '../../data/models/reciter.dart';
import '../../data/models/surah.dart';
import '../../data/repositories/quran_repository.dart';
import 'audio_resolver.dart';

/// Real clip lengths, so the session summary is measured rather than guessed.
///
/// For a bundled `single_file_with_timings` surah the lengths come straight
/// from the timings file. Otherwise each clip is opened once and its duration
/// cached for the life of the process — but only when the clip is already on
/// the device. A surah that would have to be streamed is left unmeasured: the
/// summary then shows no duration, which is honest, where downloading a whole
/// surah to draw one line of text is not.
class AyahDurationService {
  AyahDurationService({
    required QuranRepository quranRepository,
    required AudioResolver audioResolver,
    this.probe,
  }) : _quran = quranRepository,
       _resolver = audioResolver;

  final QuranRepository _quran;
  final AudioResolver _resolver;

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

    // A reciter's mode describes their *bundled* layout only: manifest audio
    // is per-ayah files whatever mode their own surahs use, so a timings
    // reciter's streamed surah is probed like any other (CLAUDE.md A.5).
    final Map<int, Duration> durations = switch (reciter.audioMode) {
      AudioMode.singleFileWithTimings
          when reciter.isBundledSurah(surah.number) =>
        await _fromTimings(reciter, surah),
      _ => await _byProbing(reciter, surah),
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
    final SurahAudio sources = await _resolver.forSurah(
      reciter: reciter,
      surah: surah,
    );
    final Map<int, Duration> durations = <int, Duration>{};

    for (int ayah = 1; ayah <= surah.ayahCount; ayah++) {
      // One remote ayah leaves the whole surah unmeasured rather than
      // half-measured: a partial map cannot be added up into a session
      // length, and filling the hole with an average is exactly the guess
      // this service exists to avoid.
      if (!sources.isLocal(ayah)) return const <int, Duration>{};

      final AudioSource source = sources.sourceFor(ayah);
      final Duration? duration = await _prober.setAudioSource(
        source,
        preload: true,
      );
      if (duration == null) {
        throw AssetNotFoundException(
          '${reciter.basePath}/${surah.number}:$ayah',
          'Could not read the length of ${surah.number}:$ayah for reciter '
              '"${reciter.id}", so the session summary cannot be computed.',
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
