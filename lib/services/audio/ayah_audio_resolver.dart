import 'package:just_audio/just_audio.dart';

import '../../core/constants/asset_paths.dart';
import '../../core/error/exceptions.dart';
import '../../data/models/ayah_timing.dart';
import '../../data/models/reciter.dart';

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

  /// The isti'adhah preamble, or null when this reciter has none.
  ///
  /// Takes only a reciter: there is nothing surah-dependent left to pass. It
  /// is not an ayah and never enters the queue as a `PlaybackUnit`.
  AudioSource? resolveIstiadhah({required Reciter reciter});

  /// The standalone bismillah clip, or null when this reciter has none.
  ///
  /// Answers only "does this reciter have the clip". Whether a given session
  /// *plays* it is a separate decision that belongs to the catalog's
  /// `bismillahMode` — see `SessionPreambles`.
  AudioSource? resolveBismillah({required Reciter reciter});

  /// The silence spacer used to build gaps between units.
  AudioSource resolveSpacer();
}

/// Shared preamble and spacer handling — identical in both audio modes.
///
/// Both preambles ship as their own reciter-level files whichever way the
/// ayahs are laid out, so there is no per-mode override and no fallback chain.
/// A `single_file_with_timings` reciter who ships no standalone clips declares
/// `hasIstiadhah`/`hasBismillah` false; the preamble windows in the timings
/// files stay unused, as documented there.
mixin _PreambleResolution on AyahAudioResolver {
  @override
  AudioSource? resolveIstiadhah({required Reciter reciter}) =>
      reciter.hasIstiadhah
      ? AudioSource.asset(AssetPaths.istiadhahFile(reciter.basePath))
      : null;

  @override
  AudioSource? resolveBismillah({required Reciter reciter}) =>
      reciter.hasBismillah
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
}
