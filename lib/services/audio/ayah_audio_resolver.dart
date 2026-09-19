import 'package:just_audio/just_audio.dart';

import '../../core/constants/asset_paths.dart';
import '../../core/error/exceptions.dart';
import '../../data/models/ayah_timing.dart';
import '../../data/models/reciter.dart';

/// Turns an ayah number into the bundled asset that holds it.
///
/// One implementation per [AudioMode], and this is the *bundled* arm only:
/// which asset a surah that ships inside the app is laid out as. Where an
/// ayah comes from when it does not ship — a downloaded pack, or the CDN — is
/// `AudioResolver`'s decision, and manifest audio is per-ayah files whatever
/// mode a reciter's bundled surahs use (CLAUDE.md A.5, A.6).
///
/// The preambles and the spacer are not here: they are fixed reciter-level
/// assets with no mode and no fallback chain, so they belong beside the rest
/// of the resolution decision rather than inside a layout strategy.
abstract class AyahAudioResolver {
  AudioSource resolve({
    required Reciter reciter,
    required int surah,
    required int ayah,
  });
}

/// `<basePath>/<surah3>/<ayah3>.mp3`
class PerAyahFilesResolver extends AyahAudioResolver {
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
class TimingsAudioResolver extends AyahAudioResolver {
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
