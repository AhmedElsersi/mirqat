import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../../core/constants/app_constants.dart';
import '../../core/constants/asset_paths.dart';
import '../../core/error/exceptions.dart';
import 'asset_reader.dart' show assetMissing;
import 'quran_database_opener.dart';

/// Opens the bundled mushaf database (`assets/data/quran.db`) — surah/ayah
/// facts, page layout and word-by-word text.
///
/// The asset itself is never opened directly: a Flutter asset is read-only
/// bundle storage, not a filesystem path sqflite can point at, so the first
/// call to [open] copies it out to a versioned file under the application
/// support directory and every call after that reopens the same file
/// read-only. Nothing is ever written back into it — download/progress state
/// lives in Hive, never here (CLAUDE.md A.2 rule 6, applied to data as well
/// as audio).
class QuranDatabase implements QuranDatabaseOpener {
  QuranDatabase({
    DatabaseFactory? factory,
    Future<Directory> Function()? resolveStorageDirectory,
  }) : _factory = factory ?? databaseFactory,
       _resolveStorageDirectory =
           resolveStorageDirectory ?? getApplicationSupportDirectory;

  final DatabaseFactory _factory;
  final Future<Directory> Function() _resolveStorageDirectory;

  static const String _filePrefix = 'quran_v';
  static const String _fileSuffix = '.db';

  Future<Database>? _opening;

  /// The open, read-only database. Safe to call repeatedly — the copy and
  /// the open both happen once, and every later call returns the same
  /// instance.
  @override
  Future<Database> open() => _opening ??= _open();

  Future<Database> _open() async {
    final Directory dir = await _resolveStorageDirectory();
    final String fileName =
        '$_filePrefix${AppConstants.quranDatabaseSchemaVersion}$_fileSuffix';
    final String targetPath = p.join(dir.path, fileName);

    await _deleteOlderVersions(dir, keep: fileName);

    if (!File(targetPath).existsSync()) {
      await _copyFromBundle(targetPath);
    }

    try {
      return await _factory.openDatabase(
        targetPath,
        options: OpenDatabaseOptions(readOnly: true),
      );
    } on Exception catch (e) {
      throw StorageException(
        'Could not open the mushaf database at "$targetPath": $e',
      );
    }
  }

  Future<void> _copyFromBundle(String targetPath) async {
    final ByteData data;
    try {
      data = await rootBundle.load(AssetPaths.quranDatabase);
    } on Exception catch (e) {
      throw assetMissing(AssetPaths.quranDatabase, e);
    }

    final File target = File(targetPath);
    await target.parent.create(recursive: true);
    // Write beside the final name, then rename, so a process killed mid-copy
    // never leaves a half-written file at the path future launches treat as
    // "already installed".
    final File staging = File('$targetPath.part');
    try {
      await staging.writeAsBytes(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        flush: true,
      );
      await staging.rename(targetPath);
    } on IOException catch (e) {
      throw StorageException(
        'Could not copy the mushaf database to "$targetPath": $e',
      );
    } finally {
      if (staging.existsSync()) await staging.delete();
    }
  }

  Future<void> _deleteOlderVersions(
    Directory dir, {
    required String keep,
  }) async {
    if (!dir.existsSync()) return;
    await for (final FileSystemEntity entity in dir.list()) {
      if (entity is! File) continue;
      final String name = p.basename(entity.path);
      final bool isVersionedCopy =
          name.startsWith(_filePrefix) &&
          (name.endsWith(_fileSuffix) || name.endsWith('$_fileSuffix.part'));
      if (isVersionedCopy && name != keep) {
        await entity.delete();
      }
    }
  }
}
