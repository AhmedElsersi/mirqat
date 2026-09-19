import 'dart:async';

import 'package:sqflite_common/sqlite_api.dart';

import '../../core/error/exceptions.dart';
import '../models/audio_pack.dart';
import 'downloads_database.dart';

/// Which audio packs are on the device, in the app's own `downloads.db`.
///
/// The files themselves stay the real truth — `AudioResolver` asks the
/// filesystem on every lookup, never this table, which is what lets a deleted
/// surah fall back to streaming with no restart. These rows answer the
/// questions a directory walk cannot: which version a surah was fetched at,
/// how big the pack was, and which downloads failed and could be retried.
abstract class DownloadsLocalDataSource {
  Future<void> open();

  Future<List<InstalledPack>> list();

  Future<InstalledPack?> get(String reciterId, int surahNumber);

  Future<void> record(InstalledPack pack);

  Future<void> remove(String reciterId, int surahNumber);

  /// Forgets every row for one reciter, whatever state it is in.
  Future<void> removeReciter(String reciterId);

  /// Marks every one of [reciterId]'s complete surahs stale.
  ///
  /// Called when the manifest's `version` for that reciter no longer matches
  /// what was fetched: the audio on disk is a reading the CDN has replaced,
  /// and it keeps playing until the user re-downloads — silence would be worse
  /// than a superseded take.
  Future<int> markReciterStale(String reciterId, String manifestVersion);

  /// Fires once per write, for screens showing a list they did not write.
  Stream<void> watchChanges();
}

class DownloadsLocalDataSourceImpl implements DownloadsLocalDataSource {
  DownloadsLocalDataSourceImpl(this._database);

  final DownloadsDatabase _database;

  Future<Database>? _opening;
  final StreamController<void> _changes = StreamController<void>.broadcast();

  static const String _table = 'downloads';

  /// Opens the database, once. Every method below awaits this rather than
  /// requiring a prior call, so registering this data source never touches
  /// sqflite — which is what lets a test swap the engine in first.
  @override
  Future<void> open() async => _db;

  Future<Database> get _db => _opening ??= _database.open();

  @override
  Future<List<InstalledPack>> list() async {
    final List<Map<String, Object?>> rows = await (await _db).query(
      _table,
      orderBy: 'reciter_id ASC, surah ASC',
    );
    return List<InstalledPack>.unmodifiable(rows.map(InstalledPack.fromRow));
  }

  @override
  Future<InstalledPack?> get(String reciterId, int surahNumber) async {
    final List<Map<String, Object?>> rows = await (await _db).query(
      _table,
      where: 'reciter_id = ? AND surah = ?',
      whereArgs: <Object?>[reciterId, surahNumber],
      limit: 1,
    );
    return rows.isEmpty ? null : InstalledPack.fromRow(rows.first);
  }

  @override
  Future<void> record(InstalledPack pack) async {
    try {
      await (await _db).insert(
        _table,
        pack.toRow(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } on DatabaseException catch (e) {
      throw StorageException('Could not record pack "${pack.key}": $e');
    }
    _announce();
  }

  @override
  Future<void> remove(String reciterId, int surahNumber) async {
    try {
      await (await _db).delete(
        _table,
        where: 'reciter_id = ? AND surah = ?',
        whereArgs: <Object?>[reciterId, surahNumber],
      );
    } on DatabaseException catch (e) {
      throw StorageException('Could not forget "$reciterId:$surahNumber": $e');
    }
    _announce();
  }

  @override
  Future<void> removeReciter(String reciterId) async {
    try {
      await (await _db).delete(
        _table,
        where: 'reciter_id = ?',
        whereArgs: <Object?>[reciterId],
      );
    } on DatabaseException catch (e) {
      throw StorageException('Could not forget "$reciterId": $e');
    }
    _announce();
  }

  @override
  Future<int> markReciterStale(String reciterId, String manifestVersion) async {
    final int changed = await (await _db).update(
      _table,
      <String, Object?>{
        'state': PackState.stale.storageValue,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'reciter_id = ? AND version != ? AND state = ?',
      whereArgs: <Object?>[
        reciterId,
        manifestVersion,
        PackState.complete.storageValue,
      ],
    );
    if (changed > 0) _announce();
    return changed;
  }

  void _announce() {
    if (!_changes.isClosed) _changes.add(null);
  }

  @override
  Stream<void> watchChanges() => _changes.stream;

  Future<void> dispose() async {
    await _changes.close();
    await _database.close();
    _opening = null;
  }
}
