import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:dartz/dartz.dart';
import 'package:path/path.dart' as p;

import '../../core/constants/asset_paths.dart';
import '../../core/error/exceptions.dart';
import '../../core/error/failures.dart';
import '../../data/models/app_settings.dart';
import '../../data/models/audio_manifest.dart';
import '../../data/models/audio_pack.dart';
import '../../data/models/reciter.dart';
import '../../data/models/surah.dart';
import '../../data/repositories/downloads_repository.dart';
import '../../data/repositories/quran_repository.dart';
import '../../data/repositories/settings_repository.dart';
import 'audio_storage.dart';
import 'manifest_service.dart';
import 'pack_fetcher.dart';

/// Downloads a surah's audio for offline use, verifies it, and unpacks it into
/// the layout `AudioResolver` already looks in.
///
/// Every step can fail loudly, unlike the rest of the audio layer: a download
/// is something the user asked for by name, so "it did not work" is
/// information they are owed. Nothing here is required for playback — a surah
/// with no pack streams (CLAUDE.md A.6) — and nothing here ever touches
/// `quran.db` (A.2 rule 6).
class AudioPackService {
  AudioPackService({
    required ManifestService manifestService,
    required AudioStorage audioStorage,
    required DownloadsRepository downloadsRepository,
    required PackFetcherFactory packFetcher,
    QuranRepository? quranRepository,
    SettingsRepository? settingsRepository,
  }) : _manifest = manifestService,
       _storage = audioStorage,
       _downloads = downloadsRepository,
       _fetcher = packFetcher,
       _quran = quranRepository,
       _settings = settingsRepository;

  final ManifestService _manifest;
  final AudioStorage _storage;
  final DownloadsRepository _downloads;
  final PackFetcherFactory _fetcher;

  /// Used only to count what a pack *should* hold. Optional, and its absence
  /// costs a warning, never an install: the manifest's digest is the check
  /// that matters.
  final QuranRepository? _quran;

  /// Where the quality preference and the Wi-Fi-only rule come from.
  final SettingsRepository? _settings;

  final Map<String, PackDownload> _state = <String, PackDownload>{};

  /// The platform task ids of each ayah-by-ayah download in flight, so a
  /// cancel can reach all of them. A pack is one task under its own key and
  /// needs no entry here.
  final Map<String, List<String>> _batches = <String, List<String>>{};
  final StreamController<PackDownload> _changes =
      StreamController<PackDownload>.broadcast();

  /// Every state change of every download this process has started.
  Stream<PackDownload> get changes => _changes.stream;

  /// What a download is doing right now — [PackStatus.idle] when nothing has
  /// been asked for.
  PackDownload stateFor({
    required String reciterId,
    required int surahNumber,
  }) =>
      _state[InstalledPack.keyFor(reciterId, surahNumber)] ??
      PackDownload.idle(reciterId: reciterId, surahNumber: surahNumber);

  /// The packs that are actually on the device — complete or stale.
  ///
  /// A failed attempt is a row too, but it is not an install: it has no files
  /// and no size, and listing it under "saved recitations" would offer the
  /// user space to free that does not exist. [failed] is where those live.
  Future<Either<Failure, List<InstalledPack>>> installed() async =>
      (await _downloads.installed()).map(
        (List<InstalledPack> packs) => List<InstalledPack>.unmodifiable(
          packs.where((InstalledPack p) => p.state != PackState.failed),
        ),
      );

  /// Emits whenever an install is recorded or forgotten.
  Stream<void> get installChanges => _downloads.changes;

  /// Downloads, verifies and installs [surahNumber] for [reciter].
  ///
  /// Returns the recorded install, or a [DownloadFailure] describing which
  /// step refused. A surah already installed at the same version is returned
  /// as it stands rather than fetched again.
  Future<Either<Failure, InstalledPack>> download({
    required Reciter reciter,
    required int surahNumber,
  }) async {
    final String key = InstalledPack.keyFor(reciter.id, surahNumber);
    if (stateFor(reciterId: reciter.id, surahNumber: surahNumber).isBusy) {
      return Left<Failure, InstalledPack>(
        DownloadFailure(key, 'A download for $key is already running.'),
      );
    }

    try {
      _emit(reciter.id, surahNumber, PackStatus.queued);
      final InstalledPack pack = await _install(reciter, surahNumber);
      _emit(reciter.id, surahNumber, PackStatus.installed, progress: 1);
      return Right<Failure, InstalledPack>(pack);
    } on AppException catch (e) {
      await _recordFailure(reciter, surahNumber, e.message);
      return Left<Failure, InstalledPack>(failureFromException(e));
    } on Object catch (e) {
      await _recordFailure(reciter, surahNumber, '$e');
      return Left<Failure, InstalledPack>(DownloadFailure(key, '$e'));
    }
  }

  /// Every surah whose last attempt failed, oldest first.
  Future<Either<Failure, List<InstalledPack>>> failed() async =>
      (await _downloads.installed()).map(
        (List<InstalledPack> packs) => List<InstalledPack>.unmodifiable(
          packs.where((InstalledPack p) => p.state == PackState.failed),
        ),
      );

  /// Re-attempts every failed download, and answers how many succeeded.
  ///
  /// Sequential on purpose: packs are tens of megabytes each, and three at
  /// once on a phone's connection is slower than three in a row as well as
  /// harder to read on a progress bar.
  Future<Either<Failure, int>> retryFailed({
    required List<Reciter> reciters,
  }) async {
    final Either<Failure, List<InstalledPack>> pending = await failed();
    final List<InstalledPack>? packs = pending.fold(
      (Failure _) => null,
      (List<InstalledPack> p) => p,
    );
    if (packs == null) {
      return pending.map((List<InstalledPack> _) => 0);
    }

    int done = 0;
    for (final InstalledPack pack in packs) {
      final Reciter? reciter = reciters
          .where((Reciter r) => r.id == pack.reciterId)
          .firstOrNull;
      // A reciter the catalog no longer has cannot be retried; the row stays
      // so the user can still see and clear it.
      if (reciter == null) continue;
      final Either<Failure, InstalledPack> result = await download(
        reciter: reciter,
        surahNumber: pack.surahNumber,
      );
      if (result.isRight()) done++;
    }
    return Right<Failure, int>(done);
  }

  /// Reconciles what is on the device against the manifest in hand.
  ///
  /// A reciter whose manifest `version` has moved on has their downloaded
  /// surahs marked stale: the audio still plays — a superseded take beats
  /// silence — and the settings screen can then offer a re-download of that
  /// reciter alone. Answers how many rows changed.
  Future<Either<Failure, int>> reconcile() async {
    await _manifest.load();
    int changed = 0;
    for (final ManifestReciter reciter in _manifest.current.reciters) {
      final Either<Failure, int> marked = await _downloads.markStale(
        reciter.id,
        reciter.version,
      );
      final int? count = marked.fold((Failure _) => null, (int c) => c);
      if (count == null) return marked;
      changed += count;
    }
    return Right<Failure, int>(changed);
  }

  Future<void> _recordFailure(
    Reciter reciter,
    int surahNumber,
    String message,
  ) async {
    _emit(reciter.id, surahNumber, PackStatus.failed, message: message);
    // Recorded, not just emitted: an app restart must not lose the fact that
    // this surah was asked for and did not arrive.
    await _downloads.record(
      InstalledPack(
        reciterId: reciter.id,
        surahNumber: surahNumber,
        bitrate: reciter.remote?.bitrate ?? 0,
        version: reciter.remote?.version ?? '',
        ayahs: 0,
        bytes: 0,
        installedAt: DateTime.now(),
        state: PackState.failed,
      ),
    );
  }

  /// Stops a running download and cleans up the half-fetched zip.
  Future<void> cancel({
    required String reciterId,
    required int surahNumber,
  }) async {
    final String key = InstalledPack.keyFor(reciterId, surahNumber);
    await _fetcher().cancel(key);
    final List<String>? batch = _batches[key];
    if (batch != null) await _fetcher().cancelAll(batch);
    final File? zip = _zipFile(reciterId, surahNumber);
    if (zip != null && zip.existsSync()) zip.deleteSync();
    _emit(reciterId, surahNumber, PackStatus.cancelled);
  }

  /// Deletes an installed surah's files and forgets the install.
  ///
  /// The surah stays playable — it streams again — and stays readable either
  /// way, so this is only ever about disk space.
  Future<Either<Failure, Unit>> delete({
    required String reciterId,
    required int surahNumber,
    required int bitrate,
  }) async {
    final Directory? dir = _surahDirectory(reciterId, bitrate);
    try {
      if (dir != null && dir.existsSync()) {
        for (final FileSystemEntity entity in dir.listSync()) {
          if (entity is File && _isAyahOf(entity.path, surahNumber)) {
            entity.deleteSync();
          }
        }
      }
    } on FileSystemException catch (e) {
      return Left<Failure, Unit>(
        StorageFailure('Could not delete the pack files: ${e.message}'),
      );
    }

    _state.remove(InstalledPack.keyFor(reciterId, surahNumber));
    return _downloads.forget(reciterId, surahNumber);
  }

  /// Deletes everything downloaded for one reciter.
  ///
  /// Every bitrate, not just the one selected now: the point is the space, and
  /// a surah fetched at 128 before the quality was changed costs just as much.
  Future<Either<Failure, Unit>> deleteReciter(String reciterId) async {
    final Directory? root = _storage.root;
    try {
      if (root != null) {
        final Directory dir = Directory(
          p.join(root.path, AssetPaths.downloadedAudioDirectory, reciterId),
        );
        if (dir.existsSync()) dir.deleteSync(recursive: true);
      }
    } on FileSystemException catch (e) {
      return Left<Failure, Unit>(
        StorageFailure('Could not delete "$reciterId": ${e.message}'),
      );
    }

    _state.removeWhere(
      (String key, PackDownload value) => value.reciterId == reciterId,
    );
    return _downloads.forgetReciter(reciterId);
  }

  Future<InstalledPack> _install(Reciter reciter, int surahNumber) async {
    final ManifestReciter? remote = reciter.remote;
    if (remote == null) {
      throw DownloadException(
        reciter.id,
        'Reciter "${reciter.id}" is not in the manifest, so there is no pack '
        'to download. Bundled surahs are already offline.',
      );
    }
    final ManifestSurah? surah = remote.surah(surahNumber);
    if (surah == null || !reciter.remoteSurahs.contains(surahNumber)) {
      throw DownloadException(
        reciter.id,
        'The manifest offers no surah $surahNumber for "${reciter.id}".',
      );
    }

    await _storage.prepare();
    final Directory? root = _storage.root;
    if (root == null) {
      throw const StorageException(
        'This platform gave the app nowhere to write, so a pack cannot be '
        'installed. Audio still streams.',
      );
    }

    final AppSettings settings = await _readSettings();
    // The quality the user asked for, where this reciter publishes it.
    final PackVariant variant = remote.variantFor(
      surahNumber,
      preferredBitrate: settings.audioQuality.bitrate,
    )!;

    // `load` is what guarantees a manifest has been read at all; without it
    // `current` can still be the empty one and the pack url would come out
    // relative to nothing.
    await _manifest.load();

    if (!remote.hasPacks) {
      return _installAyahByAyah(
        reciter: reciter,
        remote: remote,
        surah: surah,
        variant: variant,
        settings: settings,
      );
    }

    final Uri url = _manifest.current.urlFor(
      remote.packPathFor(surahNumber, bitrate: variant.bitrate),
    );
    final File zip = _requireZipFile(reciter.id, surahNumber);
    zip.parent.createSync(recursive: true);
    if (zip.existsSync()) zip.deleteSync();

    _emit(reciter.id, surahNumber, PackStatus.downloading);
    await _fetcher().fetch(
      url: url,
      destination: zip,
      taskId: InstalledPack.keyFor(reciter.id, surahNumber),
      requiresWiFi: settings.downloadOverWifiOnly,
      onProgress: (double progress) => _emit(
        reciter.id,
        surahNumber,
        PackStatus.downloading,
        // The platform reports -1 while the total size is unknown; the bar
        // stays where it was rather than jumping backwards.
        progress: progress < 0 ? null : progress,
      ),
    );

    try {
      _emit(reciter.id, surahNumber, PackStatus.verifying, progress: 1);
      await _verify(zip, variant: variant, url: url);

      _emit(reciter.id, surahNumber, PackStatus.installing);
      final int installed = await _unpack(
        zip: zip,
        reciterId: remote.id,
        bitrate: variant.bitrate,
        surahNumber: surahNumber,
        declaredAyahs: surah.ayahs,
        hasBasmala: surah.hasBasmala,
      );

      final InstalledPack pack = InstalledPack(
        reciterId: reciter.id,
        surahNumber: surahNumber,
        bitrate: variant.bitrate,
        version: remote.version,
        ayahs: installed,
        bytes: variant.bytes,
        installedAt: DateTime.now(),
      );
      final Either<Failure, Unit> recorded = await _downloads.record(pack);
      return recorded.fold(
        (Failure f) => throw StorageException(f.message),
        (_) => pack,
      );
    } finally {
      // The zip is scaffolding either way: kept, it would double what the
      // surah costs on disk.
      if (zip.existsSync()) zip.deleteSync();
    }
  }

  /// The download for a reciter published without packs (CLAUDE.md A.5): one
  /// request per ayah, straight into the directory a pack would have unzipped
  /// to, so the resolver, delete and the stale check go on as before.
  ///
  /// There is no digest to check — nobody built a pack to digest — so each
  /// file is held to the cheap truth a pack's entries are held to: not empty,
  /// and an mp3 by its first bytes, which is what tells a recitation from a
  /// host's error page saved under its name. A file already on disk is kept
  /// rather than fetched again: it is an earlier attempt's, or one a session
  /// streamed and cached, and both are whole — the cache writes beside the
  /// file and renames only at the end. What does not arrive streams, as it
  /// did before; the surah is recorded only when every ayah is here.
  Future<InstalledPack> _installAyahByAyah({
    required Reciter reciter,
    required ManifestReciter remote,
    required ManifestSurah surah,
    required PackVariant variant,
    required AppSettings settings,
  }) async {
    final String key = InstalledPack.keyFor(reciter.id, surah.number);
    _requireSurahDirectory(
      remote.id,
      variant.bitrate,
    ).createSync(recursive: true);
    File fileFor(int ayah) => _storage.fileFor(
      reciterId: remote.id,
      bitrate: variant.bitrate,
      surahNumber: surah.number,
      ayahNumber: ayah,
    )!;
    String taskFor(int ayah) => '$key/${AssetPaths.pad3(ayah)}';

    // Ayah 000 is the basmala, and only a `separate` surah has one. `false`
    // in the manifest is authoritative and it is not asked for; `true` makes
    // it required; nothing said means ask, and forgive its absence, as a
    // missing local basmala is always forgiven (CLAUDE.md A.5).
    final Surah? catalog = await _catalogSurah(surah.number);
    final bool separate =
        catalog == null ||
        catalog.bismillahMode == BismillahMode.separatePreamble;
    final bool wantsBasmala = separate && surah.hasBasmala != false;
    final bool requiresBasmala = separate && surah.hasBasmala == true;
    final List<int> wanted = <int>[
      if (wantsBasmala) 0,
      for (int ayah = 1; ayah <= surah.ayahs; ayah++) ayah,
    ];

    final List<FileRequest> requests = <FileRequest>[
      for (final int ayah in wanted)
        if (!_looksLikeMp3(fileFor(ayah)))
          (
            url: _manifest.current.urlFor(
              remote.audioPathFor(surah.number, ayah, bitrate: variant.bitrate),
            ),
            destination: fileFor(ayah),
            taskId: taskFor(ayah),
          ),
    ];

    _emit(reciter.id, surah.number, PackStatus.downloading);
    _batches[key] = <String>[for (final FileRequest r in requests) r.taskId];
    final Map<String, String> failures;
    try {
      failures = await _fetcher().fetchAll(
        requests: requests,
        requiresWiFi: settings.downloadOverWifiOnly,
        onProgress: (double progress) => _emit(
          reciter.id,
          surah.number,
          PackStatus.downloading,
          progress: progress.clamp(0, 1),
        ),
      );
    } finally {
      _batches.remove(key);
    }

    _emit(reciter.id, surah.number, PackStatus.verifying, progress: 1);
    final List<int> missing = <int>[];
    int bytes = 0;
    for (final int ayah in wanted) {
      final File file = fileFor(ayah);
      if (_looksLikeMp3(file)) {
        bytes += file.lengthSync();
        continue;
      }
      // Whatever is there is not a recitation, and must not be found by the
      // resolver as one.
      if (file.existsSync()) file.deleteSync();
      missing.add(ayah);
    }

    if (missing.remove(0)) {
      if (requiresBasmala) {
        throw DownloadException(
          key,
          'The basmala (000) the manifest promises did not arrive'
          '${failures[taskFor(0)] == null ? '' : ': ${failures[taskFor(0)]}'}. '
          'The surah was not installed.',
        );
      }
      _warn(
        '${reciter.id} surah ${surah.number}: no basmala file; the manifest '
        'did not promise one, so the surah opens on ayah 1.',
      );
    }
    if (missing.isNotEmpty) {
      final String reason =
          failures[taskFor(missing.first)] ?? 'the file was not a recitation';
      throw DownloadException(
        key,
        '${missing.length} of ${surah.ayahs} ayahs did not arrive (ayah '
        '${missing.take(8).join(', ')}: $reason). The ones that did stay on '
        'the device; the rest streams.',
      );
    }

    final InstalledPack pack = InstalledPack(
      reciterId: reciter.id,
      surahNumber: surah.number,
      bitrate: variant.bitrate,
      version: remote.version,
      ayahs: surah.ayahs,
      bytes: bytes,
      installedAt: DateTime.now(),
    );
    final Either<Failure, Unit> recorded = await _downloads.record(pack);
    return recorded.fold(
      (Failure f) => throw StorageException(f.message),
      (_) => pack,
    );
  }

  /// Byte length, then sha256, both against the manifest and both **before**
  /// anything is unzipped.
  ///
  /// Length first because it is free and catches the common failure — a
  /// truncated or interrupted download — without reading 40 MB twice. The
  /// digest is hashed in chunks, because reading a pack whole to hash it would
  /// spike memory on the devices this app is for. Neither check is advisory: a
  /// pack that fails either is never unzipped and the surah is never marked
  /// complete. The one thing worse than no recitation is the wrong recitation.
  Future<void> _verify(
    File zip, {
    required PackVariant variant,
    required Uri url,
  }) async {
    final int actualBytes = zip.lengthSync();
    if (variant.bytes > 0 && actualBytes != variant.bytes) {
      throw DownloadException(
        url.toString(),
        'The downloaded pack is $actualBytes bytes; the manifest says '
        '${variant.bytes}. It was not installed.',
      );
    }

    if (variant.sha256.isEmpty) {
      // A manifest entry with no digest is a CDN that cannot be checked. The
      // pack is still installed, because refusing it would make a whole
      // reciter undownloadable over a field the app does not control.
      _warn('pack at $url has no sha256 in the manifest; installed unverified');
      return;
    }

    final Digest digest = await sha256.bind(zip.openRead()).first;
    final String actual = digest.toString();
    if (actual != variant.sha256.toLowerCase()) {
      throw DownloadException(
        url.toString(),
        'The downloaded pack does not match the manifest: expected sha256 '
        '${variant.sha256}, got $actual.',
      );
    }
  }

  /// Unzips [zip] into `audio/<reciterId>/<bitrate>/`, and answers how many
  /// ayahs landed.
  ///
  /// Only entries whose *base name* is `<surah3><ayah3>.mp3` for this surah
  /// are written, and only ever by that base name. The zip comes off a CDN:
  /// an entry called `../../../secrets` must not be able to write outside the
  /// reciter's own directory, and nothing decides where a file goes except
  /// this method (CLAUDE.md A.5).
  Future<int> _unpack({
    required File zip,
    required String reciterId,
    required int bitrate,
    required int surahNumber,
    required int declaredAyahs,
    required bool? hasBasmala,
  }) async {
    final Directory target = _requireSurahDirectory(reciterId, bitrate)
      ..createSync(recursive: true);

    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(zip.readAsBytesSync());
    } on Object catch (e) {
      throw DownloadException(zip.path, 'The pack is not a readable zip: $e.');
    }

    final Set<int> written = <int>{};
    for (final ArchiveFile entry in archive) {
      if (!entry.isFile) continue;
      final String name = p.basename(entry.name);
      final int? ayah = _ayahOf(name, surahNumber);
      if (ayah == null) continue;

      final List<int>? bytes = entry.content as List<int>?;
      if (bytes == null || bytes.isEmpty) continue;
      File(p.join(target.path, name)).writeAsBytesSync(bytes, flush: true);
      written.add(ayah);
    }

    if (written.isEmpty) {
      throw DownloadException(
        zip.path,
        'The pack holds no ayah files for surah $surahNumber.',
      );
    }

    await _warnAboutCount(
      reciterId: reciterId,
      surahNumber: surahNumber,
      declaredAyahs: declaredAyahs,
      hasBasmala: hasBasmala,
      written: written,
    );

    // The basmala is not an ayah and is never counted as one (CLAUDE.md A.5).
    return written.where((int ayah) => ayah > 0).length;
  }

  /// Says so when a pack does not hold what the catalog would predict.
  ///
  /// A warning and not a refusal, deliberately: the sha256 above is the real
  /// check, and it has already passed, so these bytes *are* the pack the
  /// manifest published. A count that disagrees means the catalog and the
  /// recording disagree — worth a line in the log, not worth denying someone
  /// a surah the CDN vouched for.
  Future<void> _warnAboutCount({
    required String reciterId,
    required int surahNumber,
    required int declaredAyahs,
    required bool? hasBasmala,
    required Set<int> written,
  }) async {
    final Surah? surah = await _catalogSurah(surahNumber);
    final int ayahCount = surah?.ayahCount ?? declaredAyahs;
    // `separate` surahs carry their basmala as ayah 000, so they hold one
    // file more than they have ayahs.
    final bool expectsBasmala =
        hasBasmala ?? (surah?.bismillahMode == BismillahMode.separatePreamble);
    final int expected = ayahCount + (expectsBasmala ? 1 : 0);

    if (written.length == expected) return;

    final List<int> missing = <int>[
      for (int ayah = 1; ayah <= ayahCount; ayah++)
        if (!written.contains(ayah)) ayah,
    ];
    _warn(
      '$reciterId surah $surahNumber: pack holds ${written.length} files, '
      'expected $expected'
      '${missing.isEmpty ? '' : ' (missing ayah ${missing.take(8).join(', ')})'}'
      '. Installed anyway — the manifest digest verified.',
    );
  }

  Future<Surah?> _catalogSurah(int surahNumber) async {
    final QuranRepository? quran = _quran;
    if (quran == null) return null;
    return (await quran.getSurah(
      surahNumber,
    )).fold((Failure _) => null, (Surah s) => s);
  }

  Future<AppSettings> _readSettings() async {
    final SettingsRepository? settings = _settings;
    if (settings == null) return const AppSettings();
    return (await settings.read()).getOrElse(() => const AppSettings());
  }

  /// Developer-facing. Nothing here is worth a dialog: every one of these is
  /// something the user can neither cause nor fix.
  void _warn(String message) =>
      developer.log(message, name: 'AudioPackService');

  /// The ayah number a pack entry holds, or null when the name is not this
  /// surah's `<surah3><ayah3>.mp3`.
  static int? _ayahOf(String fileName, int surahNumber) {
    final RegExpMatch? match = RegExp(
      r'^(\d{3})(\d{3})\.mp3$',
    ).firstMatch(fileName);
    if (match == null) return null;
    if (int.parse(match.group(1)!) != surahNumber) return null;
    return int.parse(match.group(2)!);
  }

  static bool _isAyahOf(String path, int surahNumber) =>
      _ayahOf(p.basename(path), surahNumber) != null;

  /// Not empty, and an mp3 by its first bytes — an ID3 tag or a frame sync.
  ///
  /// Not a decoder. It tells a recitation from a host's error page saved
  /// under its name, which is the failure that actually happens.
  static bool _looksLikeMp3(File file) {
    if (!file.existsSync()) return false;
    final RandomAccessFile handle = file.openSync();
    try {
      final Uint8List head = handle.readSync(3);
      if (head.length == 3 &&
          head[0] == 0x49 &&
          head[1] == 0x44 &&
          head[2] == 0x33) {
        return true;
      }
      return head.length >= 2 && head[0] == 0xFF && (head[1] & 0xE0) == 0xE0;
    } finally {
      handle.closeSync();
    }
  }

  Directory? _surahDirectory(String reciterId, int bitrate) {
    final Directory? root = _storage.root;
    if (root == null) return null;
    return Directory(
      p.join(
        root.path,
        AssetPaths.downloadedAudioDirectory,
        reciterId,
        '$bitrate',
      ),
    );
  }

  Directory _requireSurahDirectory(String reciterId, int bitrate) =>
      _surahDirectory(reciterId, bitrate)!;

  /// Where a pack zip is fetched to: beside the audio, in a directory whose
  /// name cannot be mistaken for a reciter id.
  File? _zipFile(String reciterId, int surahNumber) {
    final Directory? root = _storage.root;
    if (root == null) return null;
    return File(
      p.join(
        root.path,
        AssetPaths.downloadedAudioDirectory,
        '.packs',
        '$reciterId-${AssetPaths.pad3(surahNumber)}.zip',
      ),
    );
  }

  File _requireZipFile(String reciterId, int surahNumber) =>
      _zipFile(reciterId, surahNumber)!;

  void _emit(
    String reciterId,
    int surahNumber,
    PackStatus status, {
    double? progress,
    String? message,
  }) {
    final String key = InstalledPack.keyFor(reciterId, surahNumber);
    final PackDownload next =
        (_state[key] ??
                PackDownload.idle(
                  reciterId: reciterId,
                  surahNumber: surahNumber,
                ))
            .copyWith(status: status, progress: progress, message: message);
    if (next == _state[key]) return;
    _state[key] = next;
    if (!_changes.isClosed) _changes.add(next);
  }

  Future<void> dispose() => _changes.close();
}

/// How the service gets a fetcher.
///
/// A factory rather than an instance so the platform downloader is not built
/// until something is actually downloaded — on most launches nothing is.
typedef PackFetcherFactory = PackFetcher Function();
