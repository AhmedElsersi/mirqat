import 'dart:io';

import 'package:dartz/dartz.dart';
import 'package:just_audio/just_audio.dart';

import '../../core/constants/asset_paths.dart';
import '../../core/error/exceptions.dart';
import '../../core/error/failures.dart';
import '../../data/models/audio_manifest.dart';
import '../../data/models/ayah_timing.dart';
import '../../data/models/reciter.dart';
import '../../data/models/app_settings.dart';
import '../../data/models/surah.dart';
import '../../data/repositories/quran_repository.dart';
import '../../data/repositories/settings_repository.dart';
import 'audio_storage.dart';
import 'ayah_audio_resolver.dart';
import 'manifest_service.dart';

/// The one place that knows where audio lives and whether we are online
/// (CLAUDE.md A.6).
///
/// For each ayah, in order: a bundled asset, a file a pack download left on
/// disk, then the CDN. The player layer never learns which of the three it
/// got — it is handed an `AudioSource` and plays it.
///
/// Resolution is bound to a reciter and a surah up front by [forSurah],
/// because the asynchronous parts — the storage root, the manifest, a timings
/// file — have to be settled before a queue is built. Everything after that
/// is synchronous, so building a queue of hundreds of entries does not await
/// once per ayah.
class AudioResolver {
  AudioResolver({
    required QuranRepository quranRepository,
    required ManifestService manifestService,
    required AudioStorage audioStorage,
    SettingsRepository? settingsRepository,
  }) : _quran = quranRepository,
       _manifest = manifestService,
       _storage = audioStorage,
       _settings = settingsRepository;

  final QuranRepository _quran;
  final ManifestService _manifest;
  final AudioStorage _storage;

  /// Where the quality preference comes from. Optional: without it every
  /// reciter is served at their own bitrate, which is what a reciter with one
  /// bitrate does anyway.
  final SettingsRepository? _settings;

  /// Everything one session needs to know about where its audio is.
  ///
  /// Throws [SessionConfigException] when a bundled `single_file_with_timings`
  /// surah has no timings file: that surah cannot be cut into ayahs, and
  /// guessing the windows would recite the wrong words.
  Future<SurahAudio> forSurah({
    required Reciter reciter,
    required Surah surah,
  }) async {
    await _storage.prepare();
    // The manifest is only ever read from memory here; `load` is what
    // guarantees the first read has happened, and it never waits on the
    // network (CLAUDE.md A.2 rule 3).
    await _manifest.load();

    return SurahAudio._(
      reciter,
      surah,
      // The bundled arm exists only for a surah that ships inside the app;
      // everything else resolves to a download or the CDN.
      reciter.isBundledSurah(surah.number)
          ? await _bundledResolver(reciter, surah)
          : null,
      _manifest.current,
      _storage,
      await preferredBitrate(),
    );
  }

  /// The bitrate the user asked for, or null when nothing has been chosen.
  ///
  /// A settings read that fails is not worth failing a session over: the
  /// reciter's own bitrate is always a valid answer.
  Future<int?> preferredBitrate() async {
    final SettingsRepository? settings = _settings;
    if (settings == null) return null;
    final AppSettings values = (await settings.read()).getOrElse(
      () => const AppSettings(),
    );
    return values.audioQuality.bitrate;
  }

  Future<AyahAudioResolver> _bundledResolver(
    Reciter reciter,
    Surah surah,
  ) async {
    switch (reciter.audioMode) {
      case AudioMode.perAyahFiles:
        return PerAyahFilesResolver();
      case AudioMode.singleFileWithTimings:
        final Either<Failure, SurahTimings> result = await _quran.getTimings(
          reciterId: reciter.id,
          surahNumber: surah.number,
        );
        return result.fold(
          (Failure failure) => throw SessionConfigException(failure.message),
          TimingsAudioResolver.new,
        );
    }
  }
}

/// One reciter's audio for one surah, already located.
class SurahAudio {
  // Positional: a named parameter cannot be a private initializing formal,
  // and the argument names would otherwise just repeat the field names.
  SurahAudio._(
    this._reciter,
    this._surah,
    this._bundled,
    this._manifest,
    this._storage,
    this._preferredBitrate,
  );

  final Reciter _reciter;
  final Surah _surah;

  /// How this surah's bundled assets are laid out, or null when the surah
  /// does not ship inside the app.
  final AyahAudioResolver? _bundled;
  final AudioManifest _manifest;
  final AudioStorage _storage;

  /// The quality the user asked for, which this reciter may or may not
  /// publish.
  final int? _preferredBitrate;

  /// The bitrate this surah streams at: the preference where the reciter has
  /// it, their own otherwise.
  int get bitrate => _bitrateFor(_surah.number);

  int _bitrateFor(int surahNumber) =>
      _reciter.remote?.bitrateFor(
        surahNumber,
        preferredBitrate: _preferredBitrate,
      ) ??
      0;

  /// Every bitrate worth looking for on disk, the streaming one first.
  List<int> _localBitratesFor(int surahNumber) {
    final ManifestReciter? remote = _reciter.remote;
    if (remote == null) return const <int>[];
    final int streaming = _bitrateFor(surahNumber);
    return <int>[
      streaming,
      ...remote.bitratesFor(surahNumber).where((int b) => b != streaming),
    ];
  }

  /// Where [ayah] of this surah comes from.
  ///
  /// Throws [SessionConfigException] when the answer is nowhere. A session is
  /// only ever started for a reciter who has the surah, so this is a
  /// contradiction between the catalog and the manifest rather than something
  /// a user can reach.
  AudioSource sourceFor(int ayah) {
    final AudioSource? source = _sourceFor(ayah);
    if (source != null) return source;
    throw SessionConfigException(
      'No audio for ${_surah.number}:$ayah from reciter "${_reciter.id}" — '
      'it is neither bundled, nor downloaded, nor in the manifest.',
    );
  }

  /// The basmala that precedes ayah 1 of a `separate` surah, or null when
  /// this reciter has none.
  ///
  /// Two layouts, one answer: a bundled reciter's single `bismillah.mp3`
  /// serves every surah, while a manifest reciter's basmala is ayah 0 of the
  /// surah itself (CLAUDE.md A.5). Whether a session plays it at all is
  /// `SessionPreambles`' decision, keyed on the surah's `bismillahMode`.
  AudioSource? basmala() {
    final AudioSource? clip = _bundledClip(
      _reciter.hasBismillah,
      AssetPaths.bismillahFile,
    );
    if (clip != null) return clip;

    // A manifest that declares no basmala file for this surah is believed —
    // the alternative is a session that opens on a 404. The basmala is then
    // borrowed from the reciter's own recording of the ayah that *is* the
    // basmala, where the catalog has named that surah and the reciter has it
    // (CLAUDE.md A.5). Otherwise nothing is queued.
    if (_reciter.remote?.surah(_surah.number)?.hasBasmala == false) {
      return _borrowsBasmala
          ? _remoteSourceFor(_reciter.basmalaAyahSurah!, 1)
          : null;
    }
    return _sourceFor(0);
  }

  /// Whether this surah's basmala is borrowed rather than its own `000`.
  bool get _borrowsBasmala =>
      _reciter.remote?.surah(_surah.number)?.hasBasmala == false &&
      _reciter.borrowsBasmala;

  /// The isti'adhah, or null when this reciter has none. Bundled only: it is
  /// not part of any surah, so there is nothing for the manifest to carry.
  AudioSource? istiadhah() =>
      _bundledClip(_reciter.hasIstiadhah, AssetPaths.istiadhahFile);

  /// Whether [ayah] is already on the device — a bundled asset or a file a
  /// download left behind — and so needs no network.
  ///
  /// Asked by anything that would have to *load* a clip rather than play it,
  /// the session summary's duration probe above all: measuring a streamed
  /// surah would download the whole thing to draw one line of text.
  bool isLocal(int ayah) {
    if (_bundled != null && ayah > 0) return true;

    final ManifestReciter? remote = _reciter.remote;
    if (remote == null) return false;
    // A borrowed basmala is local when the ayah it is borrowed from is.
    final (int surahNumber, int ayahNumber) = ayah == 0 && _borrowsBasmala
        ? (_reciter.basmalaAyahSurah!, 1)
        : (_surah.number, ayah);
    return _storage.firstDownloadedFile(
          reciterId: remote.id,
          bitrates: _localBitratesFor(surahNumber),
          surahNumber: surahNumber,
          ayahNumber: ayahNumber,
        ) !=
        null;
  }

  /// The silence spacer used to build gaps between units. Always bundled —
  /// a gap is never worth a network request.
  AudioSource spacer() => AudioSource.asset(AssetPaths.silenceSpacer);

  AudioSource? _bundledClip(bool present, String Function(String) path) =>
      present ? AudioSource.asset(path(_reciter.basePath)) : null;

  /// The fallback chain, in A.6's order. Ayah 0 is the surah's basmala.
  AudioSource? _sourceFor(int ayah) {
    final AyahAudioResolver? bundled = _bundled;
    if (bundled != null && ayah > 0) {
      return bundled.resolve(
        reciter: _reciter,
        surah: _surah.number,
        ayah: ayah,
      );
    }

    return _remoteSourceFor(_surah.number, ayah);
  }

  /// The downloaded-or-streamed arms for any surah of this reciter — this
  /// one, or the one a basmala is borrowed from.
  AudioSource? _remoteSourceFor(int surahNumber, int ayah) {
    final ManifestReciter? remote = _reciter.remote;
    if (remote == null || !_reciter.remoteSurahs.contains(surahNumber)) {
      return null;
    }
    final int bitrate = _bitrateFor(surahNumber);

    final File? downloaded = _storage.firstDownloadedFile(
      reciterId: remote.id,
      bitrates: _localBitratesFor(surahNumber),
      surahNumber: surahNumber,
      ayahNumber: ayah,
    );
    if (downloaded != null) return AudioSource.file(downloaded.path);

    // Streamed, and cached to the very path a pack download would have
    // written: whatever a session streams once it plays from disk after,
    // which is what makes a repetition session over a slow connection
    // survive (CLAUDE.md A.6).
    // LockCachingAudioSource is marked experimental in just_audio 0.10 and is
    // the only source in the package that caches while it plays. A
    // memorization session recites the same ayah five to twenty times, so on a
    // plain ProgressiveAudioSource that is five to twenty downloads of the
    // same file; the lint is suppressed rather than the feature given up.
    // ignore: experimental_member_use
    return LockCachingAudioSource(
      _manifest.urlFor(
        remote.audioPathFor(surahNumber, ayah, bitrate: bitrate),
      ),
      cacheFile: _storage.fileFor(
        reciterId: remote.id,
        bitrate: bitrate,
        surahNumber: surahNumber,
        ayahNumber: ayah,
      ),
    );
  }
}
