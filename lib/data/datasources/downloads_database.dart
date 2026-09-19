import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../../core/error/exceptions.dart';

/// Opens `downloads.db` — the app's own writable database.
///
/// Deliberately **not** `quran.db`. That one ships read-only from assets and is
/// replaced wholesale when its schema version changes (CLAUDE.md A.2 rule 6),
/// so a download record written into it would be destroyed by the next app
/// update. This file is created by the app, owned by the app, and survives
/// those replacements.
///
/// It sits beside the audio it describes, in the application support
/// directory — never in Caches, which iOS may purge in the middle of a session
/// and would leave rows pointing at files that are no longer there.
class DownloadsDatabase {
  DownloadsDatabase({
    DatabaseFactory? databaseFactoryOverride,
    Future<Directory> Function()? resolveStorageDirectory,
  }) : _factory = databaseFactoryOverride,
       _resolveStorageDirectory =
           resolveStorageDirectory ?? getApplicationSupportDirectory;

  /// Null means sqflite's global factory, read when the database is actually
  /// opened rather than when this object is built: reading it eagerly would
  /// throw under `flutter test`, where the plugin has no implementation and a
  /// test swaps in an in-process engine before anything is opened.
  final DatabaseFactory? _factory;
  final Future<Directory> Function() _resolveStorageDirectory;

  static const String fileName = 'downloads.db';
  static const int schemaVersion = 1;

  /// One row per reciter and surah.
  ///
  /// `bitrate` is not in the original sketch of this table and is here because
  /// the files cannot be found without it: a pack lives under
  /// `audio/<id>/<bitrate>/`, and the bitrate a surah was fetched at is not
  /// necessarily the quality selected now.
  static const String _createTable = '''
CREATE TABLE IF NOT EXISTS downloads (
  reciter_id TEXT    NOT NULL,
  surah      INTEGER NOT NULL,
  bitrate    INTEGER NOT NULL,
  version    TEXT    NOT NULL,
  state      TEXT    NOT NULL,
  bytes      INTEGER NOT NULL DEFAULT 0,
  ayahs      INTEGER NOT NULL DEFAULT 0,
  updated_at TEXT    NOT NULL,
  PRIMARY KEY (reciter_id, surah)
)
''';

  Future<Database>? _opening;

  Future<Database> open() => _opening ??= _open();

  Future<Database> _open() async {
    final Directory dir = await _resolveStorageDirectory();
    await dir.create(recursive: true);
    final String path = p.join(dir.path, fileName);
    try {
      return await (_factory ?? databaseFactory).openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: schemaVersion,
          onCreate: (Database db, int _) => db.execute(_createTable),
          // A future migration lands here. Creating the table if it is absent
          // covers the upgrade path from a build that had no database at all.
          onUpgrade: (Database db, int _, int _) => db.execute(_createTable),
        ),
      );
    } on Exception catch (e) {
      throw StorageException(
        'Could not open the downloads database at "$path": $e',
      );
    }
  }

  Future<void> close() async {
    final Database? db = await _opening;
    _opening = null;
    await db?.close();
  }
}
