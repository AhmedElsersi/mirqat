import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/constants/asset_paths.dart';

/// Where downloaded audio lives on the device.
///
/// A pack unzips to `audio/<reciterId>/<bitrate>/<surah3><ayah3>.mp3` under
/// the application support directory (CLAUDE.md A.5), and a streamed ayah is
/// cached to that same path — so the two are indistinguishable afterwards and
/// a surah half-streamed is a surah half-downloaded.
///
/// Resolving the directory is asynchronous and asking whether one file is
/// there is not: [prepare] is awaited once when a session loads, and every
/// lookup after it is a synchronous `existsSync`, because the resolver has to
/// answer inside `AudioSource` construction.
class AudioStorage {
  AudioStorage({Future<Directory> Function()? resolveStorageDirectory})
    : _resolveStorageDirectory =
          resolveStorageDirectory ?? getApplicationSupportDirectory;

  final Future<Directory> Function() _resolveStorageDirectory;

  Directory? _root;
  Future<Directory?>? _preparing;

  /// The application support directory, or null before [prepare] has run or
  /// when the platform gave us nowhere to write. Nothing about audio fails
  /// because of that: it means no downloads, so resolution falls through to
  /// the CDN.
  Directory? get root => _root;

  /// Resolves the storage root. Safe to call repeatedly and on every session
  /// load — the lookup happens once.
  Future<void> prepare() async {
    if (_root != null) return;
    _root = await (_preparing ??= _resolve());
    if (_root != null) await excludeFromBackup();
  }

  Future<Directory?> _resolve() async {
    try {
      return await _resolveStorageDirectory();
    } on Object {
      // No writable storage on this platform: everything streams.
      return null;
    }
  }

  /// Where [ayahNumber] of [surahNumber] would sit for this reciter, whether
  /// or not it has been downloaded. Ayah 0 is the surah's basmala. Null when
  /// there is no storage root.
  File? fileFor({
    required String reciterId,
    required int bitrate,
    required int surahNumber,
    required int ayahNumber,
  }) {
    final Directory? root = _root;
    if (root == null) return null;
    return File(
      p.join(
        root.path,
        AssetPaths.downloadedAyahFile(
          reciterId: reciterId,
          bitrate: bitrate,
          surahNumber: surahNumber,
          ayahNumber: ayahNumber,
        ),
      ),
    );
  }

  /// The file for this ayah if it is already on disk, else null.
  File? downloadedFileFor({
    required String reciterId,
    required int bitrate,
    required int surahNumber,
    required int ayahNumber,
  }) {
    final File? file = fileFor(
      reciterId: reciterId,
      bitrate: bitrate,
      surahNumber: surahNumber,
      ayahNumber: ayahNumber,
    );
    if (file == null || !file.existsSync()) return null;
    return file;
  }

  /// The first of [bitrates] that has this ayah on disk.
  ///
  /// The preferred bitrate comes first, but a surah downloaded at another one
  /// still plays from disk: changing the quality setting is a preference for
  /// the *next* download, not an instruction to stream what is already here.
  File? firstDownloadedFile({
    required String reciterId,
    required Iterable<int> bitrates,
    required int surahNumber,
    required int ayahNumber,
  }) {
    for (final int bitrate in bitrates) {
      final File? file = downloadedFileFor(
        reciterId: reciterId,
        bitrate: bitrate,
        surahNumber: surahNumber,
        ayahNumber: ayahNumber,
      );
      if (file != null) return file;
    }
    return null;
  }

  /// Keeps the audio directory out of iCloud backups.
  ///
  /// Apple rejects apps that back up re-downloadable content, and a reciter's
  /// packs are exactly that. Implemented natively on iOS (see
  /// `ios/Runner/AppDelegate.swift`); everywhere else the channel is absent
  /// and this is a no-op, which is correct rather than merely tolerated — no
  /// other platform backs this directory up.
  Future<void> excludeFromBackup() async {
    final Directory? root = _root;
    if (root == null || !Platform.isIOS) return;

    final Directory audio = Directory(
      p.join(root.path, AssetPaths.downloadedAudioDirectory),
    );
    try {
      await audio.create(recursive: true);
      await _backupChannel.invokeMethod<void>(
        'excludeFromBackup',
        <String, String>{'path': audio.path},
      );
    } on Object {
      // A device that refuses the flag still plays audio; the cost is an
      // iCloud backup larger than it should be, not a broken session.
    }
  }

  static const MethodChannel _backupChannel = MethodChannel('mirqat/storage');
}
