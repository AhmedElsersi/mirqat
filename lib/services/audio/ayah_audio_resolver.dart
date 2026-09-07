import 'package:just_audio/just_audio.dart';

import '../../core/constants/asset_paths.dart';
import '../../core/error/exceptions.dart';
import '../../data/models/ayah_timing.dart';
import '../../data/models/reciter.dart';
import '../../data/models/surah.dart';

/// Turns an ayah number into something the player can play.
///
/// One interface, one implementation per [AudioMode]. The player layer never
/// learns which mode is in use, so adding a reciter is assets plus one object
/// in `reciters.json` (CLAUDE.md A.6).
abstract class AyahAudioResolver {
  AudioSource resolve({
    required Reciter reciter,
    required int surah,
    required int ayah,
  });

  /// The isti'adhah preamble, or null when this reciter has none. It is not an
  /// ayah and never enters the queue as a `PlaybackUnit`.
  AudioSource? resolveIstiadhah({required Reciter reciter, required int surah});

  /// The standalone bismillah clip, for surahs whose `bismillahMode` is
  /// `separate_preamble`. Null for every other mode.
  AudioSource? resolveBismillah({
    required Reciter reciter,
    required Surah surah,
  });

  /// The silence spacer used to build gaps between units.
  AudioSource resolveSpacer();
}

/// Shared preamble and spacer handling — identical in both audio modes,
/// because preambles ship as their own files either way.
mixin _PreambleResolution on AyahAudioResolver {
  @override
  AudioSource? resolveIstiadhah({
    required Reciter reciter,
    required int surah,
  }) => reciter.hasIstiadhah
      ? AudioSource.asset(AssetPaths.istiadhahFile(reciter.basePath, surah))
      : null;

  @override
  AudioSource? resolveBismillah({
    required Reciter reciter,
    required Surah surah,
  }) => surah.needsBismillahPreamble
      ? AudioSource.asset(AssetPaths.bismillahFile(reciter.basePath))
      : null;

  @override
  AudioSource resolveSpacer() => AudioSource.asset(AssetPaths.silenceSpacer);
}

/// `<basePath>/<surah3>/<ayah3>.mp3`
class PerAyahFilesResolver extends AyahAudioResolver with _PreambleResolution {
  PerAyahFilesResolver();

  @override
  AudioSource resolve({
    required Reciter reciter,
    required int surah,
    required int ayah,
  }) =>
      AudioSource.asset(AssetPaths.perAyahFile(reciter.basePath, surah, ayah));
}

/// One whole-surah file, clipped to each ayah's window.
class TimingsAudioResolver extends AyahAudioResolver with _PreambleResolution {
  TimingsAudioResolver(this._timings);

  final SurahTimings _timings;

  @override
  AudioSource resolve({
    required Reciter reciter,
    required int surah,
    required int ayah,
  }) {
    final AyahTiming? timing = _timings.timingFor(ayah);
    if (timing == null) {
      throw CatalogValidationException(
        AssetPaths.timingsForSurah(reciter.id, surah),
        'No timing for ayah $surah:$ayah, so it cannot be played.',
      );
    }
    return ClippingAudioSource(
      child: AudioSource.asset(AssetPaths.surahFile(reciter.basePath, surah)),
      start: timing.start,
      end: timing.end,
    );
  }

  /// The isti'adhah is a separate clip even here — the timings file's own
  /// window into the full recording is kept only for switching modes.
  @override
  AudioSource? resolveIstiadhah({
    required Reciter reciter,
    required int surah,
  }) {
    if (!reciter.hasIstiadhah) return null;
    final AyahTiming? timing = _timings.istiadhah;
    if (timing == null) {
      return AudioSource.asset(
        AssetPaths.istiadhahFile(reciter.basePath, surah),
      );
    }
    return ClippingAudioSource(
      child: AudioSource.asset(AssetPaths.surahFile(reciter.basePath, surah)),
      start: timing.start,
      end: timing.end,
    );
  }
}
